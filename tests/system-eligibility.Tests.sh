#!/bin/bash
set -uo pipefail
test_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$test_dir/../api_endpoint.sh"
rsm_load_base() { RSM_BASE_URL='https://example.invalid/AppController/'; }
rsm_curl() { printf '%s\n200' "$fixture"; }
uuid='550e8400-e29b-41d4-a716-446655440000'
passed=0
expect_status() {
    local expected="$1" actual=0
    rsm_check_system_uuid "$uuid" 'test-token' || actual=$?
    if [ "$actual" != "$expected" ]; then
        printf 'Expected %s, got %s\n' "$expected" "$actual" >&2
        exit 1
    fi
    passed=$((passed+1))
}
fixture="[{\"1780\":\"$uuid\",\"1751\":\"Activo\",\"1972\":\"covered\",\"1785\":\"6955\"}]"
expect_status 0
fixture="[{\"1780\":\"$uuid\",\"1751\":\"Disconnected\",\"1972\":\"covered\",\"1785\":\"6955\"}]"
expect_status 5
fixture="[{\"1780\":\"$uuid\",\"1751\":\"Activo\",\"1972\":\"uncovered\",\"1785\":\"6955\"}]"
expect_status 6
fixture="[{\"1780\":\"$uuid\",\"1751\":\"Activo\",\"1972\":\"uncovered\",\"1785\":\"6956\"}]"
expect_status 0
fixture="[{\"1780\":\"$uuid\",\"1751\":\"Disconnected\",\"1972\":\"covered\",\"1785\":\"6956\"}]"
expect_status 5
fixture="[{\"1780\":\"$uuid\",\"1751\":\"Activo\",\"1972\":\"covered\"}]"
expect_status 4
fixture='[]'
expect_status 2
fixture='{"error":"denied"}'
expect_status 4
fixture="[{\"1780\":\"$uuid\"},{\"1780\":\"$uuid\"}]"
expect_status 3
# Load production functions without executing main or touching agent directories.
source <(sed '$d' "$test_dir/../rs_agent.sh")
UUID_VAL="$uuid"
AGENT_TOKEN='test-token'
AGENT_LOCALE='en_US'
RSM_RUNTIME_ELIGIBILITY_VERSION=1
make_private_temp_file() { echo 'Upload preparation must not be reached' >&2; exit 99; }
fixture='[]'
if send_to_rsm '{}' >/dev/null 2>&1; then
    echo 'Deleted system was allowed to upload' >&2
    exit 1
fi
passed=$((passed+1))
# A UUID hidden from client A must fail both runtime and installation lookup.
rsm_curl() {
    case "$*" in *"Authorization: token-client-A"*) ;; *) return 99 ;; esac
    printf '[]\n200'
}
cross_client_status=0
rsm_check_system_uuid "$uuid" token-client-A || cross_client_status=$?
[ "$cross_client_status" = "2" ] || exit 1
passed=$((passed+1))
source <(awk '/^(t|check_uuid_exists_in_rsm)\(\) \{$/{capture=1} capture{print} capture && /^}$/{capture=0}' "$test_dir/../install.sh")
RSM_SYSTEM_ITEM_TYPE_ID=191
RSM_SYSTEM_HOSTNAME_PROPERTY_ID=1749
RSM_SYSTEM_FQDN_PROPERTY_ID=1750
RSM_SYSTEM_UUID_PROPERTY_ID=1780
RSM_SYSTEM_OS_PROPERTY_ID=1752
RSM_SYSTEM_COVERAGE_PROPERTY_ID=1972
AGENT_TOKEN=token-client-A
UUID="$uuid"
AGENT_LOCALE=es_ES
RSM_BASE_URL='https://example.invalid/AppController/'
make_private_temp_file() { mktemp; }
info() { :; }
error() { printf '%s\n' "$*" >&2; }
curl() {
    local output="" request_args="$*"
    case "$request_args" in *"Authorization: token-client-A"*) ;; *) return 99 ;; esac
    while [ "$#" -gt 0 ]; do
        if [ "$1" = "--output" ]; then output="$2"; shift; fi
        shift
    done
    [ -n "$output" ] || return 99
    printf '[]' > "$output"
    printf '200'
}
if lookup_output=$( (set +o pipefail; check_uuid_exists_in_rsm) 2>&1 ); then
    echo 'Cross-client UUID was allowed to install' >&2
    exit 1
fi
case "$lookup_output" in
    *"No se ha podido validar el sistema."*) ;;
    *) echo 'Expected generic validation failure' >&2; exit 1 ;;
esac
passed=$((passed+1))
printf '%s Linux eligibility checks passed.\n' "$passed"
