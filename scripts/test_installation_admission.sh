#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
. <(sed -n '/^request_installation_admission() {/,/^}/p' install.sh)
UUID='00000000-0000-4000-8000-000000000001'
AGENT_TOKEN='fixture-not-a-real-token'
test_dir=$(mktemp -d)
trap 'rm -f "$test_dir"/response.* "$test_dir/request"; rmdir "$test_dir"' EXIT
make_private_temp_file() { mktemp "$test_dir/response.XXXXXX"; }
json_escape() { printf '%s' "$1"; }
local_system_hostname() { printf 'linux-host'; }
local_system_fqdn() { printf 'linux-host.example.test'; }
t() { printf '%s' "$1"; }
error() { printf '%s\n' "$*" >&2; }
curl() {
    local previous='' output='' arg
    printf '%s\n' "$@" > "$test_dir/request"
    for arg in "$@"; do
        [ "$previous" != '--output' ] || output="$arg"
        previous="$arg"
    done
    printf '%s' "$body" > "$output"
    printf '%s' "$code"
    return "$network"
}
expect_blocked() {
    if (request_installation_admission "${1:-false}") >/dev/null 2>&1; then
        echo "Unexpected admission: $code / $body / $network" >&2; exit 1
    fi
}
network=0; code=200; body='{"allowed":true,"activated":false}'
request_installation_admission true
# Check-only never requests allocation, and credential-bearing requests do not follow redirects.
grep -q '"checkOnly":true' "$test_dir/request"
! grep -Eq '^(-L|--location|--location-trusted)$' "$test_dir/request"
expect_blocked false
body='{"allowed":true,"activated":true}'
request_installation_admission false
grep -q '"checkOnly":false' "$test_dir/request"
for code in 401 403 404 409 500 502 302; do expect_blocked; done
code=200
for body in '' '{}' '{"allowed":false,"activated":false}' '<html>Unavailable</html>' '{"allowed":true,"activated":false}'; do expect_blocked; done
body='{"allowed":true,"activated":true}'
for network in 6 7 28; do expect_blocked; done
printf 'PASS: preflight and confirmed admission; capacity, authorization, redirects, unavailable backend and network failures stop installation.\n'
