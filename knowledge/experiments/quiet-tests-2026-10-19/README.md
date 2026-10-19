被测技能：remains-auto-testing / remains-runtime-debug 2026-10-19.1（本轮使用）；2026-10-19.2（后台桌面路由修订，基本检查）
技能归属：Remains 工作区 `.agents/skills/`
测试工作区：D:/Program Files/Steam/steamapps/common/Remains

# 后台测试不显示 AIR 启动画面

2026-10-19，用户要求测试启动时不要显示 HARMAN/AIR 标识。运行环境为 Windows，随游戏 AIR/ADL 51.1.3.3，游戏1.02，归因调试器更新为1.0.1。

## 原因与改动

AIR 启动图是独立的 `AIR_Splash` 原生窗口；应用描述符的 `visible=false` 只控制游戏初始窗口。官方[FAQ](https://airsdk.harman.com/faq)说明启动图的许可机制；[发行说明](https://airsdk.harman.com/api/versions/50.2.4.5/release-notes/Release_Notes_AIR_SDK_50.2.4.pdf)说明桌面平台会创建单独窗口。

新增 `tools/air_test_process.py`，使用 Windows [CreateDesktopW](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-createdesktopw) 和 [STARTUPINFO.lpDesktop](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/ns-processthreadsapi-startupinfow) 将整个测试进程放到临时私有桌面。默认归因测试接入此入口，保留标准输出、错误、超时及本进程退出清理，不切换用户桌面。创建失败直接报错。显式 `--visible` 保持正常可见启动，仍可能出现运行时标识。AIR DLL、许可和正式游戏二进制均未修改。

新计划记录桌面策略；旧计划或策略不匹配时要求重新 prepare，避免混用前后台测量。专用驱动可接入同一入口，旧脚本不会自动被改写。

## 实际验证

- 调试器24项离线检查通过，包括过期/错误加载证据、看门狗只杀持有进程、关闭桌面和拒绝旧/不匹配桌面计划。
- Windows原生进程3项通过：子进程报告的桌面名称与创建值相同；中文/空格/引号参数、stdout/stderr保留；超时处理、存活时拒绝提前关闭、退出后释放桌面；缺失EXE失败且不回退前台。
- 真实游戏2项通过：`perf-01-baseline` 与 `visual-01-full`（设置宿主+探针）均成功新开隔离档并正常退出；性能样本与视觉结果有效。截图实际查看，内容为新档开场字幕，没有把空截图当成功。
- [原生窗口记录](native-windows.json)：每次观察到12条窗口状态，其中 `AIR_Splash` 为可见窗口，但只在 `RemainsTest-*` 私有桌面枚举到；游戏窗口同属该桌面。输入桌面前后均为 `Default`。仅枚举本轮私有桌面，没有读取用户桌面窗口内容或截图。
- 新计划一致性保护是在上述实机结果后加入，另有离线正反检查；未据此宣称再次重跑全部实机。`--visible` 分支保持原Popen实现，本轮未主动弹窗实测。
- 紧凑证据在本目录两条试验文件夹、`session.json`、`native-windows.json`。本轮完整隔离会话路径原为 `build/out/debugger/20261019-162847-377bbcf0/`。
- 证据归档后已清理本轮完整测试副本及3个专用存档目录，未结束用户进程；清理记录见 `cleanup.json`。

## 失败与边界

- 沙箱创建桌面报 WinError 5；通过客户端正常权限流程后原生测试成功。不是静默回退用户桌面。
- 尝试 Python `STARTUPINFO.lpAttributeList` 继承桌面句柄时，子进程仍报告 Default，方案舍弃；最终用显式 `lpDesktop`。探索脚本 `desktop_probe.py` 只用于复核该失败，不是生产入口。
- 首次观察工具尝试从其他进程的线程取得桌面句柄，信息查询被拒绝，试验中止并结束自己的进程。改为仅枚举自己持有的私有桌面，窗口归属由枚举范围和PID确认；失败记录见 `native-windows-attempt1.json`。
- 退出后的窗口管理器清理可能短暂滞后；原生测试在最多2秒内回查桌面销毁，每次释放查询句柄，不要求零延迟消失。
- 桌面隔离改变焦点/调度，不能将该性能结果等同玩家前台帧率。原生GPU效果、所有玩法、多实例联机和其他专用驱动尚未覆盖。本次只确认启动图不出现在用户桌面及基础采样链可用。
- 两项技能路由更新为2026-10-19.2并保留旧版；手工前言检查、相对引用和安装指纹核对完成，不把文件安装等同新会话自动选用已验证。

本次产物为已验证后台启动实现与本报告；跨模组可复用经验留在此原址，技能已指向统一用法。
