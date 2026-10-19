import ctypes as c
from ctypes import wintypes as w
import subprocess,sys,uuid
u=c.WinDLL('user32',use_last_error=True)
class SA(c.Structure):
    _fields_=[('nLength',w.DWORD),('lpSecurityDescriptor',w.LPVOID),('bInheritHandle',w.BOOL)]
u.CreateDesktopW.argtypes=[w.LPCWSTR,w.LPCWSTR,w.LPVOID,w.DWORD,w.DWORD,c.POINTER(SA)]
u.CreateDesktopW.restype=w.HANDLE
u.CloseDesktop.argtypes=[w.HANDLE];u.CloseDesktop.restype=w.BOOL
if len(sys.argv)>1:
    k=c.WinDLL('kernel32');k.GetCurrentThreadId.restype=w.DWORD
    u.GetThreadDesktop.argtypes=[w.DWORD];u.GetThreadDesktop.restype=w.HANDLE
    u.GetUserObjectInformationW.argtypes=[w.HANDLE,c.c_int,w.LPVOID,w.DWORD,c.POINTER(w.DWORD)]
    b=c.create_unicode_buffer(256);n=w.DWORD()
    if not u.GetUserObjectInformationW(u.GetThreadDesktop(k.GetCurrentThreadId()),2,b,c.sizeof(b),c.byref(n)):raise c.WinError(c.get_last_error())
    print(b.value)
else:
    name='RemainsTest-'+uuid.uuid4().hex
    sa=SA(c.sizeof(SA),None,True)
    handle=u.CreateDesktopW(name,None,None,0,0x10000000,c.byref(sa))
    if not handle:raise c.WinError(c.get_last_error())
    try:
        info=subprocess.STARTUPINFO(lpAttributeList={'handle_list':[handle]})
        p=subprocess.run([sys.executable,__file__,'child'],startupinfo=info,close_fds=True,creationflags=subprocess.CREATE_NO_WINDOW,capture_output=True,text=True,timeout=10)
        print(p.returncode,p.stdout,p.stderr)
        assert p.stdout.strip()==name
    finally:
        if not u.CloseDesktop(handle):raise c.WinError(c.get_last_error())
