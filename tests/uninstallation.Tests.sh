#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$root/api_endpoint.sh"
rsm_load_base() { RSM_BASE_URL='https://example.invalid'; }
verification='{"missing":true,"verified":true}'
verification_status=200
verification_failure=0
rsm_status=200
rsm_curl() {
    if [[ "$*" == *'/api/agents/uninstall/missing-system'* ]]; then
        [ "$verification_failure" = 0 ] || return 7
        printf '%s\n%s' "$verification" "$verification_status"
    else
        printf '%s\n%s' "$fixture" "$rsm_status"
    fi
}
uuid='550e8400-e29b-41d4-a716-446655440000'
fixture=''
if rsm_check_uninstallation "$uuid" 'fixture-token'; then echo 'Empty response accepted' >&2; exit 1; fi
fixture="[{\"1780\":\"$uuid\",\"1751\":\"Disconnected\",\"1972\":\"uncovered\"}]"
if rsm_check_uninstallation "$uuid" 'fixture-token'; then echo 'Disconnected accepted' >&2; exit 1; fi
fixture="[{\"1780\":\"$uuid\",\"1751\":\"Agente desinstalado\",\"1972\":\"covered\"}]"
if rsm_check_uninstallation "$uuid" 'fixture-token'; then echo 'Covered accepted' >&2; exit 1; fi
fixture="[{\"1780\":\"$uuid\",\"1751\":\"Agente desinstalado\",\"1972\":\"uncovered\"}]"
verification_failure=1
rsm_check_uninstallation "$uuid" 'fixture-token'
# Normal confirmation must remain independent of the new missing-System API.
verification_failure=0
fixture="[$fixture,$fixture]"
if rsm_check_uninstallation "$uuid" 'fixture-token'; then echo 'Ambiguous UUID accepted' >&2; exit 1; fi
fixture="[{\"1780\":\"$uuid\",\"1751\":\"Agente instalado\",\"1972\":\"covered\"},{\"1780\":\"00000000-0000-4000-8000-000000000002\",\"1751\":\"Agente desinstalado\",\"1972\":\"uncovered\"}]"
if rsm_check_uninstallation "$uuid" 'fixture-token'; then echo 'Status from another System accepted' >&2; exit 1; fi
fixture='[]'
rsm_check_uninstallation "$uuid" 'fixture-token'
fixture='{}'
rsm_check_uninstallation "$uuid" 'fixture-token'
for verification in '' '{}' '[]' '{"missing":true}' '{"missing":"true","verified":true}' \
    '{"missing":false,"verified":true}' '{"missing":true,"verified":false}' \
    '{"missing":true,"verified":true,"error":"denied"}' \
    '{"mis sing":true,"verified":true}' '{"missing":tr ue,"verified":true}'; do
    if rsm_check_uninstallation "$uuid" 'fixture-token'; then echo 'Unverified absence accepted' >&2; exit 1; fi
done
verification='{"missing":true,"verified":true}'
for verification_status in 301 401 403 404 500 502; do
    if rsm_check_uninstallation "$uuid" 'fixture-token'; then echo 'Failed verification HTTP accepted' >&2; exit 1; fi
done
verification_status=200
verification_failure=1
if rsm_check_uninstallation "$uuid" 'fixture-token'; then echo 'Offline independent check accepted' >&2; exit 1; fi
verification_failure=0
rsm_status=403
if rsm_check_uninstallation "$uuid" 'fixture-token'; then echo 'Denied initial query accepted' >&2; exit 1; fi
rsm_status=200
rsm_curl() { return 7; }
if rsm_check_uninstallation "$uuid" 'fixture-token'; then echo 'Network failure accepted' >&2; exit 1; fi
echo 'PASS: uninstall confirmation rejects empty, disconnected, covered, ambiguous and offline responses.'
echo 'PASS: missing System requires independent verification; network, permission, redirect and malformed verification failures preserve the agent.'

# Run actual orchestration with a failing confirmation and harmless cleanup spies.
fixture_dir=$(mktemp -d)
trap 'rm -rf "$fixture_dir"' EXIT
for mode in 0 1; do
    (
        RS_AGENT_UNINSTALL_LIBRARY_ONLY=1 source "$root/uninstall.sh"
        load_config() { UUID_VAL="$uuid"; RUN_AS_ROOT="$mode"; }
        check_root() { :; }
        parse_args() { :; }
        mark_system_disconnected_in_rsm() { touch "$fixture_dir/cancel-remote"; }
        remove_automatic_execution() { touch "$fixture_dir/cancel-schedule"; }
        remove_local_files() { touch "$fixture_dir/cancel-files"; }
        main <<< n
    ) > /dev/null 2>&1
done
test ! -e "$fixture_dir/cancel-remote"
test ! -e "$fixture_dir/cancel-schedule"
test ! -e "$fixture_dir/cancel-files"
echo 'PASS: cancellation in root/user mode performs no remote call or local cleanup.'
if (
    RS_AGENT_UNINSTALL_LIBRARY_ONLY=1 source "$root/uninstall.sh"
    export RS_AGENT_LOCK_FILE="$fixture_dir/test.lock"
    load_config() { AGENT_TOKEN='fixture-token'; UUID_VAL="$uuid"; RUN_AS_ROOT=0; DATA_DIR="$fixture_dir"; }
    check_root() { :; }
    parse_args() { :; }
    confirm_uninstall() { :; }
    init_private_tmp_dir() { :; }
    flock() { return 0; }
    mark_system_disconnected_in_rsm() { touch "$fixture_dir/confirmation-attempted"; return 1; }
    remove_automatic_execution() { touch "$fixture_dir/schedule-removed"; }
    remove_local_files() { touch "$fixture_dir/files-removed"; }
    main
); then echo 'Failed confirmation did not cancel uninstall' >&2; exit 1; fi
test -f "$fixture_dir/confirmation-attempted"
test ! -e "$fixture_dir/schedule-removed"
test ! -e "$fixture_dir/files-removed"
echo 'PASS: failed remote confirmation preserves scheduling and local agent files.'

# Exercise the real main function for both installation modes. Cleanup is
# replaced by spies: no installed agent, service or cron is touched.
for mode in 0 1; do
    for remote_status in 0 1; do
        events="$fixture_dir/events-$mode-$remote_status"
        outcome=0
        (
            RS_AGENT_UNINSTALL_LIBRARY_ONLY=1 source "$root/uninstall.sh"
            export RS_AGENT_LOCK_FILE="$fixture_dir/mode-$mode-$remote_status.lock"
            load_config() { AGENT_TOKEN='fixture-token'; UUID_VAL="$uuid"; RUN_AS_ROOT="$mode"; DATA_DIR="$fixture_dir"; }
            check_root() { :; }
            parse_args() { :; }
            confirm_uninstall() { :; }
            init_private_tmp_dir() { :; }
            mark_system_disconnected_in_rsm() { printf 'confirm\n' >> "$events"; return "$remote_status"; }
            remove_automatic_execution() { printf 'schedule\n' >> "$events"; }
            remove_local_files() { printf 'files\n' >> "$events"; }
            main
        ) > /dev/null 2>&1 || outcome=$?
        if [ "$remote_status" = 0 ]; then
            test "$outcome" = 0
            test "$(cat "$events")" = "$(printf 'confirm\nschedule\nfiles')"
        else
            test "$outcome" != 0
            test "$(cat "$events")" = confirm
        fi
    done
done
echo 'PASS: root/user cleanup only follows successful confirmation; both modes preserve files on failure.'
