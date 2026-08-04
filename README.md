# Firulai Inventory Agent

Linux system analysis agent for vulnerability detection. It collects system information, installed packages, and relevant software data, then sends the inventory to Firulai/RSM.

## No-Root Installation

The external command remains the same shape as the UI-provided installer command:

```bash
curl -fsSL https://raw.githubusercontent.com/Redsauce/firulai-linux-agent/main/install.sh | bash -s -- <AGENT_TOKEN> <UUID> --alias <ALIAS>
```

If the installer is run as a regular user, it installs only for that user. If it is run as root, it asks whether to continue as a root/system install or re-run as a no-root user.

## No-Root Paths

By default, user-mode installation uses:

| Path | Description |
|------|-------------|
| `${XDG_DATA_HOME:-~/.local/share}/rs-agent/rs_agent.sh` | Main agent |
| `${XDG_DATA_HOME:-~/.local/share}/rs-agent/rs_agent_runner.sh` | Automatic runner |
| `${XDG_DATA_HOME:-~/.local/share}/rs-agent/uninstall.sh` | Uninstaller |
| `${XDG_STATE_HOME:-~/.local/state}/rs-agent/config.env` | Token, UUID, and alias |
| `${XDG_STATE_HOME:-~/.local/state}/rs-agent/inventory.json` | Last inventory |
| `${XDG_STATE_HOME:-~/.local/state}/rs-agent/state.env` | Last successful run |
| `${XDG_STATE_HOME:-~/.local/state}/rs-agent/rs-agent.log` | Log file |

Paths can be overridden with `RS_AGENT_INSTALL_DIR`, `RS_AGENT_DATA_DIR`, `RS_AGENT_LOG_FILE`, and `RS_AGENT_TMP_DIR`.

## Automatic Execution

The inventory is scheduled for `03:00` local time.

In no-root mode, the installer asks whether to use user cron or `systemd --user`.

User cron:

- Does not require root for the user crontab.
- Does not depend on an active user session.
- Requires cron/crontab installed, active, and allowed. If not, installation/activation will be attempted, requiring the root/admin password.
- If system policies block user crontabs, the automatic install cannot continue and the user is told to contact Firulai or the administrator.

```bash
crontab -l | grep rs_agent_runner
```

`systemd --user`:

- Better integration with systemd.
- Better visibility through `systemctl --user`.
- Requires linger to run without an active session. If it is not active, it will be enabled, requiring the root/admin password.

```bash
systemctl --user status rs-agent.timer
systemctl --user list-timers rs-agent.timer
```

If there is no interactive terminal, the installer uses user cron by default and validates its requirements before completing the installation.

## Manual Run

```bash
bash ~/.local/share/rs-agent/rs_agent.sh --token <AGENT_TOKEN> --uuid <UUID> --alias <ALIAS>
```

## Uninstall No-Root Instance

```bash
bash ~/.local/share/rs-agent/uninstall.sh
```

The no-root uninstaller only removes the current user's installation. It does not touch `/opt/rs-agent`, `/var/lib/rs-agent`, global systemd units, or an existing root installation.

## Collected Data

The agent generates a JSON inventory with:

- `system`: hostname, FQDN, UUID, alias, distribution, kernel, architecture, timezone, and agent version.
- `hardware`: CPU model and visible disks through `lscpu` and `lsblk`.
- `components`: `dpkg`, `rpm`, `pip`, and `npm` components when available to the user.
- `packages`: source packages derived from `dpkg-query` on Debian/Ubuntu.

On a normal Debian/Ubuntu system, an unprivileged user should be able to list packages with `dpkg-query`. Differences from root mode are expected mainly in restricted commands, inaccessible paths, Python/Node packages visible through `PATH`, or hardware information restricted by the environment.

## Comparing Root And No-Root Results

For a server that already has the root agent:

1. Keep the existing root installation untouched.
2. Create a normal test user without sudo or special groups.
3. Create a separate test UUID/alias in Firulai/RSM.
4. Log in as that user and run the no-root installer.
5. Compare the root inventory with the no-root inventory locally and in RSM.
6. Review counts for `dpkg`, `rpm`, `pip`, `npm`, hardware, and empty fields.

Useful commands:

```bash
id
dpkg-query -W | wc -l
cat ~/.local/state/rs-agent/inventory.json
grep -o '"manager":"dpkg"' ~/.local/state/rs-agent/inventory.json | wc -l
grep -o '"manager":"pip"' ~/.local/state/rs-agent/inventory.json | wc -l
grep -o '"manager":"npm"' ~/.local/state/rs-agent/inventory.json | wc -l
```

## Requirements

- Linux
- bash 4+
- curl
- `mktemp`
- `flock` (`util-linux`)
- `systemd --user` or `cron` for automatic execution
