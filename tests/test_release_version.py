"""Every installation and compatibility entry must select the same release."""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class ReleaseVersionTests(unittest.TestCase):
    def test_installer_and_legacy_entry_follow_the_current_agent_release(self):
        versions = {}
        for name, variable in [('firulaiAgent.sh', 'AGENT_VERSION'),
                               ('install.sh', 'INSTALLER_AGENT_VERSION'),
                               ('rs_agent.sh', 'AGENT_VERSION')]:
            match = re.search(r'^' + variable + r'="(\d+\.\d+\.\d+)"$',
                              (ROOT / name).read_text(encoding='utf-8'), re.M)
            self.assertIsNotNone(match, name)
            versions[name] = match.group(1)
        self.assertEqual(len(set(versions.values())), 1, versions)
