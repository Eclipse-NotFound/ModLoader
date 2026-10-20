# ModLoader 外置记忆

更新：2026-10-20。agent归因调试器1.0.2新增共享测试登记与自动占用协调，继续默认使用独立Windows桌面；启动器仍1.0.0，游戏运行模块仍2.4.0/settings0.5.0。已统一本机验证后直接部署规则，并归档移除旧ModSettings项目及本机加载登记。

## 1. 这个模组是什么

MainFE清单引导v2、Windows扫描器/选择启动器、游戏内设置模块。新入口RemainsModLauncher.exe；源码src/ModLauncher.cs与src/ModScanner.cs。运行模块源码src/runtime、src/settings，部署点release/ModLoaderMod.swf；不从旧ModSettings项目构建。

## 2. 用户偏好与协作约定

- 2026-10-20用户要求测试情况登记表，避免每次测试都打断别的对话确认。先用 `tools/agent-debug.ps1 tests` 刷新共享表；`run` 自动登记/等待/写回，专用驱动按[登记说明](../docs/TEST-REGISTRY.md)接入。正常占用等待或暂缓；中断按已有证据核对，无需逐次询问原会话。

- 2026-10-19用户要求测试启动不显示HARMAN/AIR标识。默认后台测试用独立桌面；需要原生画面或操作时才显式可见测试。创建桌面失败须报错，不自动回退前台。具体入口见docs/AGENT-DEBUGGING.md。

- 2026-10-19 用户持续授权：本任务新版通过本机验证与门禁后直接部署，无需再次询问；以根 `GOVERNANCE.md` §6 为准。历史记录的未部署状态保留，不据此批量安装旧候选。


- 2026-10-18用户要求简单界面扫描已安装包、选择加载并一键启动，兼顾玩家与agent排障；此前“不加模组管理”的历史范围被本次要求扩展。
- 2026-10-19用户要求给agent用的卡顿/视觉异常归因调试器，并把RemainsModLauncher.exe固化进调试流程；两项工作区技能本次获明确修改授权，原版已备份。
- 扫描器仍只更新名单；启动器提供保存/启动、精确仅选、全停/全开及CLI。扫描保留明确选择，未知新包沿用三版本默认开启，已知限制在supported-mods.txt。
- 测试用唯一AIR应用ID、独立副本/存储，只停止本轮进程，不碰玩家存档。沙箱AIR存活不等于成功，本环境实机需正常Windows权限。
- 设置值与保存归客户端；宿主管两级菜单、分组、位置记忆和录键。23项快捷键在对应模组菜单修改。
- 本次用户明确授权修改工作区所有文件以统一部署规则；本项目一直缺AGENT_SCOPE.md，权限以根GOVERNANCE为准。

## 3. 当前状态

- 测试登记：共享正本 `shared-knowledge/knowledge-validation/coordination/test-runs.sqlite3`（游戏根相对路径），同名md为自动生成阅读表；SQLite事务防双重放行，game组串行、offline可并行，默认等300秒后暂缓。记录会话/内容/时间/目录/结果/进程身份，中断保留占用并可核对恢复。10项登记检查＋24项调试器回归通过，实际本轮离线验证已登记；未运行AIR游戏。两项技能路由2026-10-20.1已安装、跨会话自动选用与其他驱动迁移待验，见[登记验证](../knowledge/experiments/test-registry-2026-10-20/README.md)。

- 后台桌面修复：tools/air_test_process.py；归因工具已默认接入，桌面策略写入计划/回执，旧计划需重新prepare。24项离线、3项原生进程及2项真实游戏采样/截图通过；确认AIR_Splash只在私有桌面，用户输入桌面未切换。证据见[后台启动验证](../knowledge/experiments/quiet-tests-2026-10-19/README.md)。两项调试技能路由2026-10-19.2已同步；其他旧驱动仍须按说明接入。

- 调试器入口tools/agent-debug.ps1，Python标准库＋src/debugger/AgentDebugProbeMod.as；仅在独立app ID及匹配计划下启动。精确选组全经启动器；冻结副本、固定依赖、基线/完整/逐个排除/可选单开、反序重复。性能与视觉分进程，输出帧间隔、内存、加载证据、截图和有上限的显示树。只支持1.02。
- 离线23项通过；两轮合成卡顿/色块12/12有效，排除后P95下降66/72ms，4张图实际复核；实际宿主/基线新档2/2、最终快照1/1、模板读档3/3通过。当前探针3999B、SHA3563828F…A3699A，未部署进正式release。证据与已修正失败见[本轮记录](../knowledge/experiments/debugger-2026-10-19/README.md)。
- remains-runtime-debug及remains-auto-testing已接入启动器/调试器路由，版本2026-10-19.1；手工前言审查、引用和指纹回读通过（selfcheck缺PyYAML，不报自动静态通过）。独立新会话自动选用待验；未改AGENTS/GOVERNANCE。

- 启动器1.0.0：C05B4C23…45F9590；配套扫描器：8FA18398…C0D33C1。完整指纹及工具备份见[安装回执](../knowledge/experiments/launcher-2026-10-18/installation.json)。两者都在本模组根目录可双击。
- 选择与有效开关同存mods/loader-manifest.txt，选择用 `# selection|...` 注释。兼容限制与缺包只屏蔽实际加载。新版扫描器保留选择，旧版会重置。保存备份、检测外部变更、互斥写入。
- 核心/真实控件38项、CLI23项、扫描器与加载器离线回归通过。1.02真实单开ModLoader、单开TDFC、全停三场景通过，禁用项无请求，重复启动拒绝。只读扫描15包、原名单启用14包。
- 游戏内正式SWF仍24865B，SHA256 BD71B6F31774B97841D4C158451DA0353B53BC46AC72F8E2A7FE2C3F3F4908B1。keybindVersion=1，旧接口兼容。2026-10-15七客户端23项正式组合175＋171、公共独立及回读各39项通过，见[改键记录](keybind-integration-2026-10-15.md)。
- master直提；任务前已有supported-mods.txt的PermanentInjury登记未提交，保留并排除本轮。EXE/build/out沿用忽略策略，源码与稳定证据入库。

## 4. 正在进行与卡点

本地启动器与调试器完成；未上传GitHub或更换公开ZIP，无待用户批准步骤。后续遇真实问题先明确症状与场景，通过完整组合复现后再跑候选，不把合成夹具成功当真实故障已归因。

## 5. 已知边界

- 新界面中文，已查看本机200% DPI默认/最小窗口；未验其他DPI、多显示器或真人完整操作。
- 扫描只检顶层release包与文件头，不证明入口、依赖或跨版本兼容；未知包明确提示。三实机场景不等于全部玩法/组合认证。
- “仅启用”严格只开所选项；需要统一设置菜单须同时选ModLoader。旧ModSettings项目及本机登记已移除；兼容接口/存储名保留，恢复历史包前必须补禁用登记，禁止两宿主并开。
- 导出选择/指纹不是运行成功证据，实际加载继续查本轮loader session的requested/ok/err。
- 清单顺序只决定发起请求先后，初始化异步；同步失败不阻止其他请求，不保证任意异步错误隔离。
- 设置模块和本轮实机只验证1.02；保留既有联机、战斗及各模组玩法边界。
- 调试器测stage帧事件间隔而非每模组独占CPU/显示器呈现帧；差异排名仅相关性。场景签名不固定RNG/AI/输入，GPU画面可能不进入软件截图；树有截断标记。后台调度与依赖缺失需另排除。
- 可选--export-save用公开saveGame(-2)写隔离槽位0诊断快照；从菜单用newGame(slot)读档，getSave检查空槽，禁止访问internal saveArr。示例模板在开场字幕，不是战斗场景认证。

## 6. 回滚与下一步

- 双击RemainsModLauncher.exe → 勾选 → 保存并启动；先退出已有游戏。Agent参数见[说明](../docs/LAUNCHER.zh-CN.md)。
- 工具回退备份work/backups/before-launcher-20261018-2216/RemainsModScanner.exe。恢复旧工具前保留名单，旧扫描器会重置选择。组合回退用work/manifest-backups/。
- tools/build_launcher.ps1只输出build/out/launcher；UI/core、CLI、scanner、loader、runtime检查入口见说明。SWF仍用build/build.ps1构建，上线另走门禁。
- Agent先看[归因操作说明](../docs/AGENT-DEBUGGING.md)，用inventory→prepare→先run完整组合→其余对照→report/verdict。首次/源码变化先tools/build_debugger.ps1。运行证据不覆盖，改输入重新prepare；任务结束保留证据后按准确路径清理自己的副本/存储。
- 技能回退先核对当前内容，再参考knowledge/experiments/debugger-2026-10-19/workflow-install.json与work/debug-workflow-backup-20261019，勿覆盖后续版本。
- 公共改键与六客户端回退用[2026-10-15记录](keybind-integration-2026-10-15.md)，不要用旧分组备份覆盖较新功能。

## 7. 深入了解

- [部署规则回执](local-deployment-policy-2026-10-19.md)、[旧ModSettings移除回执](modsettings-retirement-2026-10-19.md)。
- [启动器证据与失败记录](../knowledge/experiments/launcher-2026-10-18/README.md)、[使用与CLI](../docs/LAUNCHER.zh-CN.md)。
- [菜单改键接入](keybind-integration-2026-10-15.md)、docs/keybind-interface-v1.md。
- docs/settings-interface.md、design/grouped-settings.md；历史knowledge/experiments/grouped-settings-2026-09-24.md及settings-merge-2026-09-24.md。
- [10-14合集](collection-2026-10-14.md)、[10-08公开玩家文档](github-player-guides-2026-10-08.md)、[10-03多语言](localization-2026-10-03.md)。
