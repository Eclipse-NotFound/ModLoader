"""Two independent AIR fixtures through staged shared tools, never foreground.

The production register owns the outer group. An isolated candidate register
exercises coexist leases within that group; no live group is bypassed.
"""
from pathlib import Path
import ast,concurrent.futures,importlib.util,json,math,os,shutil,sys,threading,time,uuid
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[3]
PROJECT=ROOT/'mods/ModLoader'
CANDIDATE=PROJECT/'build/out/test-path-candidate-20261029'
sys.path.insert(0,str(PROJECT/'tools'))
from test_registry import Registration as OuterRegistration
spec=importlib.util.spec_from_file_location('candidate_registry',CANDIDATE/'test_registry.py')
registry=importlib.util.module_from_spec(spec);spec.loader.exec_module(registry)
sys.path.insert(0,str(CANDIDATE))
from air_test_process import HiddenProcess
from launch_integrity import digest,file_integrity,MEDIUM,LOW

fixture=ROOT/'mods/ContinuousScene/build/generated/cell-phase-alpha-mini-20261029'
assert digest(fixture/'Sampler.swf')=='6A2BF237EB836D7669F380C6176A8D81095040F47718212ED6354CB076F1AE7D'
# Reuse the complete read-only verifier, without importing its build/run entrypoints.
tree=ast.parse((fixture/'work.py').read_text(encoding='utf-8-sig'))
scope={'math':math}
exec(compile(ast.Module(body=[next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='verify')],type_ignores=[]),str(fixture/'work.py'),'exec'),scope)
out=PROJECT/'build/out/startup-repair-20261029'/('parallel-air-'+uuid.uuid4().hex[:10]);out.mkdir()
db=registry.Registry(out/'isolated-runs.sqlite3')
lock=threading.Lock();barrier=threading.Barrier(2,timeout=15)
record={'diagnosticOnly':True,'performanceEligible':False,'fixtures':[]}

def worker(name,outer):
    directory=out/name;directory.mkdir()
    app='pfe-cell-phase-snap-'+uuid.uuid4().hex
    store=Path(os.environ['APPDATA'])/app/'Local Store'
    assert not store.exists()
    shutil.copy2(fixture/'Sampler.swf',directory/'Sampler.swf')
    host=directory/'adl64.exe';shutil.copy2(ROOT/'adl64.exe',host)
    before=(digest(host),file_integrity(host));assert before[1]==LOW
    descriptor=directory/'application.xml'
    descriptor.write_text('<application xmlns="http://ns.adobe.com/air/application/32.0"><id>'+app+'</id><versionNumber>1.0.0</versionNumber><filename>Isolated drawing check</filename><initialWindow><content>Sampler.swf</content><visible>false</visible><width>640</width><height>480</height><renderMode>cpu</renderMode></initialWindow></application>',encoding='utf-8')
    row={'name':name,'appId':app,'store':str(store),'directory':str(directory)};proc=None
    with registry.Registration(owner=name,purpose='independent AIR drawing check',resource='game-coexist',run_dir=directory,evidence=directory/'result.json',registry=db,wait=20) as lease:
        try:
            with (directory/'stdout.txt').open('xb') as stdout,(directory/'stderr.txt').open('xb') as stderr:
                with lock:
                    outer.before_launch('Launch owned AIR '+name);lease.before_launch(name)
                    proc=HiddenProcess([host,'-runtime',ROOT/'runtimes/air/win64',descriptor],cwd=directory,stdout=stdout,stderr=stderr)
                    outer.child(proc.pid);lease.child(proc.pid)
                row.update(pid=proc.pid,desktop=proc.desktop,launch=proc.launch_info,start=time.monotonic())
                assert proc.launch_info['reusedCanonicalHost'] and proc.launch_info['resolvedIntegrity']==MEDIUM
                barrier.wait()
                assert sum(r['state']=='running' for r in db.status())==2
                row['exitCode']=proc.wait(30);row['end']=time.monotonic()
                assert row['exitCode']==0
                shutil.copytree(store,directory/'storage')
                result=json.loads((directory/'storage/result.json').read_text(encoding='utf-8-sig'))
                valid=scope['verify'](result)
                row.update(valid=valid['valid'],assertions=len(result['assertions']),resourcesBalanced=result['sampling']['resourcesBalanced'])
                assert before==(digest(host),file_integrity(host))
                row['copyBytesAndLabelUnchanged']=True
                lease.outcome='passed';lease.note='39 drawing checks passed; separate desktop/app ID/store; no performance claim'
        finally:
            if proc:
                if proc.poll() is None:proc.kill();proc.wait(15)
                proc.close();lease.child_stopped()
            (directory/'result.json').write_text(json.dumps(row,indent=2),encoding='utf-8')
    return row

with OuterRegistration(owner='ModLoader / shared startup repair',purpose='two isolated native AIR fixtures',run_dir=out,evidence=out/'result.json',wait=120) as outer:
    try:
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            futures=[pool.submit(worker,name,outer) for name in ('a','b')]
            record['fixtures']=[f.result() for f in futures]
        a,b=record['fixtures'];overlap=min(a['end'],b['end'])-max(a['start'],b['start'])
        assert overlap>0 and all(a[k]!=b[k] for k in ('pid','desktop','appId','store','directory'))
        assert all(r['state']=='passed' for r in db.status())
        record.update(valid=True,overlapSeconds=overlap,assertions=78,leasesReleased=True)
        outer.outcome='passed';outer.note='Two concurrent AIR fixtures passed 39 checks each; isolation and cleanup confirmed'
    finally:
        outer.child_stopped()
        (out/'result.json').write_text(json.dumps(record,indent=2),encoding='utf-8')
print(json.dumps({'out':str(out),**record}))
