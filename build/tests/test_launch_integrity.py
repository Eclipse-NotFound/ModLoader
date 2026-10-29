"""A low-integrity copy may only reuse an identical approved ADL, read-only."""
from pathlib import Path
import os,sys,tempfile,unittest
from unittest.mock import patch
sys.path.insert(0,os.environ.get('REMAINS_REGISTRY_CANDIDATE',str(Path(__file__).resolve().parents[2]/'tools')))
import launch_integrity as m

class LaunchIntegrityTests(unittest.TestCase):
    def setUp(self):
        root=Path(__file__).resolve().parents[1]/'out/integrity-tests';root.mkdir(parents=True,exist_ok=True)
        self.temp=tempfile.TemporaryDirectory(dir=root);self.root=Path(self.temp.name)
        self.copy=self.root/'adl64.exe';self.canonical=self.root/'canonical.exe'
        self.copy.write_bytes(b'identical host');self.canonical.write_bytes(b'identical host')
    def tearDown(self):self.temp.cleanup()
    def test_normal_file_keeps_its_original_path(self):
        with patch.object(m,'process_integrity',return_value=m.MEDIUM),patch.object(m,'file_integrity',return_value=m.MEDIUM):
            path,info=m.resolve_test_host(self.copy)
            self.assertEqual(path,self.copy);self.assertFalse(info['reusedCanonicalHost'])
    def test_low_copy_reuses_identical_normal_host_and_does_not_write_copy(self):
        stamp=self.copy.stat().st_mtime_ns
        with patch.object(m,'process_integrity',return_value=m.MEDIUM),patch.object(m,'file_integrity',side_effect=lambda p:m.LOW if Path(p)==self.copy else m.MEDIUM):
            path,info=m.resolve_test_host(self.copy,canonical=self.canonical)
            self.assertEqual(path,self.canonical);self.assertTrue(info['reusedCanonicalHost'])
        self.assertEqual(stamp,self.copy.stat().st_mtime_ns)
    def test_version_mismatch_fails_instead_of_using_different_host(self):
        self.canonical.write_bytes(b'other version')
        with patch.object(m,'process_integrity',return_value=m.MEDIUM),patch.object(m,'file_integrity',side_effect=lambda p:m.LOW if Path(p)==self.copy else m.MEDIUM):
            with self.assertRaisesRegex(ValueError,'differs'):m.resolve_test_host(self.copy,canonical=self.canonical)
    def test_low_runner_never_automatically_elevates(self):
        with patch.object(m,'process_integrity',return_value=m.LOW):
            with self.assertRaisesRegex(PermissionError,'runner is low'):m.resolve_test_host(self.copy)
    def test_unrelated_low_executable_is_not_substituted(self):
        other=self.root/'another.exe';other.write_bytes(b'identical host')
        with patch.object(m,'process_integrity',return_value=m.MEDIUM),patch.object(m,'file_integrity',return_value=m.LOW):
            with self.assertRaisesRegex(PermissionError,'Executable inherits'):m.resolve_test_host(other,canonical=self.canonical)
    def test_low_canonical_host_rejected(self):
        with patch.object(m,'process_integrity',return_value=m.MEDIUM),patch.object(m,'file_integrity',return_value=m.LOW):
            with self.assertRaisesRegex(PermissionError,'Canonical AIR'):m.resolve_test_host(self.copy,canonical=self.canonical)

if __name__=='__main__':unittest.main()
