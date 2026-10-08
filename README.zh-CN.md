# Remains 模组入门 · ModLoader

[English](README.md) · **简体中文**

第一次给《Fallout Equestria: REMAINS》装模组，从这里开始。ModLoader 负责让游戏加载模组，并提供游戏内设置入口；你可以只装自己喜欢的玩法。**不需要编程或安装开发工具。**

**[打开完整安装指南](docs/INSTALL.zh-CN.md)** · [全部下载与更新记录](https://github.com/Eclipse-NotFound/ModLoader/releases)

## 先下载哪几个文件？

| 文件 | 用途 |
|---|---|
| [Remains-GamePatch-v2.3.0.zip](https://github.com/Eclipse-NotFound/ModLoader/releases/download/v2.3.0/Remains-GamePatch-v2.3.0.zip) | 第一次安装：让游戏能加载模组，解压后运行 Patch-Game.bat |
| [ModLoader_v2.3.0-r1.zip](https://github.com/Eclipse-NotFound/ModLoader/releases/download/v2.3.0-r1/ModLoader_v2.3.0-r1.zip) | 设置组件与扫描器：把包内 mods 合并到游戏目录 |
| 下表中你喜欢的模组包 | 实际增加时停、武器、地图等玩法 |

**这两个前置下载都需要。** 最新发布页 v2.3.0-r1 只有设置/扫描器包；首次安装的 GamePatch 仍在 v2.3.0，所以上面提供了直达链接。

适用 Windows。第一次游玩建议使用 **Remains 1.02**；游戏补丁能识别部分 1.03/1.04 构建，但不表示全部模组和设置都支持这些版本。

## 安装顺序

1. 保存退出游戏；Steam 库右键 Remains → **管理 → 浏览本地文件**。
2. 解压 GamePatch，双击 **Patch-Game.bat**，按提示选择游戏目录；看到 **[done]** 后继续，保留自动生成的备份。
3. 解压 ModLoader 和所选模组，把各包内的 **mods** 文件夹合并到游戏目录（与 pfe.swf 同级）。
4. 双击 **mods/ModLoader/RemainsModScanner.exe**，完成后关闭提示，再按平常方式启动游戏。
5. 在 **哔哔小马 → 设置 → 模组** 查看已接入的模组设置；MSW 另有 F6 快捷面板。

看不到文件或模组没生效？[按图核对目录并排错](docs/INSTALL.zh-CN.md#troubleshooting)。扫描器只整理名单，不会替你启动游戏。

<a id="choose-mods"></a>

## 选你想玩的模组

| 模组 | 会改变什么 | 当前公开版 |
|---|---|---|
| [Sandevistan](https://github.com/Eclipse-NotFound/Sandevistan/blob/master/README.zh-CN.md) | 慢动作、连招回放与彩色残影 | [v1.145](https://github.com/Eclipse-NotFound/Sandevistan/releases/tag/v1.145) |
| [MoreSkillsAndWeapons](https://github.com/Eclipse-NotFound/MoreSkillsAndWeapons/blob/master/README.zh-CN.md) | 智能子弹、跳弹、激光与更多战斗操作 | [v1.15.3](https://github.com/Eclipse-NotFound/MoreSkillsAndWeapons/releases/tag/v1.15.3) |
| [TDFC](https://github.com/Eclipse-NotFound/TDFC/blob/master/README.zh-CN.md) | 不改血量伤害，增强敌人观察和战术 | [v0.6.4](https://github.com/Eclipse-NotFound/TDFC/releases/tag/v0.6.4) |
| [RealisticVision](https://github.com/Eclipse-NotFound/RealisticVision/blob/main/README.zh-CN.md) | 视线遮挡、探索迷雾与暗淡地形记忆 | [v0.30.1](https://github.com/Eclipse-NotFound/RealisticVision/releases/tag/v0.30.1) |
| [RandomRooms](https://github.com/Eclipse-NotFound/RandomRooms/blob/main/README.zh-CN.md) | 四种主题、持续扩展的随机探索地图 | [v13.2](https://github.com/Eclipse-NotFound/RandomRooms/releases/tag/v13.2) |
| [RConnect](https://github.com/Eclipse-NotFound/RConnect/blob/master/README.zh-CN.md) | 与一位朋友双人合作探索 | [v0.2.8](https://github.com/Eclipse-NotFound/RConnect/releases/tag/v0.2.8) |
| [RModifier](https://github.com/Eclipse-NotFound/RModifier/blob/master/README.zh-CN.md) | 中文桌面工具，编辑掉落、台词与地图 | [v0.4.0](https://github.com/Eclipse-NotFound/RModifier/releases/tag/v0.4.0) |

不必一次装全套。旧的 `Remains-AllMods-2026-09-24.zip` 是当天的合集，**不是持续更新的最新整合包**；想用新版本，请按各项目页面下载。RModifier 是单独运行的编辑器，按它自己的指南接入游戏。

## 更新、停用和常见问题

安装其他模组后重新运行扫描器并重启游戏。升级前备份旧模组，保留自己的配置；临时停用可把对应模组文件夹移到 `mods` 之外，再扫描重启。Steam 更新或验证文件后可能需要重新安装游戏补丁；出现“不支持的构建”时不要强行覆盖。

[完整安装、更新、停用与恢复指南](docs/INSTALL.zh-CN.md) · [反馈安装问题](https://github.com/Eclipse-NotFound/ModLoader/issues)

<details>
<summary>开发资料（玩家安装无需阅读）</summary>

[设置接口](docs/settings-interface.md) · [技术与历史验证记录](docs/DEVELOPMENT.zh-CN.md) · [源码](src/) · [发布记录](https://github.com/Eclipse-NotFound/ModLoader/releases)

运行模块 2.3.0、扫描器 2.1；r1 更新兼容性表。清单生成、构建、验证与旧部署回滚信息放在开发资料中。

</details>

非官方玩家项目；需要自行拥有游戏。
