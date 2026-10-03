from pathlib import Path
import subprocess,io,zipfile,json,hashlib,shutil
GAME=Path(__file__).resolve().parents[4]
repo=GAME/'mods/RConnect'
dest=repo/'build/localization/stable-input'
dest.mkdir(parents=True,exist_ok=True)
baseline='9583c9d'
archive=subprocess.check_output(['git','-C',str(repo),'archive','--format=zip',baseline,'src','tools/build_mod.py','tools/stubs'])
with zipfile.ZipFile(io.BytesIO(archive)) as z:
    for name in z.namelist():
        target=(dest/name).resolve()
        assert target.is_relative_to(dest.resolve())
    z.extractall(dest)
files=['rconnect/ui/NetHud.as','rconnect/core/Session.as','rconnect/core/RoomSync.as','rconnect/core/TravelGuard.as','rconnect/game/ExplorationSync.as']
for p in (repo/'src/modlocales/connect').glob('*'):files.append(str(p.relative_to(repo/'src')))
for name in files:
    target=dest/'src'/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(repo/'src'/name,target)
hashes={str(p.relative_to(dest)):hashlib.sha256(p.read_bytes()).hexdigest() for p in dest.rglob('*') if p.is_file()}
(dest/'source-input.json').write_text(json.dumps({'baseline':baseline,'purpose':'Committed and deployed M41 plus localization; no uncommitted gameplay changes','files':hashes},indent=2),encoding='utf-8')
print(dest)
