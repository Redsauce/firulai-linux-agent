#!/bin/bash
# -*- coding: utf-8 -*-
#
# Firulai Inventory Agent - Uninstaller
# Marks the system as inactive in RSM and removes the local installation.
#

set -uo pipefail

RUN_AS_ROOT=0
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    RUN_AS_ROOT=1
fi

if [ "$RUN_AS_ROOT" = "1" ]; then
    INSTALL_DIR="${RS_AGENT_INSTALL_DIR:-/opt/rs-agent}"
    DATA_DIR="${RS_AGENT_DATA_DIR:-/var/lib/rs-agent}"
    LOG_FILE="${RS_AGENT_LOG_FILE:-/var/log/rs-agent.log}"
    PRIVATE_TMP_DIR="${RS_AGENT_TMP_DIR:-/run/rs-agent/tmp}"
    SYSTEMD_USER_SERVICE_FILE=""
    SYSTEMD_USER_TIMER_FILE=""
else
    INSTALL_DIR="${RS_AGENT_INSTALL_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/rs-agent}"
    DATA_DIR="${RS_AGENT_DATA_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/rs-agent}"
    LOG_FILE="${RS_AGENT_LOG_FILE:-$DATA_DIR/rs-agent.log}"
    PRIVATE_TMP_DIR="${RS_AGENT_TMP_DIR:-${XDG_RUNTIME_DIR:-$DATA_DIR}/rs-agent/tmp}"
    SYSTEMD_USER_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
    SYSTEMD_USER_SERVICE_FILE="$SYSTEMD_USER_DIR/rs-agent.service"
    SYSTEMD_USER_TIMER_FILE="$SYSTEMD_USER_DIR/rs-agent.timer"
fi

CONFIG_FILE="$DATA_DIR/config.env"
RSM_ITEMS_GET_URL="https://rsm1.redsauce.net/AppController/commands_RSM/api/v2/items/get.php"
RSM_ITEMS_UPDATE_URL="https://rsm1.redsauce.net/AppController/commands_RSM/api/v2/items/update.php"
RSM_SYSTEM_UUID_PROPERTY_ID="1780"
RSM_SYSTEM_HOSTNAME_STATUS_PROPERTY_ID="1751"
RSM_SYSTEM_HOSTNAME_STATUS_DISCONNECTED_VALUE="Disconnected"
AGENT_TOKEN=""
UUID_VAL=""
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
        es_ES:no_root_uninstall) printf '%s' "Modo sin root: solo se eliminara la instalacion del usuario actual." ;;
        es_ES:unsafe_symlink) printf '%s' "Ruta no segura: es un enlace simbolico" ;;
        es_ES:private_dir_failed) printf '%s' "No se pudo crear un directorio privado seguro" ;;
        es_ES:unsafe_owner) printf '%s' "Directorio no seguro: no pertenece al usuario actual" ;;
        es_ES:mktemp_missing) printf '%s' "mktemp no esta disponible" ;;
        es_ES:invalid_uuid) printf '%s' "no es un UUID valido" ;;
        es_ES:unknown_argument) printf '%s' "Argumento desconocido" ;;
        es_ES:missing_token_uuid) printf '%s' "No se pudo encontrar token o UUID para notificar a RSM" ;;
        es_ES:manual_usage) printf '%s' "Uso manual: bash uninstall.sh --token <TOKEN> --uuid <UUID>" ;;
        es_ES:title) printf '%s' "Firulai Inventory Agent - Desinstalacion" ;;
        es_ES:local_only) printf '%s' "Esta accion solo eliminara la instalacion local del agente." ;;
        es_ES:rsm_not_deleted) printf '%s' "Los datos de RSM no se eliminaran." ;;
        es_ES:inactive_1) printf '%s' "El sistema se marcara como inactivo en Firulai. Desde Firulai podras" ;;
        es_ES:inactive_2) printf '%s' "eliminar sus datos permanentemente o reinstalar el agente mas tarde enlazandolo" ;;
        es_ES:inactive_3) printf '%s' "con el System y el inventario ya guardados." ;;
        es_ES:system_uuid) printf '%s' "UUID del sistema" ;;
        es_ES:confirm) printf '%s' "Aceptas desinstalar el agente local? (s/N): " ;;
        es_ES:cancelled) printf '%s' "Desinstalacion cancelada por el usuario" ;;
        es_ES:query_failed) printf '%s' "No se pudo consultar el sistema en RSM" ;;
        es_ES:query_denied) printf '%s' "RSM no permitio consultar el sistema" ;;
        es_ES:response) printf '%s' "Respuesta" ;;
        es_ES:marking_inactive) printf '%s' "Marcando sistema como inactivo en Firulai..." ;;
        es_ES:no_system) printf '%s' "No hay ningun System enlazado a este UUID en Firulai. La desinstalacion local continuara." ;;
        es_ES:mark_failed) printf '%s' "No se pudo marcar el sistema como inactivo en RSM" ;;
        es_ES:mark_denied) printf '%s' "RSM no permitio marcar el sistema como inactivo" ;;
        es_ES:marked) printf '%s' "Sistema marcado como inactivo en Firulai" ;;
        es_ES:removing_schedule) printf '%s' "Eliminando ejecucion automatica..." ;;
        es_ES:cron_removed) printf '%s' "Entradas de cron eliminadas" ;;
        es_ES:cron_update_failed) printf '%s' "No se pudo actualizar crontab o no habia entradas configuradas" ;;
        es_ES:schedule_removed) printf '%s' "Programacion automatica eliminada" ;;
        es_ES:removing_files) printf '%s' "Eliminando archivos locales..." ;;
        es_ES:files_removed) printf '%s' "Archivos locales eliminados" ;;
        es_ES:stopped_rsm) printf '%s' "Desinstalacion detenida: no se pudo actualizar el estado en RSM" ;;
        es_ES:success) printf '%s' "Agente desinstalado correctamente" ;;

        ca_ES:no_root_uninstall) printf '%s' "Mode sense root: nomes s'eliminara la instal.lacio de l'usuari actual." ;;
        ca_ES:unsafe_symlink) printf '%s' "Ruta no segura: es un enllac simbolic" ;;
        ca_ES:private_dir_failed) printf '%s' "No s'ha pogut crear un directori privat segur" ;;
        ca_ES:unsafe_owner) printf '%s' "Directori no segur: no pertany a l'usuari actual" ;;
        ca_ES:mktemp_missing) printf '%s' "mktemp no esta disponible" ;;
        ca_ES:invalid_uuid) printf '%s' "no es un UUID valid" ;;
        ca_ES:unknown_argument) printf '%s' "Argument desconegut" ;;
        ca_ES:missing_token_uuid) printf '%s' "No s'ha pogut trobar token o UUID per notificar RSM" ;;
        ca_ES:manual_usage) printf '%s' "Us manual: bash uninstall.sh --token <TOKEN> --uuid <UUID>" ;;
        ca_ES:title) printf '%s' "Firulai Inventory Agent - Desinstal.lacio" ;;
        ca_ES:local_only) printf '%s' "Aquesta accio nomes eliminara la instal.lacio local de l'agent." ;;
        ca_ES:rsm_not_deleted) printf '%s' "Les dades de RSM no s'eliminaran." ;;
        ca_ES:inactive_1) printf '%s' "El sistema es marcara com a inactiu a Firulai. Des de Firulai podras" ;;
        ca_ES:inactive_2) printf '%s' "eliminar-ne les dades permanentment o reinstal.lar l'agent mes tard enllacant-lo" ;;
        ca_ES:inactive_3) printf '%s' "amb el System i l'inventari ja desats." ;;
        ca_ES:system_uuid) printf '%s' "UUID del sistema" ;;
        ca_ES:confirm) printf '%s' "Acceptes desinstal.lar l'agent local? (s/N): " ;;
        ca_ES:cancelled) printf '%s' "Desinstal.lacio cancel.lada per l'usuari" ;;
        ca_ES:query_failed) printf '%s' "No s'ha pogut consultar el sistema a RSM" ;;
        ca_ES:query_denied) printf '%s' "RSM no ha permes consultar el sistema" ;;
        ca_ES:response) printf '%s' "Resposta" ;;
        ca_ES:marking_inactive) printf '%s' "Marcant sistema com a inactiu a Firulai..." ;;
        ca_ES:no_system) printf '%s' "No hi ha cap System enllacat a aquest UUID a Firulai. La desinstal.lacio local continuara." ;;
        ca_ES:mark_failed) printf '%s' "No s'ha pogut marcar el sistema com a inactiu a RSM" ;;
        ca_ES:mark_denied) printf '%s' "RSM no ha permes marcar el sistema com a inactiu" ;;
        ca_ES:marked) printf '%s' "Sistema marcat com a inactiu a Firulai" ;;
        ca_ES:removing_schedule) printf '%s' "Eliminant execucio automatica..." ;;
        ca_ES:cron_removed) printf '%s' "Entrades de cron eliminades" ;;
        ca_ES:cron_update_failed) printf '%s' "No s'ha pogut actualitzar crontab o no hi havia entrades configurades" ;;
        ca_ES:schedule_removed) printf '%s' "Programacio automatica eliminada" ;;
        ca_ES:removing_files) printf '%s' "Eliminant fitxers locals..." ;;
        ca_ES:files_removed) printf '%s' "Fitxers locals eliminats" ;;
        ca_ES:stopped_rsm) printf '%s' "Desinstal.lacio aturada: no s'ha pogut actualitzar l'estat a RSM" ;;
        ca_ES:success) printf '%s' "Agent desinstal.lat correctament" ;;

        *:no_root_uninstall) printf '%s' "No-root mode: only the current user's installation will be removed." ;;
        *:unsafe_symlink) printf '%s' "Unsafe path: is a symbolic link" ;;
        *:private_dir_failed) printf '%s' "Could not create a secure private directory" ;;
        *:unsafe_owner) printf '%s' "Unsafe directory: is not owned by the current user" ;;
        *:mktemp_missing) printf '%s' "mktemp is not available" ;;
        *:invalid_uuid) printf '%s' "is not a valid UUID" ;;
        *:unknown_argument) printf '%s' "Unknown argument" ;;
        *:missing_token_uuid) printf '%s' "Could not find token or UUID to notify RSM" ;;
        *:manual_usage) printf '%s' "Manual usage: bash uninstall.sh --token <TOKEN> --uuid <UUID>" ;;
        *:title) printf '%s' "Firulai Inventory Agent - Uninstall" ;;
        *:local_only) printf '%s' "This action will only remove the local agent installation." ;;
        *:rsm_not_deleted) printf '%s' "RSM data will not be deleted." ;;
        *:inactive_1) printf '%s' "The system will be marked as inactive in Firulai. From Firulai you can" ;;
        *:inactive_2) printf '%s' "delete its data permanently or reinstall the agent later by linking it" ;;
        *:inactive_3) printf '%s' "to the already saved System and inventory." ;;
        *:system_uuid) printf '%s' "System UUID" ;;
        *:confirm) printf '%s' "Do you agree to uninstall the local agent? (y/N): " ;;
        *:cancelled) printf '%s' "Uninstall cancelled by user" ;;
        *:query_failed) printf '%s' "Could not query the system in RSM" ;;
        *:query_denied) printf '%s' "RSM did not allow querying the system" ;;
        *:response) printf '%s' "Response" ;;
        *:marking_inactive) printf '%s' "Marking system as inactive in Firulai..." ;;
        *:no_system) printf '%s' "No System is linked to this UUID in Firulai. Local uninstall will continue." ;;
        *:mark_failed) printf '%s' "Could not mark the system as inactive in RSM" ;;
        *:mark_denied) printf '%s' "RSM did not allow marking the system as inactive" ;;
        *:marked) printf '%s' "System marked as inactive in Firulai" ;;
        *:removing_schedule) printf '%s' "Removing automatic execution..." ;;
        *:cron_removed) printf '%s' "Cron entries removed" ;;
        *:cron_update_failed) printf '%s' "Could not update crontab or no entries were configured" ;;
        *:schedule_removed) printf '%s' "Automatic schedule removed" ;;
        *:removing_files) printf '%s' "Removing local files..." ;;
        *:files_removed) printf '%s' "Local files removed" ;;
        *:stopped_rsm) printf '%s' "Uninstall stopped: could not update the status in RSM" ;;
        *:success) printf '%s' "Agent uninstalled successfully" ;;
        *) printf '%s' "$key" ;;
    esac
}

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
    if [ "$RUN_AS_ROOT" != "1" ]; then
        warn "$(t no_root_uninstall)"
    fi
}

ensure_private_directory() {
    local directory="$1"

    if [ -L "$directory" ]; then
        error "$(t unsafe_symlink): $directory"
        return 1
    fi

    mkdir -p "$directory"

    if [ -L "$directory" ] || [ ! -d "$directory" ]; then
        error "$(t private_dir_failed): $directory"
        return 1
    fi

    chown root:root "$directory" 2>/dev/null || true
    chmod 700 "$directory"

    if [ ! -O "$directory" ]; then
        error "$(t unsafe_owner): $directory"
        return 1
    fi
}

init_private_tmp_dir() {
    if ! command -v mktemp >/dev/null 2>&1; then
        error "$(t mktemp_missing)"
        return 1
    fi

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
        error "'$uuid' $(t invalid_uuid)"
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
        AGENT_LOCALE="${AGENT_LOCALE:-}"
    fi
    AGENT_LOCALE=$(normalize_locale "$AGENT_LOCALE")
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --token) AGENT_TOKEN="${2:-}"; shift 2 ;;
            --uuid) UUID_VAL="${2:-}"; shift 2 ;;
            *) error "$(t unknown_argument): $1"; exit 1 ;;
        esac
    done

    if [ -z "$AGENT_TOKEN" ] || [ -z "$UUID_VAL" ]; then
        error "$(t missing_token_uuid)"
        echo "$(t manual_usage)"
        exit 1
    fi

    validate_uuid "$UUID_VAL"
}

confirm_uninstall() {
    echo ""
    echo "============================================================"
    echo "$(t title)"
    echo "============================================================"
    echo ""
    echo "$(t local_only)"
    echo "$(t rsm_not_deleted)"
    echo ""
    echo "$(t inactive_1)"
    echo "$(t inactive_2)"
    echo "$(t inactive_3)"
    echo ""
    echo "$(t system_uuid): $UUID_VAL"
    echo ""
    read -rn 1 -p "$(t confirm)" reply
    echo
    case "$reply" in
        s|S|y|Y) ;;
        *)
            warn "$(t cancelled)"
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
        error "$(t query_failed) (curl exit: $exit_code)"
        return 1
    fi

    if [ "$http_code" != "200" ] && [ "$http_code" != "201" ]; then
        error "$(t query_denied) (HTTP $http_code)"
        echo "$(t response): $response_body"
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

    info "$(t marking_inactive)"
    system_id=$(find_system_id_by_uuid) || return 1

    if [ -z "$system_id" ]; then
        info "$(t no_system)"
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
        error "$(t mark_failed) (curl exit: $exit_code)"
        return 1
    fi

    if [ "$http_code" != "200" ] && [ "$http_code" != "201" ]; then
        error "$(t mark_denied) (HTTP $http_code)"
        echo "$(t response): $response_body"
        return 1
    fi

    log "$(t marked)"
    return 0
}

remove_automatic_execution() {
    info "$(t removing_schedule)"

    if [ "$RUN_AS_ROOT" = "1" ] && command -v systemctl &>/dev/null; then
        systemctl disable --now rs-agent.timer >/dev/null 2>&1 || true
        systemctl stop rs-agent.service >/dev/null 2>&1 || true
    fi
    if [ "$RUN_AS_ROOT" = "1" ]; then
        rm -f /etc/systemd/system/rs-agent.timer /etc/systemd/system/rs-agent.service
    fi
    if [ "$RUN_AS_ROOT" = "1" ] && command -v systemctl &>/dev/null; then
        systemctl daemon-reload >/dev/null 2>&1 || true
    fi
    if [ "$RUN_AS_ROOT" != "1" ] && command -v systemctl &>/dev/null; then
        systemctl --user disable --now rs-agent.timer >/dev/null 2>&1 || true
        rm -f "$SYSTEMD_USER_SERVICE_FILE" "$SYSTEMD_USER_TIMER_FILE"
        systemctl --user daemon-reload >/dev/null 2>&1 || true
    fi

    if command -v crontab &>/dev/null; then
        if ({ crontab -l 2>/dev/null || true; } | grep -Fv "$INSTALL_DIR/rs_agent" || true) | crontab -; then
            log "$(t cron_removed)"
        else
            warn "$(t cron_update_failed)"
        fi
    fi

    log "$(t schedule_removed)"
}

remove_local_files() {
    info "$(t removing_files)"

    rm -rf "$DATA_DIR"
    rm -rf "$INSTALL_DIR"
    rm -f "$LOG_FILE"

    log "$(t files_removed)"
}

main() {
    load_config
    check_root
    parse_args "$@"
    if ! init_private_tmp_dir; then
        exit 1
    fi
    confirm_uninstall

    if ! mark_system_disconnected_in_rsm; then
        error "$(t stopped_rsm)"
        exit 1
    fi

    remove_automatic_execution
    remove_local_files

    echo ""
    echo "============================================================"
    echo "$(t success)"
    echo "============================================================"
    echo ""
}

main "$@"
