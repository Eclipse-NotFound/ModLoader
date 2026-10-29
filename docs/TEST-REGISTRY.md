# 测试情况登记与占用协调

先看[共享登记表](../../../shared-knowledge/knowledge-validation/coordination/test-runs.md)，再安排测试。所有模组 agent 可运行本页的共享工具并更新自己的登记，不必为常规测试逐个询问其他会话。会话名称优先填“模组 / 任务”；已知真实会话 ID 可填，未知时不编造链接。

## 常用入口

玩家游戏不申请本表占用，可与 agent 测试同时运行。登记只协调 agent 测试组；每组仍用独立副本、随机 AIR ID、桌面与存储。默认静音及资源策略见 [TEST-RESOURCES.md](TEST-RESOURCES.md)。并行时帧率只作观察，不能作为干净的性能对照。

从 `mods/ModLoader` 执行：

```powershell
# 刷新并阅读；--json 可读取完整历史和进程身份
powershell -NoProfile -ExecutionPolicy Bypass -File tools/agent-debug.ps1 tests

# run 自动登记、等待占用、记录当前试验/实例/PID、写回结果
powershell -NoProfile -ExecutionPolicy Bypass -File tools/agent-debug.ps1 run --session "<隔离会话目录>" --owner "RealisticVision / 遮罩复验" --wait 900
```

2026-10-29 起，默认 `coexist` 计划使用 `game-coexist`：最多两个独立功能测试组同时运行，目录相同或互相包含的请求仍排队。`benchmark` 计划使用 `game`：与所有游戏测试互斥。同组双实例联机仍在一个登记内管理，并另行隔离端口。旧专用驱动未指定资源时继续使用独占 `game`，不能自动认定它适合并行。

按申请顺序放行，更新状态不会改变顺序；已排队的性能测试会阻止后来功能请求插队，已有测试正常结束。默认等待最多900秒，之后登记为“暂缓”，稍后重试即可，期间可继续其他工作。`--wait 0` 立即返回占用情况。离线检查用 `offline`，可同时进行；不要把会运行游戏的脚本标成离线。

`test-runs.sqlite3` 是占用与完整历史正本，SQLite 事务保证同时申请不会双重放行；同目录 Markdown 是自动生成的阅读表，显示未结束记录及最近50条历史。不要手改生成表或删除数据库来释放占用。无需持续后台服务；每次状态查询或更新刷新表，更新时间不是进程心跳。

Windows 上阅读表可能因读取程序未共享删除权限而暂时不能替换；此时显示提示、保留数据库登记，下次查询重试刷新，不据此放行重叠测试。数据库锁最多等60秒，超时仍报错，不绕过占用。

状态分为等待、测试中、通过、未通过、已结束（未判定）、暂缓、中断待核对、已核对中断。表里保存负责会话、内容、当前步骤、时间、进程身份、隔离目录和证据位置。归因工具的“通过”仅表示已运行试验的有效性检查通过，视觉缺陷或原因判断仍看报告。历史结果只能在包指纹、描述符、场景和测试范围匹配时复用。

## 其他模组的专用驱动

只读导入正式工具 `mods/ModLoader/tools/test_registry.py`，在会运行游戏的整个测试组外包一层登记。登记不会替你隔离游戏/存档、隐藏窗口或清理实例，继续沿自动测试技能执行这些步骤。

```python
from test_registry import Registration  # 将正式 ModLoader/tools 加入 sys.path

with Registration(owner="RConnect / 双实例复验", purpose="host/join 伤害同步",
                  resource="game-coexist", run_dir=isolated_root,
                  evidence=report_path, wait=900) as record:
    # 一组多实例共用 record，不重复嵌套申请 game 占用。
    record.before_launch("host / 唯一AIR ID / 所选组合")
    process = None
    try:
        process = launch_owned_test()  # 自己的隔离启动方式
        record.child(process.pid)
        check_results(process)
        record.outcome = "passed"    # 仅在业务断言确实通过时设置
        record.note = "伤害往返断言通过；其他玩法未覆盖"
    finally:
        stop_and_wait_owned_process(process)
        record.child_stopped()
```

上例仅用于功能验证；性能对照改用 `resource="game"`。每个原生子进程都必须遵守 `before_launch → child → 等待退出 → child_stopped`，多实例逐个登记。一个登记若由多线程启动，调用者须把启动和登记这一段加锁。不要把间接启动后脱离管理的后代当作已完整登记。未接入此协议的旧驱动应使用 `managed=False`，保持人工核对恢复。

多实例结束前等待全部退出。异常退出记“未通过”；仍有子进程或启动状态不确定则保留“中断待核对”。没有业务断言时保留默认“已结束（未判定）”，不把退出码0冒充功能通过。离线测试可用 `resource="offline"`，也可直接在原模组报告记录，无需占用游戏测试时段。

## 中断与未登记的旧测试

运行器中断后不会仅因时间久就释放占用。新版 `Registration` 标记受管协议：只有运行器及全部登记子进程均已确认退出、且不存在启动登记间隙时，查询会自动记“已核对中断”并释放占用。进程身份未知、子进程存活、启动未登记完或旧记录均保留“中断待核对”；查询进程在数据库写锁外执行，避免慢查询拖住其他申请。

需要人工恢复时，任何 agent 可先读记录与隔离目录的 `meta.json`，核对其中进程已经退出，必要时只读查看准确测试路径对应进程；不需要先找原会话确认。核对完成才执行：

```powershell
python tools/test_registry.py recover --id "<完整登记编号>" --checked-run-dir --note "已核对该隔离目录与所有测试PID均退出；证据位置……"
```

恢复工具复核已登记的 PID 和创建时间；进程存活、无法读取或创建身份不明时保留占用。`--checked-run-dir` 是执行者对隔离目录核对完成的声明，用于补足“刚启动就中断、尚未写入子PID”的窗口；工具不能代替这项检查，也不会结束任何进程。误判或不确定时保留记录、继续独立工作，只把无法从现有证据解决的冲突告知用户。

2026-10-26：若旧PID被受保护的系统进程复用，普通进程查询可能被拒绝。工具会再通过Windows CIM只读查询创建时间，并统一微秒精度比较；查不到唯一身份、查询失败或超时仍保留占用。两份原生创建时间继续按完整精度比较。此回退不终止进程、不直接释放未知身份，详见[复用PID验证](../knowledge/experiments/test-registry-2026-10-26/README.md)。

现有旧驱动和玩家游戏不会自动补录；空表只表示没有登记占用。接入前已启动的测试应在准确路径/日志中只读确认，不能以空表为由杀掉不认识的游戏。正式 SWF/名单部署沿治理章程处理，登记不授权覆盖其他会话文件。
