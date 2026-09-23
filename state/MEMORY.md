# ModLoader 外置记忆

> 2026-09-24：v2.2.0 已内置设置并安装，完成候选和正式字节复验；接续先读本文件与 README。

## 1. 这个模组是什么
三部分：MainFE清单引导v2、Windows扫描器v2.1、运行模块ModLoaderMod v2.2.0。新增运行文件提供原ModSettings v0.3.1的设置登记与两级菜单。源码src/runtime + src/settings，入口release/ModLoaderMod.swf / ModLoaderMod.init(main)。设置值和保存仍归客户端。

## 2. 用户偏好与协作约定
- 本轮Q1–Q4确认A后要求具体实施：内置原设置功能、保留接口/记忆、仅支持1.02；不加模组管理。实现与验证后已按方案安装。
- 扫描器只更新名单，不启动游戏；未登记的新模组默认三个版本全开，已知限制写supported-mods.txt。
- 隔离运行用唯一AIR app id、隐藏窗口及自有存储，不碰原游戏进程和存档；需有正常启动AIR的权限。
- 游戏SWF修改须独立走补丁/发布门禁，本轮没有改三份游戏文件。受保护治理文件未改。

## 3. 当前状态
- 正式ModLoaderMod.swf 15110字节，SHA256 C9701A91013899E2674F29990AC6E4977A6C4678D0AE47D8C14324F97084704C。
- 新入口1/0/0，旧ModSettings入口0/0/0；旧C2BC2CCE...包保留回滚，不能删禁用登记。总启用数7/3/2。三份游戏SWF仍B782.../90DE.../0BD5...，完整值见README。
- 原ModSettingsCarrier.modAPI、页面ID、apiVersion/menuVersion=1、两行标签、局部重置与MSW F6不改；菜单存储仍ModSettingsMenu（/）。ModLoader诊断存储每次启动清空，不能用于菜单。
- 2026-09-24：旧记忆迁移71项、无MSW20项、中文按钮/记录切换24项、三版本及故障94项、安装前后各50项通过；安装后新版本标记和frames=1200。证据见knowledge/experiments/settings-merge-2026-09-24.md。
- 本轮测试MSW正式指纹C233D67E...，不是旧F8DD...；未覆盖客户端或配置。build/out/installation/deployment.json状态installed-and-verified。

## 4. 正在进行与卡点
合并和安装已完成；设置后续改动只在本项目维护，ModSettings保留历史。根生成名单在仓库之外，不纳入本项目Git。

2026-09-24新需求：增加通用可展开分组接口，首用于MSW锁定豁免。Q1–Q6均A：大类逐行、小项下展；大类批量全选/清空；只改Pip而F6保留平面；部分选中点后补全；一次展开一类/可全收；跨重启记忆展开状态。见design/grouped-settings.md，等待整体确认，未实现/构建/安装。本轮MSW已是v1.12.0/B8EB77D2...，不能回盖旧C233...；其journal有他人的未提交修改，未触碰。

## 5. 已知边界
- 设置仅1.02。DLC仅验证新旧设置入口不请求、原模组初始化，不是DLC设置兼容认证。
- 清单顺序只决定请求先后，初始化仍异步，客户端保持重试。缺包/同步init失败不阻止其他请求，不保证任意后续异步错误隔离。
- 未覆盖全部联机/战斗；MSW加载成功依赖本轮SharedObject。共享日志不会被禁用旧入口误报，但旧入口requested/ok仍禁止。
- 手工双开两个宿主没有优先级保证，必须在版本表禁用旧入口。扫描器不能证明未知模组入口或跨版本兼容。
- 根AGENTS和部分技能仍描述旧结构，本项目无AGENT_SCOPE，由用户维护。

## 6. 回滚与下一步
- 备份work/backups/before-settings-merge-20260924-064730/。退出游戏后确保旧ModSettings包为C2BC2CCE...，版本表将旧入口恢复1/0/0、新入口保留0/0/0，再扫描生成名单。若还原旧版本表，须补入新入口禁用行，防止保留的新包被扫描器复活。后续新增模组须合并；无需回退游戏SWF。
- ./build/build.ps1只输出build/out；上线仍需门禁、备份与安装后复验。取当前正式客户端，勿用旧冻结MSW覆盖新版本。
- Steam更新后按README恢复三目标补丁，不为设置更新重打MainFE。

## 7. 深入了解
- README.md：结构、构建、验证、指纹与回滚；docs/settings-interface.md：API和菜单契约。
- knowledge/experiments/settings-merge-2026-09-24.md：验证与首次探针等待超时修正；state/journal.md：近期实施。
- build/test-menus.ps1：候选/正式/旧记忆/无MSW；test-button-style.ps1：中文像素和页面切换；test-startup.ps1：三版本及故障注入。
- tools/test_loader.ps1、test_scanner.ps1：离线回归；smoke_test.ps1：加载冒烟；patch_game_swfs.ps1：游戏补丁；src/ModScanner.cs：扫描器。
- knowledge/discoveries/loader-review-2026-09-23.md：历史v1问题与v2修复。
