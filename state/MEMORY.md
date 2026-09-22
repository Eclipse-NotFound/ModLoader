# ModLoader（通用清单加载器）MEMORY 快照

> 最后更新：2026-09-23（v1.0.0 部署完成）
> 冷启动阅读顺序：本文件 → journal.md → shared-knowledge\knowledge-validation\facts\mod-loader-patch-structure.md（2026-09-22 补充段）

## 当前状态：已部署，三目标实测通过

- 三份游戏 SWF（root pfe 1.02 / DLC pfe 1.03 / DLC pfeUI 1.04）的 MainFE 已打
  通用 loader 补丁（`loadModsFromManifest`，读 `mods\loader-manifest.txt`）。
- 实测：1.02 七模组全载；1.03 恰载 Sandy/RConnect/RandomRooms；1.04 恰载
  Sandy/RConnect（manifest 版本列门控生效）；三进程稳定。
- 旧 7/3/2 个专属 loader 调用点已移除；方法体留作死代码（保各模组补丁脚本幂等）。

## 关键资产

| 路径 | 作用 |
|---|---|
| `mods\loader-manifest.txt` | **加载矩阵唯一权威来源**（目录|入口类|1.02|1.03|1.04） |
| `mods\ModLoader\tools\patch_game_swfs.ps1` | 幂等补丁脚本（Steam 更新后重跑即恢复；-DryRun 干跑） |
| `mods\ModLoader\tools\smoke_test.ps1` | 冒烟（沙箱内结果不可信，见下） |
| `mods\ModLoader\work\*.patched.swf` | 已验证的补丁产物（与线上哈希一致） |
| `mods\ModLoader\spike\` | 可行性 spike 资产（Booter/MechBooter/CmpBooter/ToyT1-T5 等） |
| 游戏根 `*_before_genericloader_20260922_*.swf` | 回滚点（原七 loader 结构） |

## 已知问题 / 教训

1. **dsh 受限沙箱（workspace-write Job）内启动 adl64 = 大 SWF 装载假阴性**
   （窗口活、永不进菜单）。冒烟必须全权访问或用户桌面。本轮曾因此误判回滚。
2. FFDec 编译器**不能**编译含 `flash.filesystem.File/FileStream` **字段**的类
   （字段 trait 类型解析失败 → 类初始化静默死亡、无 INIT 无报错）；
   URLLoader/Dictionary/SharedObject/字符串链均实测可编译可运行。
   详见 journal 2026-09-22 条目与 spike ToyT1-T5。
3. ModLoader SharedObject 在部分受限上下文 flush 被拒（键仍会 trace）；
   验证模组装载用各模组自身文件日志（Local Store）更可靠。

## 工作区契约影响（需用户同步到 AGENTS.md，agent 不改）

- AGENTS §3"加载矩阵"表已过时：现为 manifest 驱动，根 pfe 1.02 实载**七**个模组
  （含 ModSettings）。
- 新模组接入流程变化：release 放 SWF + manifest 加行，**不再需要 FFDec 补丁**。
- remains-swf-patching / remains-new-mod / remains-game-update 技能的相关段落
  需要相应修订（属用户/后续任务）。

## 下一步候选

- git 仓库已初始化（见 journal）；如需 AGENT_SCOPE/完整脚手架走 remains-new-mod。
- 若 Steam 更新游戏：重跑 patch_game_swfs.ps1 + 三目标冒烟即可。
