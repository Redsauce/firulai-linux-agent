#!/bin/bash
# -*- coding: utf-8 -*-
# Ejecuta RSAgent únicamente cuando la ejecución diaria de las 03:00 está pendiente.

set -uo pipefail

INSTALL_DIR="/opt/rs-agent"
DATA_DIR="/var/lib/rs-agent"
CONFIG_FILE="$DATA_DIR/config.env"
STATE_FILE="$DATA_DIR/state.env"
LOG_FILE="/var/log/rs-agent.log"
AGENT_SCRIPT="$INSTALL_DIR/rs_agent.sh"
TRIGGER="automatico"

while [ $# -gt 0 ]; do
    case "$1" in
        --if-due) shift ;;
        --trigger)
            [ $# -ge 2 ] || { echo "ERROR: --trigger requiere un valor" >&2; exit 2; }
            TRIGGER="$2"
            shift 2
            ;;
        *) echo "ERROR: Argumento desconocido: $1" >&2; exit 2 ;;
    esac
done

log_line() {
    printf '%s [INFO] %s\n' "$(date '+%Y-%m-%d %H:%M:%S %z')" "$1" | tee -a "$LOG_FILE"
}

error_line() {
    printf '%s [ERROR] %s\n' "$(date '+%Y-%m-%d %H:%M:%S %z')" "$1" | tee -a "$LOG_FILE" >&2
}

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    error_line "El runner automático debe ejecutarse como root."
    exit 1
fi

if [ ! -r "$CONFIG_FILE" ] || [ ! -x "$AGENT_SCRIPT" ]; then
    error_line "Instalación incompleta: faltan $CONFIG_FILE o $AGENT_SCRIPT."
    exit 1
fi

# shellcheck source=/dev/null
. "$CONFIG_FILE"
AGENT_TOKEN="${AGENT_TOKEN:-}"
RSM_TOKEN="${RSM_TOKEN:-}"
UUID="${UUID:-}"
SYSTEM_ALIAS="${SYSTEM_ALIAS:-}"
if [ -z "$AGENT_TOKEN" ] || [ -z "$RSM_TOKEN" ] || [ -z "$UUID" ] || [ -z "$SYSTEM_ALIAS" ]; then
    error_line "config.env no contiene token, RSM token, UUID y alias válidos."
    exit 1
fi

now_epoch=$(date +%s)
scheduled_epoch=$(date -d "$(date +%F) 03:00:00" +%s 2>/dev/null) || {
    error_line "No se pudo calcular la ejecución diaria de las 03:00 con date."
    exit 1
}

last_success_epoch=0
if [ -r "$STATE_FILE" ]; then
    last_success_epoch=$(sed -n 's/^LAST_SUCCESS_EPOCH=\([0-9][0-9]*\)$/\1/p' "$STATE_FILE" | head -1)
    last_success_epoch="${last_success_epoch:-0}"
fi

# Antes de las 03:00 o después de una ejecución correcta del día no hay trabajo.
if [ "$now_epoch" -lt "$scheduled_epoch" ] || [ "$last_success_epoch" -ge "$scheduled_epoch" ]; then
    exit 0
fi

delay_seconds=$((now_epoch - scheduled_epoch))
log_line "Ejecución pendiente detectada. Origen=$TRIGGER, prevista=$(date -d "@$scheduled_epoch" '+%Y-%m-%d %H:%M:%S %z'), retrasoSegundos=$delay_seconds."

set +e
RS_AGENT_TRIGGER="$TRIGGER" /bin/bash "$AGENT_SCRIPT" \
    --token "$AGENT_TOKEN" \
    --rsm-token "$RSM_TOKEN" \
    --uuid "$UUID" \
    --alias "$SYSTEM_ALIAS" 2>&1 | tee -a "$LOG_FILE"
agent_status=${PIPESTATUS[0]}
set -e

if [ "$agent_status" -ne 0 ]; then
    error_line "La ejecución pendiente falló. Origen=$TRIGGER, código=$agent_status."
    exit "$agent_status"
fi

log_line "Ejecución pendiente completada. Origen=$TRIGGER."
exit 0
