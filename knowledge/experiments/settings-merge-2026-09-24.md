---
domain: ui-systems
type: experiments
game-version:
  - "1.02"
  - "1.03"
  - "1.04"
confidence: high
verified: true
discovered-by: ModLoader
evidence:
  - kind: runtime-experiment
    summary: "真实游戏副本验证旧宿主位置迁移、菜单操作、中文像素与原生页切换；三版本及缺包/init故障验证；正式字节安装后复验。设置功能仅1.02。"
date-updated: 2026-09-24
---

# v2.2.0 内置设置：实施、验证与安装

## 决定与实际改动

用户确认四项：设置成为加载器内置功能；本轮只合并原设置功能；保留接口和菜单记忆；设置仅支持1.02，原1.03/1.04加载能力不变。随后要求具体实施，按分析中的迁移、验证及安装方案执行。

新增 `src/runtime/ModLoaderMod.as`，入口 `ModLoaderMod.init(main)`，运行版本2.2.0。原ModSettings v0.3.1的六个源文件迁入 `src/settings/`，入口实现改名 `SettingsHost`，其余五个实现文件保持原字节；载体增加hostId/hostVersion诊断字段。设置版本仍为0.3.1。独立构建和测试迁到本项目；正式构建无跨项目源码依赖。

保留 `ModSettingsCarrier.modAPI`、apiVersion/menuVersion=1、页面ID、五参数登记、回调、MSW F6和两级菜单行为。位置仍存 `ModSettingsMenu` 的 `/` 路径；客户端自持配置和保存。日志保留 `ModSettings.log`。MainFE引导v2与扫描器v2.1的实现未改。

版本表新入口 `ModLoader|ModLoaderMod|1|0|0`，旧入口 `ModSettings|ModSettingsMod|0|0|0`。正式旧包保留但禁用，扫描多次、旧包缺席、新包缺失均不将旧入口重新启用。日志冒烟允许已启用新入口与禁用旧入口共享日志路径，同时仍严格禁止旧入口requested/ok状态。没有新增依赖调度或任意运行时异常隔离承诺。

## 隔离验证

测试复制真实游戏文件和当前正式客户端，隐藏窗口、唯一AIR app id、自有存储；只终止各脚本自己创建的进程。正式客户端配置和游戏文件哈希在安装前后核对一致。

| 场景 | 结果 | 本项目证据目录 |
|---|---|---|
| 旧v0.3.1先写位置，随后两个进程用新宿主读取/更新 | 47+13+11=71项 | `build/out/menus/migration/` |
| 移除MSW的设置操作与重开 | 10+10=20项 | `build/out/menus/without-msw/` |
| 新宿主完整客户端、两行分页/控件分页/局部重置/旧接口 | 50项 | `build/out/menus/candidate-complete/` |
| 中文按钮文字、选中背景、记录→模组→原生五页、持续心跳 | 24项 | `build/out/button-style/merged-verified/` |
| 1.02正常加载 | 21项 | `build/out/startup/candidate-102/` |
| 1.03 / 1.04：设置新旧入口均不请求，原模组正常加载 | 16 / 15项 | `build/out/startup/candidate-103/`、`candidate-104/` |
| 清单启用但新运行文件缺失 / 同步init抛异常 | 21 / 21项；其他模组仍初始化 | `build/out/startup/candidate-missing/`、`candidate-init-failure/` |
| 正式安装字节菜单及版本/心跳复验 | 50项 | `build/out/menus/installed/` |

离线加载器与扫描器回归通过，包含旧入口禁用仍出现requested/ok的反例、共享日志不误报、旧包保留/缺席、运行文件缺失与重复扫描；反向回滚时保留新包，将新入口0/0/0、旧入口1/0/0，多次扫描也只启用旧宿主。中文同标签文字和选中背景像素差均为0；记录页内容未覆盖新设置页，检查截图 `02-mod-after-record.png`。

首次中文回归在100秒看门狗处超时：页面操作已完成，phase=12，日志已持续到frames=1200；原探针固定再等650个Timer tick，多实例背景运行使等待变长。调整的是测试探针：导航完成后记录心跳基线，等待日志出现更大的真实帧计数，每20 tick检查，外围上限180秒。随后24项全过，未修改生产逻辑以迎合测试。菜单探针输出按RunLabel独立命名，避免并发编译共用文件。

安装后日志含 `ModLoader runtime v2.2.0 loaded; settings v0.3.1`，唯一载体/按钮、正式入口响应、frames=600/1200均通过。测试有意提交无效登记，日志的 `callbackError=invalid item in feature-13` 是对应的预期拒绝证据，未覆盖有效页面。

## 安装与指纹

2026-09-24 06:47安装新 `release/ModLoaderMod.swf`，运行扫描器切换根 `mods/loader-manifest.txt`，启用数量仍7/3/2。安装回执 `build/out/installation/deployment.json` 状态 `installed-and-verified`，含每个客户端、游戏、探针、名单与版本表指纹。

| 产物 | 字节 / SHA-256 |
|---|---|
| 新运行模块 | 15110 / `C9701A91013899E2674F29990AC6E4977A6C4678D0AE47D8C14324F97084704C` |
| 保留禁用的旧ModSettings v0.3.1 | 14929 / `C2BC2CCE45A9B7125D8CF048B352E059EC6DDF466F8625CA77BCC4B3E6A4B451` |
| 本轮测试的正式MSW | `C233D67EA0C5FC74BD0499ADFB1AD1C45823CAEEDA7145806D84BE101ABF0827` |

MSW已比旧记忆中的F8DD...更新，本轮仅取当前正式字节验证，没有覆盖或回退它。根/DLC三份游戏SWF保持README所记B782... / 90DE... / 0BD5...。正式配置、客户端SWF、用户存档和用户游戏进程均未操作。安装前app id `pfe-modsettings-menus-ed0e9a0a99cb4de5929e45b0d7a3bdc8`，安装后 `pfe-modsettings-menus-60c3c620d60947efb21b02be70e1fd01`。

## 回滚与门禁

备份：`work/backups/before-settings-merge-20260924-064730/`，包括旧正式包、旧版本表、旧生成名单和全基线 `files.json`。退出游戏后核对/必要时恢复旧ModSettings正式包，将版本表中旧入口恢复1/0/0，同时保留新ModLoader入口0/0/0，然后运行扫描器生成根名单。保留新包时必须有新入口禁用登记；若从备份恢复旧版本表，须先补入该禁用行，否则再次扫描会发现并启用新包。若后续新增了其他模组，先合并其名单变化。只换旧SWF而不恢复开关不会重新启用设置；无需回滚游戏SWF。

门禁已完成构建、新运行版本标记、候选验证、用户授权、现状指纹核对、备份、安装、独立进程正式字节冒烟与回滚说明。源码/说明/记忆纳入对应仓库提交，产物与测试工作目录按既有规则忽略。

范围限制：旧记忆迁移用独立应用存储重现旧→新过程，没有读取用户个人存档。1.03/1.04只验证加载范围与原模组初始化，不支持其中的设置页面。本轮没有覆盖所有战斗、联机玩法或任意初始化后的异步故障。保留旧ModSettings项目作为历史，设置实现后续只维护本项目。
