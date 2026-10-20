# Root missing-System validation, 2026-10-20

Command: `bash tests/uninstallation-root-missing-system.Tests.sh` in root WSL.

All three scenarios passed using the current working-tree uninstaller and API
helper, copied without modifications into disposable chroots. The production
entrypoint, root detection (`id -u = 0`), util-linux flock and filesystem removal
ran directly. HTTP responses, systemctl, crontab and polling sleeps were simulated.
No real credentials, RSM records or monitored installations were used.

| Scenario | Exit | Result |
| --- | --- | --- |
| Empty System lookup, independently verified missing | 0 | Installation, local state, log and own systemd files removed; own cron removed |
| Empty System lookup, independent verification denied (403) | 1 | Uninstaller unchanged; config, timer, log and cron retained; no systemctl cleanup |
| Transport offline (curl exit 7) | 1 | Uninstaller unchanged; config, timer, log and cron retained; no systemctl cleanup |

An unrelated history sentinel and unrelated cron entry survived every scenario.
Temporary chroots were removed after completion. This validates isolated root
behavior, not a live Proxmox-to-RSM integration or the published release binary.
