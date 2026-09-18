#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
. <(sed -n '/^write_agent_config() {/,/^}/p' install.sh)
. <(sed -n '/^check_for_updates() {/,/^}/p' rs_agent.sh)
test_dir=$(mktemp -d)
trap 'rm -f "$test_dir/config.env" "$test_dir/request"; rmdir "$test_dir"' EXIT
DATA_DIR="$test_dir"
CONFIG_FILE="$DATA_DIR/config.env"
AGENT_TOKEN='fake-token'
UUID='test-uuid'
AGENT_LOCALE='es_ES'
AGENT_VERSION='0.4.0'
GITHUB_API_URL='https://example.invalid/releases/latest'
rsm_load_base() { RSM_BASE_URL='https://rsm1.example/AppController/'; }
shell_single_quote() { printf "'%s'" "$1"; }
info() { :; }
log() { :; }
t() { :; }
curl() { touch "$test_dir/request"; printf '{"tag_name":"v0.4.0"}'; }
download_update() { echo 'Unexpected download' >&2; exit 1; }

GITHUB_RAW_URL='https://raw.githubusercontent.com/Redsauce/firulai-linux-agent/test/api-base-redirects'
write_agent_config
grep -q "^AGENT_AUTO_UPDATE='0'$" "$CONFIG_FILE"
check_for_updates
[ ! -f "$test_dir/request" ]

GITHUB_RAW_URL='https://raw.githubusercontent.com/Redsauce/firulai-linux-agent/main'
write_agent_config
grep -q "^AGENT_AUTO_UPDATE='1'$" "$CONFIG_FILE"
check_for_updates
[ -f "$test_dir/request" ]
echo 'PASS: branch installs disable automatic updates; main installs retain them.'
