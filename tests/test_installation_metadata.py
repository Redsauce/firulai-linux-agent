import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class InstallationMetadataTests(unittest.TestCase):
    def test_metadata_for_old_and_new_installations(self):
        source = (ROOT / 'rs_agent.sh').read_text(encoding='utf-8')
        functions = []
        for name in ('json_escape', 'collect_agent_installation_info'):
            start = source.index(name + '() {')
            functions.append(source[start:source.index('\n}', start) + 2])
        bash = Path(os.environ.get('PROGRAMFILES', 'C:/Program Files')) / 'Git/bin/bash.exe'
        command = str(bash) if bash.exists() else 'bash'
        with tempfile.TemporaryDirectory(dir=ROOT) as temp:
            temp_path = Path(temp)
            config = temp_path / 'config.env'
            script = temp_path / 'fixture.sh'
            script.write_text('\n'.join(functions) + '\nstat() { printf "%s" "$FIXTURE_OWNER"; }\nCONFIG_FILE="$1"\ncollect_agent_installation_info\n', encoding='utf-8', newline='\n')
            cases = [
                ("AGENT_INSTALLATION_MODE='root'\nAGENT_INSTALLATION_USER='root'\n", 'alice', {'mode': 'root', 'user': 'root'}),
                ("AGENT_INSTALLATION_MODE='user'\nAGENT_INSTALLATION_USER='alice'\n", 'root', {'mode': 'user', 'user': 'alice'}),
                ('', 'alice', {'mode': 'user', 'user': 'alice'}),
                ('', 'root', {'mode': 'root', 'user': 'root'}),
            ]
            for config_text, file_owner, expected in cases:
                with self.subTest(config=config_text, file_owner=file_owner):
                    config.write_text(config_text, encoding='utf-8', newline='\n')
                    result = subprocess.run([command, str(script), str(config)], env={**os.environ, 'FIXTURE_OWNER': file_owner}, capture_output=True, check=True)
                    self.assertEqual(json.loads(result.stdout), expected)


if __name__ == '__main__':
    unittest.main()
