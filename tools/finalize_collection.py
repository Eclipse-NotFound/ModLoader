"""Finalize only after native validation, matching ZIP-extracted payload bytes."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile

def digest(data): return hashlib.sha256(data).hexdigest()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('output_directory', type=Path)
    args = parser.parse_args()
    out = args.output_directory.resolve()
    name = 'Remains-AllMods-NoRModifier-2026-10-14'
    stage = out / name
    root = Path(__file__).resolve().parents[3]
    frozen = json.loads((out / 'frozen-inputs.json').read_text('utf-8'))
    for relative, value in frozen.items():
        assert digest((root / relative).read_bytes()) == value, 'Source changed: ' + relative
    evidence = out / 'extracted/verification-approved/result.json'
    result = json.loads(evidence.read_text('utf-8-sig'))
    assert result['passed'] and all(c['passed'] for c in result['checks'])
    manifest = json.loads((stage / 'FILES.json').read_text('utf-8'))
    assert len(manifest['versions']) == 10
    for item in manifest['files']:
        relative, value = item['path'], item['sha256']
        for directory in (stage / 'payload', out / 'extracted' / name / 'payload'):
            assert digest((directory / relative).read_bytes()) == value, relative
        if relative != 'mods/loader-manifest.txt':
            actual = out / 'extracted/verification-approved/runtime' / relative
            assert digest(actual.read_bytes()) == value, 'Tested payload changed: ' + relative
    validation = f'''分发包核验（2026-10-14）

包名：{name}
范围：当前已验证部署产物重新整理，不是新源码构建或全部混装玩法认证。
文件：{len(manifest['files'])}个安装文件；10个生产模组SWF与1个配套宿主SWF。
RConnect：0.2.22-dev A，保持预发布身份，不含M51/B。
ContinuousScene：0.3.0；RV 0.30.4-scene、WallBlend 0.4.2，按同一部署回执成组冻结。

本次：从候选ZIP完整解压，实际执行包内安装器和回退，旧1.02宿主恢复、配置保留、未知版本拒绝均通过；实际分发扫描器扫描出10项1.02，DLC为0，旧设置/RModifier禁用。没有改动本机正式游戏、正式配置或玩家存档。
解压的生产字节在独立AIR身份 {result['appId']} 启动50秒；十个原生requested/ok回执、禁用项无请求、无loader错误、各有日志模组新鲜日志、设置600帧、视野与场景/墙面持续心跳通过；无LootEditor日志，无未捕获AIR错误。本次共{len(result['checks'])}项检查通过。

原有同字节功能依据：10-03语言整合4432项；MSW闪光弹133及激光199行与900帧；RConnect A22原38组4760项；大场景0.3完整48、墙面43、视野42、安装后原生15项；枪械改装正式原字节72项。以上是历史专项，本次没有把它们全套重跑，也不保证所有联机/武器/大场景组合或长期性能。

首轮沙箱运行无法创建独立日志存储；重新在允许测试存储的环境运行后十项初始化成功。后续测试器误要求Sandy默认关闭的诊断日志，并误将WallBlend的空preferenceError字段名视为错误，均已按原生回执和明确错误内容纠正。未启用测试配置，未修改生产SWF。原失败与最终证据均保留在构建目录。

按发布检查：复用原构建/版本/同字节功能证据；新做安装、回退、隔离原生启动、版本表与ZIP逐项校验。本次无线上部署，正式配置/游戏文件改写项不适用。版本不变，不新增运行时版本号。记录及工具在ModLoader仓库提交。
'''
    (stage / 'VALIDATION.txt').write_text(validation, 'utf-8-sig')
    sums = []
    for path in sorted(stage.rglob('*')):
        if not path.is_file() or path.name == 'SHA256SUMS.txt': continue
        relative = path.relative_to(stage).as_posix()
        assert not any(part.lower() in ('rmodifier', '.git', '__pycache__', 'user-data', 'workspace') for part in path.relative_to(stage).parts)
        assert path.suffix.lower() not in ('.mp3', '.sol', '.swc')
        assert 'probe' not in path.name.lower()
        sums.append(digest(path.read_bytes()) + '  ' + relative)
    (stage / 'SHA256SUMS.txt').write_text('\n'.join(sums) + '\n', 'utf-8')
    final = out.parent / (name + '.zip')
    with zipfile.ZipFile(final, 'x', zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in sorted(stage.rglob('*')):
            if path.is_file(): archive.write(path, name + '/' + path.relative_to(stage).as_posix())
    with zipfile.ZipFile(final) as archive:
        assert archive.testzip() is None
        for entry in archive.infolist():
            assert archive.read(entry.filename) == (out / entry.filename).read_bytes()
        assert len(archive.namelist()) == sum(1 for p in stage.rglob('*') if p.is_file())
    # Detect input mutation during the compression window too.
    for relative, value in frozen.items():
        assert digest((root / relative).read_bytes()) == value, 'Source changed during compression: ' + relative
    summary = dict(package=str(final), bytes=final.stat().st_size, sha256=digest(final.read_bytes()), payload_files=len(manifest['files']), zip_files=len(sums)+1, checks=len(result['checks']), runtime_app_id=result['appId'], crc_and_all_bytes_verified=True, production_inputs_unchanged=True, scope=result['scope'])
    final.with_suffix('.zip.sha256.txt').write_text(summary['sha256'] + '  ' + final.name + '\n', 'utf-8')
    (out / 'final-verification.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2), 'utf-8')
    print(json.dumps(summary, ensure_ascii=False))

if __name__ == '__main__': main()
