"""Check staged shared tools against an isolated test database and owned children."""
from pathlib import Path
import importlib,os,sys,unittest,json,hashlib
sys.dont_write_bytecode=True
project=Path(__file__).resolve().parents[1]
candidate=project/'build/out/test-path-candidate-20261029'
sys.path.insert(0,str(candidate));os.environ['REMAINS_REGISTRY_CANDIDATE']=str(candidate)
for name in ('launch_integrity','test_resources','air_test_process','test_registry','mod_debugger'):
    importlib.import_module(name)
import mod_debugger as debugger
# These directory constants describe installed location, not algorithm changes.
debugger.PROJECT=project;debugger.GAME=project.parents[1];debugger.SESSIONS=project/'build/out/debugger'
suite=unittest.TestSuite()
for name in ('test_registry_parallel.py','test_launch_integrity.py','test_test_registry.py','test_air_test_process.py','test_resource_policy.py','test_debugger.py'):
    suite.addTests(unittest.defaultTestLoader.discover(str(project/'build/tests'),pattern=name))
with (candidate/'checks.log').open('w',encoding='utf-8') as log:
    result=unittest.TextTestRunner(stream=log,verbosity=2).run(suite)
record={'tests':result.testsRun,'success':result.wasSuccessful(),'failures':len(result.failures),'errors':len(result.errors),'skipped':len(result.skipped),
        'inputs':{p.name:hashlib.sha256(p.read_bytes()).hexdigest().upper() for p in candidate.glob('*.py')}}
(candidate/'checks.json').write_text(json.dumps(record,indent=2),encoding='utf-8')
print(json.dumps(record));sys.exit(0 if result.wasSuccessful() else 1)
