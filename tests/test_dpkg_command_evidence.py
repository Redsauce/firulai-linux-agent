"""Run the actual embedded collector on isolated dpkg and filesystem fixtures."""
import contextlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


class CommandEvidenceTests(unittest.TestCase):
    def collect(self, paths, present=(), versions=None):
        source = (ROOT/'firulaiAgent.sh').read_text(encoding='utf-8')
        code = source.split("<<'PY_DPKG_ARTIFACTS'\n",1)[1].split('\nPY_DPKG_ARTIFACTS',1)[0]
        versions = versions or [('unseen-utils','1.5-2','amd64')]
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); (root/'info').mkdir()
            (root/'status').write_text('\n\n'.join('Package: '+name+'\nVersion: '+version+'\nArchitecture: '+arch+'\nStatus: install ok installed'
                for name,version,arch in versions)+'\n\n')
            for name,version,arch in versions:
                (root/'info'/(name+':'+arch+'.list')).write_text('\n'.join(paths)+'\n')
            original = Path.is_file
            def is_file(path):
                return str(path).replace('\\','/') in present or original(path)
            output = io.StringIO()
            with patch.object(sys,'argv',['collector',str(root)]),patch.object(Path,'is_file',is_file),\
                 patch.object(Path,'is_symlink',return_value=False),patch('os.access',return_value=True),\
                 contextlib.redirect_stdout(output):
                exec(compile(code,'actual_agent_collector','exec'),{})
        return [json.loads(line.split('|',2)[2]) for line in output.getvalue().splitlines()]

    def test_observed_command_is_owned_and_bound_to_the_native_build(self):
        result = self.collect(['/usr/bin/unseen-command','/usr/share/doc/readme'],present=['/usr/bin/unseen-command'])
        self.assertEqual(len(result),1)
        self.assertEqual(result[0]['files'],[dict(path='/usr/bin/unseen-command',present=True,executable=True)])
        self.assertEqual((result[0]['package'],result[0]['version']),('unseen-utils','1.5-2'))
        self.assertEqual(result[0]['coverage'],'package_owned_commands')

    def test_registry_membership_does_not_invent_file_presence(self):
        result = self.collect(['/usr/bin/removed-command'])[0]
        self.assertFalse(result['files'][0]['present'])
        self.assertFalse(result['files'][0]['executable'])

    def test_bounded_manifests_do_not_claim_complete_coverage(self):
        result = self.collect(['/usr/bin/command-'+str(index) for index in range(200)])[0]
        self.assertGreater(len(result['files']),24)
        self.assertLessEqual(len(result['files']),128)
        self.assertLessEqual(len(json.dumps(result,separators=(',',':')).encode()),7600)
        self.assertFalse(result['complete'])

    def test_multiarch_identity_without_arch_binding_is_not_guessed(self):
        self.assertEqual(self.collect(['/usr/bin/unseen'],versions=[('unseen','1','amd64'),('unseen','1','i386')]),[])


if __name__ == '__main__': unittest.main()
