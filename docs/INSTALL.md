# Install your first Remains mods

[简体中文](INSTALL.zh-CN.md) · [Back to the mod list](../README.md#choose-mods)

For Windows. Use **Remains 1.02** for this guide. No source download, command line or development tools are required.

<a id="first-install"></a>

## 1. Find the game folder, then save and exit

Steam Library → right-click Remains → **Manage → Browse local files**. Look for **`pfe.swf` and `application.xml`**. This is the “game folder” used below, not the folder containing a desktop shortcut.

## 2. Apply the one-time game patch

Download [Remains-GamePatch-v2.3.0.zip](https://github.com/Eclipse-NotFound/ModLoader/releases/download/v2.3.0/Remains-GamePatch-v2.3.0.zip), extract it, and double-click **`Patch-Game.bat`**. It searches for the Steam installation; if it cannot find it, enter the folder from step 1.

Wait for **`[done]`**. Keep the `*_before_modloader_*.swf` backups it creates in the game folder. If it reports an unsupported build, keep the error and report it; do not overwrite your game with someone else’s `pfe.swf`.

This installs the loading entry point. You still need the scanner and mod files below.

## 3. Install the settings component, scanner and chosen mods

Download [ModLoader_v2.3.0-r1.zip](https://github.com/Eclipse-NotFound/ModLoader/releases/download/v2.3.0-r1/ModLoader_v2.3.0-r1.zip) and [the mods you want](../README.md#choose-mods).

Right-click each ZIP → **Extract All**. Copy its **`mods` folder** into the game folder and merge matching folders. Do not leave the ZIP unopened or create a nested `mods/mods` folder.

For example, after adding Sandevistan:

    Remains/                         ← game folder
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

If a package includes **`default-config`**, it contains first-install templates. Copy the mod’s `config.txt` into its `release/config.txt` **only if that file does not already exist**. Preserve your settings on updates. Some mods save in-game settings in application data, which takes priority over these templates.

RandomRooms’ `optional-editor` is for map-editor users; skip it for ordinary play. RModifier is a separate EXE; follow [its own guide](https://github.com/Eclipse-NotFound/RModifier).

## 4. Scan, then launch

Double-click **`mods/ModLoader/RemainsModScanner.exe`**. It creates or updates **`mods/loader-manifest.txt`**, the list of mods to load. Close the result message, then start the game normally.

Use **PipBuck → Settings → Mods (`模组`)** for mods that provide settings. Follow each mod’s first-session instructions: for example, `\` for Sandevistan, F1 for RandomRooms and F6 for MSW. Not every mod has a settings page.

**Run the scanner and fully close/restart the game after adding, moving or updating mods.** Returning to the main menu and loading a save is not a full restart.

## Updates and temporary removal

- **Update:** save and exit → back up the old mod folder outside the game folder → merge the new package → keep your configuration (including the old co-op package’s `config.txt`) → scan → restart.
- **Disable temporarily:** save and exit → move the mod folder outside `mods` → scan → restart. To restore it, put it back, scan and restart. Keep ModLoader installed when disabling an individual mod.
- **RandomRooms:** return to town with F2 and save before removal. **RModifier:** use its recovery tools and keep projects, backups and installation records; do not apply the whole-folder removal method.
- **Advanced switches:** the scanner rebuilds `loader-manifest.txt`, so editing that file alone may not survive a rescan. For a persistent manual disable, set the mod’s final three switches in `mods/ModLoader/supported-mods.txt` to `0|0|0`, then scan. Keep the old ModSettings entry disabled; do not enable both settings components.

## Steam updates and restoring vanilla

A Steam update or **Verify integrity of game files** can restore the original loading entry point. Save and exit, then try step 2 again. The patcher accepts only known builds; wait for an update if yours is unsupported. Scan your mod files before starting again.

To restore the vanilla game, first back up mods, edited game files and saves, then use Steam’s file verification. It restores Steam-managed files, but does not remove every extra mod/editor file or undo every saved gameplay change. Use dedicated recovery for tools such as RModifier first; do not blindly overwrite newer changes with an old full-SWF backup.

<a id="troubleshooting"></a>

## If it does not work

| Problem | First check |
|---|---|
| I downloaded code and cannot find an installer | Use the homepage download link or the named ZIP / EXE under release **Assets**, not Source code |
| The latest ModLoader release has no Patch-Game.bat | GamePatch is attached to **v2.3.0**; use the direct link in step 2 |
| The scanner is missing | Also install **ModLoader_v2.3.0-r1.zip** from step 3 |
| None of the mods work | Check the game folder, one-time patch, nested `mods/mods`, scanner and full restart |
| Only one mod does not work | Check its `release/XxxMod.swf`, unchanged folder name and use of 1.02 |
| Editing config.txt has no effect | Try the in-game settings page; saved application data can override the template |
| Mods stopped after Steam verification | Close the game and reapply GamePatch; do not force it onto an unsupported build |
| How do I know it loaded? | Try that mod’s first-session steps; a successful scan alone does not verify gameplay |

Still stuck? [Report it to ModLoader](https://github.com/Eclipse-NotFound/ModLoader/issues) with game/mod/patch versions, the exact error and a screenshot of the `mods` folder. Report individual gameplay problems to the corresponding mod repository.
