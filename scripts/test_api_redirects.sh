#!/bin/bash
set -euo pipefail
mode=--offline
module_file="$(dirname "$0")/../api_endpoint.sh"
while [ "$#" -gt 0 ]; do
    case "$1" in
        --offline|--live) mode="$1"; shift ;;
        --module)
            [ "$#" -ge 2 ] || { echo '--module requires a path' >&2; exit 2; }
            module_file="$2"; shift 2 ;;
        *) echo 'Usage: bash test_api_redirects.sh [--live] [--module /path/api_endpoint.sh]' >&2; exit 2 ;;
    esac
done
[ -r "$module_file" ] || { echo "Cannot read module: $module_file" >&2; exit 1; }
module_file="$(cd -- "$(dirname -- "$module_file")" && pwd)/$(basename -- "$module_file")"
. "$module_file"
# Never inherit a real installation's persistence destination.
unset RSM_SETTINGS_FILE
test_dir=$(mktemp -d)
trap 'rm -f "$test_dir/config.env" "$test_dir/body" "$test_dir/calls"; rmdir "$test_dir"' EXIT
CONFIG_FILE="$test_dir/config.env"
printf 'Modulo bajo prueba: %s\nConfiguracion temporal: %s\n' "$module_file" "$CONFIG_FILE"
initial='https://rsm1.invalid/AppController/'
destination='https://httpbingo.org/anything/rsm2/AppController/'
body_file="$test_dir/body"
calls_file="$test_dir/calls"

rsm_curl() {
    local args=("$@") url="${!#}" target="$destination$RSM_API_PATH"
    printf '%s\n' "$url" >> "$calls_file"
    if [ "$mode" = --live ]; then
        # Only the test adapter knows HTTPBingo's /redirect-to query syntax.
        if [ "$url" = "$initial$RSM_API_PATH" ]; then
            args[${#args[@]}-1]="https://httpbingo.org/redirect-to?url=$target&status_code=$redirect_status"
        fi
        command curl "${args[@]}"
    else
        printf '{"method":"POST","fake":"test-payload"}' > "$body_file"
        if [ "$url" = "$initial$RSM_API_PATH" ]; then
            printf '%s\n%s' "$redirect_status" "${redirect_target:-$target}"
        elif [ "$scenario" = mixed ] && [ "$url" = "$destination$RSM_API_PATH" ]; then
            printf '%s\n%s' "$second_status" "https://rsm3.invalid/AppController/$RSM_API_PATH"
        else
            printf '%s\n' "$final_status"
        fi
    fi
}

reset_case() {
    printf "AGENT_TOKEN='fake-token'\nUUID='preserved'\nAGENT_LOCALE='es_ES'\nRSM_BASE_URL='%s'\n" "$initial" > "$CONFIG_FILE"
    : > "$calls_file"
    scenario=normal
    redirect_target=''
    final_status=200
}

send_request() {
    rsm_request --silent --show-error --output "$body_file" --max-time 30 \
        --header 'Authorization: fake-token' --form-string 'RStrigger=test-event' \
        --form-string 'RSdata=test-payload' --form-string 'RStoken=fake-token'
}

for redirect_status in 301 302 307 308; do
    reset_case
    echo "HTTP $redirect_status: base before = $initial"
    [ "$(send_request)" = 200 ]
    grep -q 'POST' "$body_file"
    grep -q 'test-payload' "$body_file"
    rsm_load_base
    case "$redirect_status" in
        301|308) expected="$destination"; expected_calls=1 ;;
        *) expected="$initial"; expected_calls=2 ;;
    esac
    [ "$RSM_BASE_URL" = "$expected" ]
    echo "HTTP $redirect_status: base read from config.env = $RSM_BASE_URL"
    grep -q "UUID='preserved'" "$CONFIG_FILE"
    grep -q "AGENT_TOKEN='fake-token'" "$CONFIG_FILE"
    grep -q "AGENT_LOCALE='es_ES'" "$CONFIG_FILE"
    : > "$calls_file"
    # A fresh shell invocation reads the stored value, not the previous variable.
    [ "$(RSM_BASE_URL=; send_request)" = 200 ]
    [ "$(wc -l < "$calls_file" | tr -d ' ')" = "$expected_calls" ]
    [ "$(head -1 "$calls_file")" = "$expected$RSM_API_PATH" ]
    echo "Next execution: $(head -1 "$calls_file") ($expected_calls request(s))"
done

if [ "$mode" = --offline ]; then
    for redirect_target in 'http://bad.example/commands_RSM/api/api.php' 'https://user@bad.example/commands_RSM/api/api.php' 'https://bad.example/other.php' ''; do
        bad_target="$redirect_target"
        reset_case; redirect_status=301
        # Missing Location is represented by a target that cannot be an endpoint.
        redirect_target="${bad_target:-invalid}"
        if send_request >/dev/null 2>&1; then echo 'Invalid target accepted' >&2; exit 1; fi
        grep -q 'rsm1.invalid' "$CONFIG_FILE"
        [ "$(wc -l < "$calls_file" | tr -d ' ')" = 1 ]
    done
    reset_case; redirect_status=301; final_status=500
    [ "$(send_request)" = 500 ]; grep -q 'rsm1.invalid' "$CONFIG_FILE"
    reset_case; redirect_status=301; redirect_target="$initial$RSM_API_PATH"
    if send_request >/dev/null 2>&1; then echo 'Loop accepted' >&2; exit 1; fi
    [ "$(wc -l < "$calls_file" | tr -d ' ')" = 6 ]
    grep -q 'rsm1.invalid' "$CONFIG_FILE"
    reset_case; redirect_status=302; second_status=301; scenario=mixed
    [ "$(send_request)" = 200 ]; rsm_load_base; [ "$RSM_BASE_URL" = "$initial" ]
    reset_case; redirect_status=301; second_status=302; scenario=mixed
    [ "$(send_request)" = 200 ]; rsm_load_base; [ "$RSM_BASE_URL" = "$destination" ]
fi
echo "PASS ($mode): redirects, persisted base and next execution. Temporary config removed on exit."
