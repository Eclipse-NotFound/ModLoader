"""Post-install check: two independent debugger CLI requests, private game menus."""
from pathlib import Path
import hashlib,json,subprocess,sys,time,uuid
sys.dont_write_bytecode=True
project=Path(__file__).resolve().parents[1];root=project.parents[1]
sys.path.insert(0,str(project/'tools'))
from test_registry import Registry
from test_resources import snapshot
out=project/'build/out/startup-repair-20261029'/('debugger-pair-'+uuid.uuid4().hex[:10]);out.mkdir()
tool=project/'tools/mod_debugger.py'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
protected=[root/'mods/loader-manifest.txt',root/'pfe.swf',root/'mods/ContinuousScene/release/ContinuousSceneMod.swf']
before={str(p):sha(p) for p in protected}
record={'environmentBefore':snapshot(),'sessions':[],'drivers':[],'valid':False,'performanceEligible':False}
assert record['environmentBefore']['memory']['availableCommit']>4*1024**3
handles=[];running=[]
try:
    for name in ('a','b'):
        command=[sys.executable,'-B',str(tool),'prepare','--mods','ModLoaderMod','--scenario','menu',
                 '--profile','coexist','--plan','smoke','--warmup','1','--seconds','2','--timeout','45']
        prepared=subprocess.run(command,capture_output=True,text=True,encoding='utf-8',timeout=120)
        (out/(name+'-prepare.log')).write_text(prepared.stdout+'\n'+prepared.stderr,encoding='utf-8')
        assert prepared.returncode==0, prepared.stderr
        session=Path(json.loads(prepared.stdout.strip().splitlines()[-1])['session'])
        record['sessions'].append(str(session))
    for name,session in zip(('a','b'),record['sessions']):
        output=(out/(name+'-run.log')).open('xb');handles.append(output)
        command=[sys.executable,'-B',str(tool),'run','--session',session,'--owner','ModLoader / installed parallel '+name,'--wait','60']
        process=subprocess.Popen(command,stdout=output,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
        running.append(process);record['drivers'].append({'pid':process.pid,'session':session})
    deadline=time.monotonic()+120
    while any(p.poll() is None for p in running):
        assert time.monotonic()<deadline,'Owned debugger still running; inspect its registration before cleanup'
        if not record.get('bothLeasesRunning'):
            rows=[r for r in Registry().status() if r['runDir'] in record['sessions'] and r['state']=='running']
            if len(rows)==2:record['bothLeasesRunning']=[{'id':r['id'],'pid':r['runner']['pid'],'resource':r['resource']} for r in rows]
        time.sleep(.2)
    assert all(p.returncode==0 for p in running)
    details=[]
    for session in record['sessions']:
        trial=Path(session)/'trials/perf-01-full'
        meta=json.loads((trial/'meta.json').read_text(encoding='utf-8'))
        result=json.loads((trial/'result.json').read_text(encoding='utf-8'))
        assert result['valid'],result.get('errors')
        assert not result['environment']['performanceEligible']
        assert meta['launchHost']['reusedCanonicalHost']
        assert meta['desktopMode']=='isolated'
        details.append({'session':session,'appId':meta['appId'],'desktop':meta['desktopName'],'store':meta['store'],'pid':meta['pid'],'startedMs':meta['startedMs'],
                        'endedMs':meta['endedMs'],'valid':True,'launchHost':meta['launchHost'],'result':str(trial/'result.json')})
    assert record.get('bothLeasesRunning') and len({r['pid'] for r in record['bothLeasesRunning']})==2
    assert all(r['resource']=='game-coexist' for r in record['bothLeasesRunning'])
    assert all(len({r[k] for r in details})==2 for k in ('appId','desktop','store','pid'))
    overlap=min(r['endedMs'] for r in details)-max(r['startedMs'] for r in details)
    assert overlap>0
    final=[r for r in Registry().status() if r['runDir'] in record['sessions']]
    assert len(final)==2 and all(r['state']=='passed' for r in final)
    assert before=={str(p):sha(p) for p in protected}
    record.update(valid=True,details=details,overlapMs=overlap,allLeasesPassed=True,playerFilesUnchanged=before)
finally:
    for output in handles:output.close()
    record['driverExitCodes']=[p.poll() for p in running]
    (out/'result.json').write_text(json.dumps(record,indent=2),encoding='utf-8')
print(json.dumps({'out':str(out),**record}))
