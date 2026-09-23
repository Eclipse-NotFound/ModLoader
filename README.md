# Remains 通用清单加载器 v2

> 2026-09-23：v2 已部署到三份游戏 SWF，并用独立 AIR 实例分别验证 1.02／1.03／1.04。此文件描述当前版本。v1 的原交接报告保留在 Git 历史中（提交 `ea9cb26`）；问题审查见 `knowledge/discoveries/loader-review-2026-09-23.md`。

## 当前结构

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

## 日常维护

清单每个非注释行必须恰有五列：`目录名|入口类名|1.02开关|1.03开关|1.04开关`。开关只能是 `0` 或 `1`。目录是 `mods/` 下的单个路径段；入口类名也是 `release/<入口类名>.swf` 的文件名。入口类必须能以 `public static function init(main)` 调用，参数类型只需能接收 MainFE 实例；现有模组既有 `main:*` 也有 `main:Object`。

保留现有目录拼写：`Rconnect`（实际目录大小写靠 Windows 文件系统兼容）和 `MoreSkills&Weapons`。增加、禁用或改变版本覆盖时，编辑清单并重启游戏即可。行序只决定**发起加载请求**的顺序；各 SWF 异步完成，不能靠移动行保证 `init` 顺序或建立模组依赖。

v2 对清单去除行首尾空白和 UTF-8 BOM，检查列数、开关、入口重复和路径段；坏行会写 `err_manifest_<行号索引>` 并继续处理后续行。单个 SWF 加载或初始化失败会写 `err_<入口类>`，不阻止其余模块。清单不存在时记录 `err_loader`，模组不会加载。

## 状态与验证

加载器每次启动会清空自己的 `ModLoader` SharedObject，写入新的 `session=run_<毫秒>_<随机数>`，以及 `boot_start`、`requested_<入口类>`、`ok_<入口类>`、`boot` 或 `err_*`。值中带相同的 run id 和时间。SharedObject 若不能刷新，游戏仍可继续加载模组，但状态证据不可用；冒烟测试会保守地判失败。

离线回归检查（不启动游戏、不改 SWF）：

    .\mods\ModLoader\tools\test_loader.ps1

线上冒烟每次创建唯一 AIR app id，存档、配置和日志落在该测试 id 的 Local Store；它只终止自己启动的隐藏进程，并在结束时删除临时描述符。它核对本轮 run id、全部应载项的请求与成功、禁用项未请求、无 `err_*`、进程未提前退出，以及有文件日志的模组确实写了新日志。MSW 无独立文件日志，依赖加载器成功状态。受限沙箱里运行大 SWF 曾出现装载停滞假阴性；冒烟需在能正常启动 AIR 游戏的桌面／完整权限环境执行。

    .\mods\ModLoader\tools\smoke_test.ps1 -Descriptor application.xml
    .\mods\ModLoader\tools\smoke_test.ps1 -Descriptor app.xml
    .\mods\ModLoader\tools\smoke_test.ps1 -Descriptor app104.xml

可用 `-SwfOverride` 指向游戏根目录下的隔离补丁副本，在不替换线上 SWF 时先运行验证；脚本会核对副本路径指向的版本列。2026-09-23 v2 部署后，三个线上描述符分别以 45 秒独立实例冒烟通过。

## Steam 更新后的补丁恢复

`tools/patch_game_swfs.ps1` 可从原有专属 loader 结构或 v1 通用 loader 升级到 v2。它检查实际启动调用集合、字段与方法完整性，不再凭单个标记跳过；未知结构、部分旧调用、缺少目标或清单时会报错，不应强行放宽。它先生成并重新导出校验所有目标，之后才备份和替换游戏文件；替换阶段失败会尝试用本轮备份回滚。`work/` 在新检出仓库中会自动创建，FFDec 与 Java 路径可通过参数覆盖。

    .\mods\ModLoader\tools\patch_game_swfs.ps1 -DryRun -WorkDir .\mods\ModLoader\work\trial
    .\mods\ModLoader\tools\patch_game_swfs.ps1 -WorkDir .\mods\ModLoader\work\deploy

第一条只在 work 目录生成产物，不改游戏 SWF。第二条会修改三份游戏 SWF，执行前按工作区 SWF 发布门禁检查；运行后必须重启游戏并重新冒烟。默认工具路径见脚本参数。可以用 `-Targets` 只处理某一已知目标，但缺失的指定目标会报错。

## 本轮回滚点

2026-09-23 10:56:50 的 v2 部署前备份位于游戏根目录：

| 回滚到 v1 时的目标 | 本轮备份 |
|---|---|
| `pfe.swf` | `pfe_before_genericloader_v2_20260923_105650_843.swf` |
| `DLC/pfe.swf` | `DLC_pfe_before_genericloader_v2_20260923_105650_843.swf` |
| `DLC/pfeUI.swf` | `DLC_pfeUI_before_genericloader_v2_20260923_105650_843.swf` |

这些备份恢复的是 v1 通用加载器。更早的 `*_before_genericloader_20260922_*.swf` 才是专属 loader 结构；两组不要混用。回滚后重启游戏，按回滚目标版本验证。v2 冒烟脚本要求 v2 状态格式，不能直接用来验收 v1。

仍需同步的治理资料：根 `AGENTS.md` 的旧加载矩阵、`remains-swf-patching`／`remains-new-mod`／`remains-game-update` 的旧流程。本项目目前没有 `AGENT_SCOPE.md`；这些受保护文件由用户维护。
