# PID复用时的只读身份回退

用户于ContinuousScene会话明确允许修复共享登记器。原相机地形测试在CreateDesktop失败、尚未创建AIR时退出；其旧编译PID63256随后被MoUsoCoreWorker.exe复用。原token `134374159796693439`，CIM现创建时间对应微秒 `13437416305432210`。普通及仅查询权限的OpenProcess均返回5，原recover保守拒绝，证据在ContinuousScene的`build/generated/camera-terrain-layers-20261025/REGISTRY-ISSUE.md`。

`tools/test_registry.py`只在OpenProcess拒绝访问时用隐藏的非交互PowerShell读取CIM创建时间，15秒上限；不是唯一结果、缺时间、查询失败或超时仍unknown。仅混合CIM/原生token时统一到微秒，避免把同一进程的精度差当PID复用；两个原生token保留完整精度。登记、等待、recover及占用判断结构保持，未知身份仍不得释放。

验证：`python -B build/tests/test_test_registry.py`共15项，原有10项及新增5项。覆盖真实当前进程两种时间一致、复用PID、混合精度不误释放、未知/失败/超时、存活主进程仍阻塞、仅确认复用子进程才恢复。第一轮15项中的一项在tearDown遇WinError145目录非空，记录为失败；后续观察目录已不存在，未强制清理。完整复跑15项通过，4.739秒。未运行游戏或写正式存档。

续接时系统复用进程已经自行退出，原recover已安全释放`11d714b31b0f43258defca219d31eed2`；并未用新逻辑强行释放这条记录。新回退在昨日实际CIM只读身份及今日回归夹具验证，未再次制造受保护系统PID复用。

原源码SHA256 `8B35A6D6CA1DD94CFD5CBA9A42979EBD14D9AE65497688FA859D084425922049`，新源码 `E9F51CB75420C507F6DB1D96BE6B1430374B0B7A797607FF4438A695A717809E`。原工具与原测试备份：`work/backups/registry-cim-20261026/`。没有SWF或支持模组名单修改，未触碰既有supported-mods.txt未提交工作。
