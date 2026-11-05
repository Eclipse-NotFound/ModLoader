# ModLoader 外置记忆

> **2026-11-05 GitHub 公开**：本仓库已开源到 https://github.com/Eclipse-NotFound/ModLoader（默认分支 `master`，MIT 许可证），发布 tag `v2.5.0` 与 Release 资产 `ModLoader_v2.5.0.zip`（正式版）。由同步会话执行；未运行游戏、未改 `release/` 下已部署产物。

2026-11-04：修复测试HARMAN启动图的遗漏入口。新增 `tools/Invoke-AirTest.ps1`，共用smoke/分发/语言验证及五个近期RV测试接入独立桌面；Python支持子进程env。8项原生/桥接检查及两轮真实AIR验证通过，启动图只在私有桌面、用户桌面不切换。游戏/玩家入口未改；历史独立实验脚本未全量迁移。见[证据与回退](../knowledge/experiments/quiet-tests-2026-11-04/README.md)。

2026-11-02：调试器1.2.0应对build堆积（三活跃模组累计约176 GB、D盘剩6.2 GB）。不变资产改硬链接冻结（smoke实测297.7MB→实占0.1MB，link:101/copy:0），可写状态仍真副本；安全性依赖替换语义部署，verify_inputs每次run前复核。新增`sweep`子命令（prepare自动清闲置>14天会话，run.lock保留）。新增`tools/cleanup_test_copies.py`（plan→apply --confirm→check），按用户拍板只删"与游戏根/release SHA256相同"或"build内字节级重复"副本；首轮删20.8万文件/67.4 GiB，D盘回到约73 GB。RV/CS `.gitignore`追加`/build/`整体忽略。空间策略见[TEST-RESOURCES.md](../docs/TEST-RESOURCES.md)；各模组自带runner的输出根迁移留待其正常迭代。

2026-10-29：原启动器与共享测试路径已修复并本机部署。四个EXE入口继承Low标签导致受限启动；仅恢复为Medium，内容/DACL不变。默认功能计划现在最多两个独立组并行，性能与旧驱动仍独占，FIFO排队900秒；受管进程全部确认退出且无启动间隙时自动释放占用。68项定向检查、两AIR各39项及两个独立CLI真实菜单同时运行通过。详见[修复、证据与回退](../knowledge/experiments/startup-test-path-2026-10-29/README.md)。工具协议仍1.1.0，SWF/正式名单未改。

> 2026-10-28 分盘精简：本模组 1213 个历史副本文件（3.197 GiB）经逐文件核验后转入 F 盘；源码、release、共享工具及当前验证材料保留。查位置与恢复方法见 [archive-index.md](archive-index.md) 和[本轮记录](../../../archive/migrations/2026-10-28-01/report.md)。旧测试副本需复现时先按归档原路径恢复。

2026-10-26必要共享登记器修复（ContinuousScene会话明确授权）：`tools/test_registry.py`在OpenProcess拒绝访问时只读CIM创建时间，处理旧PID被受保护系统进程复用；失败仍unknown、同一进程不误释放。15项完整回归通过，原占用在系统进程自行退出后由原recover释放；未改SWF/名单。详见[证据与回退](../knowledge/experiments/test-registry-2026-10-26/README.md)。

> 2026-10-25 历史资料已核验转存：A01、B04、B05，共2,868文件、原始显示5.84 GiB。查找与恢复从 [archive-index.md](archive-index.md) 进入；[本次结果](../../../archive/migrations/2026-10-25-01/report.md)。当前正式包、源码、作品及保留证据未纳入。

更新：2026-10-27。运行模块仍2.5.0/settings0.5.0、FrameRecorder1.0.0、启动器1.0.0。调试器1.1.0已本机启用：自有测试内存优先级5＋HighQoS、静音、默认单次smoke与coexist；按需attribution/benchmark。50项定向检查、双实例12项断言和最终单条菜单冒烟通过。见[资源/并行/规则报告](../knowledge/experiments/resources-coexist-2026-10-27/README.md)。

## 1. 这个模组是什么

MainFE清单引导v2、Windows扫描器/选择启动器、游戏内设置模块。新入口RemainsModLauncher.exe；源码src/ModLauncher.cs与src/ModScanner.cs。运行模块源码src/runtime、src/settings，部署点release/ModLoaderMod.swf；不从旧ModSettings项目构建。

## 2. 用户偏好与协作约定

- 2026-10-27用户要求调查测试内存分配、允许玩家与agent并行，并纠正过严规则。本机公开最高内存优先级为默认5，无固定游戏配额；显式HighQoS只作用于自有测试。玩家无需退出或申请登记；仍共享CPU/GPU，并行数据不作性能排名。默认只跑完整组合一次；当前测试探针4793B，SHA256 CE82C8FF07DB8A1EBF1932127FE849FBA10C00B26ECD10D88377A4BE840DDBB9。旧1.0.2计划须重建探针/重新prepare。规则按风险验证，复用匹配证据，不要求全仓干净。见[使用入口](../docs/TEST-RESOURCES.md)。

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

- 2026-10-28 Mem Reduct 可行性调查：本机已安装3.5.2；源码确认命令行默认清理影响全系统，不能排除玩家实例，可能造成重新读盘。调查时物理可用约11.48 GiB、提交余量约10.78 GiB，未见须清理的证据。建议不接入每轮测试前自动清理；实际收益尚未A/B验证。本轮只读调查，未运行清理/改配置，来源及边界见[journal本日条目](journal.md#2026-10-28-mem-reduct测试前清理可行性调查)。

- 轻量记录器已完成：[使用说明](../docs/FRAME-RECORDER.md)。启动器启用ModLoader并重启，默认保留约5分钟的帧事件、长帧时刻、房间/坐标、内存与状态。游戏中不序列化/写盘，正常退出保存；强退/崩溃丢失本轮。卡顿排查先 report 并核对时段，再用既有启动器/调试器隔离对照。
- 验证：47项离线、6项游戏场景及正式回读第7轮通过。同进程ABBA mean差−0.1645 ms/P95差+1 ms；520秒采样、自身峰值1 ms、环300窗、游玩写盘0。负差不表示提速，不承诺零开销或全模组战斗认证。退出保存约0.2秒。见[报告与安装回执](../knowledge/experiments/frame-recorder-2026-10-24/README.md)。

- 测试登记：共享正本 `shared-knowledge/knowledge-validation/coordination/test-runs.sqlite3`，同名md自动生成。当前`game-coexist`最多两组且目录不能重合，`game`与所有游戏组互斥，`offline`可并行；FIFO最多等900秒。`Registration`默认受管，必须逐个登记启动与子进程；旧未接入协议调用用`managed=False`。完整API见[登记说明](../docs/TEST-REGISTRY.md)。初版记录见[2026-10-20验证](../knowledge/experiments/test-registry-2026-10-20/README.md)，本轮68项与真实双菜单通过。

- 后台桌面修复：tools/air_test_process.py；归因工具已默认接入，桌面策略写入计划/回执，旧计划需重新prepare。24项离线、3项原生进程及2项真实游戏采样/截图通过；确认AIR_Splash只在私有桌面，用户输入桌面未切换。证据见[后台启动验证](../knowledge/experiments/quiet-tests-2026-10-19/README.md)。两项调试技能路由2026-10-19.2已同步；其他旧驱动仍须按说明接入。

- 调试器入口tools/agent-debug.ps1，Python标准库＋src/debugger/AgentDebugProbeMod.as；仅在独立app ID及匹配计划下启动。精确选组全经启动器；冻结副本、固定依赖、基线/完整/逐个排除/可选单开、反序重复。性能与视觉分进程，输出帧间隔、内存、加载证据、截图和有上限的显示树。只支持1.02。
- 离线23项通过；两轮合成卡顿/色块12/12有效，排除后P95下降66/72ms，4张图实际复核；实际宿主/基线新档2/2、最终快照1/1、模板读档3/3通过。当时探针3999B、SHA3563828F…A3699A，未部署进正式release。证据与已修正失败见[本轮记录](../knowledge/experiments/debugger-2026-10-19/README.md)。
- remains-runtime-debug及remains-auto-testing已接入启动器/调试器路由，版本2026-10-19.1；手工前言审查、引用和指纹回读通过（selfcheck缺PyYAML，不报自动静态通过）。独立新会话自动选用待验；未改AGENTS/GOVERNANCE。

- 启动器1.0.0：C05B4C23…45F9590；配套扫描器：8FA18398…C0D33C1。完整指纹及工具备份见[安装回执](../knowledge/experiments/launcher-2026-10-18/installation.json)。两者都在本模组根目录可双击。
- 选择与有效开关同存mods/loader-manifest.txt，选择用 `# selection|...` 注释。兼容限制与缺包只屏蔽实际加载。新版扫描器保留选择，旧版会重置。保存备份、检测外部变更、互斥写入。
- 核心/真实控件38项、CLI23项、扫描器与加载器离线回归通过。1.02真实单开ModLoader、单开TDFC、全停三场景通过，禁用项无请求，重复启动拒绝。只读扫描15包、原名单启用14包。
- 正式运行模块2.5.0/28418B，SHA256 2050E023205E87FDFDF7FBA4B54B9BAD7769868E51767D0BFBE1742CDC7542E2。keybindVersion=1；设置源码仅增加frameRecorder接口，未改业务行为。2.4.0历史七客户端23项改键验证见[2026-10-15记录](keybind-integration-2026-10-15.md)。
- master直提；任务前已有supported-mods.txt的PermanentInjury登记未提交，保留并排除本轮。EXE/build/out沿用忽略策略，源码与稳定证据入库。

## 4. 正在进行与卡点

原启动器已实测显示主窗口；测试复制的低标签ADL由共享工具只读核对后复用完全同字节的根宿主，保留独立描述符/库/存储。不同版本不自动替换，运行器受限须走正常客户端审批；未来重新复制/更新EXE要复核标签。两个独立运行器的真实双菜单通过，不等于所有旧专用驱动已自动迁移；旧私有工具副本仍应导入正式工具。ContinuousScene镜头候选性能仍未验，本轮只恢复基础设施。

本地启动器与调试器完成；未上传GitHub或更换公开ZIP，无待用户批准步骤。后续遇真实问题先明确症状与场景，通过完整组合复现后再跑候选，不把合成夹具成功当真实故障已归因。

## 5. 已知边界

- 记录器只提供时段/位置及相关状态，不直接认定责任模组。配置关闭、超预算停采、异常退出或保存失败可能没有本轮日志；必须核对会话时间。程序化直接exit的驱动须先调用frameRecorder.saveForExit()，现有探针已接入。

- 新界面中文，已查看本机200% DPI默认/最小窗口；未验其他DPI、多显示器或真人完整操作。
- 扫描只检顶层release包与文件头，不证明入口、依赖或跨版本兼容；未知包明确提示。三实机场景不等于全部玩法/组合认证。
- “仅启用”严格只开所选项；需要统一设置菜单须同时选ModLoader。旧ModSettings项目及本机登记已移除；兼容接口/存储名保留，恢复历史包前必须补禁用登记，禁止两宿主并开。
- 导出选择/指纹不是运行成功证据，实际加载继续查本轮loader session的requested/ok/err。
- 清单顺序只决定发起请求先后，初始化异步；同步失败不阻止其他请求，不保证任意异步错误隔离。
- 设置模块和本轮实机只验证1.02；保留既有联机、战斗及各模组玩法边界。
- 调试器测stage帧事件间隔而非每模组独占CPU/显示器呈现帧；差异排名仅相关性。场景签名不固定RNG/AI/输入，GPU画面可能不进入软件截图；树有截断标记。后台调度与依赖缺失需另排除。
- 可选--export-save用公开saveGame(-2)写隔离槽位0诊断快照；从菜单用newGame(slot)读档，getSave检查空槽，禁止访问internal saveArr。示例模板在开场字幕，不是战斗场景认证。

## 6. 回滚与下一步

- 本轮运行模块回退点：work/backups/before-frame-recorder-20261024-123652/，精确目标和指纹见本轮installation.json。先安全退出游戏，核对正式文件仍为本轮2050E023…7542E2，再恢复；勿覆盖新版本。enabled=false并重启可仅停用记录。

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
