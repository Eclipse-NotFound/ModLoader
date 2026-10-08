# 第一次给 Remains 安装模组

[English](INSTALL.md) · [返回模组列表](../README.zh-CN.md#choose-mods)

适用于 Windows。按 **Remains 1.02** 游玩；不需要下载源码、输入命令或安装开发工具。

<a id="first-install"></a>

## 1. 找到游戏文件夹，保存并退出

Steam 库 → 右键 Remains → **管理 → 浏览本地文件**。这个文件夹里应有 **`pfe.swf` 和 `application.xml`**。后面说的“游戏目录”都是这里，不是桌面快捷方式所在位置。

## 2. 安装一次性游戏补丁

下载 [Remains-GamePatch-v2.3.0.zip](https://github.com/Eclipse-NotFound/ModLoader/releases/download/v2.3.0/Remains-GamePatch-v2.3.0.zip)，先解压，再双击里面的 **`Patch-Game.bat`**。工具会寻找 Steam 安装位置，找不到时输入第 1 步的游戏目录。

看到 **`[done]`** 后继续。工具会在游戏目录生成 `*_before_modloader_*.swf` 备份，请保留。若提示不支持的构建，不要找别人的 `pfe.swf` 来覆盖；记录报错并反馈。

这一步只装加载入口，还需要下一步的扫描器与模组文件。

## 3. 安装设置组件、扫描器与想玩的模组

下载 [ModLoader_v2.3.0-r1.zip](https://github.com/Eclipse-NotFound/ModLoader/releases/download/v2.3.0-r1/ModLoader_v2.3.0-r1.zip)，以及[你选中的模组](../README.zh-CN.md#choose-mods)。

右键 ZIP → **全部解压**。把各包里的 **`mods` 文件夹**复制到游戏目录，同名文件夹选择合并。不要把 ZIP 直接放进去，也不要复制成 `mods/mods`。

例如安装斯安维斯坦后，结构应为：

    Remains/                         ← 游戏目录
      pfe.swf
      application.xml
      mods/
        ModLoader/
          RemainsModScanner.exe
          supported-mods.txt
          release/ModLoaderMod.swf
        Sandevistan/
          release/SandevistanMod.swf
          release/config.txt

如果模组包含 **`default-config`**，它是首次安装用的配置模板：把其中对应模组的 `config.txt` 复制到该模组 `release/config.txt`，**只在还没有此文件时复制**。升级不覆盖自己的设置。部分模组的游戏内设置保存在应用数据中，优先于这个模板。

RandomRooms 的 `optional-editor` 供地图编辑器用户使用，普通游玩可跳过。RModifier 是独立 EXE，请按[它的使用指南](https://github.com/Eclipse-NotFound/RModifier/blob/master/README.zh-CN.md)操作。

## 4. 扫描，再启动

双击 **`mods/ModLoader/RemainsModScanner.exe`**。它会生成或更新 **`mods/loader-manifest.txt`**，让游戏知道有哪些模组。完成后关闭结果提示，按原来的方式启动游戏。

在 **哔哔小马 → 设置 → 模组** 查看已提供设置的模组；具体玩法按各模组首页说明操作，例如斯安维斯坦按 `\`、RandomRooms 按 F1、MSW 按 F6。不是每个模组都有设置页。

**新增、移走或更新模组后，都重新扫描并完全退出重启游戏。** 回主菜单再读档不能代替重启。

## 更新与临时停用

- **更新模组**：保存退出 → 将旧模组文件夹复制到游戏目录外作备份 → 合并新包 → 保留自己的配置（包括联机包内的旧 `config.txt`）→ 扫描 → 重启。
- **临时停用**：保存退出 → 把对应模组文件夹移到 `mods` 之外 → 扫描 → 重启。想恢复时放回原位置、再扫描重启。不要为停用单个模组移走 ModLoader。
- **RandomRooms**：停用前 F2 返回城镇并正常保存。**RModifier**：使用工具自带恢复功能并保留作品、备份与安装记录，不套用整目录移走的方法。
- **高级手动开关**：扫描器会重建 `loader-manifest.txt`；只改该文件，下次扫描可能恢复。确需长期禁用，修改 `mods/ModLoader/supported-mods.txt` 中该模组行最后三个开关为 `0|0|0`，再扫描。保留旧 ModSettings 的禁用登记，不要让两个设置组件同时启用。

## Steam 更新与恢复原版

Steam 更新或“验证文件完整性”可能还原加载入口。先保存退出，再尝试第 2 步；补丁器只接受已知构建，遇到新构建请等待适配。模组文件仍需扫描后再启动。

如果要恢复整套原版游戏，先备份模组、自己编辑过的游戏文件和存档，再使用 Steam 验证文件。它会恢复受 Steam 管理的游戏文件，但不会替你清理所有额外模组/编辑器文件，也不能当作撤销所有存档变化。RModifier 等工具的专属改动先按各自恢复说明处理；不要盲目用早期整份 SWF 备份覆盖后续修改。

<a id="troubleshooting"></a>

## 没生效时，按顺序检查

| 看到的问题 | 先做什么 |
|---|---|
| 只看到源码，不知道运行哪个 | 重新使用首页的下载链接，或发布页 **Assets** 下的具名 ZIP / EXE；不要选 Source code |
| 最新 ModLoader 发布没有 Patch-Game.bat | GamePatch 位于 **v2.3.0**；使用第 2 步的直接链接 |
| 找不到扫描器 | 还需要安装第 3 步的 **ModLoader_v2.3.0-r1.zip** |
| 全部模组都没反应 | 检查游戏目录、一次性补丁、`mods/mods` 套层、是否扫描以及是否完全重启 |
| 只有一个没反应 | 检查对应 `release/XxxMod.swf` 是否存在，目录名是否保持原样，以及是否使用 1.02 |
| 改 config.txt 但没变化 | 优先从游戏内设置页修改；已保存的应用数据可能覆盖模板 |
| Steam 验证文件后失效 | 完全退出游戏，重新运行 GamePatch；不支持的构建不要强行处理 |
| 不知道是否安装成功 | 按该模组首页的“第一次怎么玩”试一次；单纯扫描成功不等于已验证所有玩法 |

仍不能解决，请在 [ModLoader Issues](https://github.com/Eclipse-NotFound/ModLoader/issues)附上游戏版本、模组/补丁版本、错误原文和 `mods` 目录截图。单个模组的玩法问题请到它自己的 Issues 反馈。
