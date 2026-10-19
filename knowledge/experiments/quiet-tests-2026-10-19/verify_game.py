from pathlib import Path
import ctypes as c
from ctypes import wintypes as w
import sys,time,json
ROOT=Path(__file__).resolve().parents[4]
PROJECT=ROOT/'mods/ModLoader'
sys.path.insert(0,str(PROJECT/'tools'))
import mod_debugger as d
u=c.WinDLL('user32',use_last_error=True)
u.OpenInputDesktop.argtypes=[w.DWORD,w.BOOL,w.DWORD];u.OpenInputDesktop.restype=w.HANDLE
u.CloseDesktop.argtypes=[w.HANDLE];u.CloseDesktop.restype=w.BOOL
u.GetUserObjectInformationW.argtypes=[w.HANDLE,c.c_int,w.LPVOID,w.DWORD,c.POINTER(w.DWORD)]
u.GetWindowThreadProcessId.argtypes=[w.HWND,c.POINTER(w.DWORD)];u.GetWindowThreadProcessId.restype=w.DWORD
u.GetThreadDesktop.argtypes=[w.DWORD];u.GetThreadDesktop.restype=w.HANDLE
u.IsWindowVisible.argtypes=[w.HWND];u.IsWindowVisible.restype=w.BOOL
u.GetClassNameW.argtypes=[w.HWND,w.LPWSTR,c.c_int];u.GetClassNameW.restype=c.c_int
callback=c.WINFUNCTYPE(w.BOOL,w.HWND,w.LPARAM)
u.EnumDesktopWindows.argtypes=[w.HANDLE,callback,w.LPARAM];u.EnumDesktopWindows.restype=w.BOOL
def name(handle):
    b=c.create_unicode_buffer(256);n=w.DWORD()
    if not u.GetUserObjectInformationW(handle,2,b,c.sizeof(b),c.byref(n)):raise c.WinError(c.get_last_error())
    return b.value
def input_name():
    handle=u.OpenInputDesktop(0,False,1)
    if not handle:raise c.WinError(c.get_last_error())
    try:return name(handle)
    finally:u.CloseDesktop(handle)
records=[]
Original=d.HiddenProcess
class Observed(Original):
    def __init__(self,*args,**kwargs):
        super().__init__(*args,**kwargs)
        self.record={'pid':self.pid,'desktop':self.desktop,'inputBefore':input_name(),'windows':[]}
        records.append(self.record)
        assert self.desktop!=self.record['inputBefore']
        self.observed=False
    def wait(self,timeout=None):
        started=time.monotonic()
        if not self.observed:
            self.observed=True
            seen=set()
            @callback
            def inspect(hwnd,param):
                pid=w.DWORD();thread=u.GetWindowThreadProcessId(hwnd,c.byref(pid))
                if pid.value==self.pid:
                    b=c.create_unicode_buffer(256);u.GetClassNameW(hwnd,b,256)
                    # EnumDesktopWindows already restricts results to this owned desktop.
                    # Cross-process GetThreadDesktop is not a usable owned handle here.
                    desktop=self.desktop
                    key=(int(hwnd),b.value,desktop,bool(u.IsWindowVisible(hwnd)))
                    if key not in seen:
                        seen.add(key)
                        self.record['windows'].append({'hwnd':int(hwnd),'class':b.value,'desktop':desktop,'visible':key[3]})
                return True
            while time.monotonic()-started<4 and self.poll() is None:
                u.EnumDesktopWindows(self._desktop_handle,inspect,0)
                time.sleep(.025)
            assert self.record['windows'],'No owned windows observed'
            assert all(x['desktop']==self.desktop for x in self.record['windows'])
            self.record['inputAfter']=input_name()
            assert self.record['inputAfter']==self.record['inputBefore']
        return super().wait(None if timeout is None else max(0,timeout-(time.monotonic()-started)))
d.HiddenProcess=Observed
session=Path(sys.argv[1]).resolve()
try:
    for trial in sys.argv[2:]:
        d.main(['run','--session',str(session),'--trial',trial])
        result=d.read(session/'trials'/trial/'result.json')
        assert result['valid'],result
finally:
    (Path(__file__).parent/'native-windows.json').write_text(json.dumps(records,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'passed':True,'nativeWindows':[len(r['windows']) for r in records],'inputDesktopUnchanged':True}))
