"""Emit the observed uname family without guessing from a distribution name."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class KernelIdentityTests(unittest.TestCase):
    def collect(self, family, failed=False):
        source = (ROOT / 'firulaiAgent.sh').read_text(encoding='utf-8')
        functions = []
        for name in ('json_escape', 'collect_system_info'):
            start = source.index(name + '() {')
            functions.append(source[start:source.index('\n}', start) + 2])
        script = '\n'.join(functions) + '''
uname() {
    case "$1" in
        -s) [ "$FIXTURE_FAILED" = 1 ] && return 1; printf '%s' "$FIXTURE_FAMILY" ;;
        -r) printf '%s' '7.0.0-43-generic' ;;
        -m) printf '%s' 'x86_64' ;;
        *) return 1 ;;
    esac
}
collect_agent_installation_info() { printf '{}'; }
UUID_VAL=fixture
AGENT_VERSION=fixture
collect_system_info UTC
'''
        bash = Path(os.environ.get('PROGRAMFILES', 'C:/Program Files')) / 'Git/bin/bash.exe'
        with tempfile.TemporaryDirectory(dir=ROOT) as folder:
            path = Path(folder) / 'fixture.sh'
            path.write_text(script, encoding='utf-8', newline='\n')
            result = subprocess.run([str(bash) if bash.exists() else 'bash', str(path)],
                env={**os.environ, 'FIXTURE_FAMILY': family, 'FIXTURE_FAILED': str(int(failed))},
                capture_output=True, text=True, timeout=15, check=True)
        return json.loads(result.stdout)

    def test_family_and_full_release_come_from_separate_uname_observations(self):
        for family in ('Linux', 'Example "kernel"'):
            with self.subTest(family=family):
                observed = self.collect(family)['os']
                self.assertEqual(observed['kernel_name'], family)
                self.assertEqual(observed['kernel'], '7.0.0-43-generic')
                self.assertEqual(observed['architecture'], 'x86_64')

    def test_failed_family_observation_stays_empty(self):
        self.assertEqual(self.collect('Linux', failed=True)['os']['kernel_name'], '')


if __name__ == '__main__':
    unittest.main()
