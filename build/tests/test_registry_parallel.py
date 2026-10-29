"""Independent requests, fairness and evidence-based interrupted lease recovery."""
import os,sys,tempfile,unittest,threading,concurrent.futures,subprocess,time
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,os.environ.get('REMAINS_REGISTRY_CANDIDATE',str(Path(__file__).resolve().parents[2]/'tools')))
import test_registry as r

class ParallelRegistryTests(unittest.TestCase):
    def setUp(self):
        root=Path(__file__).resolve().parents[1]/'out/parallel-registry-tests'
        root.mkdir(parents=True,exist_ok=True)
        self.temp=tempfile.TemporaryDirectory(dir=root);self.root=Path(self.temp.name)
        self.identities={100:'100',200:'200',300:'300'}
        self.tokens=patch.object(r,'process_token',side_effect=lambda pid:self.identities.get(pid,'live'))
        self.tokens.start();self.db=r.Registry(self.root/'registry.sqlite3')
    def tearDown(self):self.tokens.stop();self.temp.cleanup()
    def create(self,name,resource='game-coexist',managed=True,run_dir=None):
        return self.db.create(name,'test',resource,run_dir or self.root/name,'',managed=managed)
    def row(self,ident):return next(x for x in self.db.status() if x['id']==ident)
    def finish(self,ident):self.db.update(ident,state='completed',ended=r.now())
    def test_two_independent_functional_requests_overlap_and_third_waits(self):
        a,b,c=[self.create(x) for x in ('a','b','c')]
        self.assertEqual(self.db.claim(a),[]);self.assertEqual(self.db.claim(b),[])
        self.assertTrue(self.db.claim(c));self.finish(a);self.assertEqual(self.db.claim(c),[])
    def test_benchmark_waits_and_prevents_new_functional_request_starvation(self):
        a=self.create('a');self.assertEqual(self.db.claim(a),[])
        b=self.create('benchmark','game');c=self.create('c')
        self.assertTrue(self.db.claim(b));self.assertTrue(self.db.claim(c))
        self.finish(a);self.assertTrue(self.db.claim(c));self.assertEqual(self.db.claim(b),[])
        self.assertTrue(self.db.claim(c));self.finish(b);self.assertEqual(self.db.claim(c),[])
    def test_queue_order_survives_record_updates(self):
        a=self.create('a','game');b=self.create('b','game')
        self.db.update(a,detail='still waiting')
        self.assertTrue(self.db.claim(b));self.assertEqual(self.db.claim(a),[])
    def test_shared_workspace_not_allowed_even_for_coexist(self):
        a=self.create('a',run_dir=self.root/'same')
        b=self.create('b',run_dir=self.root/'same/child')
        self.assertEqual(self.db.claim(a),[]);self.assertTrue(self.db.claim(b))
    def test_relative_workspace_is_resolved_in_requesting_process(self):
        a=self.create('relative',run_dir=Path('.'))
        self.assertEqual(self.row(a)['runDir'],str(Path('.').resolve()))
    def test_known_finished_managed_run_releases_without_manual_recovery(self):
        a=self.create('a','game');self.db.claim(a)
        self.db.update(a,runner={'pid':100,'token':'100'},children=[{'pid':200,'token':'200'}])
        self.identities[100]=self.identities[200]=None
        self.assertEqual(self.row(a)['state'],'interrupted')
        self.assertIn('自动',self.row(a)['note'])
        self.assertEqual(self.db.claim(self.create('b','game')),[])
    def test_unknown_live_or_launch_gap_retains_reservation(self):
        for variant in ('unknown','live','launch-gap'):
            with self.subTest(variant=variant):
                a=self.create(variant,'game');self.db.claim(a)
                self.db.update(a,runner={'pid':100,'token':'100'},children=[{'pid':200,'token':'200'}],launching=variant=='launch-gap')
                self.identities[100]=None;self.identities[200]={'unknown':'unknown','live':'200','launch-gap':None}[variant]
                self.assertEqual(self.row(a)['state'],'needs-check')
                self.finish(a)
    def test_old_unmanaged_record_keeps_manual_recovery(self):
        a=self.create('old','game',managed=False);self.db.claim(a)
        self.db.update(a,runner={'pid':100,'token':'100'})
        self.identities[100]=None
        self.assertEqual(self.row(a)['state'],'needs-check')
    def test_idle_managed_runner_death_never_launched_is_safe_to_release(self):
        a=self.create('idle','game');self.db.claim(a)
        self.db.update(a,runner={'pid':100,'token':'100'})
        self.identities[100]=None
        self.assertEqual(self.row(a)['state'],'interrupted')
    def test_slow_identity_query_does_not_hold_database_write_lock(self):
        a=self.create('a','game');self.db.claim(a)
        self.db.update(a,runner={'pid':100,'token':'100'})
        entered=threading.Event();release=threading.Event()
        original=r.process_token
        def token(pid):
            if pid==100 and threading.current_thread().name.startswith('slow-check'):
                entered.set();self.assertTrue(release.wait(5))
            return original(pid)
        with patch.object(r,'process_token',side_effect=token),concurrent.futures.ThreadPoolExecutor(max_workers=1,thread_name_prefix='slow-check') as pool:
            future=pool.submit(self.db.status)
            self.assertTrue(entered.wait(3))
            try:
                # Direct transaction checks the real lock, without recursively querying identities.
                with self.db.transaction() as db:
                    row=next(x for x in self.db.rows(db) if x['id']==a)
                    row['detail']='newer evidence';self.db.save(db,row)
            finally:release.set()
            future.result(5)
        self.assertEqual(self.row(a)['detail'],'newer evidence')


class RealRequestTests(unittest.TestCase):
    def test_two_separate_runner_processes_hold_functional_leases_at_once(self):
        base=Path(__file__).resolve().parents[1]/'out/parallel-registry-tests';base.mkdir(parents=True,exist_ok=True)
        with tempfile.TemporaryDirectory(dir=base) as directory:
            root=Path(directory);db=root/'runs.sqlite3';workers=[]
            source="import sys,time\nfrom pathlib import Path\n"+f"sys.path.insert(0,{str(Path(r.__file__).parent)!r})\n"+"from test_registry import Registration,Registry\nroot=Path(sys.argv[2]);root.mkdir()\nwith Registration(owner=root.name,purpose='concurrent request check',resource='game-coexist',run_dir=root,registry=Registry(sys.argv[1]),wait=5) as lease:\n (root/'ready').write_text(lease.id)\n deadline=time.monotonic()+12\n while not (root/'release').exists():\n  if time.monotonic()>deadline: raise TimeoutError('parent did not release')\n  time.sleep(.02)\n"
            script=root/'worker.py';script.write_text(source,encoding='utf-8')
            try:
                for n in ('a','b'):
                    workers.append(subprocess.Popen([sys.executable,'-B',str(script),str(db),str(root/n)],creationflags=subprocess.CREATE_NO_WINDOW))
                until=time.monotonic()+10
                while not all((root/n/'ready').exists() for n in ('a','b')):
                    self.assertLess(time.monotonic(),until,'Separate requests failed to overlap');time.sleep(.02)
                rows=r.Registry(db).status()
                self.assertEqual(sum(x['state']=='running' for x in rows),2)
                self.assertEqual(len({x['runner']['pid'] for x in rows}),2)
            finally:
                for n in ('a','b'):
                    if (root/n).exists():(root/n/'release').touch()
                for worker in workers:
                    try:worker.wait(5)
                    except subprocess.TimeoutExpired:worker.kill();worker.wait(5)
            self.assertTrue(all(worker.returncode==0 for worker in workers))
            self.assertTrue(all(x['state']=='completed' for x in r.Registry(db).status()))

if __name__=='__main__':unittest.main()
