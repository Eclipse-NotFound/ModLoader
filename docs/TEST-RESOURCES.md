# 测试资源与玩家并行

2026-10-27，调试器 1.1.0。玩家照常双击 `RemainsModLauncher.exe`；agent 在副本里测试，两边无需轮流退出。

## agent 入口

从游戏根运行（实际 Python 由现有 PowerShell 入口查找）：

```powershell
# 一次性查看内存、运行器约束与当前 AIR 实例
& mods/ModLoader/tools/agent-debug.ps1 resources

# 玩家可继续游玩。prepare 返回本轮 session 路径，run 自动登记。
& mods/ModLoader/tools/agent-debug.ps1 prepare --mods ModLoaderMod --profile coexist --mode perf --repeats 1
& mods/ModLoader/tools/agent-debug.ps1 run --session '<prepare 返回的目录>' --trial perf-01-full

# 需要比较性能时使用独立计划；不必为普通功能验证跑完整矩阵
& mods/ModLoader/tools/agent-debug.ps1 prepare --mods AMod,BMod --plan attribution --profile benchmark --mode perf
```

`coexist` 是默认值：保留帧数据、加载断言、视觉结果，帧数据不进入性能排名。`benchmark` 允许受控配对；若试验前后观察到其他 AIR、内存压力、资源设置未确认或快照失败，仍保留功能结果，排除该项性能比较。前后快照不能发现中途短暂负载，没看到其他 AIR 也不证明整机空闲；可靠性能结论仍需相同场景、恢复对照和重复验证。已有旧报告保留当时语义；新计划明确记录 profile。

默认 `--plan smoke --mode perf` 只验证完整选定组合一次；只有指定 `--plan attribution` 才生成基线、逐项排除和重复对照。视觉取证显式用 `--mode visual` 或 `both`。1.0.2 旧计划无法保证静音，运行前会拒绝，须重建探针并重新 prepare；旧报告仍可阅读，不自动改写。

## 隔离范围

- 每个计划有独立文件副本；每次运行随机 AIR ID、独立 Local Store、描述符、模组选择和日志。模组选择仍通过副本里的 `RemainsModLauncher.exe --root ... --only ...`。
- 默认在不可切换的私有 Windows 桌面启动，启动标识、窗口与键盘焦点留在测试桌面。不要用全局按键或鼠标驱动隐藏测试。`--visible` 是主动选择可见调试，会失去这层输入隔离。
- 探针默认将自己 AIR 虚拟机的声音混合器设为零，在开机阶段恢复静音；不改系统音量或玩家实例。采样结束记录 `audioVolume`；`--audio` 明确允许测试声音。非标准模组若自行改混合器或播放外部音频，应单独验证，不能声称桌面已隔离音频。
- 联机专用驱动须给本轮 host/join 单独端口、回环地址和独立配置；不要复制后自动连接玩家房间。普通调试器不代替网络端口隔离，遇到 RConnect 自动 host/join 配置应使用专用驱动。
- 共享登记仅协调 agent 测试组；玩家不申请占用，也不被占用阻止启动。2026-10-29 起，最多两个独立 `coexist` 功能组可并行，其余按申请顺序等待；`benchmark` 与所有 agent 游戏测试互斥。一组受控双实例共用一个登记。只清理自己创建的句柄，恢复时核对 PID 与创建时间。

CPU、GPU、磁盘与物理内存仍共享，无法保证同时运行时帧率完全不受影响。测试不会清理玩家内存、抢前台、改玩家文件或结束别人的进程。

## 内存机制与实现

Windows 按程序需求分配内存，没有给 Remains 预留固定份额。物理可用内存与“还能承诺的内存”是两项指标；后者受物理内存、分页文件及系统承诺量影响，物理空闲较多也可能出现分配压力。[微软分页文件说明](https://learn.microsoft.com/en-us/troubleshoot/windows-client/performance/introduction-to-the-page-file)

`HiddenProcess` 默认先挂起新建子进程，在同一个自有句柄上设置并回读：

1. 内存优先级 **5（Normal）**，这是公开 API 支持的最高值，也是通常默认值。它影响内存紧张时页面被回收的先后，不能保证多分配固定 GB，也不会让游戏高于其他正常优先级程序。[MEMORY_PRIORITY_INFORMATION](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/ns-processthreadsapi-memory_priority_information)
2. 明确关闭该进程的执行节流，即 **HighQoS**，减少隐藏窗口被按后台节能策略降速的风险；保留其他电源标志并记录设置失败。CPU 调度优先级维持 Normal。HighQoS 可能增加功耗，且不保证帧率改善。[SetProcessInformation](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-setprocessinformation)
3. 恢复主线程。资源设置只执行一次，系统快照只在试验前后读取，采样期间不轮询系统进程、不写资源日志。

不设置固定工作集、不锁定物理页、不使用 Realtime/High CPU 优先级、不改变分页文件/全机电源计划，也不降低其他应用的优先级。`--resource-policy system` 可建立未修改策略的对照；对照不被误算为确认过资源策略的性能样本。

`resources` 同时读取运行器是否处在 Windows Job（进程组约束）中，以及能查到的最内层内存上限；不能据此排除不可读的祖先约束。诊断记录放试验 `meta.json`，性能配对边界放 `result.json.environment`。

本机调查与实测见 [2026-10-27 报告](../knowledge/experiments/resources-coexist-2026-10-27/README.md)。

## 入口文件权限标签

本机游戏目录会让新复制的 EXE 继承低完整性标签，使普通用户启动的程序降到受限级别；曾因此出现原启动器无法写临时文件、AIR 初始化失败。2026-10-29 已仅修复原启动器、根 ADL 和两个模组工具入口的标签，字节内容及原有访问授权不变，没有递归修改目录权限。

共享 `HiddenProcess` 与调试器对测试入口做只读检查。低标签的 ADL 副本仅在位于本工作区且 SHA-256 与根 ADL 完全一致时，借用根目录已修复的同版本宿主；描述符、运行库参数、工作目录、独立应用 ID 和存储均保持原测试值，并记录 `launchHost` / `launch_info`。不同版本明确拒绝替换；工具不自动改标签或提高权限。运行器本身受限时须通过客户端正常审批路径执行。未来替换正式 EXE 后应重新核对其标签，不能只检查哈希。

## 空间策略（2026-11-02，调试器 1.2.0）

2026-11-02 前，每个试验持有完整文件副本；RConnect、ContinuousScene、RealisticVision 三个模组的 `build` 累计约 176 GB，D 盘一度只剩 6 GB。1.2.0 起：

- `prepare` 对不变资产（Music、Rooms、runtimes、根目录资源 SWF/XML、模组 release、ModLoader 宿主工具）使用**硬链接**，链接失败自动回退为复制；session.json 的 `assetStorage` 记录实际 link/copy 数。可写状态（试验描述符、AIR 存储、seed）始终是真副本。实测单个 smoke 会话从约 298 MB 降到 0.1 MB 实占。
- 硬链接安全依赖**替换语义部署**：更新游戏本体或 release 时必须"写新文件后替换"，禁止原地写入既有文件，否则会同时改动玩家文件与所有链接副本。`verify_inputs` 在每次 run 前复核冻结输入哈希，漂移即拒绝并要求重新 prepare。
- `prepare` 自动清理闲置超过 14 天的调试器自有会话；`agent-debug.ps1 sweep --dry-run` 可预览，`--no-sweep` 跳过。带 `run.lock`（运行中或待核查）的会话一律保留。
- 各模组自建试验目录（`mods/<Mod>/build/...`）不归调试器管理：用 `tools/cleanup_test_copies.py` 清理——`plan` 只把"与游戏根/各 release SHA256 完全相同"或"build 内字节级重复"的文件列入计划，审查 plan.json 后 `apply --confirm` 删除；git 跟踪文件、测试登记表出现的目录、48 小时内写入的子树与回退备份一律不动。
- `cleanup_test_copies.py check` 巡检配额：任一模组 build 超 10 GB 或 D 盘空闲低于 50 GB 时告警。运行时副本是临时数据：结果、报告和关键截图随跑归档进 knowledge，本体副本不作为证据长期保留。
