import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class CollectionStatusTests(unittest.TestCase):
    def run_fixture(self, curl_exit=0, endpoint='https://fixture.invalid/status'):
        source = (ROOT / 'rs_agent.sh').read_text(encoding='utf-8')
        functions = source.split('report_collection_status() {', 1)[1].split('\nmain() {', 1)[0]
        functions = 'report_collection_status() {' + functions
        bash = Path(os.environ.get('PROGRAMFILES', 'C:/Program Files')) / 'Git/bin/bash.exe'
        with tempfile.TemporaryDirectory(dir=ROOT) as directory:
            directory = Path(directory)
            script = directory / 'fixture.sh'
            script.write_text(functions + '''
json_escape() { printf '%s' "$1"; }
cat() { printf '550e8400-e29b-41d4-a716-446655440001'; }
hostname() { printf 'fixture'; }
curl() { printf '%s\\n' "$*" >> "$REPORTS"; return "$CURL_EXIT"; }
AGENT_TOKEN=fixture-token
UUID_VAL=550e8400-e29b-41d4-a716-446655440000
start_collection_status
exit 7
''', encoding='utf-8', newline='\n')
            result = subprocess.run([str(bash) if bash.exists() else 'bash', str(script)],
                env={**os.environ, 'REPORTS': (directory / 'reports').as_posix(),
                     'CURL_EXIT': str(curl_exit), 'RS_AGENT_COLLECTION_URL': endpoint},
                capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 7, result.stderr)
            reports = directory / 'reports'
            return reports.read_text() if reports.exists() else ''

    def test_exit_also_finishes_status_without_replacing_failure_code(self):
        reports = self.run_fixture()
        self.assertIn('"state":"start"', reports)
        self.assertIn('"state":"finish"', reports)
        self.assertNotIn('--location', reports)

    def test_telemetry_outage_does_not_abort_inventory(self):
        reports = self.run_fixture(curl_exit=7)
        self.assertIn('"state":"finish"', reports)

    def test_insecure_endpoint_never_receives_agent_token(self):
        self.assertEqual(self.run_fixture(endpoint='http://fixture.invalid/status'), '')
