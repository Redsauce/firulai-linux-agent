#!/usr/bin/env python3
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
FILES = ["install.sh", "rs_agent.sh", "rs_agent_runner.sh", "uninstall.sh"]
LOCALES = ["es_ES", "ca_ES", "eu_ES", "gl_ES", "fr_FR", "de_DE", "it_IT", "ja_JP", "zh_CN"]
EARLY_PREFIXES = ["es", "ca", "eu", "gl", "fr", "de", "it", "ja", "zh"]

T_KEY_RE = re.compile(r"\$\(t [\"']?([A-Za-z0-9_]+)[\"']?\)")
EARLY_KEY_RE = re.compile(r"early_t ([A-Za-z0-9_]+)")


def main() -> int:
    failed = False

    for filename in FILES:
        text = (ROOT / filename).read_text(encoding="utf-8")
        used_keys = sorted(set(T_KEY_RE.findall(text)))
        print(f"{filename}: {len(used_keys)} t() keys")

        for locale in LOCALES:
            missing = [key for key in used_keys if f"{locale}:{key})" not in text]
            if missing:
                failed = True
                print(f"  {locale}: missing {len(missing)} keys: {', '.join(missing)}")

    install_text = (ROOT / "install.sh").read_text(encoding="utf-8")
    early_keys = sorted(set(EARLY_KEY_RE.findall(install_text)))
    print(f"install.sh: {len(early_keys)} early_t() keys")

    for prefix in EARLY_PREFIXES:
        missing = [key for key in early_keys if f"{prefix}:{key})" not in install_text]
        if missing:
            failed = True
            print(f"  {prefix}: missing {len(missing)} early keys: {', '.join(missing)}")

    if failed:
        return 1

    print("i18n catalogs complete for all supported Firulai locales.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
