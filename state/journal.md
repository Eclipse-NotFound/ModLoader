# ModLoader 开发日志（journal）

## 2026-09-23 凌晨 — v1.0.0 通用清单加载器部署完成（三目标实测通过）

**做了什么**：路线 B 落地。`patch_game_swfs.ps1` 把三份游戏 SWF 的 MainFE 中
7/3/2 个专属 loader 调用点替换为单一 `loadModsFromManifest()`（读
`mods\loader-manifest.txt`，版本列门控 1.02/1.03/1.04）。旧 loader 方法体留作
死代码保各模组补丁脚本幂等。域拓扑/时序/init 契约逐字保留。

**验证**：1.02 七模组全载（六模组日志 FRESH）；1.03 恰载 Sandy/RConnect/
RandomRooms；1.04 恰载 Sandy/RConnect；三进程 60s 稳定。回滚点 =
游戏根 `*_before_genericloader_20260922_*.swf`。

**过程中的两个大坑（都已实证并写进 shared-knowledge）**：
1. **沙箱假阴性**：dsh 受限沙箱 Job 内启动 adl64，大 SWF 经 AIR URL 流式层装载
   永久停滞（≤501B 正常）——冒烟全军覆没的假象。曾据此误判补丁失败、错误回滚
   一次；用户桌面启动正名后重新部署，全绿。教训：冒烟必须全权访问或用户桌面。
2. **FFDec 编译器雷区**：类含 `flash.filesystem.File/FileStream` 字段时，importScript
   编译成功但运行时类初始化静默死亡（字段 trait 类型解析不了）。spike ToyT1-T5
   隔离实验钉死；通用 loader 代码（URLLoader/Dictionary/SharedObject/解析链）
   FFDec 编译实测完全正常。

**AI 建议 vs 用户决定 vs 实证**：方案 A/B 取舍由用户拍板（"实现路线B"）；
三道"墙"中墙 1（构造期 stage null → #1009）为真（368B 实测），墙 2/#3226
部分为沙箱假象（事后修正）。

**接手点**：AGENTS.md §3 矩阵表与三个技能（swf-patching/new-mod/game-update）
的相关段落待修订（用户侧）；manifest 日常维护见 MEMORY.md。
