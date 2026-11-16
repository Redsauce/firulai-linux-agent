"""RubyGems default markers are metadata; retain the package manager identity."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class GemInventoryVersionTests(unittest.TestCase):
    def collect(self, fixture):
        text=(ROOT/'firulaiAgent.sh').read_text(encoding='utf-8')
        function='collect_gem_packages() {'+text.split('collect_gem_packages() {',1)[1].split('# ============ AUTO UPDATE',1)[0]
        script=function+'''\njson_escape() { printf '%s' "$1"; }
gem() { cat <<'GEM_FIXTURE'
'''+fixture+'''\nGEM_FIXTURE
}
printf '['
collect_gem_packages
printf ']'
'''
        bash=Path(os.environ.get('PROGRAMFILES','C:/Program Files'))/'Git/bin/bash.exe'
        with tempfile.TemporaryDirectory(dir=ROOT) as tmp:
            path=Path(tmp)/'gem-fixture.sh';path.write_text(script,encoding='utf-8',newline='\n')
            result=subprocess.run([str(bash) if bash.exists() else 'bash',str(path)],
                                  text=True,capture_output=True,timeout=15)
        self.assertEqual(result.returncode,0,result.stderr)
        return json.loads(result.stdout)

    def test_default_numeric_versions_and_regular_versions_keep_gem_identity(self):
        rows=self.collect('openssl (default: 2.1.2)\ncgi (default:    0.1.0)\nrack (3.1.2, 3.1.1)')
        self.assertEqual(rows,[{'name':'openssl','version':'2.1.2','manager':'gem'},
                               {'name':'cgi','version':'0.1.0','manager':'gem'},
                               {'name':'rack','version':'3.1.2','manager':'gem'}])

    def test_prereleases_and_unknown_metadata_are_not_silently_removed(self):
        rows=self.collect('preview (1.0.0.pre)\nodd (default: 1.0 beta)')
        self.assertEqual(rows[0]['version'],'1.0.0.pre')
        self.assertEqual(rows[1]['version'],'default: 1.0 beta')

    def test_an_empty_listing_does_not_create_a_component(self):
        self.assertEqual(self.collect(''),[])


if __name__ == '__main__':
    unittest.main()
