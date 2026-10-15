# Reinstallation with an available seat

The Linux installer validates the existing UUID, platform and machine identity,
then calls the HTTPS Firulai `/api/agents/activate` endpoint with `checkOnly: true`.
An uncovered registration is not rejected just because coverage was released.

Before writing installation files, the installer requests activation with
`checkOnly: false`. The backend rechecks capacity under the account registration
lock, assigns coverage and marks the existing system `Agente instalado`. It does
not replace the UUID, inventory, scan dates or historical relations.

HTTP 409 means no seat is available. Missing authorization, unavailable backend,
redirects, timeouts and missing confirmation all stop installation. There is no
fallback to an asynchronous activation that could bypass account admission.

Deployment order: publish the Firulai admission backend first, verify its health
and authorization response, then publish `install.sh` on main. Existing agents
remain Linux 0.4.6; this change affects installation, not the running agent.

Validation: `bash scripts/test_installation_admission.sh`,
`bash scripts/test_uuid_reservation_validation.sh` and
`bash scripts/test_local_agent_preflight.sh`.
