#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
. <(sed -n '/^write_agent_config() {/,/^}/p' install.sh)
. <(sed -n '/^is_newer_version() {/,/^}/p' rs_agent.sh)
. <(sed -n '/^record_update_check() {/,/^}/p' rs_agent.sh)
. <(sed -n '/^check_for_updates() {/,/^}/p' rs_agent.sh)
test_dir=$(mktemp -d)
trap 'rm -f "$test_dir/config.env" "$test_dir/request" "$test_dir/update-state.env"; rmdir "$test_dir"' EXIT
DATA_DIR="$test_dir"
OUTPUT_DIR="$test_dir"
CONFIG_FILE="$DATA_DIR/config.env"
AGENT_TOKEN='fake-token'
UUID='test-uuid'
AGENT_LOCALE='es_ES'
AGENT_VERSION='0.4.0'
RUN_AS_ROOT=0
AGENT_CATALOG_URL='https://example.invalid/update-catalog'
rsm_load_base() { RSM_BASE_URL='https://rsm1.example/AppController/'; }
shell_single_quote() { printf "'%s'" "$1"; }
info() { :; }
log() { :; }
t() { :; }
curl() { touch "$test_dir/request"; printf '{"linux":"v0.4.0","windows":"0.20.8"}'; }
download_update() { echo 'Unexpected download' >&2; exit 1; }

GITHUB_RAW_URL='https://raw.githubusercontent.com/Redsauce/firulai-linux-agent/test/api-base-redirects'
write_agent_config
grep -q "^AGENT_AUTO_UPDATE='0'$" "$CONFIG_FILE"
check_for_updates
[ ! -f "$test_dir/request" ]

GITHUB_RAW_URL='https://raw.githubusercontent.com/Redsauce/firulai-linux-agent/main'
write_agent_config
grep -q "^AGENT_AUTO_UPDATE='1'$" "$CONFIG_FILE"
grep -q "^AGENT_INSTALLATION_MODE='user'$" "$CONFIG_FILE"
grep -q "^AGENT_INSTALLATION_USER='$(id -un)'$" "$CONFIG_FILE"
check_for_updates
[ -f "$test_dir/request" ]
GITHUB_RAW_URL='https://raw.githubusercontent.com/Redsauce/firulai-linux-agent/0.4.7'
write_agent_config
grep -q "^AGENT_AUTO_UPDATE='1'$" "$CONFIG_FILE"

echo 'PASS: branch installs disable automatic updates; main and pinned stable installs retain them.'
