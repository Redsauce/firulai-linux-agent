#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
. <(sed -n '/^is_newer_version() {/,/^# ============ SEND TO RSM/p' rs_agent.sh | sed '$d')
fixture=$(mktemp -d)
trap 'rm -f "$fixture/config.env" "$fixture/rs_agent.sh" "$fixture/api_endpoint.sh" "$fixture/uninstall.sh" "$fixture/rs_agent.sh.backup" "$fixture/requests"; rmdir "$fixture"' EXIT
CONFIG_FILE="$fixture/config.env"
INSTALL_DIR="$fixture"
GITHUB_API_URL='https://example.invalid/latest'
AGENT_VERSION='0.4.3'
AGENT_TOKEN='fixture-token'
UUID_VAL='00000000-0000-4000-8000-000000000001'
AGENT_LOCALE='en_US'
t() { printf '%s' "$1"; }
is_newer_version 0.4.10 0.4.3
is_newer_version 1.0.0 0.99.9
! is_newer_version 0.4.3 0.4.3
! is_newer_version 0.4.2 0.4.3
! is_newer_version 0.4.4-beta 0.4.3
! is_newer_version 999999999999999.0.0 0.4.3
fake_response='{"tag_name": "v0.4.4"}'
curl() { printf '%s' "$fake_response"; }
download_update() { printf 'selected-tag:%s' "$1"; }
case "$(check_for_updates)" in *selected-tag:v0.4.4) ;; *) exit 1 ;; esac
fake_response='{"tag_name": "0.4.2"}'
[ -z "$(check_for_updates)" ]
fake_response='{"tag_name": "0.4.4-beta"}'
[ -z "$(check_for_updates)" ]
printf "AGENT_AUTO_UPDATE='0'\n" > "$CONFIG_FILE"
fake_response='{"tag_name": "0.4.4"}'
[ -z "$(check_for_updates)" ]
printf "AGENT_AUTO_UPDATE='1'\n" > "$CONFIG_FILE"
. <(sed -n '/^download_update() {/,/^# ============ SEND TO RSM/p' rs_agent.sh | sed '$d')
printf '#!/bin/bash\necho original\n' > "$INSTALL_DIR/rs_agent.sh"
curl() {
    local url="${@: -3:1}" output="${@: -1}"
    printf '%s\n' "$url" >> "$fixture/requests"
    case "$url" in
        */v0.4.4/rs_agent.sh) printf '#!/bin/bash\nAGENT_VERSION="0.4.4"\nprintf "upgraded\\n"\n' > "$output" ;;
        */v0.4.4/api_endpoint.sh|*/v0.4.4/uninstall.sh) printf '#!/bin/bash\n:\n' > "$output" ;;
        *) return 1 ;;
    esac
}
case "$(download_update v0.4.4)" in *upgraded) ;; *) exit 1 ;; esac
grep -Fxq "AGENT_AUTO_UPDATE='1'" "$CONFIG_FILE"
grep -q original "$INSTALL_DIR/rs_agent.sh.backup"
! grep -q '/main/' "$fixture/requests"
# A release whose script has a different version must not replace local files.
curl() { printf '#!/bin/bash\nAGENT_VERSION="0.4.5"\n' > "${@: -1}"; }
before=$(cat "$INSTALL_DIR/rs_agent.sh")
download_update v0.4.4 >/dev/null
[ "$(cat "$INSTALL_DIR/rs_agent.sh")" = "$before" ]
echo 'PASS: Linux version ordering, opt-out, pinned release download, restart, config preservation and mismatched-package rejection.'
