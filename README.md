# Remains ModLoader

A manifest-driven mod loader and unified settings hub for **Fallout Equestria: REMAINS** (Steam, v1.02–1.04).

English (this page) · [简体中文](README.zh-CN.md)

## What it does

- Patches the game **once** with a generic loader; after that, installing, removing or reordering mods never touches the game files again — you only manage the `mods/` folder.
- Loads mods from `mods/loader-manifest.txt`: one line per mod, `directory|entryClass|1.02|1.03|1.04`, where the last three columns are per-game-version enable switches (`1`/`0`).
- Ships a unified in-game settings hub (press **F6**): every mod's settings in one panel, with expandable groups and settings that persist across restarts. Mods keep their legacy `ModSettingsCarrier.modAPI` interface — no separate ModSettings mod needed.
- Ships a Windows scanner (`RemainsModScanner.exe`) that discovers mod packages under `mods/<dir>/release/<Entry>Mod.swf` and regenerates the manifest. It validates basic SWF headers, keeps per-mod version ranges from `supported-mods.txt`, and never starts the game.

## Requirements

- Fallout Equestria: REMAINS installed via Steam.
- The one-time game patch applied once via the release package (below). Steam "verify integrity" restores vanilla files — just re-run the patcher afterwards; it is idempotent.

## Install / player quick start

1. Download `Remains-GamePatch-v2.3.0.zip` from [Releases](../../releases) and run `Patch-Game.bat`. It auto-locates your Steam install, verifies your game build by hash (supports five known vanilla builds across 1.02/1.03/1.04), backs the originals up and applies a binary patch that only injects this loader — no game content is redistributed.
2. Download `Remains-AllMods-*.zip` (or any individual mod package) and copy its `mods` folder into your game root (next to `pfe.swf`). Restart the game.

Full player-facing walkthrough (Chinese, with diagrams): see the "安装指南" linked in the release notes.

## How loading works

After the patch, `MainFE.onEnterFrameLoader` calls `loadModsFromManifest()` once the main menu is created. It reads `mods/loader-manifest.txt`, picks the version column for the running SWF, and `Loader.load()`s each enabled mod; on complete it resolves the entry class and calls its `static init(main)`. Manifest lines are trimmed (BOM-safe), validated for column count, switch values, duplicate entries and path segments; bad lines are logged as `err_manifest_<n>` and skipped without affecting other mods. Load/init failures are logged per-entry (`err_<Entry>`); the rest keep loading.

| Descriptor | Actual SWF | Loads |
|---|---|---|
| `application.xml` | `pfe.swf` (1.02, main play version) | all 7 mods |
| `app.xml` | `DLC/pfe.swf` (1.03) | 3 mods |
| `app104.xml` | `DLC/pfeUI.swf` (1.04) | 2 mods |

## Repository layout

```
src/runtime/    loader + settings runtime entry (compiled into release/ModLoaderMod.swf)
src/settings/   the settings hub service
tools/          patch_game_swfs.ps1 (FFDec-based patcher), scanner build/test scripts,
                player-patch/ (the player-facing RSPLICE1 patcher shipped in the GamePatch zip)
release/        ModLoaderMod.swf + supported-mods.txt
docs/           settings-interface.md (API for mods)
knowledge/, state/ — development records (Chinese)
```

The scanner exe is a local build artifact and is not committed; rebuild with `tools/build_scanner.ps1` (see the Chinese README for CLI flags such as `--dry-run --no-ui`).

## Verification tooling

- `tools/test_loader.ps1` — offline manifest regression (no game launch, no SWF changes).
- `tools/smoke_test.ps1 -Descriptor application.xml` — full smoke run in an isolated AIR app id; asserts run ids, requested/ok entries, no `err_*`.
- The player patcher verifies SHA-256 of both input (known vanilla builds) and output before writing anything.

## Related mods

[Sandevistan](https://github.com/Eclipse-NotFound/Sandevistan) ·
[MoreSkillsAndWeapons](https://github.com/Eclipse-NotFound/MoreSkillsAndWeapons) ·
[TDFC](https://github.com/Eclipse-NotFound/TDFC) ·
[RealisticVision](https://github.com/Eclipse-NotFound/RealisticVision) ·
[RandomRooms](https://github.com/Eclipse-NotFound/RandomRooms) ·
[RConnect](https://github.com/Eclipse-NotFound/RConnect)

> Fan mod project; not affiliated with the game's authors. Development records inside this repo are mostly written in Chinese.
