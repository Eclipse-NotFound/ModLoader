# 游戏内英文与俄文适配

2026-10-03。覆盖当前清单中八个在用模块：ModLoader、MoreSkills&Weapons、Sandevistan、RealisticVision、RConnect、RandomRooms、TDFC、RModifier 的 LootEditorMod。独立桌面编辑器和被禁用的旧 ModSettings 不属于本轮游戏内语言入口。

## 运行方式

直接跟随原游戏语言菜单对应的 `fe.World.w.lang`，不新增语言开关。`en` 使用英文，`ru` 使用俄文，`zh`/`tw` 保留原中文；其他语言暂回退英文。每个 SWF 自带词表和小型显示适配器，不需要额外安装共享语言组件。

- 设置页名称、说明、悬停提示、分组、分页，以及模组自己的面板、提示和 HUD 随语言更新。
- ModLoader 增加 `localizationVersion=1` 与可选 `navigation.translate(source)` 回调。现有 apiVersion/menuVersion/groupVersion、设置键、get/set、持久化和协议保持原语义；旧客户端仍可注册。兼容五参数设置服务的客户端仅在服务声明该能力时追加第六参数。
- `getPages()` 保留原始字符串；显示时调用 `api.text(page, value)`。注册时不翻译或改写设置对象，不因切换语言重新注册页面。
- 拉丁/西里尔文字用系统 `_sans`，解除原生中文 CSS 对字体/字号的覆盖。较长标签适配固定区域，导航根据标题宽度分配空间；中文仍使用原生样式。
- 用户昵称、聊天、方案名不能交给片段翻译器。LootEditor 使用带占位符的模板保留方案名；宿主用 `bind(..., alreadyTranslated=true)` 显示客户端已处理的文字。
- MSW 和 RandomRooms 只在当前语言 XML 中补充自己的武器/地图 ID，监测 XML 被原生异步加载替换的情况，不改磁盘语言文件。

## 词表维护

各模组 `src/modlocales/<package>/messages.json` 是词表正本；ModLoader 位于 `src/settings/modlocales/loader/`。同目录 `*LocaleMessages.as` 是随源码保存的生成结果，普通构建不需要 Python。中文原文作键，英文/俄文必须齐全；带 `{0}` 等占位符的消息在两种译文中保留相同参数。

在游戏根目录执行：

```powershell
python mods/ModLoader/tools/localization/generate.py mods/ModLoader 'mods/MoreSkills&Weapons'
python mods/ModLoader/tools/localization/generate.py mods/ModLoader 'mods/MoreSkills&Weapons' --check
```

可一次指定多个模组目录。Sandevistan 必须指定真源 `D:/RemainsMod/mods/Sandevistan`，先提交再定向同步；不能在游戏镜像中修改源码。

`text` 处理整条消息；`format` 一次替换参数，避免把玩家文字内的花括号再次当成参数；`render` 只处理由开发者固定片段组成的 UI 文本。不得用 `render` 处理网络聊天、用户项目或任意输入。

## 构建与复核

沿各模组原有构建入口生成候选。原始游戏和正式 release 不参与编辑。RConnect 的最终候选基于已提交并安装的 M41（9583c9d），保留该版战斗修复。

RModifier 当前源码的 LootEditor 为 0.3.0，但本机安装的仍是 0.2.1。当前游戏连接的语言候选应运行 `tools/localization/freeze-installed-loot.py`，再编译其输出目录内的 `build/build.ps1`；它只回移菜单翻译，保留 0.2.1 的规则与桥接。主线 0.3.0 也已接入相同词表，供原编辑器后续正常更新连接。语言适配不借机升级游戏桥。

完整游戏验证入口：`tools/localization/run.ps1`。可先用 `-PrepareOnly` 编译并准备，再用 `-Prepared` 启动；增加 `-Installed` 则从正式 release 取精确文件复制到隔离测试目录。需要正常桌面权限写入独立 AIR 测试数据；受限沙箱可能出现探针被请求但不完成加载，不能据此判断业务失败。

验证使用未改动的当前游戏 SWF、八个准确候选、外置 LocaleProbe、唯一 `pfe-modsettings-languages-*` 应用 ID。只结束自己启动的进程；候选指纹、结果、界面文本与截图位于 `build/localization/runs/`。探针不嵌入生产 SWF。

验证范围：全部词表的英俄结果与回退，原生中→英→俄→中切换，九个设置页的所有分页、五个展开分组、说明和悬停内容，F6、联机面板、TDFC 面板、F1 场景选择，原生自定义武器/地图名字，设置值与玩家输入保留，以及可见文字边界。新角色和操作均局限于隔离副本；这不是双端网络、武器伤害或时停机制的全面回归。

本轮准确结果、产物、安装状态与回滚见 `state/localization-2026-10-03.md`（相对 ModLoader 根目录）。本次语言发布由源码新增的 `localizationVersion=1` 标识，八个 SWF 的 SHA256 共同锁定发布内容；既有玩法版本号保留，安装后探针核对能力标记及各模块词表。
