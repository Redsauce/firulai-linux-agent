#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RS_AGENT_UNINSTALL_LIBRARY_ONLY=1 source "$root/uninstall.sh"
source "$root/api_endpoint.sh"
fixture_dir=$(mktemp -d)
trap 'rm -rf -- "$fixture_dir"' EXIT
UUID_VAL='550e8400-e29b-41d4-a716-446655440000'
AGENT_TOKEN='fixture-token'
make_private_temp_file() { mktemp "$fixture_dir/response.XXXXXX"; }
rsm_load_base() { RSM_BASE_URL='https://example.invalid'; }
# Replace transport and elapsed time only; exercise the real polling and parser.
rsm_request() {
    while [ "$#" -gt 0 ]; do
        if [ "$1" = --output ]; then
            printf '{"queued":true}' > "$2"
            break
        fi
        shift
    done
    printf '200'
}
rsm_curl() {
    local count status coverage
    count=$(cat "$fixture_dir/polls")
    count=$((count + 1))
    printf '%s' "$count" > "$fixture_dir/polls"
    status='Agente instalado'; coverage='covered'
    if [ "$count" -ge "$ready_after" ]; then
        status='Agente desinstalado'; coverage='uncovered'
    fi
    printf '[{"1780":"%s","1751":"%s","1972":"%s"}]\n200' "$UUID_VAL" "$status" "$coverage"
}
sleep() { printf 'wait\n' >> "$fixture_dir/waits"; }

for ready_after in 4 20; do
    printf '0' > "$fixture_dir/polls"
    : > "$fixture_dir/waits"
    mark_system_disconnected_in_rsm > /dev/null
    test "$(cat "$fixture_dir/polls")" = "$ready_after"
    test "$(wc -l < "$fixture_dir/waits" | tr -d '[:space:]')" = "$((ready_after - 1))"
done
echo 'PASS: delayed confirmation succeeds on fourth and final permitted poll.'

ready_after=21
printf '0' > "$fixture_dir/polls"
: > "$fixture_dir/waits"
if mark_system_disconnected_in_rsm > "$fixture_dir/timeout-log" 2>&1; then
    echo 'Unconfirmed queued event accepted' >&2
    exit 1
fi
test "$(cat "$fixture_dir/polls")" = 20
grep -q confirmation_not_verified "$fixture_dir/timeout-log"
# The queued change arrives after the first attempt timed out. Repeating the
# request must recognize persisted confirmation rather than requiring a new state.
mark_system_disconnected_in_rsm > /dev/null
test "$(cat "$fixture_dir/polls")" = 21
echo 'PASS: timeout rejects unconfirmed change; retry accepts later persisted confirmation.'
