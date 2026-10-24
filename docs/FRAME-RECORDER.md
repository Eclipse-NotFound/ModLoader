# 轻量帧率与游戏状况记录

ModLoader 2.5.0 内含 FrameRecorder 1.0.0。通过 `RemainsModLauncher.exe` 启用 ModLoader 后重启游戏即可记录，无悬浮窗、快捷键或额外常驻进程。`release/telemetry.json` 的 `enabled` 设为 `false`，重启后停用；缺省开启。坏配置或采样异常只停用记录器，不阻断设置或其他模组。

## 玩家使用

照常游玩；卡顿出现后及时正常保存并退出游戏，留下最近约五分钟的记录，再让 agent 分析。游戏中仅保留内存记录，**正常退出才保存文件；崩溃、强制结束或保存失败会丢失本轮记录**。再次启动不会立刻清除上次文件，因此分析时必须核对会话时间。

记录包括帧事件间隔、地区/房间/坐标、暂停/菜单/焦点/错误界面、AIR 内存、单位/物体/手雷数组长度和加载器状态。不采集键鼠内容、截图或存档内容，不联网。长时间无响应只有恢复到下一帧后才留下长帧证据；永远卡死无法从内存导出。

正式路径：`%APPDATA%\pfe\Local Store\frame-recorder\frames-v1.jsonl`，应用 ID 以根 `application.xml` 为准。隔离测试副本使用独立 ID。

## Agent 操作

在 `mods/ModLoader` 执行，只读文件，不启动/附加/强退游戏：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/frame-recorder.ps1 report
powershell -NoProfile -ExecutionPolicy Bypass -File tools/frame-recorder.ps1 report --json --output "<本轮证据目录>/frames.json"
powershell -NoProfile -ExecutionPolicy Bypass -File tools/frame-recorder.ps1 report --log-dir "<Local Store>/frame-recorder" --json
```

1. 核对 `session/from/to` 是否覆盖用户所述时段；保存原始目录及当时启动器 `--list --json` 和模组指纹。`loaded` 仅表示初始化成功，不证明后续功能正常，也不是准确版本清单。
2. 摘要列出最大间隔的12个窗口；JSON 的 `worstWindows[].stalls` 给出长帧结束时间、间隔和发生后的房间/坐标。表格坐标是窗口末尾位置。每窗保留前4次长帧位置；总长帧数、最大间隔和遗漏标记数仍完整统计。
3. 比较场景切换、焦点、暂停、内存及对象数量。内存下降仅与回收相符，不能据此认定 GC；数组长度不等于可见数量或渲染成本。日志只能提供线索，不能直接给某个模组定责。
4. 按[归因流程](AGENT-DEBUGGING.md)登记测试，用启动器固定组合，在相同位置/存档/焦点下做移除与恢复对照。性能采样和截图分轮运行。按[共享登记说明](TEST-REGISTRY.md)自行等待占用，无需逐个打断其他对话。

`--output` 拒绝覆盖旧证据。读取有大小上限，异常批次跳过并警告；`.pending` 是未提交文件，不当作完整证据。读取工具兼容本轮早期候选的 ring/chunk 文件，仅用于历史实验证据。

运行中已授权的游戏内探针可以按需读取 `main.getChildByName("ModSettingsCarrier").frameRecorder.status()`。字段包括 `active/reason/samples/bufferedSamples/selfPeakMs/overBudgetEvents/mode`。`writes` 在游玩阶段始终为0；正常退出保存后增加，`exportMs/exportError` 属于退出保存诊断。报告内状态在实际写入前采集，不能将其 writes=0 当作导出失败。不要为读取状态另起高频监控。

隔离开销对照可调用同一接口 `setSampling(false/true)`；仅能暂停/恢复健康记录器，配置关闭或故障停用不能强行恢复。暂停丢弃当前不足一秒的窗口并计入 `droppedSamples`，已有完整记录保留。`clockOriginMs` 用于与同进程 `getTimer()` 对齐；绝对时间为 `startedEpochMs + endMs`，不依赖游玩期间系统时钟调整。

## 资源与开销约束

- 普通帧一次计时、更新计数；每秒一次状态摘要；每窗最多4次长帧位置。无世界/显示树遍历，无 UI，无强制 GC，不修改帧率、随机数、输入或游戏对象。
- 慢帧阈值 `max(50 ms, 1.5 × 目标帧间隔)`；长帧阈值 `max(100 ms, 3 × 目标帧间隔)`。FPS 是 `ENTER_FRAME` 到达率，不是显示器呈现率或模组独占 CPU 用时。
- 固定300个窗口的内存环，通常约5分钟，严重卡顿时覆盖更久。窗口标记、标识字符串均有界；运行中不做 JSON 序列化或文件读写（启动仅读一次最多4096字节配置）。内存对象仍有分配与回收成本。
- 正常退出事件同步保存，最多60批，每批5窗、16000字符，UTF-8 最多64000字节。先写单个 `.pending` 再替换 `.jsonl`；最多两份文件，合计不超过7.68 MB。失败不弹窗、不阻止退出，旧提交文件保留。退出保存可能增加短暂关闭耗时。
- 同时监听窗口 `closing/close` 与应用 `exiting`，不取消退出、不改退出码；重复事件按序号去重。本机实测直接 `NativeApplication.exit()` 未收到预期窗口关闭事件，专用驱动必须在结束计量后先调用 `frameRecorder.saveForExit()` 再退出；已有 AgentDebugProbe 已接入。不得把保存接口放进游玩中的采样循环。
- 单次采样观测耗时达到20 ms，或60秒内3次达到4 ms即自动停采，已有记录仍可退出保存。这是事后退让，不能撤销已发生的耗时。`selfPeakMs` 是毫秒级墙钟观测，受系统调度影响，不是精确 CPU 成本。

完全零开销不能保证。实测范围、失败候选、最终对照及安装回执见[验证记录](../knowledge/experiments/frame-recorder-2026-10-24/README.md)。
