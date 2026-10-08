# ModLoader 技术与历史记录

[玩家安装指南](INSTALL.zh-CN.md) · [返回首页](../README.zh-CN.md)

以下保留此前的开发文档。部署哈希、模组数量、测试结果与回滚路径是对应日期的本机记录；不要按其中历史回滚步骤处理今天的玩家安装。日常装卸以玩家指南为准。

## 当前结构

ModLoader 由三个部分组成：游戏 MainFE 内的清单引导代码、生成清单的 Windows 扫描器、提供设置界面的 `release/ModLoaderMod.swf`。设置源代码在 `src/settings/`，运行入口在 `src/runtime/`，构建不再读取独立 ModSettings 项目。安装本项目的运行文件与版本表后，其他模组可继续使用原有 `ModSettingsCarrier.modAPI`，不需另装 ModSettings。

游戏启动后，`MainFE.onEnterFrameLoader` 在创建主菜单后调用一次 `loadModsFromManifest()`。它异步读取游戏根目录的 `mods/loader-manifest.txt`，按当前 SWF 路径选择版本列，然后向每个启用模组发起 `Loader.load()`；完成事件中解析入口类并调用其静态 `init(this)`。旧的各模组 loader 方法体仍留在 MainFE 中，但启动点的旧调用已移除。

| 描述符 | 实际 SWF | 当前启用项 |
|---|---|---|
| `application.xml` | `pfe.swf`（日常游玩，1.02） | 7 个 |
| `app.xml` | `DLC/pfe.swf`（1.03） | 3 个 |
| `app104.xml` | `DLC/pfeUI.swf`（1.04） | 2 个 |

三份已部署 SWF 的 SHA-256 分别为：

| 文件 | SHA-256 |
|---|---|
| `pfe.swf` | `B78244657ED407D03808C90E97325509DB35F802122835F58933FFF8003305AC` |
| `DLC/pfe.swf` | `90DEC445E60E352DCAD06B3171A3AE7B588DBF1FE6C8FB452FCEEC392AA9DB02` |
| `DLC/pfeUI.swf` | `0BD5D24381B5AAEA50E40B2F95A9E54DFE4A7911AAFBA27AFF06961C82F350C7` |

## 一键检测模组

双击 `RemainsModScanner.exe`（从玩家发布包获取）。程序会检查 `mods/<目录>/release/XxxMod.swf` 形式的正式模组包（入口类名为 `XxxMod`），更新游戏实际读取的 `mods/loader-manifest.txt`，然后显示三个游戏版本各准备加载几个模组。**程序不启动游戏**；关闭结果窗口后由玩家自己启动或重启游戏。它不修改游戏 SWF，也不扫描各模组的 `build/`、测试目录、`release/backup/` 或带旧版本后缀的备份包。

已知版本范围保存在 [`supported-mods.txt`](../supported-mods.txt)，包含新运行入口和禁用的旧设置入口。扫描器只在对应包存在且有基本 SWF 文件头时启用其原有版本开关；缺包时三个版本都关闭，包放回后自动恢复原有范围。未登记的新模组若符合上述目录和文件名约定，会按用户要求**自动在 1.02／1.03／1.04 全部启用**。这是自动发现与基本文件检查，不等于验证入口类、`init(main)` 或跨版本玩法兼容性；运行时失败仍由 v2 加载器逐项记录，其他模组继续尝试加载。若新模组有明确的版本限制，应把它登记进 `supported-mods.txt` 后重新扫描。

只有名单内容改变时，程序才会写入新名单，并把旧名单备份到 `work/manifest-backups/`；失败时保留原名单。双击程序无需另外安装开发工具。需要从源码重建或做隔离回归时：

    .\mods\ModLoader\tools\build_scanner.ps1
    .\mods\ModLoader\tools\test_scanner.ps1

命令行可用 `--dry-run --no-ui` 只预览，`--root <游戏目录> --no-ui` 则可针对隔离游戏目录测试。`RemainsModScanner.exe` 是本机生成产物，不纳入 Git；分发或换机器时先运行构建脚本。

## 日常维护

合并后的版本表固定登记 `ModLoader|ModLoaderMod|1|0|0` 与 `ModSettings|ModSettingsMod|0|0|0`。旧包可留作回滚，但不要删除它的禁用登记，否则扫描器会将旧包当作新模组启用。新包缺失时不会自动复活旧入口。两个设置宿主不可同时启用；不靠异步加载时谁先发布载体来选择版本。

清单每个非注释行必须恰有五列：`目录名|入口类名|1.02开关|1.03开关|1.04开关`。开关只能是 `0` 或 `1`。目录是 `mods/` 下的单个路径段；入口类名也是 `release/<入口类名>.swf` 的文件名。入口类必须能以 `public static function init(main)` 调用，参数类型只需能接收 MainFE 实例；现有模组既有 `main:*` 也有 `main:Object`。

保留现有目录拼写：`Rconnect`（实际目录大小写靠 Windows 文件系统兼容）和 `MoreSkills&Weapons`。一键扫描启用时，编辑 `supported-mods.txt` 中的已知版本范围，再运行扫描器并重启游戏；直接编辑生成后的清单会在下次扫描时被覆盖。行序只决定**发起加载请求**的顺序；各 SWF 异步完成，不能靠移动行保证 `init` 顺序或建立模组依赖。

v2 对清单去除行首尾空白和 UTF-8 BOM，检查列数、开关、入口重复和路径段；坏行会写 `err_manifest_<行号索引>` 并继续处理后续行。单个 SWF 加载或初始化失败会写 `err_<入口类>`，不阻止其余模块。清单不存在时记录 `err_loader`，模组不会加载。

## 状态与验证

设置界面和接口说明见 [settings-interface.md](../docs/settings-interface.md)。原两级菜单、MSW F6 路由、页面 ID、回调和设置归属均保留。`groupVersion=1` 支持可选分组元数据，平面 `items` 接口不变。菜单位置及每页展开组仍存于 `ModSettingsMenu`（路径 `/`），不要迁入下面每次启动被清空的 `ModLoader` 诊断存储。设置日志继续使用 `ModSettings.log`，同时输出运行模块和设置服务版本；载体附加 `hostId=ModLoader`、`hostVersion=2.3.0` 供诊断。

加载器每次启动会清空自己的 `ModLoader` SharedObject，写入新的 `session=run_<毫秒>_<随机数>`，以及 `boot_start`、`requested_<入口类>`、`ok_<入口类>`、`boot` 或 `err_*`。值中带相同的 run id 和时间。SharedObject 若不能刷新，游戏仍可继续加载模组，但状态证据不可用；冒烟测试会保守地判失败。

离线回归检查（不启动游戏、不改 SWF）：

    .\mods\ModLoader\tools\test_loader.ps1

线上冒烟每次创建唯一 AIR app id，存档、配置和日志落在该测试 id 的 Local Store；它只终止自己启动的隐藏进程，并在结束时删除临时描述符。它核对本轮 run id、全部应载项的请求与成功、禁用项未请求、无 `err_*`、进程未提前退出，以及有文件日志的模组确实写了新日志。MSW 无独立文件日志，依赖加载器成功状态。受限沙箱里运行大 SWF 曾出现装载停滞假阴性；冒烟需在能正常启动 AIR 游戏的桌面／完整权限环境执行。

    .\mods\ModLoader\tools\smoke_test.ps1 -Descriptor application.xml
    .\mods\ModLoader\tools\smoke_test.ps1 -Descriptor app.xml
    .\mods\ModLoader\tools\smoke_test.ps1 -Descriptor app104.xml

可用 `-SwfOverride` 指向游戏根目录下的隔离补丁副本，在不替换线上 SWF 时先运行验证；脚本会核对副本路径指向的版本列。2026-09-23 v2 部署后，三个线上描述符分别以 45 秒独立实例冒烟通过。

## 设置运行模块的构建与验证

在本项目目录执行；编译输出在 `build/out/`，不会自动覆盖正式 `release/`。工具链使用 Animate 自带 mxmlc 和 playerglobal，`-AnimateRoot` 可覆盖默认路径。

```powershell
./build/build.ps1
./tools/test_loader.ps1
./tools/test_scanner.ps1
./build/test-menus.ps1 -RunLabel candidate
./build/test-menus.ps1 -Scenario without-msw -RunLabel without-msw
./build/test-button-style.ps1 -CandidateHost -RunLabel candidate
./build/test-startup.ps1
```

菜单和启动测试复制当前正式客户端到独立游戏目录，使用唯一 AIR app id，保持真实存档和用户进程不受影响。`test-menus.ps1 -MigrateFrom <旧设置SWF绝对路径>` 用同一测试存储先运行旧宿主再切换新宿主，验证原位置记忆继承。`test-startup.ps1` 同时验证三版本正常加载、运行模块缺失及初始化失败，故障仅注入测试副本。安装后用 `test-menus.ps1 -InstalledHost -SmokeOnly -RunLabel installed` 检查正式字节的菜单、版本与持续心跳。

当前分组验证：跨三进程 62+6+4 项、新 MSW 配旧宿主 8 项、旧客户端及新组合各 50 项；最终文件中文按钮/记录往返 24 项、安装前后各 65 项通过。正式运行文件 17282 字节，SHA-256：`375951AE86BCCD8886CDEAC8B479A339877CEE30F5D1B489C21FE06C736C0BF5`。验证范围和精确产物对应关系见分组记录，不代表全部模组玩法认证。

分组探针：`./build/test-menus.ps1 -Probe GroupProbe -RunLabel groups`。指定候选客户端使用 `-MSWSwf <绝对路径>`；旧宿主兼容使用 `-HostSwf <绝对路径> -SmokeOnly`；正式文件复验使用 `-InstalledHost -SmokeOnly`。不加 `-SmokeOnly` 会用同一独立应用 ID 启动三次，检查展开和全收起状态的跨进程保存。

v2.2.0 首次合并历史验证为旧记忆迁移 71 项、无 MSW 20 项、中文按钮 24 项、三版本及故障 94 项、安装前后各 50 项；旧文件 15110 字节、C9701A91…，本轮没有重跑三版本故障套件。

## 当前分组版本回滚

退出游戏后，从 `work/backups/before-groups-20260924-075628/` 成对恢复 `ModLoaderMod.swf` 与 `MoreSkillsWeaponsMod.swf` 到各自正式 `release/`，再重启。分别恢复到 v2.2.0/C9701A91… 和含激光笔的 MSW v1.13.0/476430BC…；不改版本表、清单或配置。安装前后文件与保护项指纹在 `build/out/groups-installation/deployment.json`（installed-and-verified）。旧 ModSettings 继续禁用。下面是首次合并的历史回滚方法，不用于仅撤回分组功能。

## 设置合并的回滚

本次备份位于 `work/backups/before-settings-merge-20260924-064730/`，包含旧 `ModSettingsMod.swf`、合并前 `supported-mods.txt` 和生成的 `loader-manifest.txt`。先退出游戏，核对旧正式包为 v0.3.1（`C2BC2CCE...`），必要时恢复备份。版本表将旧入口恢复为 `ModSettings|ModSettingsMod|1|0|0`，同时保留 `ModLoader|ModLoaderMod|0|0|0`，再运行扫描器生成名单。新运行文件可保留；必须留下它的禁用登记，否则扫描器会把它重新发现并启用。若使用备份旧版本表，应先补入这条新入口禁用行，再扫描。后续新增模组的条目应合并保留。重启验证旧入口。详细指纹与安装回执见 `build/out/installation/deployment.json`。

旧版目录与源代码为历史资料，设置后续只在本项目维护。游戏 SWF 本轮未改，不要为回滚设置而使用下面历史游戏补丁备份。

## Steam 更新后的补丁恢复

`tools/patch_game_swfs.ps1` 可从原有专属 loader 结构或 v1 通用 loader 升级到 v2。它检查实际启动调用集合、字段与方法完整性，不再凭单个标记跳过；未知结构、部分旧调用、缺少目标或清单时会报错，不应强行放宽。它先生成并重新导出校验所有目标，之后才备份和替换游戏文件；替换阶段失败会尝试用本轮备份回滚。`work/` 在新检出仓库中会自动创建，FFDec 与 Java 路径可通过参数覆盖。

    .\mods\ModLoader\tools\patch_game_swfs.ps1 -DryRun -WorkDir .\mods\ModLoader\work\trial
    .\mods\ModLoader\tools\patch_game_swfs.ps1 -WorkDir .\mods\ModLoader\work\deploy

第一条只在 work 目录生成产物，不改游戏 SWF。第二条会修改三份游戏 SWF，执行前按工作区 SWF 发布门禁检查；运行后必须重启游戏并重新冒烟。默认工具路径见脚本参数。可以用 `-Targets` 只处理某一已知目标，但缺失的指定目标会报错。

## 历史清单引导 v2 回滚点

2026-09-23 10:56:50 的 v2 部署前备份位于游戏根目录：

| 回滚到 v1 时的目标 | 本轮备份 |
|---|---|
| `pfe.swf` | `pfe_before_genericloader_v2_20260923_105650_843.swf` |
| `DLC/pfe.swf` | `DLC_pfe_before_genericloader_v2_20260923_105650_843.swf` |
| `DLC/pfeUI.swf` | `DLC_pfeUI_before_genericloader_v2_20260923_105650_843.swf` |

这些备份恢复的是 v1 通用加载器。更早的 `*_before_genericloader_20260922_*.swf` 才是专属 loader 结构；两组不要混用。回滚后重启游戏，按回滚目标版本验证。v2 冒烟脚本要求 v2 状态格式，不能直接用来验收 v1。

仍需同步的治理资料：根 `AGENTS.md` 的旧加载矩阵、`remains-swf-patching`／`remains-new-mod`／`remains-game-update` 的旧流程。本项目目前没有 `AGENT_SCOPE.md`；这些受保护文件由用户维护。
