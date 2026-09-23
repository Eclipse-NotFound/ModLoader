# ModLoader 外置记忆

> 更新：2026-09-23，v2 已部署；一键模组检测程序已生成并在当前游戏目录运行。先读本文件，再读 README.md、journal.md 最近条目；需要核对旧问题时读 knowledge/discoveries/loader-review-2026-09-23.md。

## 1. 这个模组是什么

ModLoader 是补在游戏 MainFE 里的通用清单加载层，不是独立 release 模组 SWF。它在主菜单构造后读取 mods/loader-manifest.txt，按宿主 1.02／1.03／1.04 列决定向哪些模组发起异步加载，并调用各入口类的静态 init(MainFE)。旧的专属 loader 方法保留为死代码，启动点已收束为一次 loadModsFromManifest()。
RemainsModScanner.exe 是独立的 Windows 双击程序：只更新清单并展示结果，不自动启动游戏。它读取 supported-mods.txt 的已知兼容范围，同时发现新模组的顶层 release/*Mod.swf。

## 2. 协作与测试约定

- 修改三份游戏 SWF 要走 remains-swf-patching 与 remains-release-gate；用户本轮“请进行修复”已授权本轮 v2 部署，不代表未来任意改动可跳过门禁。
- 真机冒烟用唯一 AIR app id 和临时描述符，不碰用户 pfe 存档或用户进程。受限沙箱曾使大 SWF 装载假性停滞；运行验证需能正常启动 AIR 的环境。
- ModLoader.sol 若不能刷新，冒烟保守失败；不要把历史状态或旧日志当本轮成功。
- 用户指定扫描器只更新名单，游戏由用户手动启动；未登记的新模组默认加入 1.02／1.03／1.04 三个版本。

## 3. 当前状态

- v2 已部署：根 pfe.swf（1.02）、DLC/pfe.swf（1.03）、DLC/pfeUI.swf（1.04）。三份线上哈希与本轮 work/v2-deploy 产物一致；精确 SHA-256 见 README。
- 2026-09-23 部署后，独立实例分别以 45 秒冒烟通过：1.02 启用 7 个，1.03 启用 3 个，1.04 启用 2 个；无本轮错误状态，禁用项无请求状态，有日志的模组均写了新日志。
- 工具：tools/patch_game_swfs.ps1、tools/smoke_test.ps1、tools/smoke_assertions.ps1、tools/test_loader.ps1。离线回归检查通过；三目标 FFDec 编译与重新导出校验通过。
- 扫描器：本机已生成 RemainsModScanner.exe（Git 排除，源码与构建脚本入库）；隔离测试覆盖新增、缺失、坏包、重复运行、备份及错误回滚。2026-09-23 在当前游戏目录执行后，名单仍启用 7／3／2 个模组；旧名单备份位于 work/manifest-backups/。扫描器不改游戏 SWF。
- 本轮回滚点在游戏根：pfe_before_genericloader_v2_20260923_105650_843.swf、DLC_pfe_before_genericloader_v2_20260923_105650_843.swf、DLC_pfeUI_before_genericloader_v2_20260923_105650_843.swf。

## 4. 正在进行与卡点

- v2 修复与扫描器实现已完成，目前没有已知阻塞项。根 mods/loader-manifest.txt 由扫描器生成；该运行时文件被根治理仓 .gitignore 排除，不在 ModLoader 仓库内。

## 5. 已知边界

- 清单行序仅决定 Loader.load 发起顺序，不保证各 init 完成顺序。没有跨模组依赖调度。
- MSW 没有独立文件日志；冒烟对它依靠本轮 SharedObject 成功键。SharedObject 失效时应视为验证不足，另做人工功能检查。
- 三目标冒烟验证加载链与版本门控，未覆盖每个模组的深层玩法功能。
- 扫描器只确认正式路径、文件名与 SWF 文件头，不能静态证明入口类、init 或跨版本玩法兼容；新模组全部版本启用是用户明确选择。双击程序后仍须手动启动或重启游戏。
- 根 AGENTS.md 的旧六模组矩阵、部分 Remains 技能的旧 loader 步骤仍待用户侧修订；本项目尚无 AGENT_SCOPE.md。

## 6. 下一步

- 若 Steam 更新游戏：先用 patch_game_swfs.ps1 -DryRun 生成并验证所有目标，结构不匹配时人工核对 MainFE，部署后重启并跑三个描述符的独立冒烟。
- 若需要模组严格初始化依赖，另设计串行队列或显式依赖机制；不要假定移动清单行可实现。
- 后续可补 MSW 的独立版本日志或更直接的 UI 功能断言，降低对 SharedObject 的依赖。
- 若新模组出现版本不兼容，把其明确版本范围登记进 supported-mods.txt，再运行扫描器；直接修改生成名单不会长期保留。

## 7. 深入了解

- 当前使用、状态、验证、回滚：README.md；本轮过程：journal.md 顶部。
- 一键检测源码与构建：src/ModScanner.cs、tools/build_scanner.ps1；隔离回归：tools/test_scanner.ps1；已知版本表：supported-mods.txt。
- v1 问题及对应证据：knowledge/discoveries/loader-review-2026-09-23.md；v1 原交接说明可查 Git 提交 ea9cb26。
- 游戏本体公共结构：shared-knowledge/knowledge-validation/facts/mod-loader-patch-structure.md 的 2026-09-22 补充段（其中旧版本说明需以当前 README 为准）。
