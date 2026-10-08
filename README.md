# Remains mod starter guide · ModLoader

**English** · [简体中文](README.zh-CN.md)

Start here if you are new to modding Fallout Equestria: REMAINS. ModLoader lets the game load mods and provides their in-game settings. Pick only the gameplay changes you want. **No coding or developer tools required.**

**[Open the step-by-step installation guide](docs/INSTALL.md)** · [All downloads and release notes](https://github.com/Eclipse-NotFound/ModLoader/releases)

## Which files do I need?

| File | Purpose |
|---|---|
| [Remains-GamePatch-v2.3.0.zip](https://github.com/Eclipse-NotFound/ModLoader/releases/download/v2.3.0/Remains-GamePatch-v2.3.0.zip) | First installation: enables mod loading; extract and run Patch-Game.bat |
| [ModLoader_v2.3.0-r1.zip](https://github.com/Eclipse-NotFound/ModLoader/releases/download/v2.3.0-r1/ModLoader_v2.3.0-r1.zip) | Settings component and scanner: merge the package’s mods folder into the game folder |
| Your chosen mod package(s) below | Adds the gameplay features: bullet time, weapons, maps and more |

**You need both setup downloads.** The latest v2.3.0-r1 release contains the settings/scanner package only. The first-time GamePatch is still attached to v2.3.0, so both direct links are provided above.

For Windows. Start with **Remains 1.02**. The patcher recognizes some 1.03/1.04 builds, but that does not mean every mod or the settings component supports those versions.

## Installation order

1. Save and close the game; Steam Library → right-click Remains → **Manage → Browse local files**.
2. Extract GamePatch, double-click **Patch-Game.bat**, and select the game folder if prompted. Wait for **[done]** and keep its automatic backups.
3. Extract ModLoader and your chosen mods. Merge each package’s **mods** folder into the game folder, next to pfe.swf.
4. Double-click **mods/ModLoader/RemainsModScanner.exe**, wait for completion, close its message, then launch the game normally.
5. Open **PipBuck → Settings → Mods (`模组`)** for mods that provide settings. MSW also has its own F6 shortcut.

Missing files or no mod effect? [Check the folder diagram and troubleshooting steps](docs/INSTALL.md#troubleshooting). The scanner updates the mod list; it does not launch the game.

<a id="choose-mods"></a>

## Choose your mods

| Mod | What it adds | Public version |
|---|---|---|
| [Sandevistan](https://github.com/Eclipse-NotFound/Sandevistan) | Bullet time, fast replays and colorful afterimages | [v1.145](https://github.com/Eclipse-NotFound/Sandevistan/releases/tag/v1.145) |
| [MoreSkillsAndWeapons](https://github.com/Eclipse-NotFound/MoreSkillsAndWeapons) | Smart bullets, ricochets, lasers and combat controls | [v1.15.3](https://github.com/Eclipse-NotFound/MoreSkillsAndWeapons/releases/tag/v1.15.3) |
| [TDFC](https://github.com/Eclipse-NotFound/TDFC) | Enemy perception and tactics with vanilla HP and damage | [v0.6.4](https://github.com/Eclipse-NotFound/TDFC/releases/tag/v0.6.4) |
| [RealisticVision](https://github.com/Eclipse-NotFound/RealisticVision) | Line of sight, exploration fog and remembered terrain | [v0.30.1](https://github.com/Eclipse-NotFound/RealisticVision/releases/tag/v0.30.1) |
| [RandomRooms](https://github.com/Eclipse-NotFound/RandomRooms) | Four themes of expanding procedural exploration | [v13.2](https://github.com/Eclipse-NotFound/RandomRooms/releases/tag/v13.2) |
| [RConnect](https://github.com/Eclipse-NotFound/RConnect) | Explore together with one friend | [v0.2.8](https://github.com/Eclipse-NotFound/RConnect/releases/tag/v0.2.8) |
| [RModifier](https://github.com/Eclipse-NotFound/RModifier) | Chinese desktop tool for loot, lines and maps | [v0.4.0](https://github.com/Eclipse-NotFound/RModifier/releases/tag/v0.4.0) |

You do not need the whole collection. `Remains-AllMods-2026-09-24.zip` is a snapshot from that date, **not an automatically updated bundle**. Use the individual project pages for newer versions. RModifier is a separate desktop editor with its own game-connection steps.

## Updating, disabling and common problems

Run the scanner and restart after adding mods. Back up old mod files and preserve your configuration when updating. To disable a mod temporarily, move its folder outside `mods`, scan and restart. A Steam update or file verification may require the game patch again; do not force installation on an unsupported build.

[Full installation, updating, disabling and recovery guide](docs/INSTALL.md) · [Report an installation problem](https://github.com/Eclipse-NotFound/ModLoader/issues)

<details>
<summary>Development resources (not needed to install)</summary>

[Settings API](docs/settings-interface.md) · [Technical and historical validation notes (Chinese)](docs/DEVELOPMENT.zh-CN.md) · [Source](src/) · [Release history](https://github.com/Eclipse-NotFound/ModLoader/releases)

Runtime 2.3.0, scanner 2.1; r1 updates the compatibility table. Manifest generation, builds, validation and historical deployment recovery belong in the development reference.

</details>

An unofficial fan project; you need your own copy of the game.
