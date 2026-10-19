"""Windows integration checks; creates only owned, never-displayed test desktops."""
import ctypes as c
from ctypes import wintypes as w
from pathlib import Path
import os
import subprocess
import sys
import tempfile
import time
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
from air_test_process import HiddenProcess

CHILD = r'''
import ctypes as c
from ctypes import wintypes as w
import sys
u=c.WinDLL('user32',use_last_error=True); k=c.WinDLL('kernel32')
k.GetCurrentThreadId.restype=w.DWORD
u.GetThreadDesktop.argtypes=[w.DWORD];u.GetThreadDesktop.restype=w.HANDLE
u.GetUserObjectInformationW.argtypes=[w.HANDLE,c.c_int,w.LPVOID,w.DWORD,c.POINTER(w.DWORD)]
b=c.create_unicode_buffer(256);n=w.DWORD()
assert u.GetUserObjectInformationW(u.GetThreadDesktop(k.GetCurrentThreadId()),2,b,c.sizeof(b),c.byref(n))
print(b.value,flush=True)
print(sys.argv[1:],flush=True)
print('stderr intact',file=sys.stderr,flush=True)
'''


@unittest.skipUnless(os.name == 'nt', 'Windows desktop test')
class DesktopProcessTests(unittest.TestCase):
    def setUp(self):
        root=Path(__file__).resolve().parents[1]/'out/desktop-unit'
        root.mkdir(parents=True,exist_ok=True)
        self.folder=tempfile.TemporaryDirectory(dir=root)
        self.addCleanup(self.folder.cleanup)
        self.root=Path(self.folder.name)

    def test_child_is_on_named_desktop_and_preserves_io_arguments_and_exit(self):
        with (self.root/'stdout').open('wb') as out, (self.root/'stderr').open('wb') as err:
            p=HiddenProcess([sys.executable,'-X','utf8','-c',CHILD,'中文 & spaces','quote"tail\\'],cwd=self.root,stdout=out,stderr=err)
            try:
                self.assertEqual(p.wait(10),0)
                name=p.desktop
            finally:
                if p.poll() is None:p.kill();p.wait(10)
                p.close()
        output=(self.root/'stdout').read_text(encoding='utf-8')
        self.assertEqual(output.splitlines()[0],name)
        self.assertIn('中文 & spaces',output)
        self.assertIn('stderr intact',(self.root/'stderr').read_text())
        u=c.WinDLL('user32',use_last_error=True)
        u.OpenDesktopW.argtypes=[w.LPCWSTR,w.DWORD,w.BOOL,w.DWORD];u.OpenDesktopW.restype=w.HANDLE
        u.CloseDesktop.argtypes=[w.HANDLE];u.CloseDesktop.restype=w.BOOL
        # Window-manager teardown can lag process exit; do not retain a probe handle.
        gone=False
        for _ in range(40):
            handle=u.OpenDesktopW(name,0,False,1)
            if not handle:gone=True;break
            u.CloseDesktop(handle)
            time.sleep(.05)
        self.assertTrue(gone,'Desktop should disappear after child and owner close')

    def test_timeout_only_terminates_owned_child(self):
        with (self.root/'stdout').open('wb') as out, (self.root/'stderr').open('wb') as err:
            p=HiddenProcess([sys.executable,'-c','import time;time.sleep(30)'],cwd=self.root,stdout=out,stderr=err)
            try:
                with self.assertRaises(subprocess.TimeoutExpired):p.wait(.05)
                with self.assertRaises(RuntimeError):p.close()
                p.kill()
                self.assertEqual(p.wait(10),1)
            finally:
                if p.poll() is None:p.kill();p.wait(10)
                p.close()

    def test_missing_program_fails_without_foreground_fallback(self):
        with (self.root/'stdout').open('wb') as out, (self.root/'stderr').open('wb') as err:
            with self.assertRaises(FileNotFoundError):
                HiddenProcess([self.root/'missing.exe'],cwd=self.root,stdout=out,stderr=err)


if __name__=='__main__':unittest.main()
