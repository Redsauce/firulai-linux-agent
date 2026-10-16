#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
. <(sed -n '/^is_newer_version() {/,/^# ============ SEND TO RSM/p' rs_agent.sh | sed '$d')
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
CONFIG_FILE="$fixture/config.env"
INSTALL_DIR="$fixture"
OUTPUT_DIR="$fixture"
AGENT_CATALOG_URL=https://firulai.redsauce.net/api/agents/update-catalog
AGENT_VERSION=0.4.3
AGENT_TOKEN=fixture-token
UUID_VAL=00000000-0000-4000-8000-000000000001
AGENT_LOCALE=en_US
UPDATE_ONLY=1
t() { printf '%s' "$1"; }
is_newer_version 0.4.10 0.4.3
! is_newer_version 0.4.3 0.4.3
! is_newer_version 0.4.4-beta 0.4.3
fake_response='{"linux":"v0.4.4","windows":"0.20.8"}'
curl() { echo called >> "$fixture/catalog-requests"; printf '%s' "$fake_response"; }
download_update() { printf 'selected-tag:%s' "$1"; }
case "$(check_for_updates)" in *selected-tag:v0.4.4*) ;; *) exit 1 ;; esac
check_for_updates > /dev/null
[ "$(wc -l < "$fixture/catalog-requests")" = 1 ]
rm "$fixture/update-state.env"
fake_response='{"linux":"../latest"}'
! check_for_updates >/dev/null
failures=1
for delay in 300 600 1200 3600 3600; do
    now=$(date +%s)
    record_update_check "$now" "$failures" fixture >/dev/null
    next=$(sed -n 's/^NEXT_UPDATE_EPOCH=//p' "$fixture/update-state.env")
    [ "$next" -ge "$((now+delay))" ] && [ "$next" -le "$((now+delay+60))" ]
    [ "$failures" -ge 4 ] || failures=$((failures+1))
done
record_update_check "$(date +%s)" 0 fixture >/dev/null
next=$(sed -n 's/^NEXT_UPDATE_EPOCH=//p' "$fixture/update-state.env")
[ "$next" -ge "$(($(date +%s)+3599))" ]
# A boot identity change bypasses the old deadline.
fake_response='{"linux":"0.4.3","windows":"0.20.8"}'
check_for_updates >/dev/null
[ "$(wc -l < "$fixture/catalog-requests")" = 3 ]
printf "AGENT_AUTO_UPDATE='0'\n" > "$CONFIG_FILE"
check_for_updates
[ "$(wc -l < "$fixture/catalog-requests")" = 3 ]
printf "AGENT_AUTO_UPDATE='1'\n" > "$CONFIG_FILE"
. <(sed -n '/^download_update() {/,/^ensure_update_polling() {/p' rs_agent.sh | sed '$d')
printf '#!/bin/bash\necho original\n' > "$INSTALL_DIR/rs_agent.sh"
curl() {
    local url="${@: -3:1}" output="${@: -1}"
    printf '%s\n' "$url" >> "$fixture/requests"
    case "$url" in
        */v0.4.4/rs_agent.sh) printf '#!/bin/bash\nAGENT_VERSION="0.4.4"\nprintf "upgraded\\n"\nprintf "args:%%s\\n" "$*"\n' > "$output" ;;
        */v0.4.4/rs_agent_runner.sh) printf '#!/bin/bash\nFIRULAI_UPDATE_POLLING_VERSION=1\n' > "$output" ;;
        */v0.4.4/api_endpoint.sh|*/v0.4.4/uninstall.sh) printf '#!/bin/bash\n:\n' > "$output" ;;
        *) return 1 ;;
    esac
}
case "$(download_update v0.4.4)" in *upgraded*--check-updates*) ;; *) exit 1 ;; esac
grep -q original "$INSTALL_DIR/rs_agent.sh.backup"
! grep -q '/main/' "$fixture/requests"
curl() { printf '#!/bin/bash\nAGENT_VERSION="0.4.5"\n' > "${@: -1}"; }
before=$(cat "$INSTALL_DIR/rs_agent.sh")
! download_update v0.4.4
[ "$(cat "$INSTALL_DIR/rs_agent.sh")" = "$before" ]
# Migrate only this installation's cron watchdog; retain unrelated jobs.
RUN_AS_ROOT=0
HOME="$fixture"
XDG_CONFIG_HOME="$fixture/config"
printf '15 2 * * * echo unrelated\n*/30 * * * * /bin/bash %s/rs_agent_runner.sh --if-due\n@reboot /bin/bash %s/rs_agent_runner.sh --if-due\n' "$INSTALL_DIR" "$INSTALL_DIR" > "$fixture/cron-jobs"
crontab() { if [ "${1:-}" = -l ]; then cat "$fixture/cron-jobs"; else cat > "$fixture/cron-jobs"; fi; }
ensure_update_polling
! grep -q '^\*/30 ' "$fixture/cron-jobs"
grep -q '^\* \* \* \* \* /bin/bash ' "$fixture/cron-jobs"
grep -Fxq '15 2 * * * echo unrelated' "$fixture/cron-jobs"
grep -q '^@reboot ' "$fixture/cron-jobs"
# An updater exec must reuse the inherited lock, not deadlock itself.
. <(sed -n '/^acquire_execution_lock() {/,/^}/p' rs_agent.sh)
LOCK_FILE="$fixture/update.lock"
EXECUTION_TRIGGER=fixture
export LOCK_FILE EXECUTION_TRIGGER
export -f acquire_execution_lock t
(
    exec 9>"$LOCK_FILE"
    flock -n 9
    bash -c 'acquire_execution_lock'
)
echo 'PASS: public catalog, hourly deadline, boot recovery, progressive retries, opt-out, pinned four-file update and mismatched package rejection.'
