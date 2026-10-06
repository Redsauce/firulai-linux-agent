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
RSM_SYSTEM_CLIENT_PROPERTY_ID=1785
AGENT_TOKEN=token-client-A
UUID="$uuid"
AGENT_LOCALE=es_ES
RSM_BASE_URL='https://example.invalid/AppController/'
make_private_temp_file() { mktemp; }
info() { :; }
error() { printf '%s\n' "$*" >&2; }
installer_fixture='[]'
curl() {
    local output="" request_args="$*"
    case "$request_args" in *"Authorization: token-client-A"*) ;; *) return 99 ;; esac
    while [ "$#" -gt 0 ]; do
        if [ "$1" = "--output" ]; then output="$2"; shift; fi
        shift
    done
    [ -n "$output" ] || return 99
    printf '%s' "$installer_fixture" > "$output"
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
# Same-UUID reinstall refreshes executable files but keeps existing state.
# Existing installations report the detected distribution instead of "Linux".
local_system_hostname() { printf sonarqube; }
local_system_fqdn() { printf sonarqube.example.test; }
installer_fixture="[{\"1780\":\"$uuid\",\"1752\":\"Ubuntu\",\"1749\":\"sonarqube\",\"1750\":\"sonarqube.example.test\",\"1972\":\"covered\",\"1785\":\"6974\"}]"
(set +o pipefail; check_uuid_exists_in_rsm) || exit 1
passed=$((passed+1))
installer_fixture="[{\"1780\":\"$uuid\",\"1752\":\"Debian GNU/Linux\",\"1749\":\"sonarqube\",\"1750\":\"sonarqube.example.test\",\"1972\":\"covered\",\"1785\":\"6974\"}]"
(set +o pipefail; check_uuid_exists_in_rsm) || exit 1
passed=$((passed+1))
installer_fixture="[{\"1780\":\"$uuid\",\"1752\":\"Windows 10 Pro\",\"1749\":\"sonarqube\",\"1972\":\"covered\",\"1785\":\"6974\"}]"
if (set +o pipefail; check_uuid_exists_in_rsm) >/dev/null 2>&1; then exit 1; fi
passed=$((passed+1))
installer_fixture="[{\"1780\":\"$uuid\",\"1752\":\"Ubuntu\",\"1749\":\"sonarqube\",\"1972\":\"uncovered\",\"1785\":\"6956\"}]"
(set +o pipefail; check_uuid_exists_in_rsm) || exit 1
passed=$((passed+1))
upgrade_fixture=$(mktemp -d)
INSTALL_DIR="$upgrade_fixture"
API_MODULE_FILE="$upgrade_fixture/module-candidate"
printf 'RSM_RUNTIME_ELIGIBILITY_VERSION=1\n' > "$API_MODULE_FILE"
printf '#!/bin/bash\necho old-version\n' > "$INSTALL_DIR/rs_agent.sh"
printf 'preserved-state\n' > "$INSTALL_DIR/state.env"
LOCAL_AGENT_RETRY=1
source <(awk '/^retry_local_agent_installation\(\) \{$/{capture=1} capture{print} capture && /^}$/{capture=0}' "$test_dir/../install.sh")
update_rsm_system_on_install() { :; }
download_agent() { printf '#!/bin/bash\necho candidate-version\n' > "$INSTALL_DIR/rs_agent.sh"; }
download_runner() { :; }
download_uninstaller() { :; }
log() { :; }
if ! upgrade_output=$(retry_local_agent_installation); then exit 1; fi
[ "$upgrade_output" = "candidate-version" ] || exit 1
[ "$(cat "$INSTALL_DIR/state.env")" = "preserved-state" ] || exit 1
grep -q '^RSM_RUNTIME_ELIGIBILITY_VERSION=1$' "$INSTALL_DIR/api_endpoint.sh" || exit 1
passed=$((passed+1))
# GitHub returns formatted JSON; a future release must still be detected.
CONFIG_FILE="$upgrade_fixture/no-config"
curl() { printf '{"tag_name": "0.4.3"}'; }
download_update() { printf 'update-detected'; }
update_output=$(check_for_updates)
case "$update_output" in *update-detected*) ;; *) exit 1 ;; esac
passed=$((passed+1))
rm -f "$upgrade_fixture/rs_agent.sh" "$upgrade_fixture/api_endpoint.sh" "$upgrade_fixture/module-candidate" "$upgrade_fixture/state.env"
rmdir "$upgrade_fixture"
printf '%s Linux eligibility checks passed.\n' "$passed"
