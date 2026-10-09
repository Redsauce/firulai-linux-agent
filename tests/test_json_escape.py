import json
import os
from pathlib import Path
import subprocess
import unittest
import tempfile

ROOT = Path(__file__).resolve().parents[1]

class JsonEscapeTests(unittest.TestCase):
    def test_all_control_bytes_and_unicode_roundtrip(self):
        source = (ROOT / "rs_agent.sh").read_text(encoding="utf-8")
        start = source.index("json_escape() {")
        function = source[start:source.index("\n}", start)+2]
        bash = Path(os.environ.get("PROGRAMFILES", "C:/Program Files")) / "Git/bin/bash.exe"
        command = str(bash) if bash.exists() else "bash"
        script = function + "\nIFS= read -r -d \"\" testvalue || true\nprintf '\"%s\"' \"$(json_escape \"$testvalue\")\""
        with tempfile.TemporaryDirectory(prefix="json-escape-test-", dir=ROOT) as temp:
            path = Path(temp) / "fixture.sh"
            path.write_text(script, encoding="utf-8", newline="\n")
            for value in (''.join(chr(i) for i in range(1, 32)), 'quote" slash\\ newline\n', "\u00e1\U0001f436", "1.2.3"):
                with self.subTest(value=repr(value)):
                    result = subprocess.run([command, str(path)], input=value.encode("utf-8") + b"\0", check=True, capture_output=True)
                    self.assertEqual(json.loads(result.stdout.decode("utf-8")), value)

if __name__ == "__main__":
    unittest.main()
