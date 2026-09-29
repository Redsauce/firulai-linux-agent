#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

. <(sed -n '/^RSM_SYSTEM_ITEM_TYPE_ID=/,/^RSM_SYSTEM_COVERAGE_PROPERTY_ID=/p' install.sh)
. <(sed -n '/^check_uuid_exists_in_rsm() {/,/^}/p' install.sh)

test_dir=$(mktemp -d)
trap 'rm -f "$test_dir"/response.*; rmdir "$test_dir"' EXIT

UUID='00000000-0000-4000-8000-000000000001'
AGENT_TOKEN='fake-token'
RSM_BASE_URL='https://rsm1.invalid/AppController/'

json_escape() { printf '%s' "$1"; }
local_system_hostname() { printf '%s' 'linux-host'; }
local_system_fqdn() { printf '%s' 'linux-host.example.test'; }
make_private_temp_file() { mktemp "$test_dir/response.XXXXXX"; }
info() { :; }
error() { printf '%s\n' "$*" >&2; }
t() { printf '%s' "$1"; }
rsm_response_has_api_error() { return 1; }

curl() {
    local output_file='' previous='' argument
    for argument in "$@"; do
        if [ "$previous" = '--output' ]; then
            output_file="$argument"
            break
        fi
        previous="$argument"
    done
    [ -n "$output_file" ]
    printf '%s' "$MOCK_RESPONSE" > "$output_file"
    printf '%s' '200'
}

expect_allowed() {
    MOCK_RESPONSE="$1"
    (check_uuid_exists_in_rsm) >/dev/null 2>&1 || {
        echo "Expected reservation to be accepted: $2" >&2
        exit 1
    }
}

expect_blocked() {
    MOCK_RESPONSE="$1"
    if (check_uuid_exists_in_rsm) >/dev/null 2>&1; then
        echo "Expected reservation to be blocked: $2" >&2
        exit 1
    fi
}

expect_allowed '[{"ID":"1","1780":"00000000-0000-4000-8000-000000000001","1749":"","1750":"","1752":"Linux","1972":"covered"}]' 'new covered Linux reservation'
expect_allowed '[{"ID":"1","1780":"00000000-0000-4000-8000-000000000001","1749":"linux-host","1750":"linux-host.example.test","1752":"Linux","1972":"covered"}]' 'same-machine reactivation'
expect_blocked '[{"ID":"1","1780":"00000000-0000-4000-8000-000000000001","1749":"","1750":"","1752":"Linux","1972":"uncovered"}]' 'uncovered reservation'
expect_blocked '[{"ID":"1","1780":"00000000-0000-4000-8000-000000000001","1749":"","1750":"","1752":"Windows","1972":"covered"}]' 'Windows reservation'
expect_blocked '[]' 'missing reservation'

echo 'PASS: UUID reservations require one covered Linux System and preserve same-machine reactivation.'
