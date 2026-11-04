# 测试启动图再次出现：修复遗漏入口

2026-11-04。用户要求测试启动不显示 HARMAN/AIR 标识，未记得具体触发任务。本次定位到仍在使用的直接启动入口，不能断言用户截图一定来自其中某一条。

## 原因和范围

10月19日的 `HiddenProcess` 仍有效；`visible=false`、`WindowStyle Hidden`、`CREATE_NO_WINDOW` 都不能单独隔离 AIR 的 `AIR_Splash` 窗口。近期 RV×CS 的 `run_grid.py` 实际调用 `build/cs-rv-20261104/run_one.ps1`，后者直接启动 AIR。这条路径在共享表中有当日晚间多轮运行，符合反复弹图的条件。

- 共用工具：新增 `Invoke-AirTest.ps1` 同步桥接原 Python 私有桌面工具；Python 增加日志、结果等待、清理回执及可选 Unicode 子进程环境。原 `HiddenProcess` 接口兼容。
- ModLoader 的 `smoke_test.ps1`、`verify_collection.ps1`、`localization/run.ps1` 接入桥接。观察期限到期的 smoke 仍按“存活到期限”验收；语言测试仍要求正常完成及原业务断言。
- RV：`build/cs-rv-20261104/run_one.ps1`、`build/shadowfix-20261104/run_smoke.ps1`、两个 `build/{csopt,shadowfix}-20261104/run_checks.py`，以及受版本管理的 `tools/fov-fix-20261104/smoke.py`。保留结果、超时、真实AIR PID、隔离环境变量和原业务断言；PS 回执补桌面策略，后续测量与旧前台桌面数据分开解释。
- 游戏 SWF、AIR DLL、玩家入口、正式选择和存档均未改。没有修改 RConnect、其他模组历史实验/可见预览脚本；这些入口不自动获得本次保证。

## 证据

- 5项新集成检查通过：Unicode环境、超时清理、旧结果拒绝、缺失程序失败、PowerShell→Python参数/日志/真实PID/子进程桌面。
- 3项已有原生集成检查通过：桌面归属与参数/日志/资源策略、超时与持有句柄关闭纪律、失败不回退前台。
- 真实AIR菜单：私有桌面枚举到可见 `AIR_Splash`，该桌面为 `RemainsTest-*`；输入桌面前后均为 `Default`，探针试验有效、错误为空。`native-windows.json` 保留窗口归属；没有读取用户桌面画面。
- 安装后再通过新 PowerShell 入口运行真实AIR：独立应用ID/runId匹配、采样非空、error为空、exit=0、closed=true、timedOut=false。证据 `powershell-air-63d5afb0/`。共享登记正常结束。
- 5个PS脚本语法解析、Python语法和定向diff检查通过。未重跑分发/语言整套业务和 RV 战斗/性能矩阵，本次不作性能或玩法结论。
- 保留失败：受限上下文被既有完整性检查拒绝；正常权限流程后通过。首次PS真实AIR验证使用了不符合探针 `pfe-agentdebug-` 前缀的ID，探针按设计不激活，90秒后工具正确清理；修正测试ID后通过，失败证据 `powershell-air-f1b0c686/` 不覆盖。

## 文件与回退

安装指纹和准确回退文件见本目录 `installation.json`。原始证据、执行脚本和已装源码快照在 `mods/ModLoader/build/out/quiet-launch-20261104/`，回退副本在 `mods/ModLoader/work/backups/quiet-launch-20261104/`；本目录保留必要JSON及RV临时脚本修复后源码。回退前核对目标仍为该回执的after指纹，不覆盖并发更新。

用法见 [AGENT-DEBUGGING](../../../docs/AGENT-DEBUGGING.md)。独立桌面失败仍显式失败；普通玩家窗口及主动可见测试不在隐藏范围。
