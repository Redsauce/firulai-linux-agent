#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
repo=$PWD
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
export XDG_DATA_HOME="$fixture/share" XDG_STATE_HOME="$fixture/state" XDG_CONFIG_HOME="$fixture/config"
export PATH="$fixture/bin:$PATH"
mkdir -p "$fixture/bin" "$fixture/share/rs-agent" "$fixture/state/rs-agent" "$fixture/source"
cp "$repo/rs_agent.sh" "$fixture/share/rs-agent/rs_agent.sh"
printf '#!/bin/bash\necho old-agent-ran\n' > "$fixture/share/rs-agent/rs_agent.sh.backup"
printf "AGENT_TOKEN='fixture-token'\nUUID='00000000-0000-4000-8000-000000000001'\n" > "$fixture/state/rs-agent/config.env"
printf 'OLD_STATE=preserved\n' > "$fixture/state/rs-agent/state.env"
printf '#!/bin/bash\nAGENT_VERSION="0.4.13"\necho new-agent-ran\n' > "$fixture/source/firulaiAgent.sh"
printf '#!/bin/bash\nFIRULAI_UPDATE_POLLING_VERSION=1\n' > "$fixture/source/firulaiAgent_runner.sh"
printf '#!/bin/bash\n:\n' > "$fixture/source/api_endpoint.sh"
printf '#!/bin/bash\n:\n' > "$fixture/source/uninstall.sh"
cat > "$fixture/bin/curl" <<'CURL'
#!/bin/bash
for ((i=1; i<=$#; i++)); do
    if [ "${!i}" = -o ]; then j=$((i+1)); output=${!j}; fi
done
url=${@: -3:1}
cp "$MIGRATION_SOURCE/${url##*/}" "$output"
CURL
cat > "$fixture/bin/crontab" <<'CRON'
#!/bin/bash
if [ "${1:-}" = -l ]; then cat "$MIGRATION_CRON"; else cp "$1" "$MIGRATION_CRON"; fi
CRON
chmod +x "$fixture/bin/curl" "$fixture/bin/crontab"
export MIGRATION_SOURCE="$fixture/source" MIGRATION_CRON="$fixture/cron"
run_fixture() {
    if [ "$(id -u)" -eq 0 ]; then
        runuser -u nobody -- env PATH="$PATH" XDG_DATA_HOME="$XDG_DATA_HOME" \
            XDG_STATE_HOME="$XDG_STATE_HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
            MIGRATION_SOURCE="$MIGRATION_SOURCE" MIGRATION_CRON="$MIGRATION_CRON" \
            MIGRATION_SYSTEMCTL_LOG="${MIGRATION_SYSTEMCTL_LOG:-}" \
            bash "$fixture/share/rs-agent/rs_agent.sh" --check-updates
    else
        env PATH="$PATH" XDG_DATA_HOME="$XDG_DATA_HOME" \
            XDG_STATE_HOME="$XDG_STATE_HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
            MIGRATION_SOURCE="$MIGRATION_SOURCE" MIGRATION_CRON="$MIGRATION_CRON" \
            MIGRATION_SYSTEMCTL_LOG="${MIGRATION_SYSTEMCTL_LOG:-}" \
            bash "$fixture/share/rs-agent/rs_agent.sh" --check-updates
    fi
}
printf '0 1 * * * echo unrelated\n* * * * * /bin/bash %s/rs_agent_runner.sh --if-due\n' \
    "$fixture/share/rs-agent" > "$MIGRATION_CRON"
if [ "$(id -u)" -eq 0 ]; then chown -R nobody:nogroup "$fixture"; fi
result=$(run_fixture)
[[ "$result" == *new-agent-ran* ]]
test -f "$fixture/share/firulaiAgent/firulaiAgent.sh"
test -f "$fixture/state/firulaiAgent/config.env"
grep -Fxq OLD_STATE=preserved "$fixture/state/firulaiAgent/state.env"
grep -Fq "$fixture/share/firulaiAgent/firulaiAgent_runner.sh" "$MIGRATION_CRON"
! grep -Fq rs-agent "$MIGRATION_CRON"
test ! -e "$fixture/share/rs-agent"
test ! -e "$fixture/state/rs-agent"
echo 'PASS: legacy updater entry migrates user cron installation without changing identity or state.'

rm -rf -- "$fixture/share/firulaiAgent" "$fixture/state/firulaiAgent"
mkdir -p "$fixture/share/rs-agent" "$fixture/state/rs-agent"
cp "$repo/rs_agent.sh" "$fixture/share/rs-agent/rs_agent.sh"
printf '#!/bin/bash\necho old-agent-ran\n' > "$fixture/share/rs-agent/rs_agent.sh.backup"
printf "AGENT_TOKEN='fixture-token'\nUUID='00000000-0000-4000-8000-000000000001'\n" > "$fixture/state/rs-agent/config.env"
printf '* * * * * /bin/bash %s/rs_agent_runner.sh --if-due\n' "$fixture/share/rs-agent" > "$MIGRATION_CRON"
if [ "$(id -u)" -eq 0 ]; then chown -R nobody:nogroup "$fixture/share/rs-agent" "$fixture/state/rs-agent" "$MIGRATION_CRON"; fi
rm "$fixture/source/firulaiAgent_runner.sh"
result=$(run_fixture)
[[ "$result" == *old-agent-ran* ]]
test -f "$fixture/share/rs-agent/rs_agent.sh.backup"
test -f "$fixture/state/rs-agent/config.env"
test ! -e "$fixture/share/firulaiAgent"
test ! -e "$fixture/state/firulaiAgent"
grep -Fq "$fixture/share/rs-agent/rs_agent_runner.sh" "$MIGRATION_CRON"
echo 'PASS: failed migration keeps the old agent and scheduler active.'

printf '#!/bin/bash\nFIRULAI_UPDATE_POLLING_VERSION=1\n' > "$fixture/source/firulaiAgent_runner.sh"
mkdir -p "$fixture/config/systemd/user"
cat > "$fixture/config/systemd/user/rs-agent.service" <<SERVICE
[Unit]
Description=Firulai Inventory Agent execution
[Service]
Type=oneshot
ExecStart=/bin/bash $fixture/share/rs-agent/rs_agent_runner.sh --if-due
SERVICE
cat > "$fixture/config/systemd/user/rs-agent.timer" <<'TIMER'
[Unit]
Description=Firulai Inventory Agent daily schedule
[Timer]
Unit=rs-agent.service
[Install]
WantedBy=timers.target
TIMER
cat > "$fixture/bin/systemctl" <<'SYSTEMCTL'
#!/bin/bash
printf '%s\n' "$*" >> "$MIGRATION_SYSTEMCTL_LOG"
exit 0
SYSTEMCTL
chmod +x "$fixture/bin/systemctl"
export MIGRATION_SYSTEMCTL_LOG="$fixture/systemctl.log"
if [ "$(id -u)" -eq 0 ]; then chown -R nobody:nogroup "$fixture/config" "$fixture/source/firulaiAgent_runner.sh"; fi
result=$(run_fixture)
[[ "$result" == *new-agent-ran* ]]
grep -Fq -- '--user disable --now rs-agent.timer' "$MIGRATION_SYSTEMCTL_LOG"
grep -Fq -- '--user enable --now firulaiAgent.timer' "$MIGRATION_SYSTEMCTL_LOG"
grep -Fq "$fixture/share/firulaiAgent/firulaiAgent_runner.sh" "$fixture/config/systemd/user/firulaiAgent.service"
test ! -e "$fixture/config/systemd/user/rs-agent.timer"
test ! -e "$fixture/config/systemd/user/rs-agent.service"
test ! -e "$fixture/share/rs-agent"
echo 'PASS: legacy user systemd timer switches to the new name and path.'
