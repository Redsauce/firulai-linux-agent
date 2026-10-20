#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
for mode in 0 1; do
    for failure in data install log backup; do
        (
            export RS_AGENT_INSTALL_DIR="$fixture/$mode-$failure/install"
            export RS_AGENT_DATA_DIR="$fixture/$mode-$failure/data"
            export RS_AGENT_LOG_FILE="$fixture/$mode-$failure/log"
            RS_AGENT_UNINSTALL_LIBRARY_ONLY=1 source "$root/uninstall.sh"
            RUN_AS_ROOT="$mode"
            mkdir -p "$INSTALL_DIR" "$DATA_DIR"
            cp "$root/uninstall.sh" "$root/api_endpoint.sh" "$INSTALL_DIR/"
            printf 'AGENT_TOKEN=fixture-token\nUUID=550e8400-e29b-41d4-a716-446655440000\n' > "$CONFIG_FILE"
            chmod 600 "$CONFIG_FILE"
            cp "$CONFIG_FILE" "$fixture/expected-$mode-$failure"
            touch "$LOG_FILE"
            load_config
            rm() {
                local target="${!#}"
                case "$failure:$target" in
                    "data:$DATA_DIR") command rm -f "$CONFIG_FILE"; return 1 ;;
                    "install:$INSTALL_DIR") command rm -f "$INSTALL_DIR/uninstall.sh" "$INSTALL_DIR/api_endpoint.sh"; return 1 ;;
                    "log:$LOG_FILE") return 1 ;;
                esac
                command rm "$@"
            }
            cp() {
                [ "$failure" != backup ] || return 1
                command cp "$@"
            }
            if remove_local_files > /dev/null 2>&1; then echo 'Partial cleanup reported success' >&2; exit 1; fi
            test -f "$INSTALL_DIR/uninstall.sh"
            test -f "$INSTALL_DIR/api_endpoint.sh"
            cmp "$CONFIG_FILE" "$fixture/expected-$mode-$failure"
            test "$(stat -c %a "$CONFIG_FILE")" = 600
            unset -f rm cp
            # Actual retry with the restored files/configuration: no remote writes,
            # no scheduling changes and no installed host agent involved.
            remove_local_files > /dev/null
            test ! -e "$INSTALL_DIR"
            test ! -e "$DATA_DIR"
            test ! -e "$LOG_FILE"
        )
    done
done
echo 'PASS: root/user partial data, installer and log removal preserve private retry essentials; retry completes.'
echo 'PASS: failed recovery backup prevents deletion of the original installation.'
