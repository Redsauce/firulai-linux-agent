#!/bin/bash
# Ephemeral CI VM only: never overwrite an existing agent installation.
set -euo pipefail
cd "$(dirname "$0")/.."
[ "$(id -u)" = 0 ] && [ -d /run/systemd/system ]
for unit in /etc/systemd/system/rs-agent.service /etc/systemd/system/rs-agent.timer; do
    [ ! -e "$unit" ] || { echo 'Existing agent unit: refusing destructive test' >&2; exit 1; }
done
fixture=$(mktemp -d)
cleanup() {
    systemctl stop rs-agent.timer rs-agent.service || true
    rm -f /etc/systemd/system/rs-agent.service /etc/systemd/system/rs-agent.timer
    systemctl daemon-reload
    rm -rf -- "$fixture"
}
trap cleanup EXIT
RUN_AS_ROOT=1
INSTALL_DIR="$fixture/install"
OUTPUT_DIR="$fixture/data"
mkdir -p "$INSTALL_DIR" "$OUTPUT_DIR"
cat > "$INSTALL_DIR/rs_agent_runner.sh" <<RUNNER
#!/bin/bash
FIRULAI_UPDATE_POLLING_VERSION=1
printf 'tick\n' >> "$OUTPUT_DIR/ticks"
RUNNER
cat > /etc/systemd/system/rs-agent.service <<UNIT
[Unit]
Description=Isolated Firulai scheduling test
[Service]
Type=oneshot
ExecStart=/bin/bash $INSTALL_DIR/rs_agent_runner.sh
Restart=on-failure
RestartSec=30min
UNIT
cat > /etc/systemd/system/rs-agent.timer <<UNIT
[Unit]
Description=Isolated Firulai legacy timer
[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true
Unit=rs-agent.service
UNIT
source <(sed -n '/^ensure_update_polling() {/,/^}/p' rs_agent.sh)
ensure_update_polling
systemd-analyze verify /etc/systemd/system/rs-agent.service /etc/systemd/system/rs-agent.timer
grep -Fxq 'OnCalendar=*-*-* *:*:00' /etc/systemd/system/rs-agent.timer
grep -Fxq 'OnBootSec=1s' /etc/systemd/system/rs-agent.timer
! grep -q '^Restart=' /etc/systemd/system/rs-agent.service
systemctl is-active --quiet rs-agent.timer
systemctl start rs-agent.service
grep -Fxq tick "$OUTPUT_DIR/ticks"
echo 'PASS: actual systemd legacy timer migration, active minute timer, boot trigger and oneshot execution.'
