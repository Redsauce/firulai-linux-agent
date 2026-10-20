#!/bin/bash
# Actual root entrypoint and file cleanup in a disposable chroot. Only network,
# scheduler commands and polling time are simulated. Requires musl-based WSL.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
[ "$(id -u)" = 0 ] || { echo 'Requires root for chroot'; exit 1; }
workspace=$(mktemp -d /tmp/firulai-root-test.XXXXXX)
cleanup() {
    case "$workspace" in /tmp/firulai-root-test.?*) rm -rf -- "$workspace" ;; *) exit 1 ;; esac
}
trap cleanup EXIT
for scenario in missing denied offline; do
    jail="$workspace/$scenario"
    mkdir -p "$jail"/{bin,usr/bin,usr/lib,lib,dev,etc/systemd/system,opt/rs-agent,var/lib/rs-agent,var/log,run/lock,tmp,harness}
    for binary in /bin/bash /bin/busybox /usr/bin/flock /lib/ld-musl-x86_64.so.1 /usr/lib/libreadline.so.7 /usr/lib/libncursesw.so.6; do
        cp -L "$binary" "$jail$binary"
    done
    ln -s ld-musl-x86_64.so.1 "$jail/lib/libc.musl-x86_64.so.1"
    for applet in cat chmod chown cp dirname grep hostname id mkdir mktemp mv rm sed stat tail tr wc; do
        ln -s busybox "$jail/bin/$applet"
    done
    : > "$jail/dev/null"
    printf 'root:x:0:0:root:/:/bin/bash\n' > "$jail/etc/passwd"
    printf 'root:x:0:\n' > "$jail/etc/group"
    cp "$repo/uninstall.sh" "$repo/api_endpoint.sh" "$jail/opt/rs-agent/"
    printf 'fixture collector\n' > "$jail/opt/rs-agent/rs_agent.sh"
    cat > "$jail/var/lib/rs-agent/config.env" <<'CONFIG'
AGENT_TOKEN='fixture-token'
UUID='11111111-2222-4333-8444-555555555555'
RSM_BASE_URL='https://fixture.invalid/'
AGENT_LOCALE='en_US'
CONFIG
    chmod 600 "$jail/var/lib/rs-agent/config.env"
    printf 'fixture unit\n' > "$jail/etc/systemd/system/rs-agent.service"
    printf 'fixture unit\n' > "$jail/etc/systemd/system/rs-agent.timer"
    printf 'fixture log\n' > "$jail/var/log/rs-agent.log"
    printf 'unrelated inventory history\n' > "$jail/harness/other-system"
    printf '* * * * * /opt/rs-agent/rs_agent_runner.sh\n0 0 * * * unrelated-backup\n' > "$jail/harness/crontab"
    printf '%s' "$scenario" > "$jail/harness/scenario"
    cat > "$jail/bin/systemctl" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >> /harness/systemctl.calls
SCRIPT
    cat > "$jail/bin/crontab" <<'SCRIPT'
#!/bin/bash
if [ "${1:-}" = -l ]; then
    cat /harness/crontab
else
    cat > /harness/crontab.new
    mv /harness/crontab.new /harness/crontab
fi
SCRIPT
    cat > "$jail/bin/sleep" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT
    cat > "$jail/bin/curl" <<'SCRIPT'
#!/bin/bash
set -eu
url='' output='' authorized=0
while [ $# -gt 0 ]; do
    case "$1" in
        --output) output="$2"; shift ;;
        --header) [ "$2" != 'Authorization: fixture-token' ] || authorized=1; shift ;;
        https://*) url="$1" ;;
    esac
    shift
done
[ "$authorized" = 1 ] || exit 97
printf '%s\n' "$url" >> /harness/http.calls
scenario=$(cat /harness/scenario)
[ "$scenario" != offline ] || exit 7
case "$url" in
    https://fixture.invalid/commands_RSM/api/api.php)
        printf '{"queued":true}' > "$output"
        printf '200\n' ;;
    https://fixture.invalid/commands_RSM/api/v2/items/get.php)
        printf '{}\n200' ;;
    https://firulai.redsauce.net/api/agents/uninstall/missing-system)
        if [ "$scenario" = missing ]; then
            printf '{"missing":true,"verified":true}\n200'
        else
            printf '{"error":"forbidden"}\n403'
        fi ;;
    *) exit 98 ;;
esac
SCRIPT
    chmod +x "$jail/bin/"{curl,crontab,systemctl,sleep}
    [ "$(chroot "$jail" /bin/id -u)" = 0 ]
    result=0
    printf 'y\n' | chroot "$jail" /bin/bash /opt/rs-agent/uninstall.sh > "$workspace/$scenario.log" 2>&1 || result=$?
    # Every unexpected tool failure is a test failure, even on rejection paths.
    if grep -Eq 'command not found|No such file or directory|unrecognized option' "$workspace/$scenario.log"; then
        cat "$workspace/$scenario.log"; exit 1
    fi
    if [ "$scenario" = missing ]; then
        [ "$result" = 0 ] || { cat "$workspace/$scenario.log"; exit 1; }
        for path in opt/rs-agent var/lib/rs-agent var/log/rs-agent.log etc/systemd/system/rs-agent.service etc/systemd/system/rs-agent.timer; do
            [ ! -e "$jail/$path" ] || { echo "Unexpected retained path: $path"; exit 1; }
        done
        grep -q '^disable --now rs-agent.timer$' "$jail/harness/systemctl.calls"
        ! grep -q /opt/rs-agent "$jail/harness/crontab"
        grep -q '/uninstall/missing-system$' "$jail/harness/http.calls"
    else
        [ "$result" != 0 ]
        cmp "$repo/uninstall.sh" "$jail/opt/rs-agent/uninstall.sh"
        [ -f "$jail/var/lib/rs-agent/config.env" ]
        [ -f "$jail/etc/systemd/system/rs-agent.timer" ]
        [ -f "$jail/var/log/rs-agent.log" ]
        [ ! -e "$jail/harness/systemctl.calls" ]
        grep -q /opt/rs-agent "$jail/harness/crontab"
    fi
    [ "$(cat "$jail/harness/other-system")" = 'unrelated inventory history' ]
    grep -q '^0 0 \* \* \* unrelated-backup$' "$jail/harness/crontab"
    printf 'PASS root chroot: %s (exit=%s; unrelated history/cron preserved)\n' "$scenario" "$result"
done
