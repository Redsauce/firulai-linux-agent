"""Test the agent's actual embedded byte observer without running executables."""
import contextlib
import hashlib
import io
from pathlib import Path
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


class DpkgFingerprintTests(unittest.TestCase):
    def load(self, directory):
        (directory / 'status').write_text('')
        code = (ROOT/'firulaiAgent.sh').read_text(encoding='utf8').split("<<'PY_DPKG_ARTIFACTS'\n",1)[1].split('\nPY_DPKG_ARTIFACTS',1)[0]
        ns = {}
        with patch.object(sys, 'argv', ['collector',str(directory)]), contextlib.redirect_stdout(io.StringIO()):
            exec(compile(code,'actual_agent_observer','exec'),ns)
        ns['fingerprint_budget']['deadline'] = time.monotonic()+10
        return ns

    def test_observes_real_bytes_and_size_without_executing_file(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);ns=self.load(root)
            file=root/'unrelated-tool';content=b'not an executable; only bytes\x00\xff'
            file.write_bytes(content)
            result=ns['file_fingerprint'](file)
            self.assertEqual(result['sha256'],hashlib.sha256(content).hexdigest())
            self.assertEqual(result['size_bytes'],len(content))
            self.assertEqual(result['mtime_ns'],file.stat().st_mtime_ns)
            self.assertEqual(Path(result['resolved_path']),file.resolve())
            self.assertNotIn('verified',result)

    def test_missing_directory_and_over_limit_file_supply_no_fingerprint(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);ns=self.load(root)
            self.assertIsNone(ns['file_fingerprint'](root/'missing'))
            self.assertIsNone(ns['file_fingerprint'](root))
            file=root/'too-large';file.write_bytes(b'abc')
            ns['fingerprint_budget']['bytes']=2
            self.assertIsNone(ns['file_fingerprint'](file))

    def test_resource_limits_leave_unknown_rather_than_partial_digest(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);ns=self.load(root);file=root/'tool';file.write_bytes(b'content')
            ns['fingerprint_budget']['files']=0
            self.assertIsNone(ns['file_fingerprint'](file))
            ns['fingerprint_budget']['files']=1
            ns['fingerprint_budget']['deadline']=time.monotonic()-1
            self.assertIsNone(ns['file_fingerprint'](file))

    def test_symlink_is_not_used_as_measurement_of_its_target(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);ns=self.load(root);file=root/'tool';file.write_bytes(b'content')
            with patch.object(Path,'is_symlink',return_value=True):
                self.assertIsNone(ns['file_fingerprint'](file))

    def test_change_while_reading_discards_the_digest(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);ns=self.load(root);file=root/'tool';file.write_bytes(b'content')
            original=ns['os'].fstat;calls=[]
            def changed(descriptor):
                value=original(descriptor);calls.append(True)
                if len(calls)>1:
                    from types import SimpleNamespace
                    return SimpleNamespace(st_dev=value.st_dev,st_ino=value.st_ino,st_size=value.st_size,
                        st_mtime_ns=value.st_mtime_ns+1,st_ctime_ns=value.st_ctime_ns)
                return value
            with patch.object(ns['os'],'fstat',side_effect=changed):
                self.assertIsNone(ns['file_fingerprint'](file))


if __name__=='__main__':unittest.main()
