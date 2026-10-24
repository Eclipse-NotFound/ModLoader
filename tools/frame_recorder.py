"""Read the bounded passive recording without attaching to or polling the game."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import math
import os
import struct
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[3]


def default_log_dir():
    descriptor = ET.parse(ROOT / "application.xml").getroot()
    app_id = next(e.text for e in descriptor if e.tag.rsplit("}", 1)[-1] == "id")
    return Path(os.environ["APPDATA"]) / app_id / "Local Store" / "frame-recorder"


def read_blocks(directory, warnings):
    """Bound all reads. Exit exports commit a completed temporary file; legacy trial logs remain readable."""
    path = Path(directory) / "frames-v1.jsonl"
    if path.exists():
        try:
            with path.open("rb") as stream:
                for i in range(60):
                    raw = stream.readline(64001)
                    if not raw:
                        break
                    yield f"{path.name}:{i + 1}", raw
                    if len(raw) > 64000:
                        break
                if stream.read(1):
                    warnings.append(f"{path.name}: 超过读取上限，剩余内容跳过")
        except OSError as error:
            warnings.append(f"{path.name}: {error}")
    if (Path(directory) / "frames-v1.pending").exists():
        warnings.append("存在未提交的退出记录；保存可能失败，请核对会话时间，未将它当作完整记录")
    for i in range(60):
        path = Path(directory) / f"chunk-{i:02d}.jsonl"
        if not path.exists():
            continue
        try:
            with path.open("rb") as stream:
                raw = stream.read(64001)
            yield path.name, raw
        except OSError as error:
            warnings.append(f"{path.name}: {error}")
    ring = Path(directory) / "frames-v1.ring"
    if not ring.exists():
        return
    try:
        with ring.open("rb") as stream:
            for i in range(60):
                stream.seek(i * 65536)
                header = stream.read(8)
                if not header or header == b"\0" * 8:
                    continue
                if len(header) != 8:
                    warnings.append(f"slot-{i}: 不完整的头部")
                    continue
                magic, size = struct.unpack(">II", header)
                if magic != 0x46523031 or size > 64000:
                    warnings.append(f"slot-{i}: 无效头部或超过64 KB上限")
                    continue
                if size == 0:
                    warnings.append(f"slot-{i}: 写入未完成，跳过")
                    continue
                raw = stream.read(size)
                # Concurrent overwrite may have started while reading this slot.
                stream.seek(i * 65536)
                if stream.read(8) != header or len(raw) != size:
                    warnings.append(f"slot-{i}: 读取期间改变，跳过")
                    continue
                yield f"slot-{i}", raw
    except OSError as error:
        warnings.append(f"{ring.name}: {error}")


def read_recording(directory):
    """Bound file count and input bytes; tolerate an in-progress async chunk."""
    chunks, warnings = [], []
    for label, raw in read_blocks(directory, warnings):
        try:
            if len(raw) > 64000:
                raise ValueError("超过 64 KB 上限")
            chunk = json.loads(raw)
            if chunk.get("schema") != 1 or not isinstance(chunk.get("samples"), list):
                raise ValueError("不支持的格式")
            if len(chunk["samples"]) > 5:
                raise ValueError("样本数量超过上限")
            for sample in chunk["samples"]:
                for key in ("sequence", "startMs", "endMs", "elapsedMs", "frames", "maxMs", "fps"):
                    if not isinstance(sample.get(key), (int, float)) or not math.isfinite(sample[key]) or sample[key] < 0:
                        raise ValueError("无效样本字段 " + key)
                if not isinstance(sample.get("before"), dict) or not isinstance(sample.get("after"), dict):
                    raise ValueError("缺少场景信息")
                if len(sample.get("stalls", [])) > 4:
                    raise ValueError("长帧标记超过上限")
            if not isinstance(chunk.get("startedEpochMs"), (int, float)) or not math.isfinite(chunk["startedEpochMs"]) or not 0 <= chunk["startedEpochMs"] < 4102444800000 or not chunk.get("session"):
                raise ValueError("缺少会话信息")
            chunks.append(chunk)
        except (OSError, ValueError, TypeError, AttributeError) as error:
            warnings.append(f"{label}: {error}（游戏写入中可稍后重读）")
    if not chunks:
        return None, warnings
    newest = max(chunks, key=lambda c: (c["startedEpochMs"], c.get("writtenMs", 0)))
    current = sorted((c for c in chunks if c["session"] == newest["session"]), key=lambda c: c["writtenMs"])
    samples = {s["sequence"]: s for c in current for s in c["samples"]}
    return {"header": newest, "samples": [samples[k] for k in sorted(samples)]}, warnings


def summarize(recording, warnings=()):
    header, samples = recording["header"], recording["samples"]
    epoch = header["startedEpochMs"]
    def when(ms):
        return datetime.fromtimestamp((epoch + ms) / 1000, timezone.utc).astimezone().isoformat(timespec="milliseconds")
    def clues(sample):
        a, b = sample["before"], sample["after"]
        tags = []
        if a.get("focus") is False or b.get("focus") is False:
            tags.append("窗口不在前台；需用相同焦点条件对照")
        if any(a.get(k) != b.get(k) for k in ("land", "loc")):
            tags.append("采样窗口内发生场景切换")
        if a.get("targetFps") != b.get("targetFps"):
            tags.append("游戏目标帧率改变；先核对暂停或慢动作设置")
        if b.get("paused") or b.get("menu") or b.get("allStat") != 1:
            tags.append("菜单/暂停/非正常游玩状态")
        if b.get("error"):
            tags.append("游戏错误界面可见")
        if b.get("memoryBytes", 0) < a.get("memoryBytes", 0) - 4 * 1024 * 1024:
            tags.append("内存下降；仅与回收相符，不能认定 GC 是原因")
        return tags
    worst = []
    for s in sorted(samples, key=lambda s: s["maxMs"], reverse=True)[:12]:
        worst.append({"time": when(s["endMs"]), **s, "clues": clues(s),
                      "stalls": [{**mark, "time": when(mark["endMs"])} for mark in s.get("stalls", [])]})
    elapsed = sum(s["elapsedMs"] for s in samples)
    gaps = [b["sequence"] - a["sequence"] - 1 for a, b in zip(samples, samples[1:])]
    return {"session": header["session"], "startedEpochMs": epoch, "directoryFormat": "frame-recorder/schema-1",
            "from": when(samples[0]["startMs"]) if samples else None,
            "to": when(samples[-1]["endMs"]) if samples else None,
            "sampleCount": len(samples), "recordedSeconds": elapsed / 1000,
            "weightedFps": sum(s["frames"] for s in samples) * 1000 / elapsed if elapsed else None,
            "maxMs": max((s["maxMs"] for s in samples), default=0),
            "longFrames": sum(s.get("longFrames", 0) for s in samples),
            "omittedMarks": sum(s.get("omittedMarks", 0) for s in samples),
            "missingSamplesInsideRange": sum(gaps), "droppedSamples": header.get("droppedSamples", 0),
            "selfPeakMs": header.get("selfPeakMs"), "loader": header.get("loader", {}),
            "recorder": header.get("recorder", {}),
            "warnings": list(warnings), "worstWindows": worst,
            "limits": "帧事件间隔不是显示器呈现帧率或模组 CPU 用时；线索仅表示同时发生。每窗最多保留前4次长帧位置；窗口仍统计全部长帧及最大间隔。只保留最近300个窗口，约5分钟。正常退出时保存；崩溃、强退或保存失败会丢失本轮内存记录。没有近期日志不证明游戏正常或记录器仍在工作；务必核对会话时间。"}


def markdown(result):
    lines = ["# Remains 帧率与状况记录", "", f"会话：`{result['session']}`",
             f"时间：{result['from']} — {result['to']}",
             f"已记录 {result['recordedSeconds']:.1f} 秒；平均帧事件率 {result['weightedFps'] or 0:.1f} FPS；最大间隔 {result['maxMs']} ms；长帧 {result['longFrames']} 次。",
             f"当前加载成功：{', '.join(result['loader'].get('loaded', [])) or '未取得'}",
             f"缺失样本 {result['missingSamplesInsideRange']}；累计丢弃 {result['droppedSamples']}；未逐条保留的长帧 {result['omittedMarks']}。",
             "", "| 窗口结束时间 | FPS | 最大间隔 ms | 地区 / 房间 | 玩家位置 | 线索 |",
             "|---|---:|---:|---|---|---|"]
    def cell(value):
        return str(value).replace("|", "\\|").replace("\n", " ").replace("\r", " ")
    for s in result["worstWindows"]:
        state = s["after"]
        lines.append(f"| {cell(s['time'])} | {s['fps']:.1f} | {s['maxMs']} | {cell(state.get('land'))} / {cell(state.get('loc'))} | {state.get('x')}, {state.get('y')} | {cell('；'.join(s['clues']) or '需复现和隔离对照')} |")
    lines += ["", "长帧具体时间（endMs）和发生后的坐标见 JSON 的 worstWindows[].stalls；表中坐标为窗口末尾状态。",
              "", result["limits"], "", "下一步：保留日志及当时模组指纹；用 RemainsModLauncher.exe 固定组合，在相同场景/焦点条件下运行 agent-debug.ps1 的完整组合和排除对照。截图另开一轮。"]
    if result["loader"].get("errors"):
        lines += ["", "加载错误：" + json.dumps(result["loader"]["errors"], ensure_ascii=False)]
    status = result.get("recorder", {})
    if status and not status.get("active"):
        lines += ["", "退出保存时采样已停止：" + str(status.get("reason", "未知原因"))]
    lines += ["", *["读取提示：" + w for w in result["warnings"]]]
    return "\n".join(lines) + "\n"


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    report = sub.add_parser("report", help="只读最近一次会话；不会启动或操纵游戏")
    report.add_argument("--log-dir", type=Path)
    report.add_argument("--json", action="store_true")
    report.add_argument("--output", type=Path, help="输出摘要；拒绝覆盖已有证据")
    args = parser.parse_args(argv)
    directory = args.log_dir or default_log_dir()
    recording, warnings = read_recording(directory)
    if recording is None:
        parser.exit(2, f"未取得有效记录：{directory}\n" + "\n".join(warnings) + "\n记录暂存在游戏内存：请先正常保存并退出游戏，再导出。确认已启用 ModLoader、已重启；停用/保存失败不会弹窗。强退不会保存本轮记录。\n")
    result = summarize(recording, warnings)
    result["logDirectory"] = str(directory.resolve())
    output = json.dumps(result, ensure_ascii=False, indent=2) + "\n" if args.json else markdown(result)
    if args.output:
        with args.output.open("x", encoding="utf-8") as stream:
            stream.write(output)
        print(args.output.resolve())
    else:
        print(output)


if __name__ == "__main__":
    main()
