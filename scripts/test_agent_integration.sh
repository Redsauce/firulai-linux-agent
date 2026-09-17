#!/bin/bash
# Runs the real agent entry point in isolation. Only collectors and the HTTP
# test-server adapter are replaced, in a COPY of the installed module.
set -euo pipefail
source_dir=/opt/rs-agent
mode=--offline
while [ "$#" -gt 0 ]; do
    case "$1" in
        --source) [ "$#" -ge 2 ] || exit 2; source_dir="$2"; shift 2 ;;
        --live|--offline) mode="$1"; shift ;;
        *) echo 'Usage: bash test_agent_integration.sh [--source /opt/rs-agent] [--live]' >&2; exit 2 ;;
    esac
done
for file in rs_agent.sh api_endpoint.sh; do
    [ -r "$source_dir/$file" ] || { echo "Missing $source_dir/$file" >&2; exit 1; }
done
command -v flock >/dev/null || { echo 'This test requires Linux flock (util-linux).' >&2; exit 1; }
test_root=$(mktemp -d "${TMPDIR:-/tmp}/rs-agent-integration.XXXXXX")
mkdir "$test_root/install"
cp "$source_dir/rs_agent.sh" "$test_root/install/rs_agent.sh"
cp "$source_dir/api_endpoint.sh" "$test_root/install/api_endpoint.sh"
cmp "$source_dir/rs_agent.sh" "$test_root/install/rs_agent.sh"
cmp "$source_dir/api_endpoint.sh" "$test_root/install/api_endpoint.sh"
printf 'Copia del agente: %s/rs_agent.sh\nResultados conservados en: %s\n' "$source_dir" "$test_root"

# This fixture code is appended only to the temporary copy. No inventory from
# the machine is collected, and the exact outbound payload is checked below.
cat >> "$test_root/install/api_endpoint.sh" <<'FIXTURES'

collect_timezone() { printf 'UTC'; }
collect_system_info() { printf '{"name":"api-redirect-test","uuid":"00000000-0000-4000-8000-000000000001"}'; }
collect_hardware() { printf '{"firmware":[]}'; }
collect_packages() {
    SYSTEM_COMPONENTS_JSON=''; SYSTEM_PACKAGES_JSON=''
    SYSTEM_COMPONENTS_COUNT=0; SYSTEM_PACKAGES_COUNT=0
}
collect_pip_packages() { :; }
collect_npm_packages() { :; }
collect_snap_packages() { :; }
collect_flatpak_packages() { :; }
collect_gem_packages() { :; }
rsm_curl() {
    local args=("$@") url="${!#}" arg payload_file='' output_file='' i payload_index=0
    local expected='{"RStoken":"fake-token","system":{"name":"api-redirect-test","uuid":"00000000-0000-4000-8000-000000000001"},"hardware":{"firmware":[]},"components":[],"packages":[]}'
    for ((i=0; i<${#args[@]}; i++)); do
        arg="${args[i]}"
        case "$arg" in
            'RSdata=<'*) payload_file="${arg#RSdata=<}"; payload_file="${payload_file%;type=application/json}"; payload_index="$i" ;;
            --output) output_file="${args[i+1]}" ;;
        esac
    done
    [ -f "$payload_file" ] && [ "$(cat "$payload_file")" = "$expected" ] || {
        echo 'Refusing to send unexpected inventory data' >&2; return 1;
    }
    # Native Windows curl needs a Windows path for this embedded multipart file.
    if command -v cygpath >/dev/null 2>&1; then
        args[payload_index]="RSdata=<$(cygpath -m "$payload_file");type=application/json"
    fi
    printf '%s\n' "$url" >> "$INTEGRATION_CALLS"
    case "$url" in
        "https://rsm1.invalid/AppController/$RSM_API_PATH")
            if [ "$INTEGRATION_MODE" = --live ]; then
                args[${#args[@]}-1]="https://httpbingo.org/redirect-to?url=https://httpbingo.org/anything/rsm2/AppController/$RSM_API_PATH&status_code=$INTEGRATION_STATUS"
                command curl "${args[@]}"
            else
                printf '{}' > "$output_file"
                printf '%s\n%s' "$INTEGRATION_STATUS" "https://httpbingo.org/anything/rsm2/AppController/$RSM_API_PATH"
            fi ;;
        "https://httpbingo.org/anything/rsm2/AppController/$RSM_API_PATH")
            if [ "$INTEGRATION_MODE" = --live ]; then command curl "${args[@]}"
            else printf '{"ok":true}' > "$output_file"; printf '200\n'; fi ;;
        *) echo 'Unexpected destination; request blocked' >&2; return 1 ;;
    esac
}
FIXTURES

unset RSM_SETTINGS_FILE RSM_BASE_URL
export RS_AGENT_INSTALL_DIR="$test_root/install"
export RS_AGENT_TRIGGER=integration-test
export RS_AGENT_DEBUG=0
export INTEGRATION_MODE="$mode"
for status in 301 302; do
    case_dir="$test_root/$status"
    mkdir -p "$case_dir/data" "$case_dir/runtime"
    config="$case_dir/data/config.env"
    printf "AGENT_TOKEN='fake-token'\nUUID='00000000-0000-4000-8000-000000000001'\nAGENT_LOCALE='en_US'\nRSM_BASE_URL='https://rsm1.invalid/AppController/'\nAGENT_AUTO_UPDATE='0'\n" > "$config"
    export RS_AGENT_DATA_DIR="$case_dir/data"
    export RS_AGENT_TMP_DIR="$case_dir/runtime/tmp"
    export RS_AGENT_LOCK_FILE="$case_dir/runtime/agent.lock"
    export INTEGRATION_STATUS="$status"
    expected_base='https://rsm1.invalid/AppController/'
    expected_count=2
    if [ "$status" = 301 ]; then
        expected_base='https://httpbingo.org/anything/rsm2/AppController/'
        expected_count=1
    fi
    for run in 1 2; do
        export INTEGRATION_CALLS="$case_dir/calls-$run.txt"
        if ! bash "$test_root/install/rs_agent.sh" --token fake-token --uuid 00000000-0000-4000-8000-000000000001 --locale en_US > "$case_dir/run-$run.log" 2>&1; then
            cat "$case_dir/run-$run.log"
            echo "FAIL: HTTP $status execution $run. Evidence: $test_root" >&2
            exit 1
        fi
        grep -Fxq "RSM_BASE_URL='$expected_base'" "$config"
        grep -q '^LAST_SUCCESS_EPOCH=' "$case_dir/data/state.env"
        [ -s "$case_dir/data/inventory.json" ]
        if [ "$run" = 2 ]; then
            [ "$(wc -l < "$INTEGRATION_CALLS" | tr -d ' ')" = "$expected_count" ]
            [ "$(head -1 "$INTEGRATION_CALLS")" = "${expected_base}commands_RSM/api/api.php" ]
        else
            [ "$(wc -l < "$INTEGRATION_CALLS" | tr -d ' ')" = 2 ]
        fi
        printf 'HTTP %s, ejecucion %s: ' "$status" "$run"
        grep '^RSM_BASE_URL=' "$config"
    done
done
echo 'PASS: entrada real del agente, inventario ficticio, envio, persistencia y segundo proceso.'
printf 'Inspeccionar 301: cat "%s/301/data/config.env"\n' "$test_root"
printf 'Inspeccionar 302: cat "%s/302/data/config.env"\n' "$test_root"
echo 'La instalacion original no se ha modificado. Se conservan archivos de prueba y logs.'
