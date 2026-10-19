# Remains 模组归因报告

完成 12/12；有效 12。

测量的是游戏帧事件间隔，不是每个模组的独占耗时。逐项排除只产生相关线索；单开、恢复原组合和相同症状复测后再判断。

场景：menu；固定依赖：无。未固定随机数/AI；隐藏窗口的后台调度仍可能影响结果。

| 排除模组 | 成对比较次数 | P95 中位下降(ms) | 结论 |
|---|---:|---:|---|
| DebugFaultMod | 2 | 69.0 | repeated-removal-association |

| 试验 | 有效 | P95(ms) | >50ms/秒 | 证据/错误 |
|---|---|---:|---:|---|
| perf-01-baseline | True | 38 | 0.6587615283267457 | [原始记录](trials/perf-01-baseline/result.json)  |
| perf-01-full | True | 106 | 10.003226847370119 | [原始记录](trials/perf-01-full/result.json)  |
| perf-01-without-DebugFaultMod | True | 40 | 0.0 | [原始记录](trials/perf-01-without-DebugFaultMod/result.json)  |
| perf-02-baseline | True | 37 | 0.33322225924691773 | [原始记录](trials/perf-02-baseline/result.json)  |
| perf-02-full | True | 111 | 10.025873221216042 | [原始记录](trials/perf-02-full/result.json)  |
| perf-02-without-DebugFaultMod | True | 39 | 0.3299241174529858 | [原始记录](trials/perf-02-without-DebugFaultMod/result.json)  |
| visual-01-baseline | True | — | — | [原始记录](trials/visual-01-baseline/result.json)  |
| visual-01-full | True | — | — | [原始记录](trials/visual-01-full/result.json)  |
| visual-01-without-DebugFaultMod | True | — | — | [原始记录](trials/visual-01-without-DebugFaultMod/result.json)  |
| visual-02-baseline | True | — | — | [原始记录](trials/visual-02-baseline/result.json)  |
| visual-02-full | True | — | — | [原始记录](trials/visual-02-full/result.json)  |
| visual-02-without-DebugFaultMod | True | — | — | [原始记录](trials/visual-02-without-DebugFaultMod/result.json)  |

## 视觉对照

打开图片确认具体症状，再用 verdict 记录 good / bad / unknown 和依据。像素或显示树变化本身不等于异常。

DebugFaultMod / 第 1 轮： [完整组合](trials/visual-01-full/storage/agent-debug/frame.png) · [排除后](trials/visual-01-without-DebugFaultMod/storage/agent-debug/frame.png) · [显示树差异](comparisons/01-DebugFaultMod-tree.json)

DebugFaultMod / 第 2 轮： [完整组合](trials/visual-02-full/storage/agent-debug/frame.png) · [排除后](trials/visual-02-without-DebugFaultMod/storage/agent-debug/frame.png) · [显示树差异](comparisons/02-DebugFaultMod-tree.json)

## 下一步

先处理无效试验，再用相同存档/输入重复候选；--singles 可补单开对照。固定依赖缺失时不能归因性能。
确认症状消失且重新加入后复现，才能收窄到该模组或它与其他模组的交互；组合故障继续缩小 --mods，依赖保留在 --fixed。
