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
        warn "No-root mode: only the current user's installation will be removed."
    fi
}

ensure_private_directory() {
    local directory="$1"

    if [ -L "$directory" ]; then
        error "Unsafe path: $directory is a symbolic link"
        return 1
    fi

    mkdir -p "$directory"

    if [ -L "$directory" ] || [ ! -d "$directory" ]; then
        error "Could not create a secure private directory: $directory"
        return 1
    fi

    chown root:root "$directory" 2>/dev/null || true
    chmod 700 "$directory"

    if [ ! -O "$directory" ]; then
        error "Unsafe directory: $directory is not owned by the current user"
        return 1
    fi
}

init_private_tmp_dir() {
    if ! command -v mktemp >/dev/null 2>&1; then
        error "mktemp is not available"
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
        error "'$uuid' is not a valid UUID"
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
            *) error "Unknown argument: $1"; exit 1 ;;
        esac
    done

    if [ -z "$AGENT_TOKEN" ] || [ -z "$UUID_VAL" ]; then
        error "Could not find token or UUID to notify RSM"
        echo "Manual usage: bash uninstall.sh --token <TOKEN> --uuid <UUID>"
        exit 1
    fi

    validate_uuid "$UUID_VAL"
}

confirm_uninstall() {
    echo ""
    echo "============================================================"
    echo "Firulai Inventory Agent - Uninstall"
    echo "============================================================"
    echo ""
    echo "This action will only remove the local agent installation."
    echo "RSM data will not be deleted."
    echo ""
    echo "The system will be marked as inactive in Firulai. From Firulai you can"
    echo "delete its data permanently or reinstall the agent later by linking it"
    echo "to the already saved System and inventory."
    echo ""
    echo "System UUID: $UUID_VAL"
    echo ""
    read -rn 1 -p "Do you agree to uninstall the local agent? (y/N): " reply
    echo
    case "$reply" in
        s|S|y|Y) ;;
        *)
            warn "Uninstall cancelled by user"
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
        error "Could not query the system in RSM (curl exit: $exit_code)"
        return 1
    fi

    if [ "$http_code" != "200" ] && [ "$http_code" != "201" ]; then
        error "RSM did not allow querying the system (HTTP $http_code)"
        echo "Response: $response_body"
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

    info "Marking system as inactive in Firulai..."
    system_id=$(find_system_id_by_uuid) || return 1

    if [ -z "$system_id" ]; then
        info "No System is linked to this UUID in Firulai. Local uninstall will continue."
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
        error "Could not mark the system as inactive in RSM (curl exit: $exit_code)"
        return 1
    fi

    if [ "$http_code" != "200" ] && [ "$http_code" != "201" ]; then
        error "RSM did not allow marking the system as inactive (HTTP $http_code)"
        echo "Response: $response_body"
        return 1
    fi

    log "System marked as inactive in Firulai"
    return 0
}

remove_automatic_execution() {
    info "Removing automatic execution..."

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
            log "Cron entries removed"
        else
            warn "Could not update crontab or no entries were configured"
        fi
    fi

    log "Automatic schedule removed"
}

remove_local_files() {
    info "Removing local files..."

    rm -rf "$DATA_DIR"
    rm -rf "$INSTALL_DIR"
    rm -f "$LOG_FILE"

    log "Local files removed"
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
        error "Uninstall stopped: could not update the status in RSM"
        exit 1
    fi

    remove_automatic_execution
    remove_local_files

    echo ""
    echo "============================================================"
    echo "Agent uninstalled successfully"
    echo "============================================================"
    echo ""
}

main "$@"
