"""离线 A/B 校验台：把 baseline / production 源码 public 化后与 stub 游戏类一起编进
一个独立 AIR 应用，跑断言夹具，输出 PASS/FAIL 到 stdout。

不启动游戏、不写 %APPDATA%（结果只走 stdout 与工作区日志）。
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import uuid

HERE = Path(__file__).resolve().parent
MOD = HERE.parents[1]
GAME = MOD.parents[1]
TOOLS = GAME / 'mods/Sandevistan/build/tools'
JAVA = Path('D:/Program Files/Adobe Animate 2024/jre/bin/java.exe')
SDK = TOOLS / 'flexsdk'
AIR = TOOLS / 'airsdk/frameworks/libs/air/airglobal.swc'


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def publicize(source: Path, dest: Path, rename_from: str = None, rename_to: str = None) -> None:
    dest.mkdir(parents=True, exist_ok=True)
    for path in source.rglob('*.as'):
        target = dest / path.relative_to(source)
        target.parent.mkdir(parents=True, exist_ok=True)
        text = path.read_text(encoding='utf-8-sig')
        text = re.sub(r'\bprivate\b', 'public', text)
        if rename_from and path.name == rename_from + '.as':
            text = text.replace(rename_from, rename_to)
            target = dest / (rename_to + '.as')
        target.write_text(text, encoding='utf-8')


def compile_as(entry: Path, out: Path, sources, externs=None) -> str:
    out.parent.mkdir(parents=True, exist_ok=True)
    config = out.with_suffix('.compiler.xml')
    externs = externs if externs is not None else [AIR]
    config.write_text(
        '<flex-config><compiler><external-library-path>'
        + ''.join('<path-element>' + str(p) + '</path-element>' for p in externs)
        + '</external-library-path><source-path>'
        + ''.join('<path-element>' + str(p) + '</path-element>' for p in sources)
        + '</source-path><debug>false</debug><optimize>true</optimize>'
        + '<omit-trace-statements>false</omit-trace-statements><theme/></compiler>'
        + '<target-player>32.0</target-player><swf-version>32</swf-version>'
        + '<use-network>false</use-network>'
        + '<static-link-runtime-shared-libraries>true</static-link-runtime-shared-libraries>'
        + '</flex-config>', encoding='utf-8')
    result = subprocess.run(
        [str(JAVA), '-Dfile.encoding=UTF-8', '-jar', str(SDK / 'lib/mxmlc.jar'),
         '+flexlib=' + str(SDK / 'frameworks'), '-load-config=' + str(config),
         '-output=' + str(out), str(entry)],
        capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=240)
    log = result.stdout + result.stderr
    out.with_suffix('.log').write_text(log, encoding='utf-8')
    if result.returncode:
        raise RuntimeError(log)
    return log


def run_air(swf: Path, folder: Path, timeout: int = 240) -> tuple:
    import sys
    sys.path.insert(0, str(GAME / 'mods/ModLoader/tools'))
    from air_test_process import HiddenProcess
    desc = folder / 'test.xml'
    app_id = 'pfe-modsettings-rv-csopt-' + uuid.uuid4().hex
    desc.write_text(
        '<application xmlns="http://ns.adobe.com/air/application/30.0"><id>' + app_id
        + '</id><versionNumber>1.0</versionNumber><filename>RvCsOpt</filename>'
        + '<initialWindow><content>' + swf.name + '</content><visible>false</visible>'
        + '<width>1280</width><height>800</height><renderMode>cpu</renderMode>'
        + '</initialWindow><supportedProfiles>extendedDesktop</supportedProfiles></application>',
        encoding='utf-8')
    log_path = folder / (swf.stem + '.air.log')
    with log_path.open('w', encoding='utf-8') as log:
        process = HiddenProcess(
            [str(GAME / 'adl64.exe'), '-runtime', str(GAME / 'runtimes/air/win64'),
             str(desc), '-nodebug'],
            cwd=str(folder), stdout=log, stderr=log)
        try:
            code = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            process.kill(); process.wait(); code = 124
        finally:
            if process.poll() is None:
                process.kill(); process.wait(15)
            process.close()
    desc.unlink(missing_ok=True)
    return code, log_path.read_text(encoding='utf-8', errors='replace')


def prepare_sources(arm: str = 'ab', baseline_dir: Path = None) -> Path:
    """arm=ab：production 保持类名 + baseline 改名 BaselineVision（A/B 夹具用）。
       arm=baseline：只用基线源码，类名保持 RealisticVisionMod（给既有回归夹具做参照）。
       arm=candidate：只用候选源码。
       baseline_dir：可换成上一版（如 refit 前的 v0.35.0）做机制夹具对照。"""
    base_src = baseline_dir if baseline_dir is not None else (HERE / 'baseline/src')
    root = HERE / ('checks/src' if arm == 'ab' else ('checks/src-' + arm))
    if root.exists():
        shutil.rmtree(root)
    if arm == 'baseline':
        publicize(base_src, root)
        return root
    publicize(HERE / 'production/src', root)
    if arm == 'ab':
        publicize(base_src, root, 'RealisticVisionMod', 'BaselineVision')
        for name in ('RVExplorationCarrier.as', 'RVKeybinds.as', 'RVWallSurface.as'):
            shutil.copyfile(HERE / 'production/src' / name, root / name)
        locales = HERE / 'production/src/modlocales'
        if locales.exists():
            shutil.copytree(locales, root / 'modlocales', dirs_exist_ok=True)
    return root


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('harness', nargs='?', default='CsOptHarness')
    parser.add_argument('--arm', default='ab', choices=['ab', 'baseline', 'candidate'])
    parser.add_argument('--baseline-dir', default=None,
                        help='ab 臂的 BaselineVision 源目录（默认 <这里>/baseline/src）')
    parser.add_argument('--timeout', type=int, default=240)
    args = parser.parse_args()

    src = prepare_sources(args.arm, Path(args.baseline_dir) if args.baseline_dir else None)
    stubs = HERE / 'checks/stubs-ext'
    entry = HERE / 'checks' / (args.harness + '.as')
    if not entry.exists():
        entry = MOD / 'build/motion-tests' / (args.harness + '.as')
    out = HERE / 'out'
    out.mkdir(exist_ok=True)
    swf = out / (args.harness + '.swf')
    log = compile_as(entry, swf, [src, HERE / 'checks', MOD / 'build/motion-tests', stubs])
    print('compiled', swf.name, swf.stat().st_size, flush=True)
    code, air_log = run_air(swf, out, args.timeout)
    print(air_log, flush=True)
    passed = len(re.findall(r'^PASS ', air_log, re.M))
    failed = len(re.findall(r'^FAIL ', air_log, re.M))
    summary = {'harness': args.harness, 'arm': args.arm, 'swf': sha(swf), 'exit': code,
               'passed': passed, 'failed': failed,
               'complete': 'COMPLETE' in air_log}
    (out / (args.harness + '.' + args.arm + '.json')).write_text(
        json.dumps(summary, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(summary, ensure_ascii=False), flush=True)
    return 0 if (code == 0 and failed == 0 and summary['complete']) else 1


if __name__ == '__main__':
    sys.exit(main())
