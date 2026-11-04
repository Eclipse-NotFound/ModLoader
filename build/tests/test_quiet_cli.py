"""Integration checks for the shared PowerShell/Python quiet launch boundary."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

TOOLS = Path(os.environ.get('QUIET_TEST_TOOLS', str(Path(__file__).resolve().parents[2] / 'tools')))
sys.path.insert(0, str(TOOLS))
from air_test_process import HiddenProcess

CHILD = '''
import ctypes as c, json, os, sys, time
from ctypes import wintypes as w
from pathlib import Path
u=c.WinDLL('user32'); k=c.WinDLL('kernel32')
u.GetThreadDesktop.argtypes=[w.DWORD]; u.GetThreadDesktop.restype=w.HANDLE
u.GetUserObjectInformationW.argtypes=[w.HANDLE,c.c_int,w.LPVOID,w.DWORD,w.LPVOID]
b=c.create_unicode_buffer(256); n=w.DWORD()
assert u.GetUserObjectInformationW(u.GetThreadDesktop(k.GetCurrentThreadId()),2,b,c.sizeof(b),c.byref(n))
print(json.dumps(dict(desktop=b.value, custom=os.environ.get('QUIET_CUSTOM'), args=sys.argv[1:])),flush=True)
print('stderr preserved',file=sys.stderr,flush=True)
if len(sys.argv)>1: Path(sys.argv[1]).write_text('done')
time.sleep(30)
'''

class QuietCliTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.child = self.root / 'child.py'
        self.child.write_text(CHILD)

    def command(self, *options):
        return [sys.executable, str(TOOLS/'air_test_process.py'), '--cwd', str(self.root),
                '--stdout', str(self.root/'stdout'), '--stderr', str(self.root/'stderr'),
                '--receipt', str(self.root/'receipt.json'), *options, '--', sys.executable, str(self.child)]

    def test_custom_environment_is_unicode_and_does_not_mutate_parent(self):
        with (self.root/'stdout').open('wb') as out, (self.root/'stderr').open('wb') as err:
            proc=HiddenProcess([sys.executable, str(self.child), str(self.root/'done')], cwd=self.root,
                               stdout=out, stderr=err, env=dict(os.environ, QUIET_CUSTOM='中文 & value'))
            try:
                import time
                deadline=time.monotonic()+10
                while not (self.root/'done').exists() and time.monotonic()<deadline: time.sleep(.05)
                self.assertTrue((self.root/'done').exists())
            finally:
                proc.kill(); proc.wait(10); proc.close()
        data=json.loads((self.root/'stdout').read_text(encoding='utf-8'))
        self.assertEqual(data['custom'],'中文 & value')
        self.assertEqual(data['desktop'],proc.desktop)
        self.assertNotIn('QUIET_CUSTOM',os.environ)

    def test_timeout_preserves_receipt_and_stops_child(self):
        result=subprocess.run(self.command('--timeout','1'),capture_output=True,text=True,errors='replace')
        self.assertEqual(result.returncode,124,result.stderr)
        receipt=json.loads((self.root/'receipt.json').read_text(encoding='utf-8'))
        self.assertTrue(receipt['timedOut'] and receipt['closed'])
        self.assertEqual(receipt['exitCode'],1)
        self.assertEqual(json.loads((self.root/'stdout').read_text(encoding='utf-8'))['desktop'],receipt['desktopName'])

    def test_stale_result_is_rejected_before_launch(self):
        result=self.root/'done'; result.write_text('old')
        run=subprocess.run(self.command('--until-file',str(result)),capture_output=True,text=True,errors='replace')
        self.assertEqual(run.returncode,2)
        self.assertFalse((self.root/'receipt.json').exists())

    def test_missing_executable_fails_closed(self):
        command=self.command('--timeout','1'); command[-2:]=[str(self.root/'missing.exe')]
        result=subprocess.run(command,capture_output=True,text=True,errors='replace')
        self.assertNotEqual(result.returncode,0)
        receipt=json.loads((self.root/'receipt.json').read_text(encoding='utf-8'))
        self.assertIn('error',receipt)
        self.assertNotIn('pid',receipt)

    def test_powershell_wrapper_forwards_pid_and_result_without_splash_desktop(self):
        def quote(value): return "'"+str(value).replace("'","''")+"'"
        script=self.root/'wrapper.ps1'
        script.write_text("$ErrorActionPreference='Stop'\n. "+quote(TOOLS/'Invoke-AirTest.ps1')+"\n"+
            '$r=Invoke-AirTest -Executable '+quote(sys.executable)+' -Arguments @('+quote(self.child)+','+quote(self.root/'done')+", 'space & quote')"+
            ' -WorkingDirectory '+quote(self.root)+' -EvidenceDirectory '+quote(self.root)+
            ' -UntilFile '+quote(self.root/'done')+' -TimeoutSeconds 10 -GraceSeconds 0.1\n'+
            'if (!$r.resultObserved -or !$r.closed -or $r.timedOut) { throw "Bad receipt" }\n')
        result=subprocess.run(['powershell','-NoProfile','-ExecutionPolicy','Bypass','-File',str(script)],capture_output=True,text=True,errors='replace',
                              env=dict(os.environ, REMAINS_DEBUG_PYTHON=sys.executable))
        self.assertEqual(result.returncode,0,result.stderr)
        receipt=json.loads((self.root/'air-process.json').read_text(encoding='utf-8'))
        self.assertIn('Isolated AIR PID '+str(receipt['pid']),result.stdout)
        child=json.loads((self.root/'adl-output.log').read_text(encoding='utf-8'))
        self.assertEqual(child['desktop'],receipt['desktopName'])
        self.assertTrue(child['desktop'].startswith('RemainsTest-'))
        self.assertIn('space & quote',child['args'])
        self.assertIn('stderr preserved',(self.root/'adl-error.log').read_text(encoding='utf-8'))

if __name__=='__main__': unittest.main()
