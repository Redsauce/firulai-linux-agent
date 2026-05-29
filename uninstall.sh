#!/bin/bash
# -*- coding: utf-8 -*-
#
# Redsauce Inventory Agent - Uninstaller
# Notifica a RSM que debe borrar los datos del sistema y elimina la instalacion local.
#

set -uo pipefail

INSTALL_DIR="/opt/rs-agent"
DATA_DIR="/var/lib/rs-agent"
CONFIG_FILE="$DATA_DIR/config.env"
LOG_FILE="/var/log/rs-agent.log"
RSM_API_URL="https://rsm1.redsauce.net/AppController/commands_RSM/api/api.php"
AGENT_TOKEN=""
UUID_VAL=""

log() {
    printf '[OK] %s\n' "$1"
}

info() {
    printf '[INFO] %s\n' "$1"
}

warn() {
    printf '[WARN] %s\n' "$1"
}

error() {
    printf '[ERROR] %s\n' "$1" >&2
}

check_root() {
    if [ "${EUID:-$(id -u)}" -ne 0 ]; then
        error "Este script requiere permisos de root"
        echo "Ejecuta: sudo bash $INSTALL_DIR/uninstall.sh"
        exit 1
    fi
}

validate_uuid() {
    local uuid="$1"
    if [[ ! "$uuid" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
        error "'$uuid' no es un UUID valido"
        exit 1
    fi
}

load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        # shellcheck source=/dev/null
        . "$CONFIG_FILE"
        AGENT_TOKEN="${AGENT_TOKEN:-}"
        UUID_VAL="${UUID_VAL:-${UUID:-}}"
    fi
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --token) AGENT_TOKEN="${2:-}"; shift 2 ;;
            --uuid) UUID_VAL="${2:-}"; shift 2 ;;
            *) error "Argumento desconocido: $1"; exit 1 ;;
        esac
    done

    if [ -z "$AGENT_TOKEN" ] || [ -z "$UUID_VAL" ]; then
        error "No se encontro token o UUID para notificar a RSM"
        echo "Uso manual: sudo bash uninstall.sh --token <TOKEN> --uuid <UUID>"
        exit 1
    fi

    validate_uuid "$UUID_VAL"
}

confirm_uninstall() {
    echo ""
    echo "============================================================"
    echo "Redsauce Inventory Agent - Desinstalacion"
    echo "============================================================"
    echo ""
    echo "Esta accion borrara la instalacion local del agente y solicitara"
    echo "a RSM el borrado de todos los datos relacionados con este sistema."
    echo ""
    echo "UUID del sistema: $UUID_VAL"
    echo ""
    read -r -p "Estas de acuerdo con borrar todos los datos relacionados con este sistema? (s/N): " reply
    case "$reply" in
        s|S|si|SI|Si|yes|YES|Yes) ;;
        *)
            warn "Desinstalacion cancelada por el usuario"
            exit 0
            ;;
    esac
}

send_delete_request_to_rsm() {
    local delete_payload
    delete_payload="{\"uuid\":\"$UUID_VAL\"}"

    info "Solicitando a RSM el borrado de datos del sistema..."
    printf 'UUID: %s\n' "$UUID_VAL"
    printf 'URL: %s\n' "$RSM_API_URL"

    curl \
        --location "$RSM_API_URL" \
        --form "RStrigger=deleteSystemData" \
        --form "RSdata=$delete_payload" \
        --form "RStoken=$AGENT_TOKEN" \
        --max-time 30 \
        --show-error
    local exit_code=$?

    if [ "$exit_code" -eq 0 ]; then
        log "Solicitud de borrado enviada correctamente a RSM"
        return 0
    fi

    error "No se pudo solicitar el borrado en RSM (curl exit: $exit_code)"
    return 1
}

remove_cron() {
    info "Eliminando ejecucion automatica..."
    if ({ crontab -l 2>/dev/null || true; } | grep -v "$INSTALL_DIR/rs_agent.sh" || true) | crontab -; then
        log "Entrada de cron eliminada"
    else
        warn "No se pudo actualizar el crontab o no habia entrada configurada"
    fi
}

remove_local_files() {
    info "Eliminando archivos locales..."

    rm -rf "$DATA_DIR"
    rm -rf "$INSTALL_DIR"
    rm -f "$LOG_FILE"

    log "Archivos locales eliminados"
}

main() {
    check_root

    load_config
    parse_args "$@"
    confirm_uninstall

    if ! send_delete_request_to_rsm; then
        error "Desinstalacion detenida: RSM no confirmo la solicitud de borrado"
        exit 1
    fi

    remove_cron
    remove_local_files

    echo ""
    echo "============================================================"
    echo "Agente desinstalado correctamente"
    echo "============================================================"
    echo ""
}

main "$@"
