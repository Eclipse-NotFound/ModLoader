"""Freeze verified deployed artifacts; never rebuild or deploy the live game."""
from pathlib import Path
import datetime as dt
import hashlib
import json
import shutil
import zipfile

ROOT = Path(__file__).resolve().parents[3]
MOD = ROOT / 'mods/ModLoader'
STAMP = dt.datetime.now(dt.timezone(dt.timedelta(hours=8))).strftime('%Y%m%d-%H%M%S')
NAME = 'Remains-AllMods-NoRModifier-2026-10-14'
OUT = MOD / 'build/out' / ('collection-' + STAMP)
STAGE = OUT / NAME
PAYLOAD = STAGE / 'payload'
EXPECTED = {
    'pfe.swf': '838d8f02e844c19d7985b99c27907c93811140866b34b79144b7934f09b4943d',
    'ModLoader/ModLoaderMod': '2d01241a89fb25d608ac5138254e14dc3e5fb46e7120319a0d5922e4cf9816fd',
    'Sandevistan/SandevistanMod': 'a6e706f0af8cc912a600d3b2262d3aae1ccffb7a9dd18b6b45f354fa860272e4',
    'RConnect/RConnectMod': '32602e77a21b206d1f7ff0e927b953878c28254e7201529455818923a3539732',
    'RealisticVision/RealisticVisionMod': '89b391bce114534d6f2c0147bd4b136602168ee4362aa36f6f0c37ecd47173b5',
    'MoreSkills&Weapons/MoreSkillsWeaponsMod': '92454203d369fc48853602a4dca702b85ce829c1bc01104fb1f6c7352d33a956',
    'TDFC/TDFCMod': '99bfbaa68229635fbaa496ef9287a94bb9ea7c65d71339cef3fde65f47e30275',
    'RandomRooms/RandomRoomsMod': 'f21d7c04ff1ccf59779f0b8d9f52d982585145447c47727c660e9ecc7d62c0df',
    'WallBlend/WallBlendMod': '0595077b2cfb0c065db3470eac9f6c1d51c53048117d0c9af847cbf76a2b132b',
    'ContinuousScene/ContinuousSceneMod': 'ce279fe569a671594c934b408ceb50b2e9d9b17b0d58532638674fd891f07824',
    'FirearmAttachments/FirearmAttachmentsMod': 'ab6825ead02974f09e8b7bb688aee15adedcd1656bfb50e35a53fcf047d3eb38',
}
VERSIONS = dict(zip(list(EXPECTED)[1:], ['2.3.0 / settings 0.4.0 + 2026-10-03 languages', '1.145 + 2026-10-03 languages', '0.2.22-dev A (prerelease)', '0.30.4-scene', '1.16.0-flashbang', '0.6.4 + 2026-10-03 languages', '13.2 + 2026-10-03 languages', '0.4.2', '0.3.0', '0.1.0']))
FROZEN = {}
def sha(data): return hashlib.sha256(data).hexdigest()
def put(name, data):
    target = STAGE / name
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(data)
def copy(relative, destination=None, expected=None):
    source = ROOT / relative
    data = source.read_bytes()
    digest = sha(data)
    if expected: assert digest == expected, (relative, digest, expected)
    FROZEN[relative] = digest
    put('payload/' + (destination or relative), data)
def check_sources():
    for relative, digest in FROZEN.items():
        assert sha((ROOT / relative).read_bytes()) == digest, 'Input changed: ' + relative
def build():
    STAGE.mkdir(parents=True)
    copy('pfe.swf', expected=EXPECTED['pfe.swf'])
    for key, digest in list(EXPECTED.items())[1:]:
        folder, entry = key.split('/')
        copy(f'mods/{folder}/release/{entry}.swf', expected=digest)
    copy('mods/ContinuousScene/release/scene.xml', expected='8bf1794609aaa3c776566835f87edfea8e929bf509a44e797f8b6289e70e59b9')
    copy('mods/ModLoader/RemainsModScanner.exe', expected='5753a0a6824b47f9146b9c2d2a0f7c19ea60fa15e9f2c72e510d11aac1e5a727')
    # Use the already audited A publication package, never current B tools/config.
    archive = 'mods/RConnect/build/github-a22-package-20261014/RConnect_v0.2.22-dev.zip'
    blob = (ROOT / archive).read_bytes()
    assert sha(blob) == '53823865250d981e1fefbddb656199062082ba812e8a150d00f9e995f26a05ad'
    FROZEN[archive] = sha(blob)
    with zipfile.ZipFile(ROOT / archive) as z:
        assert z.testzip() is None
        for name in z.namelist():
            if name.startswith('mods/RConnect/'):
                assert 'config.txt' not in name
                put('payload/' + name, z.read(name))
    # Existing users keep their own values. Fresh users use SWF defaults;
    # stale local/testing config and obsolete Sandy F9 templates are not shipped.
    put('payload/mods/WallBlend/release/config.json', b'{"enabled":true,"mode":"current"}\n')
    for folder in ('Sandevistan',):
        copy(f'mods/{folder}/release/音乐配置.txt')
    for folder in ('ContinuousScene', 'FirearmAttachments'):
        copy(f'mods/{folder}/README.md')
    lines = ['# Collection 2026-10-14; Windows / Remains 1.02 only.', '# folder|entry|1.02|1.03|1.04']
    for key in list(EXPECTED)[1:]:
        folder, entry = key.split('/')
        if folder == 'RConnect': folder = 'Rconnect'
        lines.append(f'{folder}|{entry}|1|0|0')
    lines.extend(['ModSettings|ModSettingsMod|0|0|0', 'RModifier|LootEditorMod|0|0|0'])
    table = ('\n'.join(lines) + '\n').encode()
    put('payload/mods/loader-manifest.txt', table)
    put('payload/mods/ModLoader/supported-mods.txt', table)
    installer = (MOD / 'tools/collection-install.ps1').read_bytes()
    put('Install.ps1', b'\xef\xbb\xbf' + installer.removeprefix(b'\xef\xbb\xbf'))
    put('Install.bat', b'@echo off\r\nchcp 65001 >nul\r\npowershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install.ps1" %*\r\nif errorlevel 1 (echo Installation failed. & pause & exit /b 1)\r\npause\r\n')
    put('Restore.bat', b'@echo off\r\npowershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install.ps1" -Restore %*\r\nif errorlevel 1 (echo Restore failed. & pause & exit /b 1)\r\npause\r\n')
    rows = '\n'.join(f'| {key.split("/")[0]} | {version} |' for key, version in VERSIONS.items())
    readme = f'''# Remains 模组合集 · 2026-10-14

Windows / Remains **1.02**。包含当前已验证部署的十个运行组件（九个玩法模组及 ModLoader 设置/加载组件），排除 RModifier。使用者需要自行安装游戏；这不是完整游戏。

## 安装

1. 双方保存并完全退出游戏。将本压缩包完整解压到单独文件夹，不要直接在压缩包里运行。
2. 双击 **Install.bat**，输入游戏目录（含 pfe.swf 的文件夹，不要加引号）。工具先校验包，再核对游戏版本、自动备份并安装；现有配置保留，不改玩家存档。
3. 看到 Installed 后正常启动游戏。默认 application.xml 必须指向根 pfe.swf。不要运行旧模组自带安装器。
4. 哔哔小马 → 设置 → 模组。MSW 另有 F6；视野 F11/F12；时停默认反斜杠；枪械改装 Ctrl+M；信息页顶部进入连续大场景。

不需要安装 Python、Java、Flex 或开发工具。首次安装不用另外下载 ModLoader 补丁：payload/pfe.swf 已包含加载器和大场景所需宿主改动。安装器只接受已识别的 1.02 文件；遇到不支持版本会停止，不能强制覆盖。原游戏的其它资源、启动器、AIR 运行时和语言文件继续使用原安装。

安装器会备份到游戏目录 **.modpack-backups/时间戳/**，在 receipt.json 记录本次文件。回退时先保存退出，运行 Restore.bat，输入该备份文件夹。若文件在安装后又被修改，工具停止，避免覆盖更新。配置及存档仍保留；卸载枪械改装前先恢复枪械原装并保存。

## 包内版本

| 组件 | 版本 |
|---|---|
{rows}

这些是已部署且有验证证据的原始字节，未从当前开发源码重新编译。**RConnect 保留 0.2.22-dev 预发布身份**；不将其宣传为正式稳定发行。新 B 架构及 M51 未收入。ContinuousScene 0.3.0 是已验证安装的测试场景，首次进入约13.5秒，实测步行中位55ms，未稳定30帧，完整测试峰值内存约3.1GB。

## 双人合作

两人使用相同合集。F10 显示浮窗，点击 ▼ → 连接，一人 Host、一人 Join；局域网填写宿主地址，默认端口23456。同机可运行 mods/RConnect/Start-Coop.bat；该入口会使自己的后台游戏保持运行，可能增加耗电。Ctrl+Enter 聊天。详见包内 mods/RConnect/README.zh-CN.md 与 docs/local-coop.md。

联机与密集战斗仍有已知边界，不保证公网、稳定重连、三人以上，亦未认证联机与新大场景/枪械改装的全部组合。本次整合只复核准确文件和统一加载，既有专项实测不等于全部混装玩法已经验收。

## 设置、音乐与排除项

新装使用各模组内置默认值；未复制本机 RConnect 的自动跟随/冻结AI测试配置，也未复制玩家设置、存档、昵称或IP。升级会保留已有配置。无音乐也可正常使用时停；自备MP3的说明在 mods/Sandevistan/release/音乐配置.txt。

RModifier 无文件收入，清单和扫描器表中禁用该入口。旧 ModSettings 已由 ModLoader 内置设置替代，保留禁用登记，不附带旧SWF。mods/DLC 是未接入游戏的个人剧情创作工程，未作为可玩模组分发。没有开发工具、测试驱动、旧备份、测试地图编辑器、个人工程或本地音乐。

本合集只启用1.02。扫描器兼容表已补齐新模组，避免把未知组件误开到1.03/1.04；DLC宿主及高帧pfe60不在本包。原来安装的其它未知模组需要自行确认兼容，不应直接把本合集当作任意混装保证。

FILES.json 保存每个安装文件的大小、SHA256及版本；SHA256SUMS.txt 可核对全部包文件。验证详情见 VALIDATION.txt。
'''
    put('先读我.md', readme.encode('utf-8-sig'))
    accepted = ['ee2599b0e518750c454b6d099fb28afea1e74507caa59c9454d2f75de97e30dd', 'f39cbbd6c5352a3932fc739d9809164462eefccf1496361cbba51949ce81ee11', 'c631cbf3511b6ee303f533d08d51511fe0eb702f43e5db17f5241d8576c64867', '8737d543b1f0256335766422705a54d0b345ca543c36918071e3b397155cecc9', EXPECTED['pfe.swf']]
    files = []
    for path in sorted(PAYLOAD.rglob('*')):
        if path.is_file():
            relative = path.relative_to(PAYLOAD).as_posix()
            files.append(dict(path=relative, bytes=path.stat().st_size, sha256=sha(path.read_bytes()), preserveExisting=path.name in ('config.txt', 'config.json')))
    put('FILES.json', (json.dumps(dict(name=NAME, supportedGame='1.02', versions=VERSIONS, acceptedHostHashes=accepted, files=files), ensure_ascii=False, indent=2) + '\n').encode())
    (OUT / 'frozen-inputs.json').write_text(json.dumps(FROZEN, indent=2), 'utf-8')
    check_sources()
    print(json.dumps(dict(out=str(OUT), stage=str(STAGE), files=len(files)), ensure_ascii=False))
if __name__ == '__main__': build()
