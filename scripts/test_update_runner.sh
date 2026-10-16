#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
mkdir -p "$fixture/bin" "$fixture/install" "$fixture/data"
export RS_AGENT_INSTALL_DIR="$fixture/install" RS_AGENT_DATA_DIR="$fixture/data" RS_AGENT_LOG_FILE="$fixture/log"
export FIXTURE="$fixture"
cat > "$fixture/bin/date" <<'MOCK'
#!/bin/bash
case "$*" in
    +%s) echo 2051258400 ;;
    +%F) echo 2035-01-01 ;;
    *) /bin/date "$@" ;;
esac
MOCK
cat > "$fixture/install/rs_agent.sh" <<'MOCK'
#!/bin/bash
if [ "$1" = --check-updates ]; then echo update >> "$FIXTURE/calls"; exit 0; fi
echo inventory >> "$FIXTURE/calls"
exit 1
MOCK
chmod +x "$fixture/bin/date" "$fixture/install/rs_agent.sh"
export PATH="$fixture/bin:$PATH"
printf "AGENT_TOKEN='test'\nUUID='00000000-0000-4000-8000-000000000001'\n" > "$fixture/data/config.env"
# A failed upload schedules its own 30-minute retry.
! bash rs_agent_runner.sh --if-due >/dev/null 2>&1
grep -Fxq NEXT_INVENTORY_EPOCH=2051260200 "$fixture/data/inventory-retry.env"
# Subsequent minute ticks continue update checks, without retrying inventory early.
bash rs_agent_runner.sh --if-due >/dev/null 2>&1
[ "$(grep -c '^update$' "$fixture/calls")" = 2 ]
[ "$(grep -c '^inventory$' "$fixture/calls")" = 1 ]
# Even a completed daily inventory must not suppress update checks.
printf 'LAST_SUCCESS_EPOCH=2051258400\n' > "$fixture/data/state.env"
bash rs_agent_runner.sh --if-due >/dev/null 2>&1
[ "$(grep -c '^update$' "$fixture/calls")" = 3 ]
[ "$(grep -c '^inventory$' "$fixture/calls")" = 1 ]
echo 'PASS: update checks survive completed inventory and inventory failures; upload retries wait 30 minutes.'
