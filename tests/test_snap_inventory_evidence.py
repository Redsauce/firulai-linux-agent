import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class SnapInventoryEvidenceTests(unittest.TestCase):
    def collect(self, fixture):
        text = (ROOT/'firulaiAgent.sh').read_text(encoding='utf-8')
        function = 'collect_snap_packages() {'+text.split('collect_snap_packages() {',1)[1].split('collect_flatpak_packages() {',1)[0]
        script = function + '\njson_escape() { printf "%s" "$1"; }\nsnap() { cat <<\'FIXTURE\'\n'+fixture+'\nFIXTURE\n}\nprintf "["\ncollect_snap_packages\nprintf "]"\n'
        bash = Path(os.environ.get('PROGRAMFILES', 'C:/Program Files'))/'Git/bin/bash.exe'
        with tempfile.TemporaryDirectory(dir=ROOT) as folder:
            path = Path(folder)/'snap.sh'
            path.write_text(script,encoding='utf-8',newline='\n')
            result = subprocess.run([str(bash) if bash.exists() else 'bash', str(path)], capture_output=True,text=True,encoding='utf-8',timeout=15)
        self.assertEqual(result.returncode,0,result.stderr)
        return json.loads(result.stdout)

    def test_preserves_observed_build_and_publisher_without_deriving_upstream(self):
        rows = self.collect('Name Version Rev Tracking Publisher Notes\nnew-tool 8.4-3 123 latest/stable vendor -')
        self.assertEqual(rows,[dict(name='new-tool',version='8.4-3',manager='snap',inventory_evidence=dict(
            schema=1,source='snap_list',revision='123',tracking='latest/stable',publisher='vendor',notes='-'))])
        self.assertNotIn('upstream_version', rows[0])

    def test_local_unasserted_build_is_not_treated_as_store_verified(self):
        row = self.collect('tool 1.0 x1 - - devmode,dangerous')[0]
        self.assertEqual(row['inventory_evidence']['revision'],'x1')
        self.assertEqual(row['inventory_evidence']['notes'],'devmode,dangerous')
        self.assertNotIn('verified', row['inventory_evidence'])

    def test_missing_columns_preserve_inventory_without_fabricated_evidence(self):
        self.assertEqual(self.collect('old-tool 1.0'),[dict(name='old-tool',version='1.0',manager='snap')])
        self.assertEqual(self.collect('Name Version Rev Tracking Publisher Notes'),[])

if __name__ == '__main__': unittest.main()
