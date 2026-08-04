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
AGENT_LOCALE="${RS_AGENT_LOCALE:-}"

normalize_locale() {
    local value
    value=$(printf '%s' "${1:-}" | tr '[:upper:]-' '[:lower:]_')
    case "$value" in
        es*) printf '%s' "es_ES" ;;
        ca*) printf '%s' "ca_ES" ;;
        eu*) printf '%s' "eu_ES" ;;
        gl*) printf '%s' "gl_ES" ;;
        fr*) printf '%s' "fr_FR" ;;
        de*) printf '%s' "de_DE" ;;
        it*) printf '%s' "it_IT" ;;
        ja*) printf '%s' "ja_JP" ;;
        zh*) printf '%s' "zh_CN" ;;
        *) printf '%s' "en_US" ;;
    esac
}

t() {
    local key="$1"
    case "$(normalize_locale "$AGENT_LOCALE"):$key" in
        es_ES:trigger_requires_value) printf '%s' "ERROR: --trigger requiere un valor" ;;
        es_ES:unknown_argument) printf '%s' "ERROR: Argumento desconocido" ;;
        es_ES:incomplete_installation) printf '%s' "Instalacion incompleta: falta el archivo de configuracion o el script del agente." ;;
        es_ES:invalid_config) printf '%s' "config.env no contiene valores validos de token, UUID y alias." ;;
        es_ES:date_failed) printf '%s' "No se pudo calcular la ejecucion diaria de las 03:00 con date." ;;
        es_ES:pending_detected) printf '%s' "Ejecucion pendiente detectada." ;;
        es_ES:pending_failed) printf '%s' "La ejecucion pendiente fallo." ;;
        es_ES:pending_completed) printf '%s' "Ejecucion pendiente completada." ;;
        ca_ES:trigger_requires_value) printf '%s' "ERROR: --trigger requereix un valor" ;;
        ca_ES:unknown_argument) printf '%s' "ERROR: Argument desconegut" ;;
        ca_ES:incomplete_installation) printf '%s' "Instal.lacio incompleta: falta el fitxer de configuracio o el script de l'agent." ;;
        ca_ES:invalid_config) printf '%s' "config.env no conte valors valids de token, UUID i alias." ;;
        ca_ES:date_failed) printf '%s' "No s'ha pogut calcular l'execucio diaria de les 03:00 amb date." ;;
        ca_ES:pending_detected) printf '%s' "Execucio pendent detectada." ;;
        ca_ES:pending_failed) printf '%s' "L'execucio pendent ha fallat." ;;
        ca_ES:pending_completed) printf '%s' "Execucio pendent completada." ;;
        *:trigger_requires_value) printf '%s' "ERROR: --trigger requires a value" ;;
        *:unknown_argument) printf '%s' "ERROR: Unknown argument" ;;
        *:incomplete_installation) printf '%s' "Incomplete installation: missing config file or agent script." ;;
        *:invalid_config) printf '%s' "config.env does not contain valid token, UUID, and alias values." ;;
        *:date_failed) printf '%s' "Could not calculate the daily 03:00 execution with date." ;;
        *:pending_detected) printf '%s' "Pending execution detected." ;;
        *:pending_failed) printf '%s' "Pending execution failed." ;;
        *:pending_completed) printf '%s' "Pending execution completed." ;;
        *) printf '%s' "$key" ;;
    esac
}

while [ $# -gt 0 ]; do
    case "$1" in
        --if-due) shift ;;
        --trigger)
            [ $# -ge 2 ] || { echo "$(t trigger_requires_value)" >&2; exit 2; }
            TRIGGER="$2"
            shift 2
            ;;
        *) echo "$(t unknown_argument): $1" >&2; exit 2 ;;
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
    error_line "$(t incomplete_installation) ($CONFIG_FILE / $AGENT_SCRIPT)"
    exit 1
fi

# shellcheck source=/dev/null
. "$CONFIG_FILE"
AGENT_TOKEN="${AGENT_TOKEN:-}"
UUID="${UUID:-}"
SYSTEM_ALIAS="${SYSTEM_ALIAS:-}"
AGENT_LOCALE=$(normalize_locale "${AGENT_LOCALE:-}")
if [ -z "$AGENT_TOKEN" ] || [ -z "$UUID" ] || [ -z "$SYSTEM_ALIAS" ]; then
    error_line "$(t invalid_config)"
    exit 1
fi

now_epoch=$(date +%s)
scheduled_epoch=$(date -d "$(date +%F) 03:00:00" +%s 2>/dev/null) || {
    error_line "$(t date_failed)"
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
log_line "$(t pending_detected) Trigger=$TRIGGER, scheduled=$(date -d "@$scheduled_epoch" '+%Y-%m-%d %H:%M:%S %z'), delaySeconds=$delay_seconds."

set +e
RS_AGENT_TRIGGER="$TRIGGER" /bin/bash "$AGENT_SCRIPT" \
    --token "$AGENT_TOKEN" \
    --uuid "$UUID" \
    --alias "$SYSTEM_ALIAS" \
    --locale "$AGENT_LOCALE" 2>&1 | tee -a "$LOG_FILE"
agent_status=${PIPESTATUS[0]}
set -e

if [ "$agent_status" -ne 0 ]; then
    error_line "$(t pending_failed) Trigger=$TRIGGER, code=$agent_status."
    exit "$agent_status"
fi

log_line "$(t pending_completed) Trigger=$TRIGGER."
exit 0
