被测技能：ui-design 2026-09-17.1（C:/Users/hello/.agents/skills/ui-design/SKILL.md）；remains-auto-testing（本区）
技能归属：ui-design 用户级/总控维护；remains-auto-testing Remains 工作区
测试工作区：D:/Program Files/Steam/steamapps/common/Remains/mods/ModLoader

# 2026-10-18 模组选择启动器

用户要求扫描已安装模组、选择加载项并一键启动，供玩家与 agent 定位故障。Windows 启动器 1.0.0 和配套扫描器已放到本模组根目录。游戏内运行模块仍为 2.4.0 / settings 0.5.0；本轮未改游戏SWF、描述符、正式名单、兼容表或其他模组，未上传公开包。

## 实现

复用原 C# 扫描器，真实 WinForms 界面和 CLI 共用规则。三版本分别勾选，支持全开、全停、精确仅选、保存/启动、诊断导出。用户选择以 `# selection|...` 注释与有效开关同存一个原子替换的名单，包缺席或不兼容不抹掉选择。旧 ModSettings 继续由兼容表禁用。

保存检查名单、兼容表和包集合是否改变，同一名单用互斥量保护写入并备份。启动检查游戏版本、文件和运行时，拒绝同目录重复启动。启动/导出记录保存入口及包SHA-256；明确不是实际运行加载成功证据。

## 证据

| 检查 | 结果 | 证据 |
|---|---|---|
| 构建 | 两个EXE零错误，警告视为错误 | tools/build_launcher.ps1、installation.json |
| 核心/真实控件 | 38项通过 | ui-core-results.txt；build/out/launcher-tests/20261018-221100-623 |
| 独立命令行 | 23项通过 | cli-results.json；build/out/launcher-cli/20261018-220955-135 |
| 原扫描器/加载器离线回归 | 两套均通过 | tools/test_scanner.ps1、tools/test_loader.ps1 |
| 真实1.02只开ModLoader | 仅所选项有requested/ok，日志新鲜；重复启动拒绝 | ModLoaderMod-result.json |
| 真实1.02只开TDFC | 仅所选项有requested/ok，其余无请求；重复启动拒绝 | TDFCMod-result.json |
| 真实1.02全停 | boot成功，所有项无请求；重复启动拒绝 | none-result.json |
| 安装后回读 | 两工具与候选相同；15包/14启用；7项保护输入指纹不变 | installation.json、installed-list.json |

真实游戏用独立目录、唯一AIR应用ID/存储，35秒观察窗口，只终止本轮进程。前两组位于 build/out/launcher-runtime/20261018-220928-605，全停补验位于20261018-221357-280。

ui-design采用用途优先的操作层次、真实安装内容、中文混排、禁用/未保存反馈及渲染后修正；读了SKILL.md与references/实战验证.md。实际查看本机200% DPI的默认/最小窗口、长中文名、15项列表和按钮，截图见 [preview.png](preview.png)。控件测试走真实WinForms事件，不等于真人鼠标键盘验收。其他DPI、多显示器、DLC实机、所有模组组合及用户满意度未验证。

## 失败与修正

1. 动态控件提前布局使高DPI文字放大而尺寸未同步，发生裁切；构造时SuspendLayout，完整创建后ResumeLayout，复查两尺寸通过。
2. winexe直接设置Console.OutputEncoding报无效句柄；改为对重定向标准流写UTF-8，跨进程JSON中文通过。
3. 游戏子进程继承CLI输出管道导致调用脚本一直等待；改用ShellExecute启动固定EXE（不经过命令解释器），真实启动后脚本可继续。
4. 沙箱AIR进程存活却未创建存储/日志，未计成功；正常Windows权限下完成三组验证。失败记录20261018-220619-593/ModLoaderMod-result.json保留。
5. 全停测试单元素数组被PowerShell展开成字符串，splat成字符，报未知参数“-”；显式string[]后单独补验通过。
6. 旧离线测试固定断言玩家当前1.04恰有两个包，新增包后失效；改用自有固定名单，补查选择注释忽略。
7. EXE安装命令混入只读SWF指纹检查触发本机hook，整条未执行；拆成只读核验与两个EXE明确路径复制后完成，没有放宽hook。

## 安装与恢复

完整指纹见installation.json。启动器C05B4C23…45F9590；扫描器8FA18398…C0D33C1。旧扫描器备份work/backups/before-launcher-20261018-2216/RemainsModScanner.exe，5753A0A6…1E5A727。回退时关闭启动器，移走新启动器并恢复旧扫描器；旧扫描器会重置选择，须先保留名单。恢复某组选择用work/manifest-backups/。

原有未提交supported-mods.txt的PermanentInjury登记保留，排除本轮提交；本项目原本缺AGENT_SCOPE.md，未擅自新增治理文件。使用说明见docs/LAUNCHER.zh-CN.md。已向全局测试报告台账查重追加，状态待吸收。大型隔离游戏副本已删除，名单、描述符、启动配置与成功/失败摘要仍留原测试目录；首轮残留进程按唯一EXE路径及命令行定位后停止，未碰玩家进程。
