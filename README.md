# ModLoader 交接报告 —— 通用清单模组加载器 v1.0.0

> 2026-09-22~23 会话完成，用户授权（"分析可行性" → "实现路线B"）。
> 本报告覆盖：全部更改清单 / 使用手册 / 调试手册 / 验证记录 / 实施纪要。
> 日常维护只需读 §三、§四；排障读 §五。

---

## 一、一页速览

**做了什么**：把三份游戏 SWF 里"每个模组一段专属 loader"的结构，换成**一个读文本清单的通用 loader**。从此加/删/禁模组、调顺序、改版本覆盖 = **只编辑 `mods\loader-manifest.txt`**，游戏文件零改动。Steam 更新冲掉补丁后，跑一个脚本即恢复。

**为什么不是"完全不改游戏"**：方案 A（外部 booter 子装载 pfe.swf）被实机判死——`MainFE` 构造器第一行就解引用 `stage`，而子内容文档类构造期 `stage==null` → 必然 #1009。详见 `shared-knowledge\knowledge-validation\experiments\independent-mod-loader-feasibility.md`。

**当前状态**：三目标已部署、已实测（1.02 七模组全载；1.03 恰载 3 个；1.04 恰载 2 个；三进程稳定）。回滚点在游戏根目录。

---

## 二、全部更改清单

### 2.1 游戏本体文件（已修改，均有备份）

| 文件 | 更改 | 备份（游戏根，即回滚点） |
|---|---|---|
| `pfe.swf`（1.02，实玩目标） | MainFE 打通用 loader 补丁（详见 §5.5） | `pfe_before_genericloader_20260922_230137.swf` |
| `DLC\pfe.swf`（1.03） | 同上 | `DLC_pfe_before_genericloader_20260922_230335.swf` |
| `DLC\pfeUI.swf`（1.04） | 同上 | `DLC_pfeUI_before_genericloader_20260922_230509.swf` |

补丁内容（三份一致，逐条可审计）：MainFE 移除 7/3/2 个 `this.loadXxxMod();` 调用行 → 换成一行 `this.loadModsFromManifest();`（位于 `new MainMenu(this);` 之后）；新增 import `URLLoader`/`Dictionary`（1.02 还补 `SharedObject`）；新增字段 `manifestUrlLoader:URLLoader`、`modEntryByLoader:Dictionary`；类尾追加 7 个方法（§5.5）。**旧 loader 方法体与字段留作死代码**——刻意保留，让各模组自有补丁脚本的幂等标记（如 RConnect 查 `loadRConnectMod`）继续判定"已打补丁"。

### 2.2 游戏根新增文件（不动现有文件）

| 文件 | 作用 |
|---|---|
| `mods\loader-manifest.txt` | **加载矩阵唯一权威来源**（§三） |
| `app_booter_spike.xml` | 可行性 spike 的测试描述符（指向 spike 玩具，与生产无关，可删；保留是为复用实验装置） |

### 2.3 `mods\ModLoader\`（新项目，独立 git 仓库，v1.0.0 已提交）

```text
tools\patch_game_swfs.ps1   ★ 幂等补丁脚本（Steam 更新后重跑即恢复；-DryRun 干跑）
tools\smoke_test.ps1        ★ 冒烟脚本（注意 §5.4 沙箱警告！）
state\MEMORY.md             记忆快照（状态/资产/教训/接手点）
state\journal.md            开发日志（含两次大坑完整实证）
spike\src\*.as              可行性 spike 全部源码（Booter/MechBooter/CmpBooter/
                             ToyGame/ToyCrash/BigToy/ToyLoader/ToyT1-T5/ToyHostBooter）
spike\build\*.xml, gen_bigtoy.mjs   编译配置（amxmlc，绝对路径挂 playerglobal+airglobal）
spike\release\*.swf（19 个，未入 git）   spike 编译产物
work\（未入 git）            补丁脚本的导出/导入/校验中间物 + 已验证的
                             *.patched.swf（与线上哈希一致）+ 实验日志
```

### 2.4 shared-knowledge（编辑过 3 个文件）

| 文件 | 更改 |
|---|---|
| `facts\mod-loader-patch-structure.md` | 追加"2026-09-22 补充段"（新结构权威描述），frontmatter 日期更新 |
| `coordination\registry.md` | 登记 SharedObject 名 `ModLoader`；"游戏 SWF loader 路径"章节改为指向 manifest |
| `experiments\independent-mod-loader-feasibility.md` | 方案 A 判死全程 + 方案 B 实施终态 + 沙箱假阴性更正（新建文件，本轮两次大改） |

### 2.5 创建后又删除的临时物（留档备查）

`app_generictest.xml`、`pfe_generic_test.swf`（诊断用副本，已删）；计划任务 RemainsBootTest（创建失败即弃）；`1.BAT` 经 explorer 的启动尝试（未生效）。

### 2.6 明确未动的

`application.xml` / `app.xml` / `app104.xml` / `1.BAT` / `Remains.vbs` / 各模组目录与 release SWF（七个模组零改动）/ AGENTS.md / GOVERNANCE.md / 各技能。

---

## 三、使用手册（日常只碰这一个文件）

### 3.1 manifest 格式（`mods\loader-manifest.txt`）

```
# 注释行；空行忽略
目录名|入口类名|1.02开关|1.03开关|1.04开关
```

- **目录名** = `mods\` 下的目录，**保留既有怪癖原文**：`Rconnect`（小写 c，实际目录 `RConnect`，靠 Windows 大小写不敏感成立）、`MoreSkills&Weapons`（含 `&`）——**勿"顺手统一"**。
- **入口类名** = release 下 SWF 文件名（运行时契约：入口类名 = SWF 文件名，`init` 必须是 `public static function init(main:*)`）。
- **三列开关**：1=加载 0=跳过。1.02=根 `pfe.swf`；1.03=`DLC\pfe.swf`；1.04=`DLC\pfeUI.swf`。
- **行序 = 加载发起顺序**（当前 = 原调用序：ModSettings 最先，RandomRooms 最后）。
- 改完**重启游戏**生效（换 SWF/清单都要重启，AIR 已把内容读进内存）。

### 3.2 五个日常操作

| 想做什么 | 怎么做 |
|---|---|
| 加新模组 | SWF 放 `mods\<目录>\release\`，manifest 加一行，重启游戏 |
| 禁用某模组 | 对应列改 0（或整行注释掉），重启 |
| 调整加载顺序 | 移动行位置，重启 |
| 只在某版本加载 | 改三列开关 |
| 临时全部恢复原版行为 | 把三列全改 0（比回滚 SWF 轻得多） |

### 3.3 Steam 更新冲掉补丁后（一键恢复）

```powershell
cd "D:\Program Files\Steam\steamapps\common\Remains\mods\ModLoader\tools"
.\patch_game_swfs.ps1            # 三份全打；幂等：已打过会跳过
.\patch_game_swfs.ps1 -DryRun    # 先干跑看它会做什么（不动游戏文件）
```

脚本每步自校验（锚点失配即中止、导入后重新反编译断言），自动做时间戳备份再原子替换。**前置条件**：`D:\RemainsMod\mods\Sandevistan\build\tools\ffdec\ffdec-cli.jar` 与 Animate 2024 自带 JRE（路径可参数覆盖，见脚本头部）。若游戏更新改了 MainFE 结构导致锚点失配，脚本会明确报错——那是需要人工适配的信号，不要盲改。

### 3.4 回滚到补丁前（恢复原七-loader 结构）

```powershell
cd "D:\Program Files\Steam\steamapps\common\Remains"
Copy-Item pfe_before_genericloader_20260922_230137.swf pfe.swf -Force
Copy-Item DLC_pfe_before_genericloader_20260922_230335.swf DLC\pfe.swf -Force
Copy-Item DLC_pfeUI_before_genericloader_20260922_230509.swf DLC\pfeUI.swf -Force
```

重启游戏即回到 2026-09-22 之前的行为（含 ModSettings 在内的七模组硬编码 loader）。

---

## 四、体系如何运转（读代码前的地图）

```
游戏启动(adl64 → application.xml → pfe.swf)
 └─ MainFE.onEnterFrameLoader：bytesLoaded 满
     └─ new MainMenu(this)
     └─ this.loadModsFromManifest()          ← 新增的唯一调用点
         └─ URLLoader 读 app:/mods/loader-manifest.txt   （异步）
             └─ onManifestLoaded：
                 · this.loaderInfo.url 含 "pfeUI"→第5列 / "DLC"→第4列 / 否则第3列
                 · 逐行解析 → 对每个开关=1 的行：
                     new Loader().load("app:/mods/<目录>/release/<入口类>.swf",
                                       new LoaderContext(false))     ← 域拓扑与旧版逐字相同
                     modEntryByLoader[loader] = 入口类名             （Dictionary）
                 · onModSwfLoaded：getDefinition(入口类).init(this)   ← this=MainFE 实例，契约不变
                 · 全程 try/catch，任何失败只记标记，绝不阻断游戏
```

**保持不变的契约**：模组路径红线（`mods\<目录>\release\<Xxx>Mod.swf`）；`init` 静态签名；`new LoaderContext(false)` 子域语义（兄弟隔离、父域可见）；加载时机（晚于 MainMenu 构造，模组帧代码晚于游戏 step，capture 键监听先于游戏）；`<id>pfe</id>` 未动 → 存档/SharedObject/各模组 Local Store 全部原位。

**时序差异**（相对旧版，实测无感）：模组 load 比旧版晚约 1~3 帧（manifest 异步读取），各模组 init 完成仍错落在启动后约 10 秒内，与旧行为一致。

---

## 五、调试手册

### 5.1 四个观察通道（按可靠度排序）

| 通道 | 位置 | 看什么 |
|---|---|---|
| ① 模组自身文件日志 | `%APPDATA%\Roaming\pfe\Local Store\`：`sandy_modlog.txt`/`RConnect.log`/`RVision.log`/`RandomRooms_diag.log`/`ModSettings.log`/`tdfc.log` | 时间戳是否在本次启动后刷新 = 该模组是否完成 init（**主验证手段**；MSW 无日志文件，用其设置页 F6 出现与否判断） |
| ② ModLoader SharedObject | `Local Store\#SharedObjects\…\ModLoader.sol` | 键：`boot`（清单已读，值含 col=N）、`ok_<入口类>`（init 完成）、`err_loader`（清单读取/解析失败）、`err_<入口类>`（该模组 load/init 失败，值含错误文本）。**注意**：部分受限启动上下文 flush 会被拒（键只进 trace）——sol 缺失不等于 loader 没跑，以 ① 为准 |
| ③ 游戏是否到菜单 | 启动后能否看到载入条走完、主菜单出现 | 到了菜单 = 游戏本体 OK，问题在装载链；没到 = 游戏本体/环境问题，与 loader 无关 |
| ④ patch 脚本输出 | 脚本日志 | 部署期问题（锚点/导入/校验）都在这里报 |

### 5.2 常见故障对照表

| 症状 | 首查 | 常见原因 |
|---|---|---|
| 某模组没加载，其余正常 | ② 的 `err_<入口类>` | manifest 行写错：列数不足 5、目录名大小写/拼写与实际不符、入口类名 ≠ SWF 文件名；或 release SWF 缺失（IOError 文本会写进 err_ 值） |
| 全部模组都没加载 | ② 是否连 `boot` 都没有 | `mods\loader-manifest.txt` 不存在/不可读（`err_loader` 会记 IOError）；或游戏没到菜单（见 ③） |
| 游戏起不来（黑屏/卡载入） | ③ | 与本 loader 无关的概率大（loader 全程 catch 不阻断）；先回滚排除：§3.4 恢复备份后若同样起不来 → 环境问题，参考 §5.4 |
| init 报错 #1006 | ② 的 `err_<入口类>` | 模组入口 `init` 不是 `public static`（老坑，见 mod-loading-pitfalls #1） |
| 模组行为异常但加载了 | 模组自身日志 | 属模组 bug，走各模组调试（remains-runtime-debug），不是 loader 问题 |

### 5.3 快速验证三目标

```powershell
cd <游戏根>
# 1.02（application.xml）：期望七模组全载
# 1.03（app.xml）：期望恰载 Sandevistan/RConnect/RandomRooms
# 1.04（app104.xml）：期望恰载 Sandevistan/RConnect
# 用 smoke_test.ps1 自动断言（-Descriptor 换目标）：
.\mods\ModLoader\tools\smoke_test.ps1 -Descriptor application.xml
```

### 5.4 ⚠ 大坑一：受限沙箱里的冒烟全是假阴性

**dsh 受限沙箱（workspace-write 的 Windows Job）内启动 adl64，大 SWF 经 AIR URL 流式层装载会永久停滞**——窗口开、进程活、永远进不了菜单（≤约 500B 的小文件正常；FileStream 直读不受影响）。本轮曾据此把好补丁误判为失败并错误回滚一次，由用户桌面启动正名。

**纪律：验证游戏启动必须全权访问模式或用户桌面。**沙箱里能做的只有读日志/sol/文件（这些不受影响）。

### 5.5 ⚠ 大坑二：FFDec 编译器不能用 File/FileStream 字段

**给 MainFE（或任何经 `-importScript` 重编译的类）加 `flash.filesystem.File/FileStream` 类型的字段，importScript 编译会成功，但运行时类初始化静默死亡**（字段 trait 类型解析失败；无 INIT、无报错、黑屏）。方法内局部使用未测、不推荐。URLLoader/Dictionary/SharedObject/Event/字符串解析链均实测安全（spike ToyT1–T5 隔离实验）。通用 loader 代码里刻意只用后者。**想扩展 loader 功能时先查这份白名单。**

### 5.6 进阶：补丁/锚点维护

`patch_game_swfs.ps1` 的锚点：字段锚 `internal var mainMenu:MainMenu;`、调用锚 `this.mainMenu = new MainMenu(this);`、类尾 `\r\n   }\r\n}`、import 锚（URLRequest/getQualifiedClassName，缺失回退 ContextMenu）。**游戏官方更新若重构 MainFE，锚点失配会硬中止并报错**——那时需要人工适配（对照 `work\export-pfe\scripts\MainFE.as` 看新结构），不要盲目放宽断言。幂等标记 = `loadModsFromManifest`；已打补丁的文件直接跳过。

### 5.7 spike 实验装置（复用指南）

`spike\` 里的玩具是可复用的探针库：**CmpBooter**（对照装载两个 SWF 看 INIT/#1009/超时）、**ToyGame/ToyCrash**（构造器 stage 约束判定对）、**ToyT1–T5 + ToyHostBooter**（FFDec 编译器新构造白名单二分装置；宿主从 `work\toyhost-files.txt` 读装载清单）。配合游戏根 `app_booter_spike.xml`（content 指向 `spike\release\` 下某 SWF）用 `adl64 -runtime runtimes\air\win64 app_booter_spike.xml -nodebug` 启动。编译命令范本在 `spike\build\*.xml` + journal。

---

## 六、验证记录（2026-09-23 凌晨，全权访问模式）

| 目标 | 描述符 | 期望 | 实测 |
|---|---|---|---|
| 1.02 | application.xml | 七模组全载 | ✅ 六份模组日志启动后 5 秒内全 FRESH（MSW 无日志），60s 进程稳定 |
| 1.03 | app.xml | Sandy/RConnect/RandomRooms | ✅ 三者 FRESH，ModSettings 正确未载（col 门控生效） |
| 1.04 | app104.xml | Sandy/RConnect | ✅ 两者 FRESH，RandomRooms/ModSettings 正确未载 |

部署链每步自校验：干跑（三目标全绿）→ 备份 → 原子替换 → 哈希断言（线上 = work 副本）→ SWF 字符串标记扫描。

## 七、实施纪要（一段话版；全程详见 state\journal.md）

可行性分析判方案 A 死刑（墙 1：构造期 stage null，368B 复刻实测 #1009）→ 用户拍板路线 B → 导出三份 MainFE 盘点 7/3/2 个 loader → 写 manifest + 幂等补丁脚本 → 干跑全绿 → 部署 → **冒烟"失败"→ 误判回滚 → 用户桌面启动正名（沙箱假阴性，§5.4）→ 重新部署 → 三目标实测通过**。中途另用玩具隔离实验排除了 FFDec 编译器嫌疑并钉死 File/FileStream 字段雷区（§5.5）。

## 八、待办交接（用户侧 / 后续会话）

1. **AGENTS.md §3 加载矩阵表已过时**（现为 manifest 驱动、根目录实载七模组含 ModSettings）——用户维护，建议照 `facts\mod-loader-patch-structure.md` 2026-09-22 补充段更新。
2. `remains-swf-patching` / `remains-new-mod` / `remains-game-update` 技能的相关段落需修订（loader 注册从"FFDec 补丁"变"manifest 加行"；game-update 的恢复动作变"跑 patch_game_swfs.ps1"）。
3. `mods\ModLoader` 尚无 AGENT_SCOPE/完整脚手架，需要时走 remains-new-mod。
4. `app_booter_spike.xml` 与 `spike\release\` 的 19 个实验 SWF 属研究资产，不需要时可整体删除（git 里有源码可重建）。
