# Agent 模组归因调试器

入口为 `tools/agent-debug.ps1`，使用现有 `RemainsModLauncher.exe` 扫描与选择。它会复制游戏资源与待测模组，冻结文件指纹，自动运行基线、完整组合、逐个排除的对照。正式名单、游戏 SWF 和玩家存档不被修改。当前支持根目录 `pfe.swf` 的 1.02。

## Agent 从这里开始

ModLoader 2.5.0 起可保留正常游玩最近约5分钟的帧率/场景记录。游戏中记录留在内存，正常退出时保存；强退/崩溃不会保存本轮。用户报告卡顿时，先按 [FRAME-RECORDER.md](FRAME-RECORDER.md) 导出并核对时段、房间、坐标和焦点状态，再做隔离对照。同时出现的状态仅作线索，不能直接给模组定责。

运行游戏前先刷新[测试情况登记表](../../../shared-knowledge/knowledge-validation/coordination/test-runs.md)：`tools/agent-debug.ps1 tests`。1.0.2 起 `run` 自动登记并等待其他游戏测试释放占用；`--owner` 可写模组/任务名，`--wait 300` 默认最多等待5分钟。占用冲突先等待或暂缓，无需为了常规测试打断其他对话。专用驱动与中断恢复见[登记说明](TEST-REGISTRY.md)。

1. 明确现象、复现位置/动作及“异常消失”的可观察标准。没有具体复现场景时，菜单/新档结果只能验证工具与提供探索线索。
2. 用启动器只读扫描，记录当前启用组合与入口类名；依赖放在 `--fixed`，待排查模组放在 `--mods`。不要用旧扫描器覆盖选择，也不要靠移动、改名 SWF 禁用模组。
3. 先在隔离副本验证完整组合确实复现症状，再执行对照。每个试验均有唯一 AIR ID 和全新存储；需要旧进度时传入只读复制的存档模板。不要对真实 `pfe` 存储做写入实验。
4. 看有效性，再看候选排名。加载失败、缺少依赖、场景变化、焦点切换和超时不是性能改善；无效试验禁止参与排名。
5. 看截图并标记同一具体症状，必要时读显示树差异和当前试验日志。显示路径/类名只是定位线索，不能直接断言所属模组。
6. 对候选重复“移除→恢复”，用单开或更小组合验证。保留依赖、同一存档/输入/位置、相同窗口策略；分别写出单模组异常、组合交互、尚未排除的环境因素。移除后变好不自动证明模组有 bug。

## 命令

下列命令从 `mods/ModLoader` 执行。PowerShell 的示例以 `powershell -File` 启动包装脚本，避免 `exit` 关闭调用者的交互终端。Python 3.10+、Windows AIR 和已有启动器是运行依赖；无第三方 Python 包。包装脚本优先 `REMAINS_DEBUG_PYTHON`，再检测 Python 与本机 Codex 运行时。

```powershell
# 只读清点，等价于启动器 --list --json --no-ui
powershell -NoProfile -ExecutionPolicy Bypass -File tools/agent-debug.ps1 inventory

# 首次使用或探针源码变化时构建；只输出 build/out，不部署进正式 release
powershell -NoProfile -ExecutionPolicy Bypass -File tools/build_debugger.ps1

# 示例：把设置宿主固定，比较两个模组及它们的组合（替换为本次怀疑对象）
powershell -NoProfile -ExecutionPolicy Bypass -File tools/agent-debug.ps1 prepare --mods RealisticVisionMod,TDFCMod --fixed ModLoaderMod --singles --repeats 3 --scenario new-game

# prepare 输出 session 路径。先跑一条或指定完整组合以检查是否复现
powershell -NoProfile -ExecutionPolicy Bypass -File tools/agent-debug.ps1 run --session "<session路径>" --trial perf-01-full
powershell -NoProfile -ExecutionPolicy Bypass -File tools/agent-debug.ps1 run --session "<session路径>" --trial visual-01-full

# 继续余下试验；已产生证据的试验不会覆盖
powershell -NoProfile -ExecutionPolicy Bypass -File tools/agent-debug.ps1 run --session "<session路径>"
```

`--mods current`（默认）使用当前启用组合；全部模组逐项排除耗时较长，已有嫌疑时优先小范围。`--singles` 加入“固定依赖＋单个待测模组”，用于区分单开与组合故障。`--fixed` 始终开启，基线也包含它们；探针始终开启用于测量。

`--mode perf|visual|both` 默认 both。性能与截图使用不同进程；默认预热 8 秒、测量 15 秒、3 轮，每轮交替正反顺序。`--warmup`、`--seconds`、`--timeout` 可按场景调整；卡死由外部看门狗结束自己持有的进程。1.0.1 起，默认把整个 AIR 测试进程放到独立 Windows 桌面，游戏窗口及 HARMAN/AIR 启动图均不会出现在用户桌面；测试结束关闭进程句柄与临时桌面，不切换用户桌面。需要原生画面或玩家操作时显式使用 `--visible`，该模式仍会显示运行时启动图，所有对照必须保持同样设置。旧计划须重新 prepare，避免把不同桌面策略的性能数据混用。不要在测量中切换焦点、截屏或同时跑其他性能试验。

独立桌面创建失败会报错，绝不自动改用前台启动。Codex 受限环境可能拒绝创建桌面，应通过当前客户端正常权限流程运行本机测试。隔离桌面影响窗口焦点与调度，结果不代表玩家前台帧率；软件截图仍由游戏探针生成，原生显卡画面需可见模式另验。工具不修改 AIR DLL、许可、游戏 SWF、系统电源计划或其他游戏进程。

专用 Python 驱动可从 `tools/air_test_process.py` 导入 `HiddenProcess`，沿用 `poll/wait/kill/close` 管理自己的进程；先停止并等待退出，再 `close()`。其他驱动可直接使用以下入口，**前提仍是独立游戏副本、唯一 AIR ID 和已选好的模组组合**：

```powershell
python tools/air_test_process.py --cwd "<隔离游戏目录>" --timeout 120 -- "<隔离游戏目录>/adl64.exe" -runtime "<隔离游戏目录>/runtimes/air/win64" "<隔离游戏目录>/application-test.xml"
```

该入口只隔离窗口，不创建游戏副本或隔离存档，也不会自动改造旧脚本。旧驱动直接运行 ADL 或调用启动器 `--launch` 仍可能弹出启动图，后台验证前应接入本入口。实际窗口归属、帧采样与截图证据见[后台启动验证](../knowledge/experiments/quiet-tests-2026-10-19/README.md)。

### 从存档复现

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/agent-debug.ps1 prepare --mods RealisticVisionMod,TDFCMod --fixed ModLoaderMod --scenario load --seed-store "<存档模板的Local Store目录>" --slot 0 --repeats 3
```

传入实际 `Local Store`，工具冻结模板，再为每条试验复制；不会写回模板。从主菜单用 `newGame(slot, "LP", null)` 的正常读档路径建游戏骨架，不先开新档清空槽位。空槽位直接失败。存档之外的动态输入、随机数、敌人行为并未录制/重放；需要战斗、传送或特定触发动作时沿 `remains-auto-testing` 建立专用驱动，不将静止采样冒充完整复现。

需要自建固定进度模板时，对 `--scenario new-game` 加 `--export-save`；采样结束后用游戏的 `saveGame(-2)` 强制自动保存分支将诊断快照写入隔离槽位 0，驱动再检查存档文件落盘（教程对话中普通保存可能静默拒绝）。查看原始结果的 `seedExport`，成功后再把该试验的 `storage/` 作为后续 `--seed-store`。这是采样后的诊断快照，不是输入回放；仅存在于隔离存储。

### 视觉复核

用 `view_image` 看报告链接中的完整组合与排除后图片；记录相同位置的具体缺陷，而非笼统“画面不同”。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/agent-debug.ps1 verdict --session "<session路径>" --trial visual-01-full --value bad --note "角色左侧遮罩残留；位置……"
powershell -NoProfile -ExecutionPolicy Bypass -File tools/agent-debug.ps1 verdict --session "<session路径>" --trial visual-01-without-RealisticVisionMod --value good --note "同一位置残留消失；其他效果变化不计为缺陷"
powershell -NoProfile -ExecutionPolicy Bypass -File tools/agent-debug.ps1 report --session "<session路径>"
```

证据不足填 `unknown`。至少两轮有效、场景签名匹配且 full=bad / without=good 才列为“已复核的移除相关性”；仍需加回和组合验证。异常只在真实窗口/显卡效果中出现时，软件截图可能遗漏，需另用获授权的屏幕捕获方式；不要因截图正常判定游戏正常。

## 报告与判断边界

会话在 `build/out/debugger/<时间-随机号>/`，`report.md` 供阅读，`summary.json` 供 agent 处理。每条试验保存：

- `selection.json`：启动器导出的选择及包指纹；**不是加载成功证明**。
- `meta.json` / `plan.json`：PID、唯一应用ID、时间、场景和所选组合；meta 另记运行器版本、桌面策略与本轮桌面名称。
- `storage/agent-debug/result.json`：本轮 loader session、requested/ok/err、场景、内存和原始帧间隔。
- `frames.csv`：性能样本；报告含均值、P50/P95/最大值、>50/100ms 次数及 >50ms/秒。
- `storage/agent-debug/frame.png`、`tree.json`：独立视觉试验截图与有数量上限的显示树；`comparisons/` 保存变化路径、类名、位置、透明度、遮罩等线索。
- `storage/`：测试实例的存档与模组日志副本；日志可能很大，定向读关键字。ADL 标准输出和错误输出也会保存。

P95 规则只是排序启发：至少两轮成对比较，每轮移除后下降≥5ms 且≥20%。没有命中不等于模组没有问题（低频卡顿、依赖冲突、特定动作可能未覆盖）。帧事件间隔不是模组独占 CPU，也不是显示器真实呈现帧率；内存变化含垃圾回收等因素。场景签名只排除明显差异，不能保证随机数/AI/玩家输入一致。新档的随机场景对照属于探索结果。

后台调度、其他进程和窗口状态可能造成卡顿；涉及 Windows 背景 QoS 时参考 KB-000071 的条件做单独对照，不据此默认改全机设置。测量和截图分进程来自 KB-000056 的已验证经验。

所有组合使用同一冻结输入；文件变化会停止后续运行。失败试验不覆盖，修复后重新 prepare。运行中断会留下 `run.lock`，先核对 `meta.json` 对应进程确已退出，再移除该锁。不要用进程名批量结束游戏。

## 启动器本身的调试用法

玩家可直接双击 `RemainsModLauncher.exe`。Agent 只读查看正式安装：

```powershell
& .\RemainsModLauncher.exe --list --json --no-ui
```

在已经具备独立 AIR ID 的测试副本中，可用 `--root <副本> --only AMod,BMod --no-ui --report <新文件>` 保存精确组合，再启动同一副本。`--none` 全停，`--dry-run` 预览；需要设置菜单时明确加入 `ModLoaderMod`。调试器按此流程选择，再直接持有 ADL 进程句柄以执行超时清理；不绕过启动器重写清单。`--root` 本身不隔离存档，不能单独当作隔离保证。更多参数见 [启动器说明](LAUNCHER.zh-CN.md)。

## 开发验证

`build/tests/test_debugger.py` 覆盖过期日志、禁用项偷载、失败初始化、场景/焦点变化、输入变化、成对排名等负例。`tools/build_debugger.ps1 -WithFixture` 仅在 build/out 生成测试包 DebugFaultMod：故意每帧阻塞约85ms并添加紫色色块。用 `prepare --mods DebugFaultMod --extra-mod build/out/debugger-tools/DebugFault` 在私有副本验证，绝不部署到正式 mods/release。实测记录见 [调试器验证](../knowledge/experiments/debugger-2026-10-19/README.md)。
