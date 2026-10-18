# ModLoader 外置记忆

更新：2026-10-18。模组选择启动器1.0.0已放本目录；游戏运行模块仍为2.4.0/settings0.5.0。本轮未改正式名单、游戏SWF、描述符或其他模组。

## 1. 这个模组是什么

MainFE清单引导v2、Windows扫描器/选择启动器、游戏内设置模块。新入口RemainsModLauncher.exe；源码src/ModLauncher.cs与src/ModScanner.cs。运行模块源码src/runtime、src/settings，部署点release/ModLoaderMod.swf；不从旧ModSettings项目构建。

## 2. 用户偏好与协作约定

- 2026-10-18用户要求简单界面扫描已安装包、选择加载并一键启动，兼顾玩家与agent排障；此前“不加模组管理”的历史范围被本次要求扩展。
- 扫描器仍只更新名单；启动器提供保存/启动、精确仅选、全停/全开及CLI。扫描保留明确选择，未知新包沿用三版本默认开启，已知限制在supported-mods.txt。
- 测试用唯一AIR应用ID、独立副本/存储，只停止本轮进程，不碰玩家存档。沙箱AIR存活不等于成功，本环境实机需正常Windows权限。
- 设置值与保存归客户端；宿主管两级菜单、分组、位置记忆和录键。23项快捷键在对应模组菜单修改。
- 不改受保护治理文件；本项目一直缺AGENT_SCOPE.md，权限以根GOVERNANCE为准。

## 3. 当前状态

- 启动器1.0.0：C05B4C23…45F9590；配套扫描器：8FA18398…C0D33C1。完整指纹及工具备份见[安装回执](../knowledge/experiments/launcher-2026-10-18/installation.json)。两者都在本模组根目录可双击。
- 选择与有效开关同存mods/loader-manifest.txt，选择用 `# selection|...` 注释。兼容限制与缺包只屏蔽实际加载。新版扫描器保留选择，旧版会重置。保存备份、检测外部变更、互斥写入。
- 核心/真实控件38项、CLI23项、扫描器与加载器离线回归通过。1.02真实单开ModLoader、单开TDFC、全停三场景通过，禁用项无请求，重复启动拒绝。只读扫描15包、原名单启用14包。
- 游戏内正式SWF仍24865B，SHA256 BD71B6F31774B97841D4C158451DA0353B53BC46AC72F8E2A7FE2C3F3F4908B1。keybindVersion=1，旧接口兼容。2026-10-15七客户端23项正式组合175＋171、公共独立及回读各39项通过，见[改键记录](keybind-integration-2026-10-15.md)。
- master直提；任务前已有supported-mods.txt的PermanentInjury登记未提交，保留并排除本轮。EXE/build/out沿用忽略策略，源码与稳定证据入库。

## 4. 正在进行与卡点

本地启动器实现、验证和安装完成；未上传GitHub或更换公开ZIP，无待用户批准的部署步骤。

## 5. 已知边界

- 新界面中文，已查看本机200% DPI默认/最小窗口；未验其他DPI、多显示器或真人完整操作。
- 扫描只检顶层release包与文件头，不证明入口、依赖或跨版本兼容；未知包明确提示。三实机场景不等于全部玩法/组合认证。
- “仅启用”严格只开所选项；需要统一设置菜单须同时选ModLoader。旧ModSettings保持禁用，禁止两宿主并开。
- 导出选择/指纹不是运行成功证据，实际加载继续查本轮loader session的requested/ok/err。
- 清单顺序只决定发起请求先后，初始化异步；同步失败不阻止其他请求，不保证任意异步错误隔离。
- 设置模块和本轮实机只验证1.02；保留既有联机、战斗及各模组玩法边界。

## 6. 回滚与下一步

- 双击RemainsModLauncher.exe → 勾选 → 保存并启动；先退出已有游戏。Agent参数见[说明](../docs/LAUNCHER.zh-CN.md)。
- 工具回退备份work/backups/before-launcher-20261018-2216/RemainsModScanner.exe。恢复旧工具前保留名单，旧扫描器会重置选择。组合回退用work/manifest-backups/。
- tools/build_launcher.ps1只输出build/out/launcher；UI/core、CLI、scanner、loader、runtime检查入口见说明。SWF仍用build/build.ps1构建，上线另走门禁。
- 公共改键与六客户端回退用[2026-10-15记录](keybind-integration-2026-10-15.md)，不要用旧分组备份覆盖较新功能。

## 7. 深入了解

- [启动器证据与失败记录](../knowledge/experiments/launcher-2026-10-18/README.md)、[使用与CLI](../docs/LAUNCHER.zh-CN.md)。
- [菜单改键接入](keybind-integration-2026-10-15.md)、docs/keybind-interface-v1.md。
- docs/settings-interface.md、design/grouped-settings.md；历史knowledge/experiments/grouped-settings-2026-09-24.md及settings-merge-2026-09-24.md。
- [10-14合集](collection-2026-10-14.md)、[10-08公开玩家文档](github-player-guides-2026-10-08.md)、[10-03多语言](localization-2026-10-03.md)。
