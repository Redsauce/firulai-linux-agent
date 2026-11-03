#!/bin/bash
# Ephemeral CI VM only: never overwrite an existing agent installation.
set -euo pipefail
cd "$(dirname "$0")/.."
[ "$(id -u)" = 0 ] && [ -d /run/systemd/system ]
for unit in /etc/systemd/system/firulaiAgent.service /etc/systemd/system/firulaiAgent.timer; do
    [ ! -e "$unit" ] || { echo 'Existing agent unit: refusing destructive test' >&2; exit 1; }
done
fixture=$(mktemp -d)
cleanup() {
    systemctl stop firulaiAgent.timer firulaiAgent.service || true
    rm -f /etc/systemd/system/firulaiAgent.service /etc/systemd/system/firulaiAgent.timer
    systemctl daemon-reload
    rm -rf -- "$fixture"
}
trap cleanup EXIT
RUN_AS_ROOT=1
INSTALL_DIR="$fixture/install"
OUTPUT_DIR="$fixture/data"
mkdir -p "$INSTALL_DIR" "$OUTPUT_DIR"
cat > "$INSTALL_DIR/firulaiAgent_runner.sh" <<RUNNER
#!/bin/bash
FIRULAI_UPDATE_POLLING_VERSION=1
printf 'tick\n' >> "$OUTPUT_DIR/ticks"
RUNNER
cat > /etc/systemd/system/firulaiAgent.service <<UNIT
[Unit]
Description=Isolated Firulai scheduling test
[Service]
Type=oneshot
ExecStart=/bin/bash $INSTALL_DIR/firulaiAgent_runner.sh
Restart=on-failure
RestartSec=30min
UNIT
cat > /etc/systemd/system/firulaiAgent.timer <<UNIT
[Unit]
Description=Isolated Firulai legacy timer
[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true
Unit=firulaiAgent.service
UNIT
source <(sed -n '/^ensure_update_polling() {/,/^}/p' firulaiAgent.sh)
ensure_update_polling
systemd-analyze verify /etc/systemd/system/firulaiAgent.service /etc/systemd/system/firulaiAgent.timer
grep -Fxq 'OnCalendar=*-*-* *:*:00' /etc/systemd/system/firulaiAgent.timer
grep -Fxq 'OnBootSec=1s' /etc/systemd/system/firulaiAgent.timer
! grep -q '^Restart=' /etc/systemd/system/firulaiAgent.service
systemctl is-active --quiet firulaiAgent.timer
systemctl start firulaiAgent.service
grep -Fxq tick "$OUTPUT_DIR/ticks"
echo 'PASS: actual systemd legacy timer migration, active minute timer, boot trigger and oneshot execution.'
