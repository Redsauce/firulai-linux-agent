#!/bin/bash
# Shared by installation, inventory and uninstallation. No test URLs here.
RSM_API_PATH='commands_RSM/api/api.php'

rsm_valid_base() {
    [[ "$1" =~ ^https://[A-Za-z0-9.-]+(:[0-9]+)?(/[A-Za-z0-9._~/-]*)?/$ ]]
}

rsm_load_base() {
    local settings="${RSM_SETTINGS_FILE:-${CONFIG_FILE:-}}" stored=""
    if [ -f "$settings" ]; then
        stored=$(sed -n "s/^RSM_BASE_URL='\([^']*\)'$/\1/p" "$settings" | tail -1)
        if grep -q '^RSM_BASE_URL=' "$settings" && [ -z "$stored" ]; then
            echo "Invalid RSM_BASE_URL: use RSM_BASE_URL='https://host/base/'" >&2
            return 1
        fi
    fi
    RSM_BASE_URL="${stored:-${RSM_BASE_URL:-https://rsm1.redsauce.net/AppController/}}"
    RSM_BASE_URL="${RSM_BASE_URL%/}/"
    rsm_valid_base "$RSM_BASE_URL" || { echo 'Invalid API base URL' >&2; return 1; }
    RSM_API_URL="$RSM_BASE_URL$RSM_API_PATH"
}

rsm_save_base() {
    local base="$1" settings="${RSM_SETTINGS_FILE:-${CONFIG_FILE:-}}" temporary
    rsm_valid_base "$base" || return 1
    [ -f "$settings" ] || { echo 'Missing API settings file' >&2; return 1; }
    temporary=$(mktemp "${settings}.XXXXXX") || return 1
    if ! { sed '/^RSM_BASE_URL=/d' "$settings" && printf "RSM_BASE_URL='%s'\n" "$base"; } > "$temporary" ||
        ! chmod 600 "$temporary" || ! mv -f "$temporary" "$settings"; then
        rm -f "$temporary"
        return 1
    fi
}

# RSM may report authentication, authorization or routing failures inside an
# XML envelope while still returning HTTP 200. Callers must reject that body
# explicitly instead of treating the status code as proof that an event exists.
rsm_response_has_api_error() {
    printf '%s' "${1:-}" | grep -qiE '<RSError([[:space:]>])|RSerrorMessage|RSerrorCode|ACCESS[[:space:]]+DENIED'
}

# Test harnesses override this transport boundary, never production settings.
rsm_curl() { curl "$@"; }

# Call with curl options for output, body, headers and timeout. URL and
# write-out are owned here; automatic --location must not be enabled.
rsm_request() {
    local url result status target base hop permanent="" permanent_prefix=1
    rsm_load_base || return 1
    url="$RSM_API_URL"
    for ((hop=0; hop<=5; hop++)); do
        result=$(rsm_curl "$@" --proto '=https' --write-out $'%{http_code}\n%{redirect_url}' "$url") || return $?
        result="${result//$'\r'/}"
        status="${result%%$'\n'*}"
        target="${result#*$'\n'}"
        case "$status" in
            301|302|307|308)
                [ "$hop" -lt 5 ] || { echo 'Too many API redirects' >&2; return 1; }
                # curl resolves relative Location headers in redirect_url.
                case "$target" in
                    *"$RSM_API_PATH") base="${target%"$RSM_API_PATH"}" ;;
                    *) echo 'API redirect does not end with the expected endpoint' >&2; return 1 ;;
                esac
                rsm_valid_base "$base" || { echo 'Invalid API redirect base' >&2; return 1; }
                url="$base$RSM_API_PATH"
                case "$status" in 302|307) permanent_prefix=0 ;; esac
                [ "$permanent_prefix" = 0 ] || permanent="$base"
                ;;
            *)
                if [[ "$status" == 2?? ]] && [ -n "$permanent" ]; then
                    rsm_save_base "$permanent" || return 1
                fi
                printf '%s' "$status"
                return 0
                ;;
        esac
    done
}

# Synchronous preflight for an already-installed agent. Return 0 for exactly
# one System, 2 when missing, 3 when ambiguous, and 4 when RSM cannot be read.
# Keep this separate from newServerData: that trigger acknowledges the queue,
# not the later inventory result.
rsm_check_system_uuid() {
    local uuid="$1" token="$2" url payload response status body count
    rsm_load_base || return 4
    url="${RSM_BASE_URL%/}/commands_RSM/api/v2/items/get.php"
    payload="{\"itemTypeID\":\"191\",\"propertyIDs\":[\"1780\"],\"translateIDs\":false,\"filterRules\":[{\"propertyID\":\"1780\",\"value\":\"$uuid\",\"operation\":\"=\"}]}"
    response=$(rsm_curl --silent --show-error --location --max-redirs 5 \
        --proto '=https' --proto-redir '=https' --request POST "$url" \
        --header "Authorization: $token" --header 'Content-Type: application/json' \
        --data "$payload" --max-time 20 --write-out $'\n%{http_code}') || return 4
    status="${response##*$'\n'}"
    body="${response%$'\n'*}"
    [ "$status" = "200" ] && [ -n "$body" ] || return 4
    if rsm_response_has_api_error "$body" || printf '%s' "$body" | grep -qE '"error"[[:space:]]*:'; then
        return 4
    fi
    count=$(printf '%s' "$body" | grep -Eio "\"1780\"[[:space:]]*:[[:space:]]*\"$uuid\"" | wc -l | tr -d '[:space:]')
    [ "$count" = "1" ] && return 0
    [ "$count" = "0" ] && return 2
    return 3
}
