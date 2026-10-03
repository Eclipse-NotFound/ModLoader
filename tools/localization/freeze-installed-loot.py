"""Backport only the localization UI to installed LootEditor 0.2.1.

The current RModifier source also supports bridge v2 (LootEditor 0.3.0).
Localization must not silently upgrade the installed game connection.
"""
import hashlib
import io
import json
import shutil
import subprocess
import zipfile
from pathlib import Path

game = Path(__file__).resolve().parents[4]
repo = game / "mods/RModifier"
target = repo / "build/out/localization/installed-input"
baseline = "6567ebe"
archive = subprocess.check_output([
    "git", "-C", str(repo), "archive", "--format=zip", baseline,
    "src", "desktop/data/catalog.json", "build/build.ps1",
])
target.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(io.BytesIO(archive)) as files:
    for name in files.namelist():
        if not (target / name).resolve().is_relative_to(target.resolve()):
            raise ValueError("Archive path escaped the private build directory")
    files.extractall(target)
source = target / "src/LootEditorMod.as"
old = source.read_text(encoding="utf-8-sig")
current = (repo / "src/LootEditorMod.as").read_text(encoding="utf-8-sig")
assert 'VERSION:String="0.2.1"' in old
assert "translateMenu" in current
begin = "        private static function registerMenu():void {"
end = "        public static function selectRule(ctx:Object):Object {"
old = old[:old.index(begin)] + current[current.index(begin):current.index(end)] + old[old.index(end):]
old = old.replace("package {", "package {\n    import modlocales.loot.LootLocale;", 1)
old = old.replace("private static var menuReady:Boolean=false;", "private static var menuReady:Boolean=false;\n        private static var menuDescription:String=\"\";", 1)
source.write_text(old, encoding="utf-8")
shutil.copytree(repo / "src/modlocales/loot", target / "src/modlocales/loot", dirs_exist_ok=True)
hashes = {str(p.relative_to(target)): hashlib.sha256(p.read_bytes()).hexdigest()
          for folder in ["src", "desktop/data"] for p in (target / folder).rglob("*") if p.is_file()}
(target / "source-input.json").write_text(json.dumps({
    "baseline": baseline, "version": "0.2.1", "scope": "localized UI only; existing bridge and rules retained", "files": hashes,
}, indent=2) + "\n", encoding="utf-8")
print(target)
