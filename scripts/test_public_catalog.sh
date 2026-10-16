#!/bin/bash
# Read-only integration check of the public production catalog; no credentials,
# inventory collection, scheduler changes or real installation.
set -euo pipefail
cd "$(dirname "$0")/.."
source <(sed -n '/^is_newer_version() {/,/^download_update() {/p' rs_agent.sh | sed '$d')
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
OUTPUT_DIR="$fixture"
CONFIG_FILE="$fixture/config.env"
AGENT_VERSION=999999999.999999999.999999999
AGENT_CATALOG_URL=https://firulai.redsauce.net/api/agents/update-catalog
t() { printf '%s' "$1"; }
download_update() { echo 'This read-only test must never install anything' >&2; return 1; }
check_for_updates
grep -Fxq UPDATE_FAILURES=0 "$fixture/update-state.env"
echo 'PASS: real Linux updater read the production Firulai catalog without credentials or installation.'
