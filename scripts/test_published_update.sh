#!/bin/bash
# Uses real public GitHub downloads in an isolated Linux directory. The final
# restart is intercepted so no inventory or fake credentials reach RSM.
set -euo pipefail
fixture=$(mktemp -d)
mkdir -p "$fixture/install" "$fixture/data" "$fixture/bin"
base='https://raw.githubusercontent.com/Redsauce/firulai-linux-agent'
for file in rs_agent.sh api_endpoint.sh uninstall.sh; do
    curl -fsSL "$base/0.4.2/$file" -o "$fixture/install/$file"
done
cp "$fixture/install/rs_agent.sh" "$fixture/original.sh"
printf "AGENT_AUTO_UPDATE='1'\nUUID='00000000-0000-4000-8000-000000000001'\nAGENT_TOKEN='fixture-only'\n" > "$fixture/data/config.env"
cp "$fixture/data/config.env" "$fixture/original-config.env"
cat > "$fixture/bin/bash" <<'RESTART'
#!/bin/sh
if [ "$1" = '-n' ]; then exec /bin/bash "$@"; fi
[ "$1" = "$RS_AGENT_INSTALL_DIR/rs_agent.sh" ] || exit 1
grep -Fxq 'AGENT_VERSION="0.4.3"' "$1" || exit 1
printf 'restart verified\n' > "$RS_AGENT_DATA_DIR/restart.txt"
RESTART
chmod +x "$fixture/bin/bash"
export PATH="$fixture/bin:$PATH"
export RS_AGENT_INSTALL_DIR="$fixture/install" RS_AGENT_DATA_DIR="$fixture/data"
run_check() {
    (
        source <(sed '$d' "$fixture/install/rs_agent.sh")
        AGENT_TOKEN='fixture-only'
        UUID_VAL='00000000-0000-4000-8000-000000000001'
        AGENT_LOCALE='en_US'
        check_for_updates
    )
}
run_check
cmp "$fixture/original-config.env" "$fixture/data/config.env"
cmp "$fixture/original.sh" "$fixture/install/rs_agent.sh.backup"
grep -Fxq 'AGENT_VERSION="0.4.3"' "$fixture/install/rs_agent.sh"
test -s "$fixture/data/restart.txt"
echo 'PASS: released Linux 0.4.2 detects and downloads 0.4.3, preserves config and delegates restart.'
# Exercise the new pinned downloader directly using the published tag.
(
    source <(sed '$d' "$fixture/install/rs_agent.sh")
    AGENT_TOKEN='fixture-only'
    UUID_VAL='00000000-0000-4000-8000-000000000001'
    AGENT_LOCALE='en_US'
    download_update 0.4.3
)
cmp "$fixture/original-config.env" "$fixture/data/config.env"
echo 'PASS: new Linux downloader retrieves and validates the real 0.4.3 tag.'
echo "Isolated evidence: $fixture"
