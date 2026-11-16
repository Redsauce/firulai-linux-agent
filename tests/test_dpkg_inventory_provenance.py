"""Exercise the real collector using package-manager observations."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class DpkgInventoryProvenanceTests(unittest.TestCase):
    def collect(self, rows):
        source = (ROOT / 'firulaiAgent.sh').read_text(encoding='utf-8')
        functions = 'select_source_package_version() {' + source.split(
            'select_source_package_version() {', 1)[1].split('collect_packages_rpm() {', 1)[0]
        script = functions + '''
json_escape() { printf '%s' "$1"; }
dpkg-query() { cat <<'DPKG_FIXTURE'
''' + rows + '''
DPKG_FIXTURE
}
collect_packages_dpkg
printf '{"components":[%s],"packages":[%s]}' "$SYSTEM_COMPONENTS_JSON" "$SYSTEM_PACKAGES_JSON"
'''
        bash = Path(os.environ.get('PROGRAMFILES', 'C:/Program Files')) / 'Git/bin/bash.exe'
        with tempfile.TemporaryDirectory(dir=ROOT) as folder:
            path = Path(folder) / 'fixture.sh'
            path.write_text(script, encoding='utf-8', newline='\n')
            result = subprocess.run([str(bash) if bash.exists() else 'bash', str(path)],
                                    capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_same_name_binary_keeps_native_identity_and_both_full_versions(self):
        inventory = self.collect('tar|1.34+dfsg-1+deb11u1+b1|tar|1.34+dfsg-1+deb11u1|1.34+dfsg|install ok installed')
        self.assertEqual(inventory['packages'], [{'name': 'tar', 'version': '1.34+dfsg-1+deb11u1'}])
        self.assertEqual(inventory['components'], [{'name': 'tar', 'version': '1.34+dfsg-1+deb11u1+b1',
            'manager': 'dpkg', 'source_package': 'tar', 'source_version': '1.34+dfsg-1+deb11u1',
            'upstream_version': '1.34+dfsg'}])

    def test_real_members_share_one_source_and_uninstalled_records_supply_no_proof(self):
        inventory = self.collect('''foo|1.0-2|foo|1.0-2|1.0|hold ok installed
libfoo1|1.0-2+b1|foo|1.0-2|1.0|install ok installed
gone|9.0-1|gone|9.0-1|9.0|unknown ok not-installed
config|9.0-1|config|9.0-1|9.0|deinstall ok config-files''')
        self.assertEqual([x['name'] for x in inventory['components']], ['foo', 'libfoo1'])
        self.assertEqual(inventory['packages'], [{'name': 'foo', 'version': '1.0-2'}])

    def test_no_source_metadata_does_not_invent_a_source(self):
        inventory = self.collect('orphan|1.0-2||||install ok installed')
        self.assertEqual(inventory['components'], [{'name': 'orphan', 'version': '1.0-2', 'manager': 'dpkg'}])
        self.assertEqual(inventory['packages'], [])


if __name__ == '__main__':
    unittest.main()
