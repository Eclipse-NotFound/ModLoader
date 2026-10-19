# 模组启动器

双击 `mods/ModLoader/RemainsModLauncher.exe`，勾选要玩的模组，再点 **保存并启动**。默认读取 `application.xml` 判断游戏版本；也可切换到 1.03 / 1.04。启动前请先保存并退出已经打开的游戏。

这是本地新增的启动器 1.0.0，尚未上传到 GitHub 旧发布包。它沿用现有游戏补丁和设置组件，首次安装仍需要游戏加载补丁。

## 日常使用

- 打开窗口自动扫描 `mods/<目录>/release/XxxMod.swf`。新增或更新包后点 **重新扫描**；未保存的勾选也会保留。
- **保存选择** 只更新下次启动使用的名单；**保存并启动** 还会启动所选版本。关闭窗口不会自动保存。
- **全部启用** 只勾选当前版本允许的已安装包；**全部停用** 用于检查无模组时的问题。三版本的选择分别保存。
- 灰色行会说明未安装、文件损坏、不支持当前版本或属于已停用旧组件。新发现的包会提示兼容性尚未核验，文件头合格不代表玩法验证通过。
- `ModLoader` 是游戏内统一设置组件，可以为排障停用；停用后其余勾选包仍由游戏内的加载入口加载，但统一设置菜单会消失。旧 `ModSettings` 不可与它同时启用。
- 包暂时移走时不会加载；放回后保留上次明确保存的选择。旧扫描器应换成同次构建的新版，否则旧程序会重建名单并重置选择。

## 定位模组故障

1. 点 **全部停用**，保存并启动，检查问题在无模组时是否出现。
2. 退出游戏，在列表中选中一个或多个模组行，点 **仅启用选中项**，再启动。Ctrl / Shift 可以多选。这个操作严格只开所选项，若需要统一设置菜单，请同时选中 `ModLoader`。
3. 逐步增减模组以缩小范围。模组间冲突可能只有组合启用时出现，单独启动正常不能排除组合冲突。
4. **导出排障记录** 保存当前选择、版本、包入口和 SHA-256 文件指纹；每次启动也会自动在 `work/launch-history/` 留一份。记录说明“打算加载什么”，运行成功仍需核对游戏日志。

关闭模组不会撤销已写入存档或被编辑器修改的游戏数据。RandomRooms 等模组的停用前操作仍按各自说明进行。

## Agent 命令行

卡顿或视觉异常需要自动对照时，使用 [Agent 归因调试器](AGENT-DEBUGGING.md)。它通过本启动器选组，自动创建隔离副本并采集帧间隔、截图、显示树和本轮加载证据。

以下从 `mods/ModLoader` 执行。图形窗口与命令行使用同一套选择规则；错误返回 1，成功返回 0，输出 UTF-8。使用入口名而非显示名称，多个入口用逗号分隔。

```powershell
# 只读扫描，适合自动化脚本
./RemainsModLauncher.exe --list --json --no-ui

# 当前版本只开 TDFC 和统一设置组件，保存但不启动
./RemainsModLauncher.exe --only TDFCMod,ModLoaderMod --no-ui

# 停用一个包；其他选择和其他版本保持原样
./RemainsModLauncher.exe --disable TDFCMod --no-ui

# 预览全部停用，不写名单、不启动
./RemainsModLauncher.exe --none --dry-run --json --no-ui

# 独立测试目录：先用唯一 AIR app id 的描述符隔离存储
./RemainsModLauncher.exe --root 'D:\test-game' --descriptor application-test.xml --only TDFCMod --launch --no-ui

# 导出排障记录；目标目录须存在，文件名须为尚不存在的 .json
./RemainsModLauncher.exe --report './work/selection-001.json' --no-ui
```

另有 `--all`、`--enable <入口>`、`--version 1.02|1.03|1.04`、`--help`。选择操作一次只用一种。`--root` 仅更换游戏目录，不会自动隔离 AIR 存档；自动测试必须使用独立目录和唯一 application id。`--descriptor` 必须指向该目录内 XML，且 `<content>` 为 `pfe.swf`、`DLC/pfe.swf` 或 `DLC/pfeUI.swf`。检测到该目录的游戏正在运行时，启动请求会在保存前拒绝。

## 保存与恢复

有效加载开关和用户选择一起原子写入 `mods/loader-manifest.txt`：普通行供游戏读取，`# selection|...` 注释保存选择。兼容表仍是 `supported-mods.txt`，界面不会改它。缺包或不兼容只屏蔽实际加载，不删除选择。

变动前的名单自动存入 `work/manifest-backups/`。若要恢复旧组合，关闭启动器和游戏，将对应备份复制回 `mods/loader-manifest.txt`，再打开启动器核对。不要只改普通数据行而留下相反的选择注释。窗口打开后若名单、兼容表或包集合改变，保存会要求重新扫描。

## 构建与检查

```powershell
./tools/build_launcher.ps1
./tools/test_launcher.ps1
./tools/test_launcher_cli.ps1
./tools/test_scanner.ps1 -ScannerPath ./build/out/launcher/RemainsModScanner.exe
./tools/test_loader.ps1
./tools/test_launcher_runtime.ps1
```

构建使用 Windows 自带的 .NET Framework 编译器，输出 `build/out/launcher/` 下两个 EXE，不自动覆盖当前工具。验证后把两者复制到 `mods/ModLoader/`，保留旁边的 `supported-mods.txt`。运行测试只写本项目隔离副本并使用独立存储；真实加载验证覆盖 1.02 的设置组件单开、TDFC 单开和全部停用，不是所有模组组合及 DLC 玩法认证。
