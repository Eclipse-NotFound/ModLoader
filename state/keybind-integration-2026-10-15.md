# 各模组菜单改键

状态：七客户端候选及最终公共服务组合验证通过。公共ModLoader已按用户在改装会话的明确授权安装，正式文件回读39项也通过；其余六客户端仍为候选。FA由其对应会话独立部署并负责复验。

用户在本会话要求“把快捷键更改加入对应模组菜单，若有需要可向对应模组发送消息”。公共服务由本会话实现；在已有模组会话协作客户端，不创建新任务。RConnect 的 UI 与 RealisticVision 输入接入由本会话直接完成。

## 玩家入口

打开「模组 → 对应模组 → 快捷键」，点击当前绑定，再按希望使用的按键或组合。Esc取消，Delete或右侧「清除」解除绑定；修改立即保存到各模组自己的本机设置。页面的「恢复默认」只恢复该快捷键页。中英俄跟随原版语言选择。

七个模组共23项：技能武器2、时停1、视野3、联机2、随机房间8、枪械改装5、光暗2。没有独立快捷操作的五个运行模块不新增空页面；面板内部 Enter/Esc/方向键保持原导航用法。

新绑定检查当前原版单键、固定保留键和所有已注册模组的重复组合。已有的F10共用保持原值，并显示「!」及具体占用说明；不会自动替用户选新键。修饰键精确匹配。持续举枪与维修使用共同的按住状态，失焦、菜单及改键捕获时结束动作。

## 实现与验证

- ModLoader 2.4.0 / settings 0.5.0；新增 `keybindVersion=1`，现有 api/menu/group/localization 版本及 check/slider 接口保持兼容。完整客户端合同：[keybind-interface-v1.md](../docs/keybind-interface-v1.md)。
- 最终公共候选 `build/out/ModLoaderMod.swf`，24865 B，SHA256 `BD71B6F31774B97841D4C158451DA0353B53BC46AC72F8E2A7FE2C3F3F4908B1`。
- 最终公共真实游戏39项通过：`build/out/menus/keybind-core-fit-20261015/`，首进程29、重启10。覆盖真实按钮、冲突/取消/清除/默认、语言切换、捕获到松开的屏障、捕获前旧按键松开、精确持续按住与失焦清理。此前sealed-gui的39项仍保留，对应字体修正前3C63候选。
- 最终七客户端组合346项通过：`build/out/menus/keybind-all-fit-20261015/`，首进程175、重启171。23项逐一真实按钮录键、精确匹配、显示值及文字宽高、跨模组冲突、解除/重绑、重启恢复与全部默认恢复通过；实际视野开关/模式、联机面板/聊天、防重复按键也通过。完整1.02原宿主及12个活动模组与探针同时加载，无loader错误。
- 共385项为最终公共服务证据；各客户端自身验证独立列入其回执，不把多个夹具计数等同于覆盖全部玩法。
- 最终日志、运行输入指纹、两张复核截图和公共部署回执副本已保存到[稳定证据目录](../knowledge/experiments/keybind-2026-10-15/README.md)。
- 最终候选输入：[keybind-all-candidates.json](../build/keybind-all-candidates.json)。运行器每次冻结复制实际字节，并在独立run.json记录SHA、来源、唯一AIR应用ID和测试存储；不依赖源码目录当前改动推定运行版本。

测试中公共服务直接读取原版 internal `GUI.dial` 导致持续按住一直false，已改为公开 `guiPause/dialScript.running`；使用真实sealed GUI复验。`World.dialOn`是全局对话启用开关，不能当作忙碌。隐藏输入框及隐藏父容器焦点不再造成假忙碌。相关本体事实已归档shared-knowledge/ui-systems/facts/dialogue-busy-public-surface.md。

实际查看最终RandomRooms八行和俄文公共控件截图。原版按钮20pt字号会裁切绑定文本，已为紧凑按钮独立设字号并按真实字体度量收缩；最终23项按钮文本宽高均通过。`keybind-all-final-20261015`保留第一次字号修正的度量失败；`keybind-core-final-font-20261015`保留一次启动超时，未计通过。最终运行使用后续BD71同字节。

保留原失败：`keybind-core-final-20261015`暴露上述公共问题；早期组合探针误读视野配置路径、从main而非Stage找联机浮窗、重启后仍要求默认F10冲突，均为夹具问题，分别修正，不记为产品成功。另一次启动无心跳超时保留。最终检查必须以同一组候选的新结果为准。

## 安装边界

2026-10-15 21:25:24 已仅替换正式 `mods/ModLoader/release/ModLoaderMod.swf` 为24865 B / BD71B6F3…F4908B1。授权来源已实际回读改装会话01a13b7b-fe67-7a00-a10f-dd2df045fad9的用户消息01a13fb7-9a82-7421-9c1f-831774bfc1a6“请部署”和01a13fb9-429b-7421-96c5-4080ba0a2efc“允许联系并协调依赖部署”；权限仅为FA改键所需公共菜单依赖，不扩展到其余六个客户端。

回执：`build/out/keybind-installation/deployment.json`；已标记installed-and-verified。原版备份 `build/backups/before-keybinds-20261015-212524-00da1b79/ModLoaderMod.swf`，20032 B / 2D01241A…9816FD。回退 `build/deploy-keybinds.ps1 -Action Rollback` 会先确认当前仍为本轮BD71，避免覆盖别人后续部署。正式文件读回的唯一隔离应用 `keybind-installed-20261015` 两进程29＋10项通过，日志含runtime2.4.0/settings0.5.0，未关闭玩家游戏。安装脚本Verify已复核宿主/清单/其它模组及配置指纹；FA是另一授权事务，明确排除其同时更新。

本会话没有替换其余客户端release、根/DLC游戏SWF、清单、原有配置或真实存档。FA拥有独立部署授权，由改装会话处理，不写FA文件。测试只终止各自启动的唯一测试进程。剩余六个快捷键页需要对应客户端候选也安装后才会出现在正式游戏中。

FA对应会话已实际安装0.3.5 / B3304596…D2A4B9，并从正式FA＋BD71公共服务读回再验481/481；主会话只读核对其正式SHA。详见[FA独立部署回执](../../FirearmAttachments/state/keybind-deployment-2026-10-15.md)，不把其权限扩大到其他模组。RConnect已协调：其fix24仍独立验证，我方不会在未授权时替换其fix15或覆盖后续修复。

RealisticVision候选沿已安装0.30.5-scene生产线，RConnect沿A22 fix15，Sandevistan沿已安装单人线，排除各自HEAD的未发布实验。MSW保留主线已有B接口并逐方法合入正式A22智能目标保护，未提交Pointer实验不带入。光暗稳定线候选位于隔离分支，主工作目录性能WIP保留；源码整合另验，不能用主目录旧候选覆盖本轮绑定。

安装前按工作区GOVERNANCE §6与发布门禁核对授权、当时正式文件指纹、备份和各客户端回执；有其它会话新部署时先协调，不能用本轮旧输入覆盖新功能。无需修改游戏loader。所有测试限1.02；不扩称DLC、真人硬件输入、全部联机战斗或长期性能验收。
