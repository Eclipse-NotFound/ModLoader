"""Extract selected bundle entries for offline inspection; never execute the launcher."""
from pathlib import Path
import hashlib,json,struct,zlib,re,importlib.util
ROOT=Path(__file__).resolve().parents[3];out=ROOT/'mods/ModLoader/build/out/startup-repair-20261029'
data=(ROOT/'Remains.exe').read_bytes();discovery=json.loads((out/'bundle-discovery.json').read_text('utf-8'))
assert hashlib.sha256(data).hexdigest().upper()==discovery['sha256'] and len(discovery['headers'])==1
cursor=discovery['headers'][0]['offset']
def read(fmt):
    global cursor
    result=struct.unpack_from(fmt,data,cursor);cursor+=struct.calcsize(fmt);return result
def string():
    global cursor
    length=shift=0
    while True:
        v=data[cursor];cursor+=1;length|=(v&127)<<shift;shift+=7
        if not(v&128):break
        assert shift<=35
    assert 0<=length<=32768
    value=data[cursor:cursor+length].decode('utf-8');cursor+=length;return value
major,minor,count=read('<III');ident=string();meta=read('<qqqqQ')
assert (major,minor,count)==(6,0,356)
rows=[]
for index in range(count):
    offset,size,compressed,kind=read('<qqqB');name=string()
    assert offset>=0 and size>=0 and compressed>=0 and offset+(compressed or size)<=len(data)
    row=dict(offset=offset,size=size,compressed=compressed,kind=kind,name=name)
    if name in ('Remains.dll','Remains.runtimeconfig.json','Remains.deps.json'):
        content=data[offset:offset+(compressed or size)]
        if compressed:content=zlib.decompress(content,-15)
        assert len(content)==size
        target=out/name
        with target.open('xb') as f:f.write(content)
        row['sha256']=hashlib.sha256(content).hexdigest().upper()
    rows.append(row)
assert cursor==len(data)
(out/'bundle-manifest.json').write_text(json.dumps(rows,indent=2),encoding='utf-8')
assembly=(out/'Remains.dll').read_bytes()
terms=[m.group().decode('ascii') for m in re.finditer(rb'[A-Za-z_][A-Za-z0-9_<>.]{3,120}',assembly) if re.search(rb'(?i)temp|extract|error|cache|runtime|program|startup',m.group())]
print(json.dumps({'selected':[r for r in rows if 'sha256' in r],'terms':sorted(set(terms)),'dnfile':bool(importlib.util.find_spec('dnfile'))},ensure_ascii=False))
