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
