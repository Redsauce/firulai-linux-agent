#!/bin/bash
# -*- coding: utf-8 -*-
#
# Redsauce Inventory Agent - Uninstaller
# Marca el sistema como inactivo en RSM y elimina la instalacion local.
#

set -uo pipefail

RUN_AS_ROOT=0
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    RUN_AS_ROOT=1
fi

if [ "$RUN_AS_ROOT" = "1" ]; then
    INSTALL_DIR="/opt/rs-agent"
    DATA_DIR="/var/lib/rs-agent"
    LOG_FILE="/var/log/rs-agent.log"
    PRIVATE_TMP_DIR="/run/rs-agent/tmp"
else
    INSTALL_DIR="${RS_AGENT_INSTALL_DIR:-$HOME/.local/share/rs-agent}"
    DATA_DIR="${RS_AGENT_DATA_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/rs-agent}"
    LOG_FILE="${RS_AGENT_LOG_FILE:-$DATA_DIR/rs-agent.log}"
    PRIVATE_TMP_DIR="${RS_AGENT_TMP_DIR:-${XDG_RUNTIME_DIR:-$DATA_DIR}/rs-agent/tmp}"
fi

CONFIG_FILE="$DATA_DIR/config.env"
RSM_ITEMS_GET_URL="https://rsm1.redsauce.net/AppController/commands_RSM/api/v2/items/get.php"
RSM_ITEMS_UPDATE_URL="https://rsm1.redsauce.net/AppController/commands_RSM/api/v2/items/update.php"
RSM_SYSTEM_UUID_PROPERTY_ID="1780"
RSM_SYSTEM_HOSTNAME_STATUS_PROPERTY_ID="1751"
RSM_SYSTEM_HOSTNAME_STATUS_DISCONNECTED_VALUE="Disconnected"
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
        warn "Modo no-root experimental: solo se eliminara la instalacion del usuario actual."
    fi
}

ensure_private_directory() {
    local directory="$1"

    if [ -L "$directory" ]; then
        error "Ruta insegura: $directory es un enlace simbolico"
        return 1
    fi

    mkdir -p "$directory"

    if [ -L "$directory" ] || [ ! -d "$directory" ]; then
        error "No se pudo crear un directorio privado seguro: $directory"
        return 1
    fi

    chown root:root "$directory" 2>/dev/null || true
    chmod 700 "$directory"

    if [ ! -O "$directory" ]; then
        error "Directorio inseguro: $directory no pertenece al usuario actual"
        return 1
    fi
}

init_private_tmp_dir() {
    if ! command -v mktemp >/dev/null 2>&1; then
        error "mktemp no esta disponible"
        return 1
    fi

    ensure_private_directory "$DATA_DIR"
    ensure_private_directory "$(dirname "$PRIVATE_TMP_DIR")"
    ensure_private_directory "$PRIVATE_TMP_DIR"
}

make_private_temp_file() {
    local prefix="$1"
    mktemp "$PRIVATE_TMP_DIR/${prefix}.XXXXXX"
}

validate_uuid() {
    local uuid="$1"
    if [[ ! "$uuid" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
        error "'$uuid' no es un UUID valido"
        exit 1
    fi
}

json_extract_first_scalar_key() {
    local json="$1"
    local key="$2"

    printf '%s' "$json" \
        | tr -d '\n' \
        | sed "s/\"$key\"[[:space:]]*:/\\n&/g" \
        | sed -n "s/^\"$key\"[[:space:]]*:[[:space:]]*\"\\{0,1\\}\\([^\",}]*\\).*$/\\1/p" \
        | head -1
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
        error "No se encontrÓ token o UUID para notificar a RSM"
        echo "Uso manual: sudo bash uninstall.sh --token <TOKEN> --uuid <UUID>"
        exit 1
    fi

    validate_uuid "$UUID_VAL"
}

confirm_uninstall() {
    echo ""
    echo "============================================================"
    echo "Redsauce Inventory Agent - DesinstalaciÓn"
    echo "============================================================"
    echo ""
    echo "Esta acción solo borrará la instalación local del agente."
    echo "No se borrarán los datos de RSM."
    echo ""
    echo "El sistema quedará como inactivo en Firulai. Desde Firulai podrás"
    echo "eliminar definitivamente sus datos o volver a instalar el agente"
    echo "más adelante enlazándolo al System y al inventario ya guardados."
    echo ""
    echo "UUID del sistema: $UUID_VAL"
    echo ""
    read -rn 1 -p "Estas de acuerdo con desinstalar el agente local? (s/N): " reply
    echo
    case "$reply" in
        s|S|y|Y) ;;
        *)
            warn "Desinstalación cancelada por el usuario"
            exit 0
            ;;
    esac
}

find_system_id_by_uuid() {
    local payload response_file http_code exit_code response_body system_id
    response_file=$(make_private_temp_file "rsm_uninstall_uuid_lookup") || return 1
    payload="{\"propertyIDs\":[\"$RSM_SYSTEM_UUID_PROPERTY_ID\"],\"translateIDs\":true,\"filterRules\":[{\"propertyID\":\"$RSM_SYSTEM_UUID_PROPERTY_ID\",\"value\":\"$UUID_VAL\",\"operation\":\"=\"}]}"

    http_code=$(curl \
        --silent \
        --show-error \
        --output "$response_file" \
        --write-out '%{http_code}' \
        --location "$RSM_ITEMS_GET_URL" \
        --request GET \
        --header "Authorization: $AGENT_TOKEN" \
        --header "Content-Type: application/json" \
        --data "$payload" \
        --max-time 20)
    exit_code=$?
    response_body=$(cat "$response_file" 2>/dev/null || true)
    rm -f "$response_file"

    if [ "$exit_code" -ne 0 ]; then
        error "No se pudo consultar el sistema en RSM (curl exit: $exit_code)"
        return 1
    fi

    if [ "$http_code" != "200" ] && [ "$http_code" != "201" ]; then
        error "RSM no permitió consultar el sistema (HTTP $http_code)"
        echo "Respuesta: $response_body"
        return 1
    fi

    if ! printf '%s' "$response_body" | grep -Fq "$UUID_VAL"; then
        printf ''
        return 0
    fi

    system_id=$(json_extract_first_scalar_key "$response_body" "ID")
    [ -z "$system_id" ] && system_id=$(json_extract_first_scalar_key "$response_body" "id")
    printf '%s' "$system_id"
}

mark_system_disconnected_in_rsm() {
    local system_id payload response_file http_code exit_code response_body

    info "Marcando sistema como inactivo en Firulai..."
    system_id=$(find_system_id_by_uuid) || return 1

    if [ -z "$system_id" ]; then
        info "No hay ningun System enlazado a este UUID en Firulai. Se continuará con la desinstalación local."
        return 0
    fi

    response_file=$(make_private_temp_file "rsm_uninstall_status_update") || return 1
    payload="[{\"ID\":\"$system_id\",\"$RSM_SYSTEM_HOSTNAME_STATUS_PROPERTY_ID\":\"$RSM_SYSTEM_HOSTNAME_STATUS_DISCONNECTED_VALUE\"}]"

    http_code=$(curl \
        --silent \
        --show-error \
        --output "$response_file" \
        --write-out '%{http_code}' \
        --location \
        --request PATCH \
        "$RSM_ITEMS_UPDATE_URL" \
        --header "Authorization: $AGENT_TOKEN" \
        --header "Content-Type: application/json" \
        --data "$payload" \
        --max-time 20)
    exit_code=$?
    response_body=$(cat "$response_file" 2>/dev/null || true)
    rm -f "$response_file"

    if [ "$exit_code" -ne 0 ]; then
        error "No se pudo marcar el sistema como inactivo en RSM (curl exit: $exit_code)"
        return 1
    fi

    if [ "$http_code" != "200" ] && [ "$http_code" != "201" ]; then
        error "RSM no permitió marcar el sistema como inactivo (HTTP $http_code)"
        echo "Respuesta: $response_body"
        return 1
    fi

    log "Sistema marcado como inactivo en Firulai"
    return 0
}

remove_automatic_execution() {
    info "Eliminando ejecución automática..."

    if [ "$RUN_AS_ROOT" = "1" ]; then
        if command -v systemctl &>/dev/null; then
            systemctl disable --now rs-agent.timer >/dev/null 2>&1 || true
            systemctl stop rs-agent.service >/dev/null 2>&1 || true
        fi
        rm -f /etc/systemd/system/rs-agent.timer /etc/systemd/system/rs-agent.service
        if command -v systemctl &>/dev/null; then
            systemctl daemon-reload >/dev/null 2>&1 || true
        fi
    fi

    if command -v crontab &>/dev/null; then
        if ({ crontab -l 2>/dev/null || true; } | grep -v "$INSTALL_DIR/rs_agent" || true) | crontab -; then
            log "Entradas de cron eliminadas"
        else
            warn "No se pudo actualizar el crontab o no había entradas configuradas"
        fi
    fi

    log "Programación automática eliminada"
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
    if ! init_private_tmp_dir; then
        exit 1
    fi
    confirm_uninstall

    if ! mark_system_disconnected_in_rsm; then
        error "Desinstalación detenida: no se pudo actualizar el estado en RSM"
        exit 1
    fi

    remove_automatic_execution
    remove_local_files

    echo ""
    echo "============================================================"
    echo "Agente desinstalado correctamente"
    echo "============================================================"
    echo ""
}

main "$@"
