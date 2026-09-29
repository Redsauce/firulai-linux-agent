#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

. <(sed -n '/^check_local_agent_installation() {/,/^}/p' install.sh)

test_dir=$(mktemp -d)
trap 'rm -f "$test_dir"/config.env "$test_dir"/rs_agent.sh; rmdir "$test_dir"' EXIT

INSTALL_DIR="$test_dir"
DATA_DIR="$test_dir"
CONFIG_FILE="$test_dir/config.env"
UUID='00000000-0000-4000-8000-000000000001'
RUN_AS_ROOT=0
LOCAL_AGENT_RETRY=0

warn() { :; }
error() { :; }
t() { printf '%s' "$1"; }

check_local_agent_installation
[ "$LOCAL_AGENT_RETRY" = '0' ]

printf "UUID='11111111-1111-4111-8111-111111111111'\n" > "$CONFIG_FILE"
if (check_local_agent_installation) >/dev/null 2>&1; then
    echo 'A different locally installed UUID was accepted.' >&2
    exit 1
fi

printf "UUID='%s'\n" "$UUID" > "$CONFIG_FILE"
check_local_agent_installation
[ "$LOCAL_AGENT_RETRY" = '1' ]

main_block=$(sed -n '/^main() {/,/^}/p' install.sh)
local_line=$(printf '%s\n' "$main_block" | grep -n 'check_local_agent_installation' | head -1 | cut -d: -f1)
rsm_line=$(printf '%s\n' "$main_block" | grep -n 'check_uuid_exists_in_rsm' | head -1 | cut -d: -f1)
retry_line=$(printf '%s\n' "$main_block" | grep -n 'retry_local_agent_installation' | head -1 | cut -d: -f1)
availability_line=$(printf '%s\n' "$main_block" | grep -n 'check_uuid_available' | head -1 | cut -d: -f1)
scheduler_line=$(printf '%s\n' "$main_block" | grep -n 'choose_scheduler_interactively' | head -1 | cut -d: -f1)

[ "$local_line" -lt "$rsm_line" ]
[ "$retry_line" -gt "$availability_line" ]
[ "$scheduler_line" -gt "$retry_line" ]

echo 'PASS: local and RSM validation complete before recovery or scheduler selection.'
