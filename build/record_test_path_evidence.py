"""Read completed evidence, preserve compact receipts; launches no process."""
from pathlib import Path
import hashlib,json,shutil
project=Path(__file__).resolve().parents[1]
base=project/'build/out/startup-repair-20261029'
target=project/'knowledge/experiments/startup-test-path-2026-10-29';target.mkdir(parents=True,exist_ok=True)
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
pair=read(base/'debugger-pair-8b2a050bc9/result.json')
details=[]
for session in pair['sessions']:
    directory=Path(session)/'trials/perf-01-full'
    meta=read(directory/'meta.json');result=read(directory/'result.json')
    raw=read(directory/'storage/agent-debug/result.json')
    assert result['valid'] and result['scene']['menuLoaded'] and not result['environment']['performanceEligible']
    assert meta['desktopMode']=='isolated' and meta['desktopName'].startswith('RemainsTest-') and raw['audioVolume']==0
    details.append({k:meta[k] for k in ('pid','appId','desktopName','store','startedMs','endedMs')})
    details[-1].update(audioVolume=raw['audioVolume'],resultSHA256=sha(directory/'result.json'),metaSHA256=sha(directory/'meta.json'))
assert all(len({r[k] for r in details})==2 for k in ('pid','appId','desktopName','store'))
assert pair['valid'] and pair['allLeasesPassed'] and pair['driverExitCodes']==[0,0]
checks=read(project/'build/out/test-path-candidate-20261029/checks.json')
assert checks['success'] and checks['tests']==68
for name,expected in checks['inputs'].items():assert sha(project/'tools'/name)==expected
summary={'valid':True,'checks':checks,'parallelAIR':read(base/'parallel-air-081755fb65/result.json'),
         'installedDebugger':pair,'installedDesktopReadback':details,
         'originalLauncher':read(base/'probe-launcher-78fd5415cd/result.json'),
         'originalAIR':{k:v for k,v in read(base/'probe-air-root-9e3204cbe8/result.json').items() if k!='windows'}}
(target/'validation.json').write_text(json.dumps(summary,indent=2,ensure_ascii=False),encoding='utf-8')
for name in ('entry-label-repair.json','mod-entry-label-repair.json'):shutil.copy2(base/name,target/name)
shutil.copy2(project/'work/backups/before-test-path-20261029-de6a185d96/installation.json',target/'installation.json')
print(json.dumps({'record':str(target),'checks':68,'nativeFixtureAssertions':78,'gameMenus':2,'distinctDesktopsAndStores':True}))
