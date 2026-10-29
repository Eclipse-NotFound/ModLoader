"""Install only the fingerprinted, checked shared-tool candidate with backups."""
from pathlib import Path
import hashlib,json,os,shutil,sys,uuid
sys.dont_write_bytecode=True
project=Path(__file__).resolve().parents[1]
tools=project/'tools';candidate=project/'build/out/test-path-candidate-20261029'
sys.path.insert(0,str(tools))
from test_registry import Registration,Registry
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
baseline={
 'launch_integrity.py':None,
 'air_test_process.py':'ECE3ED087D9E31AC4EC91FA1E7B7F82985A149D503C55E682C1C2241027CC3B0',
 'test_registry.py':'E3E43581D677D26C83B7E887C64669634CCC8D901AEFA5A826E1CFED8A5F0CF0',
 'mod_debugger.py':'AA8AA91E2AC5795DD3D5F5625625992221393280F8D0487C3C079F362A5AEFC4'}
checks=json.loads((candidate/'checks.json').read_text(encoding='utf-8'))
assert checks['success'] and checks['tests']==68
backup=project/'work/backups'/('before-test-path-20261029-'+uuid.uuid4().hex[:10]);backup.mkdir(parents=True)
receipt={'backup':str(backup),'files':[],'valid':False}
with Registration(owner='ModLoader / test path repair',purpose='install validated shared tools',run_dir=backup,evidence=backup/'installation.json',wait=120) as lease:
    try:
        assert not [r for r in Registry().status() if r['id']!=lease.id and r['state'] in ('waiting','running','needs-check')], 'Other test request present; retry installation after it completes'
        for name,expected in baseline.items():
            path=tools/name
            assert (sha(path) if path.exists() else None)==expected, 'Concurrent change: '+name
            assert sha(candidate/name)==checks['inputs'][name]
            if expected:shutil.copy2(path,backup/name)
            receipt['files'].append({'path':str(path),'before':expected,'after':checks['inputs'][name],'installed':False})
        for row in receipt['files']:
            path=Path(row['path']);temp=path.with_name(path.name+'.install-'+uuid.uuid4().hex)
            try:
                shutil.copy2(candidate/path.name,temp)
                assert (sha(path) if path.exists() else None)==row['before']
                os.replace(temp,path);row['installed']=True
                assert sha(path)==row['after']
            finally:temp.unlink(missing_ok=True)
        receipt['valid']=True;lease.outcome='passed';lease.note='Four verified shared tools installed; no SWF/manifest changes'
    except BaseException:
        for row in reversed(receipt['files']):
            path=Path(row['path'])
            if row['installed'] and path.exists() and sha(path)==row['after']:
                if row['before']:
                    temp=path.with_name(path.name+'.rollback-'+uuid.uuid4().hex);shutil.copy2(backup/path.name,temp);os.replace(temp,path)
                else:path.unlink()
                row['rolledBack']=True
        raise
    finally:
        (backup/'installation.json').write_text(json.dumps(receipt,indent=2),encoding='utf-8')
print(json.dumps(receipt))
