# 八个在用模组：英文与俄文适配

2026-10-03 · **八个模组已按用户明确授权安装，安装后隔离复验通过。保存当前进度并重启游戏后生效。**

沿用游戏已有语言切换入口：英语 en、俄语 ru；中文保留。覆盖统一设置、说明、悬停提示、F6/联机/战术面板、随机场景选择以及模组武器和地图名称，共 526 条消息。独立桌面编辑器、旧 ModSettings 不在本轮游戏入口范围内。

## 实际验证

- 当前正常游玩宿主 1.02，准确候选加载；通过原生语言按钮执行中→英→俄→中。
- **安装前 4,431 项、安装后 4,432 项自动断言通过，0 失败；文字边界检查 0 溢出。** 安装后增加 `localizationVersion=1` 发布标记检查，原生产 SWF 字节保持不变。 包括词表结果/回退、全部九个设置页的所有分页、五个分组、说明和悬停内容，以及常用面板与自定义物品/地图名称。
- 113 个设置值在语言往返后保持不变；含中文、俄文和花括号的昵称/聊天以及客户端已处理的用户文字保持原样。
- 已查看最终英文场景选择、俄文设置/场景/战术画面。检查范围不等于双端网络、伤害结算或时停机制的完整回归；本轮未改这些机制。
- 新角色、截图和日志位于唯一测试应用数据目录。正式存档未操作；主游戏、语言 XML、加载清单、配置和其他资源共 498 个受保护文件指纹不变。只替换八个正式模组 SWF，源码与记录随各自仓库保存。

## 版本衔接

RConnect 保留另一会话在本轮期间完成并安装的 M41 / 0.2.13-dev 修复；语言候选基于 9583c9d。

LootEditor 安装候选保留本机当前 0.2.1 与现有游戏桥，只回移菜单翻译。RModifier 主线 0.3.0 也已接入相同翻译，供以后从原编辑器正常更新连接；本轮不替用户升级游戏桥或编辑器。

Sandevistan 修改来自 D:/RemainsMod 真源，已先提交语言实现及源 release（6a67abd），再定向安装到游戏；音乐和运行配置保持原状。

## 准确安装文件

所有已安装文件保留在 [verified](../build/localization/verified)，与本轮测试输入逐一核对 SHA256。安装目标、旧文件指纹、当前指纹和备份见 [机器回执](localization-2026-10-03.json)。

| 模块 | 消息数 | SWF 字节 | SHA256 |
|---|---:|---:|---|
| ModLoader | 19 | 20032 | `2D01241A89FB25D608AC5138254E14DC3E5FB46E7120319A0D5922E4CF9816FD` |
| MoreSkills&Weapons | 179 | 75389 | `F9CECF74823D6DCA7009E04F01B83F49788FB5F2E874BC529C5F6124A9986362` |
| Sandevistan | 42 | 54944 | `A6E706F0AF8CC912A600D3B2262D3AAE1CCFFB7A9DD18B6B45F354FA860272E4` |
| RealisticVision | 31 | 25298 | `72D2F75BA89E7B40CC78C5A5E48E1C61AF297753CBE2DCA929E0F1AD5BA6A303` |
| Rconnect | 38 | 93060 | `2B25A7D2301D1BAAC40E04E70BA48E9BC40B5C292C0B3938A69BF6B151B41186` |
| RandomRooms | 73 | 100081 | `F21D7C04FF1CCF59779F0B8D9F52D982585145447C47727C660E9ECC7D62C0DF` |
| TDFC | 138 | 38656 | `99BFBAA68229635FBAA496EF9287A94BB9EA7C65D71339CEF3FDE65F47E30275` |
| RModifier | 6 | 37127 | `4F1D6CF19979F4EA4960F8CCD8377C1D3CAC490BED9949866885357D073C8625` |

## 证据与接续

- [测试结果](../build/localization/verified/results.txt)、[输入指纹](../build/localization/verified/inputs.json)、[布局检查](../build/localization/verified/layout.json)。
- [英文场景画面](../build/localization/runs/pfe-modsettings-languages-2c5161957d14498d92dace734f166b3a/en-rooms.png)、[俄文设置画面](../build/localization/runs/pfe-modsettings-languages-2c5161957d14498d92dace734f166b3a/ru-msw-exempt.png)、[俄文场景画面](../build/localization/runs/pfe-modsettings-languages-2c5161957d14498d92dace734f166b3a/ru-rooms.png)。
- 维护和复现见 [语言适配说明](../docs/localization.md)；生成的 AS3 词表与 JSON 已检查一致。
- [安装后复验结果](../build/localization/verified/post-install-results.txt)、[正式路径输入指纹](../build/localization/verified/post-install-inputs.json)、[安装后布局检查](../build/localization/verified/post-install-layout.json)。测试实例已退出，玩家窗口未操作。
- 发布标记：源码新增 `SettingsRegistry.localizationVersion=1`，各包词表和八个 SHA256 锁定本次发布；保留玩法版本号。

## 回滚

旧文件备份：`D:\Program Files\Steam\steamapps\common\Remains\mods\ModLoader\build\localization\backups\before-languages-20261003-160623-9ebd8cd6`。每个模组子目录中的旧 SWF 对应上述正式目标；安装前已逐个核对旧指纹。

需要撤回本轮语言适配时，先保存并关闭游戏，将八个备份 SWF 分别恢复到对应 release 路径后重启。Sandevistan 同时将 `Sandevistan-source.swf` 恢复到 `D:/RemainsMod/mods/Sandevistan/release/SandevistanMod.swf`，防止未来同步重新装回。不要恢复主游戏、配置或存档；回滚前如有新版本安装，应先核对当前指纹，避免覆盖后续更新。

当前任务已安装并验证完成，无待授权步骤。
