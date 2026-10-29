"""Read-only discovery of the original launcher's .NET bundle manifest."""
from pathlib import Path
import hashlib,json,re,struct
root=Path(__file__).resolve().parents[3];data=(root/'Remains.exe').read_bytes()
tail=max(0,len(data)-256*1024)
names=[]
for match in re.finditer(rb'[A-Za-z0-9_.\-/]{3,120}\.(?:dll|json|pdb)',data[tail:]):
    names.append({'offset':tail+match.start(),'name':match.group().decode('ascii')})
headers=[]
for match in re.finditer(rb'[\x01\x02\x06]\x00\x00\x00\x00\x00\x00\x00',data[tail:]):
    off=tail+match.start();major,minor,count=struct.unpack_from('<III',data,off)
    if 1<=count<=1000 and off+13<len(data) and 8<=data[off+12]<=64:headers.append({'offset':off,'major':major,'count':count,'idLength':data[off+12]})
out=root/'mods/ModLoader/build/out/startup-repair-20261029';out.mkdir(parents=True,exist_ok=True)
record={'sha256':hashlib.sha256(data).hexdigest().upper(),'length':len(data),'names':names,'headers':headers}
(out/'bundle-discovery.json').write_text(json.dumps(record,indent=2),encoding='utf-8')
print(json.dumps({'length':len(data),'headers':headers,'names':names[-15:]}))
