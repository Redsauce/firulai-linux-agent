# Feature Specification: System Timezone Inventory

**Feature Branch**: `main`
**Created**: 2026-07-07
**Status**: Draft
**Input**: User description: "El agente debe poner la timezone del sistema y, si no hay nada en el sistema, usar por defecto Europe/Madrid."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Send The Host Timezone (Priority: P1)

An installed Linux inventory agent reports the host's configured IANA timezone in the system inventory payload, so Firulai/RSM can know which timezone belongs to the collected machine.

**Why this priority**: Inventory data should describe the real host environment. Timezone is part of that environment and should not depend on the browser or the Firulai user preference.

**Independent Test**: Run the agent on a Linux host where `timedatectl show -p Timezone --value` returns `Europe/Paris`; verify the outbound system JSON includes `"timezone_name":"Europe/Paris"`.

**Acceptance Scenarios**:

1. **Given** a host exposes a non-empty timezone through `timedatectl`, **When** the agent builds the system payload, **Then** `timezone_name` contains that trimmed value.
2. **Given** `timedatectl` is unavailable or returns an empty value, **When** `/etc/timezone` contains a non-empty value, **Then** `timezone_name` contains the trimmed `/etc/timezone` value.
3. **Given** neither `timedatectl` nor `/etc/timezone` provides a value, **When** the agent builds the system payload, **Then** `timezone_name` is `Europe/Madrid`.
4. **Given** the timezone value contains leading or trailing whitespace, **When** the agent serializes the payload, **Then** the whitespace is removed before sending.

### User Story 2 - Keep The Field Reliable (Priority: P1)

Firulai receives a `timezone_name` field that is always present for current agents, so downstream processing does not need to guess whether the agent forgot to collect it.

**Why this priority**: Empty or missing fields create inconsistent host records and make the default behavior ambiguous.

**Independent Test**: Run the agent in an environment without `timedatectl` and without `/etc/timezone`; verify the system payload still includes `"timezone_name":"Europe/Madrid"`.

**Acceptance Scenarios**:

1. **Given** timezone discovery fails, **When** the agent sends inventory, **Then** the field is present and non-empty.
2. **Given** the selected timezone contains JSON-significant characters, **When** the agent serializes the payload, **Then** it is JSON-escaped like every other string field.
3. **Given** the agent logs collection progress, **When** timezone collection finishes, **Then** the log includes the selected timezone value.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The Linux inventory agent MUST include a top-level `timezone_name` string in the system inventory JSON payload.
- **FR-002**: `timezone_name` MUST contain the host system timezone when the host exposes one.
- **FR-003**: The agent MUST first try `timedatectl show -p Timezone --value` to collect the timezone.
- **FR-004**: If `timedatectl` is unavailable, fails, or returns an empty value, the agent MUST read `/etc/timezone` as a fallback.
- **FR-005**: The agent MUST trim leading and trailing whitespace from whichever timezone value it collects.
- **FR-006**: If no system timezone value is available after those checks, the agent MUST set `timezone_name` to `Europe/Madrid`.
- **FR-007**: The agent MUST NOT send an empty `timezone_name` value in current-version inventory payloads.
- **FR-008**: The agent MUST JSON-escape `timezone_name` consistently with other string fields before sending it.
- **FR-009**: The agent MUST log the final timezone value selected for the run.
- **FR-010**: The fallback to `Europe/Madrid` is an agent-side default only; it MUST NOT require reading an RSM user preference or a Firulai browser preference.
- **FR-011**: User application preferences, including Firulai's user-selected display timezone, MUST remain separate from this host inventory timezone.
- **FR-012**: Agent version `0.3.4` and later MUST implement this `timezone_name` behavior.

### Collection Order

| Priority | Source | Behavior |
| --- | --- | --- |
| 1 | `timedatectl show -p Timezone --value` | Use when command succeeds and returns a non-empty value |
| 2 | `/etc/timezone` | Use when the file exists and contains a non-empty value |
| 3 | Agent default | Use `Europe/Madrid` |

### Key Entities

- **System Timezone**: The IANA timezone configured on the monitored Linux host.
- **`timezone_name`**: Top-level string field in the system inventory payload.
- **Agent Default Timezone**: `Europe/Madrid`, used only when the host does not expose a timezone.
- **Firulai User Timezone Preference**: Per-user display preference in Firulai/RSM; it is not the same thing as the host inventory timezone.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In 100% of runs where `timedatectl` returns a non-empty timezone, the payload contains that exact trimmed value.
- **SC-002**: In 100% of runs where `timedatectl` has no value and `/etc/timezone` has one, the payload contains the trimmed file value.
- **SC-003**: In 100% of runs where neither source provides a value, the payload contains `Europe/Madrid`.
- **SC-004**: In 100% of current-agent payloads, `timezone_name` is present and non-empty.

## Assumptions

- Supported hosts use IANA timezone identifiers when they expose timezone configuration.
- Legacy payloads from older agents may not include `timezone_name`; downstream compatibility for those payloads is outside this agent spec.
- Firulai user display timezone behavior is defined by the web app specs and does not override the host inventory timezone reported by the agent.
