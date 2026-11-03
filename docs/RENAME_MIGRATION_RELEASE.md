# Firulai Security Agent 0.4.13: migration release

The currently installed Linux updater downloads four exact paths from the tag:
`rs_agent.sh`, `rs_agent_runner.sh`, `api_endpoint.sh`, and `uninstall.sh`.
The first two remain in the published tag as compatibility entries. They
migrate the installation to `firulaiAgent`; they are removed from a migrated
machine. A new installation downloads `firulaiAgent.sh` and
`firulaiAgent_runner.sh` directly.

## Release sequence

1. Test against the currently published root and user agents on disposable
   Linux hosts, with systemd and cron. Verify identity, state, scheduled runs,
   failure recovery, and the absence of old active units and paths.
2. Commit and push the code. Create and push tag `0.4.13` pointing to that
   commit. Confirm that `AGENT_VERSION` in both `firulaiAgent.sh` and
   `rs_agent.sh`, and `INSTALLER_AGENT_VERSION` in `install.sh`, all match.
3. Create the GitHub Release for `0.4.13`. Linux scripts are not signed by the
   Windows signing workflow. Verify all six tag paths are accessible through
   `raw.githubusercontent.com/Redsauce/firulai-linux-agent/0.4.13/`.
4. After validating the tag, change the Firulai catalog Linux version to
   `0.4.13`. An installed agent then downloads the compatibility entries,
   migrates, and uses the renamed updater for later releases.

Future Linux tags offered by the current global catalog must retain the two
compatibility entries and update their `AGENT_VERSION` to that tag. Otherwise
an offline old agent that skips 0.4.13 cannot update automatically.
