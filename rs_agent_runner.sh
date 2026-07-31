#!/bin/bash
# -*- coding: utf-8 -*-
# Runs RSAgent only when the daily 03:00 execution is pending.

set -uo pipefail

RUN_AS_ROOT=0
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    RUN_AS_ROOT=1
fi

if [ "$RUN_AS_ROOT" = "1" ]; then
    INSTALL_DIR="${RS_AGENT_INSTALL_DIR:-/opt/rs-agent}"
    DATA_DIR="${RS_AGENT_DATA_DIR:-/var/lib/rs-agent}"
    LOG_FILE="${RS_AGENT_LOG_FILE:-/var/log/rs-agent.log}"
else
    INSTALL_DIR="${RS_AGENT_INSTALL_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/rs-agent}"
    DATA_DIR="${RS_AGENT_DATA_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/rs-agent}"
    LOG_FILE="${RS_AGENT_LOG_FILE:-$DATA_DIR/rs-agent.log}"
fi

CONFIG_FILE="$DATA_DIR/config.env"
STATE_FILE="$DATA_DIR/state.env"
AGENT_SCRIPT="$INSTALL_DIR/rs_agent.sh"
TRIGGER="automatic"

while [ $# -gt 0 ]; do
    case "$1" in
        --if-due) shift ;;
        --trigger)
            [ $# -ge 2 ] || { echo "ERROR: --trigger requires a value" >&2; exit 2; }
            TRIGGER="$2"
            shift 2
            ;;
        *) echo "ERROR: Unknown argument: $1" >&2; exit 2 ;;
    esac
done

log_line() {
    printf '%s [INFO] %s\n' "$(date '+%Y-%m-%d %H:%M:%S %z')" "$1" | tee -a "$LOG_FILE"
}

error_line() {
    printf '%s [ERROR] %s\n' "$(date '+%Y-%m-%d %H:%M:%S %z')" "$1" | tee -a "$LOG_FILE" >&2
}

mkdir -p "$(dirname "$LOG_FILE")"

if [ ! -r "$CONFIG_FILE" ] || [ ! -x "$AGENT_SCRIPT" ]; then
    error_line "Incomplete installation: missing $CONFIG_FILE or $AGENT_SCRIPT."
    exit 1
fi

# shellcheck source=/dev/null
. "$CONFIG_FILE"
AGENT_TOKEN="${AGENT_TOKEN:-}"
UUID="${UUID:-}"
SYSTEM_ALIAS="${SYSTEM_ALIAS:-}"
if [ -z "$AGENT_TOKEN" ] || [ -z "$UUID" ] || [ -z "$SYSTEM_ALIAS" ]; then
    error_line "config.env does not contain valid token, UUID, and alias values."
    exit 1
fi

now_epoch=$(date +%s)
scheduled_epoch=$(date -d "$(date +%F) 03:00:00" +%s 2>/dev/null) || {
    error_line "Could not calculate the daily 03:00 execution with date."
    exit 1
}

last_success_epoch=0
if [ -r "$STATE_FILE" ]; then
    last_success_epoch=$(sed -n 's/^LAST_SUCCESS_EPOCH=\([0-9][0-9]*\)$/\1/p' "$STATE_FILE" | head -1)
    last_success_epoch="${last_success_epoch:-0}"
fi

# Before 03:00, or after a successful execution today, there is no work to do.
if [ "$now_epoch" -lt "$scheduled_epoch" ] || [ "$last_success_epoch" -ge "$scheduled_epoch" ]; then
    exit 0
fi

delay_seconds=$((now_epoch - scheduled_epoch))
log_line "Pending execution detected. Trigger=$TRIGGER, scheduled=$(date -d "@$scheduled_epoch" '+%Y-%m-%d %H:%M:%S %z'), delaySeconds=$delay_seconds."

set +e
RS_AGENT_TRIGGER="$TRIGGER" /bin/bash "$AGENT_SCRIPT" \
    --token "$AGENT_TOKEN" \
    --uuid "$UUID" \
    --alias "$SYSTEM_ALIAS" 2>&1 | tee -a "$LOG_FILE"
agent_status=${PIPESTATUS[0]}
set -e

if [ "$agent_status" -ne 0 ]; then
    error_line "Pending execution failed. Trigger=$TRIGGER, code=$agent_status."
    exit "$agent_status"
fi

log_line "Pending execution completed. Trigger=$TRIGGER."
exit 0
