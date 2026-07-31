#!/bin/bash
# -*- coding: utf-8 -*-
#
# Firulai Inventory Agent
# Version: 0.3.4 - Persistent state and missed execution recovery
# Requires: bash 4+, curl, lscpu, lsblk, uname
#

set -uo pipefail

# ============ CONFIGURATION ============

AGENT_VERSION="0.3.4"
GITHUB_API_URL="https://api.github.com/repos/Redsauce/firulai-linux-agent/releases/latest"
GITHUB_AGENT_URL="${RS_AGENT_GITHUB_AGENT_URL:-https://raw.githubusercontent.com/Redsauce/firulai-linux-agent/experiment/non-root-install-from-main/rs_agent.sh}"

RUN_AS_ROOT=0
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    RUN_AS_ROOT=1
fi

if [ "$RUN_AS_ROOT" = "1" ]; then
    INSTALL_DIR="${RS_AGENT_INSTALL_DIR:-/opt/rs-agent}"
    OUTPUT_DIR="${RS_AGENT_DATA_DIR:-/var/lib/rs-agent}"
    LOCK_FILE="${RS_AGENT_LOCK_FILE:-/run/lock/rs-agent.lock}"
    PRIVATE_TMP_DIR="${RS_AGENT_TMP_DIR:-/run/rs-agent/tmp}"
else
    INSTALL_DIR="${RS_AGENT_INSTALL_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/rs-agent}"
    OUTPUT_DIR="${RS_AGENT_DATA_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/rs-agent}"
    LOCK_FILE="${RS_AGENT_LOCK_FILE:-$OUTPUT_DIR/rs-agent.lock}"
    PRIVATE_TMP_DIR="${RS_AGENT_TMP_DIR:-${XDG_RUNTIME_DIR:-$OUTPUT_DIR}/rs-agent/tmp}"
fi

OUTPUT_FILE="inventory.json"
STATE_FILE="$OUTPUT_DIR/state.env"
RSM_API_URL="https://rsm1.redsauce.net/AppController/commands_RSM/api/api.php"
RSM_ITEMS_GET_URL="https://rsm1.redsauce.net/AppController/commands_RSM/api/v2/items/get.php"
RSM_SYSTEM_HOSTNAME_PROPERTY_ID="1749"
RSM_SYSTEM_FQDN_PROPERTY_ID="1750"
RSM_SYSTEM_UUID_PROPERTY_ID="1780"
AGENT_TOKEN=""
UUID_VAL=""
SYSTEM_ALIAS=""
EXECUTION_TRIGGER="${RS_AGENT_TRIGGER:-manual}"

# ============ UTILITIES ============

acquire_execution_lock() {
    if ! command -v flock >/dev/null 2>&1; then
        echo "ERROR: flock is not available; install the util-linux package."
        exit 1
    fi
    mkdir -p "$(dirname "$LOCK_FILE")"
    exec 9>"$LOCK_FILE"
    if ! flock -n 9; then
        echo "INFO: Another agent run is already in progress; this request is skipped. Trigger=$EXECUTION_TRIGGER"
        # EX_TEMPFAIL lets systemd reschedule the automatic request.
        exit 75
    fi
}

ensure_private_directory() {
    local directory="$1"

    if [ -L "$directory" ]; then
        echo "ERROR: Unsafe path: $directory is a symbolic link"
        return 1
    fi

    mkdir -p "$directory"

    if [ -L "$directory" ] || [ ! -d "$directory" ]; then
        echo "ERROR: Could not create a secure private directory: $directory"
        return 1
    fi

    chown root:root "$directory" 2>/dev/null || true
    chmod 700 "$directory"

    if [ ! -O "$directory" ]; then
        echo "ERROR: Unsafe directory: $directory is not owned by the current user"
        return 1
    fi
}

init_private_tmp_dir() {
    if ! command -v mktemp >/dev/null 2>&1; then
        echo "ERROR: mktemp is not available."
        return 1
    fi

    ensure_private_directory "$(dirname "$PRIVATE_TMP_DIR")"
    ensure_private_directory "$PRIVATE_TMP_DIR"
}

make_private_temp_file() {
    local prefix="$1"
    mktemp "$PRIVATE_TMP_DIR/${prefix}.XXXXXX"
}

record_success_state() {
    local completed_epoch completed_utc temporary_file
    completed_epoch=$(date +%s)
    completed_utc=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    temporary_file=$(mktemp "${STATE_FILE}.tmp.XXXXXX") || return 1

    if ! printf 'LAST_SUCCESS_EPOCH=%s\nLAST_SUCCESS_UTC=%s\n' "$completed_epoch" "$completed_utc" > "$temporary_file"; then
        echo "ERROR: Could not write temporary state file $temporary_file"
        rm -f "$temporary_file"
        return 1
    fi
    chmod 600 "$temporary_file" 2>/dev/null || true
    if ! mv -f "$temporary_file" "$STATE_FILE"; then
        echo "ERROR: Could not update persistent state $STATE_FILE"
        rm -f "$temporary_file"
        return 1
    fi

    echo "State updated: last successful run=$completed_utc ($completed_epoch)"
}

# Escapes a string to embed it as a JSON value (without jq).
# Replacement order: backslash first to avoid double escaping.
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

json_extract_first_string_key() {
    local json="$1"
    local key="$2"

    printf '%s' "$json" \
        | tr -d '\n' \
        | sed 's/,"/\n"/g' \
        | sed -n "s/^.*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*$/\1/p" \
        | head -1
}

json_extract_rsm_property() {
    local json="$1"
    local property_id="$2"
    local value

    value=$(json_extract_first_string_key "$json" "$property_id")
    if [ -n "$value" ]; then
        printf '%s' "$value"
        return 0
    fi

    json_extract_first_string_key "$json" "${property_id}trs"
}

# ============ VALIDATION AND ARGUMENTS ============

check_root() {
    if [ "$RUN_AS_ROOT" != "1" ]; then
        echo "INFO: No-root mode; inventory may be less complete if the system restricts some commands."
    fi
}

validate_uuid() {
    local uuid="$1"
    if [[ ! "$uuid" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
        echo "ERROR: '$uuid' is not a valid UUID"
        exit 1
    fi
}

parse_args() {
    if [ $# -eq 0 ]; then
        echo "Usage: bash rs_agent.sh --token <TOKEN> --uuid <UUID> --alias <ALIAS>"
        exit 1
    fi

    while [ $# -gt 0 ]; do
        case "$1" in
            --token)
                [ $# -ge 2 ] || { echo "ERROR: --token requires a value"; exit 1; }
                AGENT_TOKEN="$2"
                shift 2
                ;;
            --uuid)
                [ $# -ge 2 ] || { echo "ERROR: --uuid requires a value"; exit 1; }
                UUID_VAL="$2"
                shift 2
                ;;
            --alias)
                [ $# -ge 2 ] || { echo "ERROR: --alias requires a value"; exit 1; }
                SYSTEM_ALIAS="$2"
                shift 2
                ;;
            *) echo "Unknown argument: $1"; exit 1 ;;
        esac
    done

    if [ -z "$AGENT_TOKEN" ] || [ -z "$UUID_VAL" ] || [ -z "$SYSTEM_ALIAS" ]; then
        echo "ERROR: --token, --uuid, and --alias are required"
        exit 1
    fi

    validate_uuid "$UUID_VAL"
}

local_system_hostname() {
    hostname -s 2>/dev/null || hostname 2>/dev/null || echo "unknown"
}

local_system_fqdn() {
    hostname -f 2>/dev/null || hostname 2>/dev/null || echo "unknown"
}

identity_matches_local_system() {
    local existing_hostname="$1"
    local existing_fqdn="$2"
    local current_hostname
    local current_fqdn

    current_hostname=$(local_system_hostname)
    current_fqdn=$(local_system_fqdn)

    [ -n "$existing_hostname" ] && [ "$existing_hostname" = "$current_hostname" ] && return 0
    [ -n "$existing_fqdn" ] && [ "$existing_fqdn" = "$current_fqdn" ] && return 0
    [ -n "$existing_hostname" ] && [ "$existing_hostname" = "$current_fqdn" ] && return 0
    [ -n "$existing_fqdn" ] && [ "$existing_fqdn" = "$current_hostname" ] && return 0

    return 1
}

validate_uuid_ownership() {
    local payload response_file http_code exit_code response_body
    response_file=$(make_private_temp_file "rsm_uuid_check_response") || return 1
    payload="{\"propertyIDs\":[\"$RSM_SYSTEM_HOSTNAME_PROPERTY_ID\",\"$RSM_SYSTEM_FQDN_PROPERTY_ID\",\"$RSM_SYSTEM_UUID_PROPERTY_ID\"],\"translateIDs\":true,\"filterRules\":[{\"propertyID\":\"$RSM_SYSTEM_UUID_PROPERTY_ID\",\"value\":\"$UUID_VAL\",\"operation\":\"=\"}]}"

    echo "Validating that the UUID does not belong to another system..."

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
        echo "ERROR: Could not validate the UUID before sending inventory (curl exit: $exit_code)."
        echo "For safety, installation will not continue without confirming that the UUID does not belong to another system."
        return 1
    fi

    if [ "$http_code" != "200" ] && [ "$http_code" != "201" ]; then
        echo "ERROR: RSM did not allow UUID validation before sending inventory (HTTP $http_code)."
        echo "For safety, installation will not continue without confirming that the UUID does not belong to another system."
        echo "Response: $response_body"
        return 1
    fi

    if ! printf '%s' "$response_body" | grep -Fq "$UUID_VAL"; then
        echo "ERROR: Invalid UUID: it does not exist in RSM."
        echo "Inventory cannot be sent with a UUID that was not generated from Add New System."
        echo ""
        echo "UUID: $UUID_VAL"
        return 1
    fi

    local existing_hostname existing_fqdn
    existing_hostname=$(json_extract_rsm_property "$response_body" "$RSM_SYSTEM_HOSTNAME_PROPERTY_ID")
    existing_fqdn=$(json_extract_rsm_property "$response_body" "$RSM_SYSTEM_FQDN_PROPERTY_ID")

    if [ -z "$existing_hostname" ] && [ -z "$existing_fqdn" ]; then
        echo "   -> UUID reserved in RSM and ready to install"
        return 0
    fi

    if identity_matches_local_system "$existing_hostname" "$existing_fqdn"; then
        echo "   -> UUID already associated with this system; its inventory will be updated"
        return 0
    fi

    echo ""
    echo "ERROR: This UUID already belongs to another system in RSM."
    echo "This agent cannot be installed on the local machine with that UUID."
    return 1
}

# ============ COLLECTORS ============

collect_system_info() {
    local timezone=""
    [ $# -gt 0 ] && timezone="$1"
    local hostname fqdn kernel arch
    local os_name="Unknown" os_version="Unknown" distro_id="unknown" distro_version="Unknown"

    hostname=$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo "unknown")
    fqdn=$(hostname -f 2>/dev/null || hostname 2>/dev/null || echo "unknown")
    kernel=$(uname -r 2>/dev/null || echo "unknown")
    arch=$(uname -m 2>/dev/null || echo "unknown")

    if [ -f /etc/os-release ]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        os_name="${NAME:-Unknown}"
        os_version="${VERSION:-Unknown}"
        distro_id="${ID:-unknown}"
        distro_version="${VERSION_ID:-Unknown}"
    elif [ -f /etc/redhat-release ]; then
        os_name=$(cat /etc/redhat-release 2>/dev/null || echo "Unknown")
        distro_id="rhel-based"
    elif [ -f /etc/debian_version ]; then
        os_name="Debian"
        os_version=$(cat /etc/debian_version 2>/dev/null || echo "Unknown")
        distro_id="debian"
        distro_version="$os_version"
    fi

    local collected_at
    collected_at=$(date '+%Y-%m-%d %H:%M:%S')

    printf '{"hostname":"%s","fqdn":"%s","uuid":"%s","alias":"%s","os":{"name":"%s","version":"%s","distro_id":"%s","distro_version":"%s","kernel":"%s","architecture":"%s"},"collected_at":"%s","timezone":"%s","agent_version":"%s"}' \
        "$(json_escape "$hostname")" \
        "$(json_escape "$fqdn")" \
        "$(json_escape "$UUID_VAL")" \
        "$(json_escape "$SYSTEM_ALIAS")" \
        "$(json_escape "$os_name")" \
        "$(json_escape "$os_version")" \
        "$(json_escape "$distro_id")" \
        "$(json_escape "$distro_version")" \
        "$(json_escape "$kernel")" \
        "$(json_escape "$arch")" \
        "$(json_escape "$collected_at")" \
        "$(json_escape "$timezone")" \
        "$(json_escape "$AGENT_VERSION")"
}

collect_timezone() {
    local timezone_name=""

    # Try timedatectl
    if command -v timedatectl &>/dev/null; then
        timezone_name=$(timedatectl show -p Timezone --value 2>/dev/null) || true
    fi

    # Fallback: read /etc/timezone
    if [ -z "$timezone_name" ] && [ -f "/etc/timezone" ]; then
        timezone_name=$(cat /etc/timezone 2>/dev/null) || true
    fi

    printf '%s' "$timezone_name"
}

collect_hardware() {
    local cpu_model firmware_json="" first=1

    # CPU: extract "Model name" with awk to handle spaces correctly
    cpu_model=$(lscpu 2>/dev/null | awk -F':[[:space:]]+' '/^Model name/{print $2; exit}')
    [ -z "$cpu_model" ] && cpu_model="Unknown"

    # Disks: awk extracts NAME and MODEL (may contain spaces), filtering disks only
    while IFS=$'\t' read -r dev model; do
        [ -z "$dev" ] && continue
        [ -z "$model" ] && model="Unknown"

        [ "$first" = "1" ] && first=0 || firmware_json+=","
        firmware_json+="{\"device\":\"/dev/$(json_escape "$dev")\",\"model\":\"$(json_escape "$model")\"}"
    done < <(lsblk -d -o NAME,TYPE,MODEL -n 2>/dev/null \
        | awk '$2=="disk" {
            dev=$1
            model=""
            for(i=3; i<=NF; i++) model=(model=="" ? $i : model" "$i)
            if(model=="") model="Unknown"
            print dev "\t" model
          }')

    printf '{"cpu_model":"%s","firmware":[%s]}' \
        "$(json_escape "$cpu_model")" \
        "$firmware_json"
}

select_source_package_version() {
    local component_version="$1"
    local source_version="$2"
    local upstream_version="$3"

    if [ -n "$source_version" ] && [ "$source_version" = "$component_version" ] && [ -n "$upstream_version" ] && [ "$upstream_version" != "unknown" ]; then
        printf '%s' "$upstream_version"
        return
    fi

    if [ -n "$source_version" ] && [ "$source_version" != "unknown" ]; then
        printf '%s' "$source_version"
        return
    fi

    if [ -n "$upstream_version" ] && [ "$upstream_version" != "unknown" ]; then
        printf '%s' "$upstream_version"
    fi
}

select_component_version() {
    local component_version="$1"
    local source_version="$2"
    local upstream_version="$3"

    if [ -n "$source_version" ] && [ "$source_version" = "$component_version" ] && [ -n "$upstream_version" ] && [ "$upstream_version" != "unknown" ]; then
        printf '%s' "$upstream_version"
        return
    fi

    printf '%s' "$component_version"
}

collect_packages_dpkg() {
    local components_json="" source_packages_json="" first_component=1 first_source=1
    local component_count=0 source_package_count=0
    declare -A seen_source_packages=()

    while IFS='|' read -r name version source_package source_version upstream_version status; do
        [ -z "$name" ] && continue
        # Only packages with "installed" status
        case "$status" in *"installed"*) ;; *) continue ;; esac

        if [ -n "$source_package" ]; then
            if [ -z "${seen_source_packages[$source_package]+x}" ]; then
                local selected_source_version source_json
                selected_source_version=$(select_source_package_version "$version" "$source_version" "$upstream_version")
                source_json="{\"name\":\"$(json_escape "$source_package")\",\"version\":\"$(json_escape "$selected_source_version")\"}"

                [ "$first_source" = "1" ] && first_source=0 || source_packages_json+=","
                source_packages_json+="$source_json"
                seen_source_packages[$source_package]=1
                source_package_count=$((source_package_count + 1))
            fi

            if [ "$name" = "$source_package" ]; then
                continue
            fi
        fi

        local component_json selected_component_version
        selected_component_version=$(select_component_version "$version" "$source_version" "$upstream_version")
        component_json="{\"name\":\"$(json_escape "$name")\",\"version\":\"$(json_escape "$selected_component_version")\",\"manager\":\"dpkg\""

        if [ -n "$source_package" ]; then
            component_json+=",\"source_package\":\"$(json_escape "$source_package")\""
            [ -n "$source_version" ] && component_json+=",\"source_version\":\"$(json_escape "$source_version")\""
            [ -n "$upstream_version" ] && component_json+=",\"upstream_version\":\"$(json_escape "$upstream_version")\""
        fi

        component_json+="}"

        [ "$first_component" = "1" ] && first_component=0 || components_json+=","
        components_json+="$component_json"
        component_count=$((component_count + 1))
    done < <(dpkg-query -W -f='${Package}|${Version}|${source:Package}|${source:Version}|${source:Upstream-Version}|${Status}\n' 2>/dev/null)

    SYSTEM_COMPONENTS_JSON="$components_json"
    SYSTEM_PACKAGES_JSON="$source_packages_json"
    SYSTEM_COMPONENTS_COUNT="$component_count"
    SYSTEM_PACKAGES_COUNT="$source_package_count"
}

collect_packages_rpm() {
    local components_json="" first=1 component_count=0

    while IFS=$'\t' read -r name version; do
        [ -z "$name" ] && continue

        [ "$first" = "1" ] && first=0 || components_json+=","
        components_json+="{\"name\":\"$(json_escape "$name")\",\"version\":\"$(json_escape "$version")\",\"manager\":\"rpm\"}"
        component_count=$((component_count + 1))
    done < <(rpm -qa --queryformat '%{NAME}\t%{VERSION}-%{RELEASE}\n' 2>/dev/null)

    SYSTEM_COMPONENTS_JSON="$components_json"
    SYSTEM_PACKAGES_JSON=""
    SYSTEM_COMPONENTS_COUNT="$component_count"
    SYSTEM_PACKAGES_COUNT=0
}

collect_packages() {
    SYSTEM_COMPONENTS_JSON=""
    SYSTEM_PACKAGES_JSON=""
    SYSTEM_COMPONENTS_COUNT=0
    SYSTEM_PACKAGES_COUNT=0

    if command -v dpkg-query &>/dev/null; then
        collect_packages_dpkg
    elif command -v rpm &>/dev/null; then
        collect_packages_rpm
    fi
}

collect_pip_packages() {
    local packages_json="" first=1
    local pip_cmd=""

    command -v pip3 &>/dev/null && pip_cmd="pip3"
    { command -v pip &>/dev/null && [ -z "$pip_cmd" ]; } && pip_cmd="pip"
    [ -z "$pip_cmd" ] && return

    # --format=columns produces: "Package    Version" with 2 header lines (name + separator)
    # tail -n +3 removes them; the third field (_rest) absorbs any extra annotation
    while read -r name version _rest; do
        [ -z "$name" ] && continue

        [ "$first" = "1" ] && first=0 || packages_json+=","
        packages_json+="{\"name\":\"$(json_escape "$name")\",\"version\":\"$(json_escape "$version")\",\"manager\":\"pip\"}"
    done < <("$pip_cmd" list --format=columns 2>/dev/null | tail -n +3)

    printf '%s' "$packages_json"
}

collect_npm_packages() {
    local packages_json="" first=1

    command -v npm &>/dev/null || return

    # "npm list -g --depth=0" produce lineas como:
    #   ├── package@1.2.3
    #   └── @scope/package@4.5.6
    # Se eliminan los prefijos de arbol con sed y se separa nombre/version
    # por el ultimo "@" (soporta scoped packages como @angular/cli@16.0.0)
    while IFS= read -r line; do
        # Remove tree prefix (characters up to and including "── ")
        local pkg_ver
        pkg_ver=$(printf '%s' "$line" | sed 's/^.*── //' | tr -d ' ')
        [[ "$pkg_ver" == *"@"* ]] || continue

        local version="${pkg_ver##*@}"   # todo despues del ultimo @
        local name="${pkg_ver%@*}"       # todo antes del ultimo @

        # Limpiar anotaciones tipo " deduped" o " extraneous"
        version="${version%% *}"

        [ -z "$name" ] || [ -z "$version" ] && continue

        [ "$first" = "1" ] && first=0 || packages_json+=","
        packages_json+="{\"name\":\"$(json_escape "$name")\",\"version\":\"$(json_escape "$version")\",\"manager\":\"npm\"}"
    done < <(npm list -g --depth=0 2>/dev/null | grep -E '[├└]')

    printf '%s' "$packages_json"
}

# ============ AUTO UPDATE ============

check_for_updates() {
    command -v curl &>/dev/null || return 0

    local response latest_version
    response=$(curl -sf --max-time 5 "$GITHUB_API_URL" 2>/dev/null) || return 0

    # Extract "tag_name" from JSON without jq: find the "tag_name":"vX.Y.Z" pattern
    latest_version=$(printf '%s' "$response" \
        | grep -o '"tag_name":"[^"]*"' \
        | sed 's/"tag_name":"v\?//;s/"//')

    [ -z "$latest_version" ] && return 0
    [ "$latest_version" = "$AGENT_VERSION" ] && return 0

    echo "New version available: $latest_version (current: $AGENT_VERSION)"
    download_update
}

download_update() {
    local script_path="$INSTALL_DIR/rs_agent.sh"
    local backup_path="${script_path}.backup"

    echo "Downloading update..."
    [ -f "$script_path" ] && cp "$script_path" "$backup_path"

    if curl -fsSL --max-time 10 "$GITHUB_AGENT_URL" -o "$script_path"; then
        chmod +x "$script_path"
        echo "Update completed. Restarting agent..."
        exec bash "$script_path" --token "$AGENT_TOKEN" --uuid "$UUID_VAL" --alias "$SYSTEM_ALIAS"
    else
        echo "Error downloading update"
        [ -f "$backup_path" ] && mv "$backup_path" "$script_path"
    fi
}

# ============ SEND TO RSM ============

send_to_rsm() {
    local inventory_json="$1"
    local inventory_json_path
    local response_file
    local response_headers_file
    local curl_trace_file=""
    local inventory_hash="unavailable"

    inventory_json_path=$(make_private_temp_file "rsm_inventory_payload") || return 1
    response_file=$(make_private_temp_file "rsm_response") || return 1
    response_headers_file=$(make_private_temp_file "rsm_response_headers") || return 1
    if [ "${RS_AGENT_DEBUG:-0}" = "1" ]; then
        curl_trace_file=$(make_private_temp_file "rsm_curl_verbose") || return 1
    fi

    echo ""
    echo "Sending inventory to RSM..."

    printf '%s' "$inventory_json" > "$inventory_json_path"
    chmod 600 "$inventory_json_path" 2>/dev/null || true
    printf 'JSON saved at: %s\n' "$inventory_json_path"
    printf 'Length: %d characters (%d KB approx)\n' "${#inventory_json}" "$(( ${#inventory_json} / 1024 ))"
    if command -v sha256sum >/dev/null 2>&1; then
        inventory_hash=$(printf '%s' "$inventory_json" | sha256sum | awk '{print $1}')
    elif command -v shasum >/dev/null 2>&1; then
        inventory_hash=$(printf '%s' "$inventory_json" | shasum -a 256 | awk '{print $1}')
    fi
    printf 'SHA256 RSdata: %s\n' "$inventory_hash"

    echo ""
    echo "RSM configuration:"
    echo "   - URL:   $RSM_API_URL"
    echo "   - Agent token: <configured; value hidden>"
    echo "   - Alias: $SYSTEM_ALIAS"
    echo "   - Debug: ${RS_AGENT_DEBUG:-0}"
    echo ""
    echo "Request to be sent:"
    echo "   - Method: POST multipart/form-data"
    echo "   - Endpoint: $RSM_API_URL"
    echo "   - Flow: api.php receives newServerData and RSM creates/queues jobs and events"
    echo "   - Authorization header: <hidden>"
    echo "   - Form RStrigger: newServerData"
    echo "   - Form RStoken: <hidden>"
    echo "   - Form RSdata: $inventory_json_path (${#inventory_json} chars)"
    echo "   - Response body: $response_file"
    echo "   - Response headers: $response_headers_file"
    if [ "${RS_AGENT_DEBUG:-0}" = "1" ]; then
        echo "   - Curl verbose: $curl_trace_file"
    fi
    echo ""
    echo "Executing request to RSM..."

    local curl_args=(
        --silent
        --show-error
        --output "$response_file"
        --dump-header "$response_headers_file"
        --write-out "%{http_code}"
        --location "$RSM_API_URL"
        --header "Authorization: $AGENT_TOKEN"
        --form "RStrigger=newServerData"
        --form "RSdata=<$inventory_json_path;type=application/json"
        --form "RStoken=$AGENT_TOKEN"
        --max-time 30
    )

    if [ "${RS_AGENT_DEBUG:-0}" = "1" ]; then
        curl_args=(--verbose "${curl_args[@]}")
    fi

    local http_code
    if [ "${RS_AGENT_DEBUG:-0}" = "1" ]; then
        http_code=$(curl "${curl_args[@]}" 2>"$curl_trace_file")
        sed -i "s/$AGENT_TOKEN/<AGENT_TOKEN>/g" "$curl_trace_file" 2>/dev/null || true
        chmod 600 "$curl_trace_file" 2>/dev/null || true
    else
        http_code=$(curl "${curl_args[@]}")
    fi
    local exit_code=$?
    local response_body
    response_body=$(cat "$response_file" 2>/dev/null || true)
    chmod 600 "$response_file" "$response_headers_file" 2>/dev/null || true

    echo ""
    echo "HTTP result:"
    echo "   - curl exit: $exit_code"
    echo "   - HTTP code: $http_code"
    echo "   - Response body bytes: $(wc -c < "$response_file" 2>/dev/null || echo 0)"
    echo "   - Response body: $response_file"
    echo "   - Response headers: $response_headers_file"
    if [ "${RS_AGENT_DEBUG:-0}" = "1" ]; then
        echo "   - Curl verbose: $curl_trace_file"
    fi

    if [ "$exit_code" -ne 0 ]; then
        echo ""
        echo "ERROR: Failed to send inventory to RSM (curl exit: $exit_code)"
        echo "Response: $response_body"
        return 1
    fi

    if [ "$http_code" = "409" ] || echo "$response_body" | grep -iqE 'uuid.*(exists|ya existe)|already exists|duplicate|pertenece a otro sistema'; then
        echo ""
        echo "ERROR: RSM indicates that the UUID already exists or belongs to another system."
        echo "This agent cannot be installed on the local machine with that UUID."
        echo "Response: $response_body"
        return 1
    fi

    if [ "$http_code" != "200" ] && [ "$http_code" != "201" ]; then
        echo ""
        echo "ERROR: RSM returned HTTP $http_code"
        echo "Response: $response_body"
        return 1
    fi

    echo ""
    printf 'Inventory sent successfully (%d KB)\n' "$(( ${#inventory_json} / 1024 ))"
    return 0
}

# ============ MAIN ============

main() {
    parse_args "$@"

    echo ""
    echo "============================================================"
    printf  'Firulai Inventory Agent v%s - Collecting system information\n' "$AGENT_VERSION"
    echo "============================================================"
    echo ""

    check_root
    acquire_execution_lock
    if ! init_private_tmp_dir; then
        exit 1
    fi
    echo "Execution trigger: $EXECUTION_TRIGGER"
    check_for_updates
    if ! validate_uuid_ownership; then
        exit 1
    fi
    if ! ensure_private_directory "$OUTPUT_DIR"; then
        exit 1
    fi

    # --- Timezone ---
    echo "Collecting timezone information..."
    local timezone
    timezone=$(collect_timezone)
    [ -z "$timezone" ] && timezone=""
    echo "   -> Timezone: ${timezone:-unknown}"

    # --- System ---
    echo "Collecting system information..."
    local system_json
    system_json=$(collect_system_info "$timezone")
    if [ -z "$system_json" ]; then
        echo "ERROR: Could not collect system information"
        exit 1
    fi

    # --- Hardware ---
    echo "Collecting hardware information..."
    local hardware_json
    hardware_json=$(collect_hardware)
    local firmware_count
    firmware_count=$(printf '%s' "$hardware_json" | grep -o '"device"' | wc -l | tr -d ' ')
    echo "   -> ${firmware_count} firmware(s) detected"

    # --- System Packages ---
    echo "Collecting system packages..."
    collect_packages
    local sys_json="$SYSTEM_COMPONENTS_JSON"
    local source_packages_json="$SYSTEM_PACKAGES_JSON"
    local sys_count="$SYSTEM_COMPONENTS_COUNT"
    local source_package_count="$SYSTEM_PACKAGES_COUNT"
    echo "   -> ${sys_count} system components"
    echo "   -> ${source_package_count} source packages"

    # --- Python Packages ---
    echo "Collecting Python packages..."
    local pip_json pip_count=0
    pip_json=$(collect_pip_packages)
    [ -n "$pip_json" ] && pip_count=$(printf '%s' "$pip_json" | grep -o '"manager":"pip"' | wc -l | tr -d ' ')
    echo "   -> ${pip_count} Python packages"

    # --- Node.js Packages ---
    echo "Collecting Node.js packages..."
    local npm_json npm_count=0
    npm_json=$(collect_npm_packages)
    [ -n "$npm_json" ] && npm_count=$(printf '%s' "$npm_json" | grep -o '"manager":"npm"' | wc -l | tr -d ' ')
    echo "   -> ${npm_count} Node.js packages"

    # Merge all components into one JSON array
    local all_components_json=""
    for part in "$sys_json" "$pip_json" "$npm_json"; do
        [ -z "$part" ] && continue
        [ -n "$all_components_json" ] && all_components_json+=","
        all_components_json+="$part"
    done
    local total=$(( sys_count + pip_count + npm_count ))
    echo "   Unified total: ${total} components"

    # --- Build Final JSON ---
    local inventory_json
    inventory_json="{\"RSToken\":\"$(json_escape "$AGENT_TOKEN")\",\"system\":${system_json},\"hardware\":${hardware_json},\"components\":[${all_components_json}],\"packages\":[${source_packages_json}]}"

    # --- Save Locally ---
    local output_path="${OUTPUT_DIR}/${OUTPUT_FILE}"
    local temporary_output_path
    echo ""
    echo "Saving inventory to ${output_path}..."
    temporary_output_path=$(mktemp "$OUTPUT_DIR/${OUTPUT_FILE}.XXXXXX") || {
        echo "ERROR: Could not create temporary inventory in $OUTPUT_DIR"
        exit 1
    }
    chmod 600 "$temporary_output_path" 2>/dev/null || true
    if ! printf '%s' "$inventory_json" > "$temporary_output_path"; then
        echo "ERROR: Could not write temporary inventory $temporary_output_path"
        rm -f "$temporary_output_path"
        exit 1
    fi
    chown root:root "$temporary_output_path" 2>/dev/null || true
    mv -f "$temporary_output_path" "$output_path"
    chmod 600 "$output_path" 2>/dev/null || true

    # --- Send To RSM ---
    if ! send_to_rsm "$inventory_json"; then
        echo ""
        echo "============================================================"
        echo "CRITICAL ERROR: Could not send inventory to RSM"
        echo "============================================================"
        echo ""
        echo "Check:"
        echo "   - Agent token: <configured; value hidden>"
        echo "   - UUID:  $UUID_VAL"
        echo "   - Alias: $SYSTEM_ALIAS"
        echo "   - URL:   $RSM_API_URL"
        echo "   - Network connectivity"
        exit 1
    fi

    if ! record_success_state; then
        echo "CRITICAL ERROR: Inventory was sent, but execution state could not be saved."
        exit 1
    fi

    # --- Final Summary ---
    local file_size
    file_size=$(stat -c%s "$output_path" 2>/dev/null || stat -f%z "$output_path" 2>/dev/null || echo "?")

    echo ""
    echo "============================================================"
    echo "Inventory collected and sent successfully"
    echo "============================================================"
    echo ""
    echo "Summary:"
    echo "   - System:       $(printf '%s' "$system_json" | grep -o '"name":"[^"]*"' | head -1 | sed 's/"name":"//;s/"//')"
    echo "   - Hostname:     $(hostname -s 2>/dev/null || hostname)"
    echo "   - Firmware:     ${firmware_count}"
    echo "   - Total components: ${total}"
    echo "   - Total packages:   ${source_package_count}"
    echo "   - File:         ${output_path}"
    echo "   - Size:         ${file_size} bytes"
    echo ""
}

main "$@"
