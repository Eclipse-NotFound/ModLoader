# 测试情况登记与占用协调

先看[共享登记表](../../../shared-knowledge/knowledge-validation/coordination/test-runs.md)，再安排测试。所有模组 agent 可运行本页的共享工具并更新自己的登记，不必为常规测试逐个询问其他会话。会话名称优先填“模组 / 任务”；已知真实会话 ID 可填，未知时不编造链接。

## 常用入口

玩家游戏不申请本表占用，可与 agent 测试同时运行。登记只协调 agent 测试组；每组仍用独立副本、随机 AIR ID、桌面与存储。默认静音及资源策略见 [TEST-RESOURCES.md](TEST-RESOURCES.md)。并行时帧率只作观察，不能作为干净的性能对照。

从 `mods/ModLoader` 执行：

```powershell
# 刷新并阅读；--json 可读取完整历史和进程身份
powershell -NoProfile -ExecutionPolicy Bypass -File tools/agent-debug.ps1 tests

# run 自动登记、等待占用、记录当前试验/实例/PID、写回结果
powershell -NoProfile -ExecutionPolicy Bypass -File tools/agent-debug.ps1 run --session "<隔离会话目录>" --owner "RealisticVision / 遮罩复验" --wait 300
```

运行游戏的测试共用 `game` 占用，一次放行一组，避免别的游戏测试污染性能对照；同一组的双实例联机在一个登记内管理。默认等待最多300秒，之后登记为“暂缓”，稍后重试即可，期间可在会话中继续其他工作。`--wait 0` 立即返回占用情况。离线检查用 `offline` 登记，可同时进行；不要把会运行游戏的脚本标成离线。

`test-runs.sqlite3` 是占用与完整历史正本，SQLite 事务保证同时申请不会双重放行；同目录 Markdown 是自动生成的阅读表，显示未结束记录及最近50条历史。不要手改生成表或删除数据库来释放占用。无需持续后台服务；每次状态查询或更新刷新表，更新时间不是进程心跳。

Windows 上阅读表可能因读取程序未共享删除权限而暂时不能替换；此时显示提示、保留数据库登记，下次查询重试刷新，不据此放行重叠测试。数据库锁最多等60秒，超时仍报错，不绕过占用。

状态分为等待、测试中、通过、未通过、已结束（未判定）、暂缓、中断待核对、已核对中断。表里保存负责会话、内容、当前步骤、时间、进程身份、隔离目录和证据位置。归因工具的“通过”仅表示已运行试验的有效性检查通过，视觉缺陷或原因判断仍看报告。历史结果只能在包指纹、描述符、场景和测试范围匹配时复用。

## 其他模组的专用驱动

只读导入正式工具 `mods/ModLoader/tools/test_registry.py`，在会运行游戏的整个测试组外包一层登记。登记不会替你隔离游戏/存档、隐藏窗口或清理实例，继续沿自动测试技能执行这些步骤。

```python
from test_registry import Registration  # 将正式 ModLoader/tools 加入 sys.path

with Registration(owner="RConnect / 双实例复验", purpose="host/join 伤害同步",
                  run_dir=isolated_root, evidence=report_path, wait=300) as record:
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

多实例为每个子进程调用 `child`，结束前等待全部退出。异常退出记“未通过”；仍有子进程或启动状态不确定则保留“中断待核对”占用。没有业务断言时保留默认“已结束（未判定）”，不把退出码0冒充功能通过。离线测试可用 `resource="offline"`，也可直接在原模组报告记录，无需占用游戏测试时段。

## 中断与未登记的旧测试

运行器中断后不会仅因时间久就释放占用。任何 agent 可先读记录与隔离目录的 `meta.json`，核对其中进程已经退出，必要时只读查看准确测试路径对应进程；不需要先找原会话确认。核对完成才执行：

```powershell
python tools/test_registry.py recover --id "<完整登记编号>" --checked-run-dir --note "已核对该隔离目录与所有测试PID均退出；证据位置……"
```

恢复工具复核已登记的 PID 和创建时间；进程存活、无法读取或创建身份不明时保留占用。`--checked-run-dir` 是执行者对隔离目录核对完成的声明，用于补足“刚启动就中断、尚未写入子PID”的窗口；工具不能代替这项检查，也不会结束任何进程。误判或不确定时保留记录、继续独立工作，只把无法从现有证据解决的冲突告知用户。

2026-10-26：若旧PID被受保护的系统进程复用，普通进程查询可能被拒绝。工具会再通过Windows CIM只读查询创建时间，并统一微秒精度比较；查不到唯一身份、查询失败或超时仍保留占用。两份原生创建时间继续按完整精度比较。此回退不终止进程、不直接释放未知身份，详见[复用PID验证](../knowledge/experiments/test-registry-2026-10-26/README.md)。

现有旧驱动和玩家游戏不会自动补录；空表只表示没有登记占用。接入前已启动的测试应在准确路径/日志中只读确认，不能以空表为由杀掉不认识的游戏。正式 SWF/名单部署沿治理章程处理，登记不授权覆盖其他会话文件。
