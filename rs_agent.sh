#!/bin/bash
# Compatibility entry point for agents installed before the firulaiAgent rename.
# The published legacy updater requires this exact filename and version line.
AGENT_VERSION="0.4.13"
set -euo pipefail

legacy_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    new_dir=/opt/firulaiAgent
    legacy_data=/var/lib/rs-agent
    new_data=/var/lib/firulaiAgent
    unit_dir=/etc/systemd/system
    systemctl_scope=()
else
    new_dir="${XDG_DATA_HOME:-$HOME/.local/share}/firulaiAgent"
    legacy_data="${XDG_STATE_HOME:-$HOME/.local/state}/rs-agent"
    new_data="${XDG_STATE_HOME:-$HOME/.local/state}/firulaiAgent"
    unit_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
    systemctl_scope=(--user)
fi

if [ -f "$new_dir/firulaiAgent.sh" ] && [ -f "$new_data/config.env" ] &&
    [ -f "$new_data/migration-complete" ]; then
    exec /bin/bash "$new_dir/firulaiAgent.sh" "$@"
fi

old_agent="$legacy_dir/rs_agent.sh.backup"
original_args=("$@")
release="https://raw.githubusercontent.com/Redsauce/firulai-linux-agent/$AGENT_VERSION"
stage=$(mktemp -d "${TMPDIR:-/tmp}/firulaiAgent-migration.XXXXXXXX") || exit 1
chmod 700 "$stage"
committed=0
old_timer_stopped=0
new_timer_started=0
created_new=0
old_cron=""
rollback() {
    if [ "$committed" = 1 ]; then return; fi
    if [ "$new_timer_started" = 1 ]; then
        systemctl "${systemctl_scope[@]}" disable --now firulaiAgent.timer >/dev/null 2>&1 || true
        rm -f -- "$unit_dir/firulaiAgent.service" "$unit_dir/firulaiAgent.timer"
        systemctl "${systemctl_scope[@]}" daemon-reload >/dev/null 2>&1 || true
    fi
    if [ -n "$old_cron" ] && command -v crontab >/dev/null 2>&1; then
        crontab "$old_cron" || true
    fi
    if [ "$old_timer_stopped" = 1 ]; then
        systemctl "${systemctl_scope[@]}" enable --now rs-agent.timer >/dev/null 2>&1 || true
    fi
    if [ "$created_new" = 1 ]; then rm -rf -- "$new_dir" "$new_data"; fi
}
on_exit() {
    local status=$?
    rollback
    rm -rf -- "$stage"
    if [ "$status" -ne 0 ] && [ -f "$old_agent" ]; then
        echo 'Migration deferred; running the previous agent.' >&2
        trap - EXIT
        exec /bin/bash "$old_agent" "${original_args[@]}"
    fi
}
trap on_exit EXIT

if [ ! -f "$legacy_data/config.env" ] || [ ! -f "$old_agent" ] ||
    [ -e "$new_dir" ] || [ -L "$new_dir" ] ||
    [ -e "$new_data" ] || [ -L "$new_data" ]; then
    echo 'Migration preflight failed; keeping the previous agent.' >&2
    exit 1
fi

for file in firulaiAgent.sh firulaiAgent_runner.sh api_endpoint.sh uninstall.sh; do
    curl -fsSL --proto '=https' --proto-redir '=https' --max-time 30 \
        "$release/$file" -o "$stage/$file" || exit 1
    bash -n "$stage/$file" || exit 1
done
grep -Fxq "AGENT_VERSION=\"$AGENT_VERSION\"" "$stage/firulaiAgent.sh" || exit 1
grep -Fxq 'FIRULAI_UPDATE_POLLING_VERSION=1' "$stage/firulaiAgent_runner.sh" || exit 1

mkdir -m 700 -p -- "$new_dir" "$new_data"
created_new=1
cp -a -- "$legacy_data/." "$new_data/" || exit 1
cp -p -- "$stage/firulaiAgent.sh" "$stage/firulaiAgent_runner.sh" \
    "$stage/api_endpoint.sh" "$stage/uninstall.sh" "$new_dir/" || exit 1
chmod 755 "$new_dir/firulaiAgent.sh" "$new_dir/firulaiAgent_runner.sh" "$new_dir/uninstall.sh"
chmod 644 "$new_dir/api_endpoint.sh"
chmod 700 "$new_data"
chmod 600 "$new_data/config.env"

if [ -f "$unit_dir/rs-agent.timer" ] && [ -f "$unit_dir/rs-agent.service" ]; then
    command -v systemctl >/dev/null 2>&1 || exit 1
    touch "$new_data/migration-pending" || exit 1
    sed -e "s|$legacy_dir|$new_dir|g" -e 's/rs_agent_runner.sh/firulaiAgent_runner.sh/g' \
        -e 's/rs-agent/firulaiAgent/g' -e 's/Firulai Inventory Agent/Firulai Security Agent/g' \
        "$unit_dir/rs-agent.service" > "$stage/firulaiAgent.service"
    sed -e 's/rs-agent/firulaiAgent/g' -e 's/Firulai Inventory Agent/Firulai Security Agent/g' \
        "$unit_dir/rs-agent.timer" > "$stage/firulaiAgent.timer"
    grep -Fq "$new_dir/firulaiAgent_runner.sh" "$stage/firulaiAgent.service" || exit 1
    cp -p -- "$stage/firulaiAgent.service" "$stage/firulaiAgent.timer" "$unit_dir/"
    systemctl "${systemctl_scope[@]}" daemon-reload || exit 1
    new_timer_started=1
    systemctl "${systemctl_scope[@]}" enable --now firulaiAgent.timer || exit 1
    systemctl "${systemctl_scope[@]}" is-active --quiet firulaiAgent.timer || exit 1
    touch "$new_data/migration-complete" || exit 1
    rm -f -- "$new_data/migration-pending"
    old_timer_stopped=1
    systemctl "${systemctl_scope[@]}" disable --now rs-agent.timer || exit 1
elif command -v crontab >/dev/null 2>&1; then
    crontab -l > "$stage/old-cron" || exit 1
    old_cron="$stage/old-cron"
    grep -Fq "$legacy_dir/rs_agent_runner.sh" "$old_cron" || exit 1
    sed -e "s|$legacy_dir/rs_agent_runner.sh|$new_dir/firulaiAgent_runner.sh|g" \
        "$old_cron" > "$stage/new-cron"
    touch "$new_data/migration-complete" || exit 1
    crontab "$stage/new-cron" || exit 1
    crontab -l | grep -Fq "$new_dir/firulaiAgent_runner.sh" || exit 1
else
    echo 'Unknown scheduler; keeping the previous agent.' >&2
    exit 1
fi

committed=1
if [ "$old_timer_stopped" = 1 ]; then
    rm -f -- "$unit_dir/rs-agent.service" "$unit_dir/rs-agent.timer"
    systemctl "${systemctl_scope[@]}" daemon-reload || true
fi
rm -rf -- "$legacy_dir" "$legacy_data"
rm -rf -- "$stage"
echo 'Firulai Security Agent migration completed.'
exec /bin/bash "$new_dir/firulaiAgent.sh" "$@"
