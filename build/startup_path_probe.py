"""Bounded owned-launcher/AIR startup probe, private desktop, no game launch/input."""
from pathlib import Path
import argparse,ctypes,json,os,shutil,sys,time,uuid,hashlib
from ctypes import wintypes as W
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'mods/ModLoader/tools'))
from air_test_process import HiddenProcess
from test_registry import Registration
from test_resources import runner_limits

def token_info(handle):
    a=ctypes.WinDLL('advapi32',use_last_error=True);k=ctypes.WinDLL('kernel32')
    a.OpenProcessToken.argtypes=[W.HANDLE,W.DWORD,ctypes.POINTER(W.HANDLE)]
    a.GetTokenInformation.argtypes=[W.HANDLE,ctypes.c_int,W.LPVOID,W.DWORD,ctypes.POINTER(W.DWORD)]
    a.IsTokenRestricted.argtypes=[W.HANDLE];k.CloseHandle.argtypes=[W.HANDLE]
    a.GetSidSubAuthorityCount.argtypes=[W.LPVOID];a.GetSidSubAuthorityCount.restype=ctypes.POINTER(ctypes.c_ubyte)
    a.GetSidSubAuthority.argtypes=[W.LPVOID,W.DWORD];a.GetSidSubAuthority.restype=ctypes.POINTER(W.DWORD)
    t=W.HANDLE();result={}
    if not a.OpenProcessToken(handle,8,ctypes.byref(t)):return {'error':ctypes.get_last_error()}
    try:
        value=W.DWORD();length=W.DWORD()
        if a.GetTokenInformation(t,29,ctypes.byref(value),4,ctypes.byref(length)):result['appContainer']=bool(value.value)
        result['restricted']=bool(a.IsTokenRestricted(t))
        a.GetTokenInformation(t,25,None,0,ctypes.byref(length));buf=ctypes.create_string_buffer(length.value)
        if a.GetTokenInformation(t,25,buf,len(buf),ctypes.byref(length)):
            sid=ctypes.cast(buf,ctypes.POINTER(W.LPVOID))[0];n=a.GetSidSubAuthorityCount(sid)[0]
            result['integrityRID']=a.GetSidSubAuthority(sid,n-1)[0]
    finally:k.CloseHandle(t)
    return result

def own_windows(process):
    u=ctypes.WinDLL('user32',use_last_error=True)
    cb=ctypes.WINFUNCTYPE(W.BOOL,W.HWND,W.LPARAM)
    u.EnumDesktopWindows.argtypes=[W.HANDLE,cb,W.LPARAM];u.EnumChildWindows.argtypes=[W.HWND,cb,W.LPARAM]
    u.GetWindowThreadProcessId.argtypes=[W.HWND,ctypes.POINTER(W.DWORD)]
    u.GetWindowTextW.argtypes=[W.HWND,W.LPWSTR,ctypes.c_int];u.GetClassNameW.argtypes=[W.HWND,W.LPWSTR,ctypes.c_int]
    records=[]
    def item(h):
        pid=W.DWORD();u.GetWindowThreadProcessId(h,ctypes.byref(pid))
        if pid.value!=process.pid:return None
        txt=ctypes.create_unicode_buffer(2048);cls=ctypes.create_unicode_buffer(200)
        u.GetWindowTextW(h,txt,len(txt));u.GetClassNameW(h,cls,len(cls))
        return dict(text=txt.value,windowClass=cls.value)
    @cb
    def top(h,p):
        row=item(h)
        if row is not None:
            row['children']=[]
            @cb
            def child(ch,param):
                v=item(ch)
                if v and v['text'] and len(row['children'])<60:row['children'].append(v)
                return True
            u.EnumChildWindows(h,child,0);records.append(row)
        return True
    u.EnumDesktopWindows(process._desktop_handle,top,0)
    return records

p=argparse.ArgumentParser();p.add_argument('--case',choices=['launcher','air-root','air-system','air-medium'],required=True);args=p.parse_args()
out=ROOT/'mods/ModLoader/build/out/startup-repair-20261029'/('probe-'+args.case+'-'+uuid.uuid4().hex[:10]);out.mkdir()
k=ctypes.WinDLL('kernel32');k.GetCurrentProcess.restype=W.HANDLE
record={'case':args.case,'runner':runner_limits(),'runnerToken':token_info(k.GetCurrentProcess()),'diagnosticOnly':True};proc=None;store=None
if args.case=='launcher':
    command=[ROOT/'Remains.exe'];cwd=ROOT
else:
    source=ROOT/'mods/ContinuousScene/build/generated/cell-phase-alpha-mini-20261029/Sampler.swf'
    assert hashlib.sha256(source.read_bytes()).hexdigest().upper()=='6A2BF237EB836D7669F380C6176A8D81095040F47718212ED6354CB076F1AE7D'
    shutil.copy2(source,out/'Sampler.swf');app='pfe-cell-phase-snap-'+uuid.uuid4().hex
    descriptor=out/'application.xml'
    descriptor.write_text('<application xmlns="http://ns.adobe.com/air/application/32.0"><id>'+app+'</id><versionNumber>1.0.0</versionNumber><filename>Startup check</filename><initialWindow><content>Sampler.swf</content><visible>false</visible><width>640</width><height>480</height><renderMode>cpu</renderMode></initialWindow></application>',encoding='utf-8')
    host=ROOT/'adl64.exe'
    if args.case=='air-medium':
        host=ROOT/'mods/ModLoader/build/out/startup-repair-20261029/medium-host-check/adl64.exe'
        assert hashlib.sha256(host.read_bytes()).digest()==hashlib.sha256((ROOT/'adl64.exe').read_bytes()).digest()
    command=[host,'-runtime',ROOT/'runtimes/air/win64',descriptor]
    cwd=ROOT if args.case=='air-root' else out
    store=Path(os.environ['APPDATA'])/app/'Local Store'
    record['store']=str(store)
with Registration(owner='ModLoader / startup repair / 01a13816',purpose=args.case+' startup diagnosis',run_dir=out,evidence=out/'result.json',wait=120) as lease:
    try:
        with (out/'stdout.txt').open('xb') as stdout,(out/'stderr.txt').open('xb') as stderr:
            lease.before_launch('Owned private-desktop startup, at most 20 seconds')
            proc=HiddenProcess(command,cwd=cwd,stdout=stdout,stderr=stderr,resource_policy='system' if args.case=='air-system' else 'test')
            lease.child(proc.pid);record.update(pid=proc.pid,desktop=proc.desktop,token=token_info(proc._process),policy=proc.resource_policy)
            start=time.monotonic();record['windows']=[]
            while proc.poll() is None and time.monotonic()-start<20:
                windows=own_windows(proc)
                if windows!=record['windows']:record['windows']=windows
                if args.case=='launcher' and time.monotonic()-start>=8:break
                time.sleep(.2)
            record['naturalExit']=proc.poll();record['elapsedSeconds']=time.monotonic()-start
            if store:record['sampleResultExists']=(store/'result.json').exists()
            if store and store.exists():shutil.copytree(store,out/'storage')
            lease.note='Only startup diagnosis; see result.json, no performance conclusion'
    finally:
        if proc:
            if proc.poll() is None:record['stoppedOwnedAfterObservation']=True;proc.kill();proc.wait(15)
            record['finalExit']=proc.poll();proc.close();lease.child_stopped()
        (out/'result.json').write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'out':str(out),**record},ensure_ascii=False))
