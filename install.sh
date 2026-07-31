#!/bin/bash
# ============================================================================
# Firulai Inventory Agent - One-liner installer
# Version 0.2.4 - Missed execution recovery with systemd/cron
# ============================================================================
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Redsauce/firulai-linux-agent/experiment/non-root-install-from-main/install.sh | bash -s -- <AGENT_TOKEN> <UUID> --alias <ALIAS>
#

set -e

# ============================================================================
# PARAMETERS
# ============================================================================

AGENT_TOKEN=${1:-""}
UUID=${2:-""}
SYSTEM_ALIAS=""
SCHEDULER_CHOICE="${RS_AGENT_SCHEDULER:-}"

if [ -z "$AGENT_TOKEN" ] || [ -z "$UUID" ]; then
    echo "[ERROR] Usage: curl ... | bash -s -- <AGENT_TOKEN> <UUID> --alias <ALIAS>"
    exit 1
fi

shift 2
while [ $# -gt 0 ]; do
    case "$1" in
        --alias)
            if [ $# -lt 2 ]; then
                echo "[ERROR] --alias requires a value"
                exit 1
            fi
            SYSTEM_ALIAS="$2"
            shift 2
            ;;
        *)
            echo "[ERROR] Unknown argument: $1"
            echo "[ERROR] Usage: curl ... | bash -s -- <AGENT_TOKEN> <UUID> --alias <ALIAS>"
            exit 1
            ;;
    esac
done

if [ -n "$SCHEDULER_CHOICE" ]; then
    case "$SCHEDULER_CHOICE" in
        cron|systemd-user) ;;
        *)
            echo "[ERROR] RS_AGENT_SCHEDULER must be: cron or systemd-user"
            exit 1
            ;;
    esac
fi

# ============================================================================
# CONFIGURATION
# ============================================================================

# GitHub URL where the agent is hosted. In this experimental branch it points to
# the same branch to test no-root installation without mixing it with main.
GITHUB_RAW_URL="${RS_AGENT_GITHUB_RAW_URL:-https://raw.githubusercontent.com/Redsauce/firulai-linux-agent/experiment/non-root-install-from-main}"

RUN_AS_ROOT=0
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    RUN_AS_ROOT=1
fi

early_trim_string() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

early_shell_single_quote() {
    printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

early_user_linger_enabled_for() {
    local username="$1"
    command -v loginctl >/dev/null 2>&1 || return 1
    [ "$(loginctl show-user "$username" -p Linger --value 2>/dev/null || true)" = "yes" ]
}

early_user_runtime_dir_for() {
    local username="$1"
    local user_uid
    user_uid=$(id -u "$username" 2>/dev/null) || return 1
    printf '/run/user/%s' "$user_uid"
}

early_wait_for_user_systemd_bus_for() {
    local username="$1"
    local runtime_dir attempts=0
    runtime_dir=$(early_user_runtime_dir_for "$username") || return 1

    while [ "$attempts" -lt 10 ]; do
        [ -S "$runtime_dir/bus" ] && return 0
        sleep 1
        attempts=$((attempts + 1))
    done

    return 1
}

early_start_user_systemd_manager_for() {
    local username="$1"
    local user_uid
    user_uid=$(id -u "$username" 2>/dev/null) || return 1

    if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
        systemctl start "user@${user_uid}.service" 2>/dev/null || true
    fi

    early_wait_for_user_systemd_bus_for "$username"
}

early_cron_daemon_active() {
    if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
        systemctl is-active --quiet cron.service 2>/dev/null && return 0
        systemctl is-active --quiet crond.service 2>/dev/null && return 0
        systemctl is-active --quiet cronie.service 2>/dev/null && return 0
    fi

    if command -v service >/dev/null 2>&1; then
        service cron status >/dev/null 2>&1 && return 0
        service crond status >/dev/null 2>&1 && return 0
    fi

    if command -v pgrep >/dev/null 2>&1; then
        pgrep -x cron >/dev/null 2>&1 && return 0
        pgrep -x crond >/dev/null 2>&1 && return 0
    fi

    return 1
}

early_cron_install_command() {
    if command -v apt-get >/dev/null 2>&1; then
        printf '%s' 'apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y cron'
        return 0
    fi

    if command -v dnf >/dev/null 2>&1; then
        printf '%s' 'dnf install -y cronie'
        return 0
    fi

    if command -v yum >/dev/null 2>&1; then
        printf '%s' 'yum install -y cronie'
        return 0
    fi

    if command -v zypper >/dev/null 2>&1; then
        printf '%s' 'zypper --non-interactive install cron'
        return 0
    fi

    return 1
}

early_cron_enable_command() {
    if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
        printf '%s' 'systemctl enable --now cron.service 2>/dev/null || systemctl enable --now crond.service 2>/dev/null || systemctl enable --now cronie.service'
        return 0
    fi

    if command -v service >/dev/null 2>&1; then
        printf '%s' 'service cron start 2>/dev/null || service crond start'
        return 0
    fi

    return 1
}

early_choose_no_root_scheduler() {
    local reply

    if [ -n "$SCHEDULER_CHOICE" ]; then
        return 0
    fi

    if [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then
        echo "[WARN] No interactive terminal detected; user cron will be used by default."
        SCHEDULER_CHOICE="cron"
        return 0
    fi

    echo "" > /dev/tty
    echo "No-root automatic execution setup:" > /dev/tty
    echo "  1) User cron" > /dev/tty
    echo "     + Does not require root for agent execution and does not depend on an active user session." > /dev/tty
    echo "     - Requires cron/crontab installed, active, and allowed." > /dev/tty
    echo "  2) systemd --user" > /dev/tty
    echo "     + Better integration with systemd and systemctl --user." > /dev/tty
    echo "     - Requires linger to run without an active session; it will be enabled now as root if needed." > /dev/tty
    printf "Choose scheduler [1=cron, 2=systemd-user] (1): " > /dev/tty
    IFS= read -r reply < /dev/tty || reply=""
    reply=$(early_trim_string "$reply")

    case "$reply" in
        ""|cron|c|1)
            SCHEDULER_CHOICE="cron"
            ;;
        systemd|systemd-user|s|2)
            SCHEDULER_CHOICE="systemd-user"
            ;;
        *)
            echo "[ERROR] Unknown scheduler: $reply" > /dev/tty
            echo "[ERROR] Use 1/cron or 2/systemd-user." > /dev/tty
            exit 1
            ;;
    esac
}

early_preconfigure_no_root_privileged_requirements() {
    local target_user="$1"

    early_choose_no_root_scheduler

    if [ "$SCHEDULER_CHOICE" = "cron" ]; then
        local cron_command

        if ! command -v crontab >/dev/null 2>&1; then
            cron_command=$(early_cron_install_command) || {
                echo "[ERROR] Could not determine how to install cron automatically on this distribution." >&2
                exit 1
            }
            echo "[INFO] Installing cron as root..."
            sh -c "$cron_command"
            if ! command -v crontab >/dev/null 2>&1; then
                echo "[ERROR] cron/crontab is still not available after installation." >&2
                exit 1
            fi
        fi

        if ! early_cron_daemon_active; then
            cron_command=$(early_cron_enable_command) || {
                echo "[ERROR] Could not determine how to enable cron automatically on this distribution." >&2
                exit 1
            }
            echo "[INFO] Enabling cron as root..."
            sh -c "$cron_command"
            if ! early_cron_daemon_active; then
                echo "[ERROR] cron does not appear to be active after enabling it." >&2
                exit 1
            fi
        fi
    elif [ "$SCHEDULER_CHOICE" = "systemd-user" ]; then
        if ! command -v loginctl >/dev/null 2>&1; then
            echo "[ERROR] loginctl is required to enable linger for systemd --user." >&2
            exit 1
        fi

        if early_user_linger_enabled_for "$target_user"; then
            echo "[OK] linger is already enabled for $target_user"
        else
            echo "[INFO] Enabling linger for $target_user as root..."
            loginctl enable-linger "$target_user"
            if ! early_user_linger_enabled_for "$target_user"; then
                echo "[ERROR] Could not enable linger for $target_user." >&2
                exit 1
            fi
            echo "[OK] linger enabled for $target_user"
        fi

        echo "[INFO] Starting systemd user manager for $target_user..."
        if ! early_start_user_systemd_manager_for "$target_user"; then
            echo "[ERROR] systemd user bus was not available for $target_user after enabling linger." >&2
            exit 1
        fi
        echo "[OK] systemd user manager is available for $target_user"
    fi
}

reexec_as_no_root_user() {
    local target_user="$1"
    local command_string

    if ! id "$target_user" >/dev/null 2>&1; then
        echo "[ERROR] User does not exist: $target_user"
        exit 1
    fi

    if [ "$(id -u "$target_user")" -eq 0 ]; then
        echo "[ERROR] The selected no-root user cannot be root."
        exit 1
    fi

    early_preconfigure_no_root_privileged_requirements "$target_user"

    local target_uid target_runtime_dir
    target_uid=$(id -u "$target_user")
    target_runtime_dir="/run/user/$target_uid"

    command_string="export RS_AGENT_SCHEDULER=$(early_shell_single_quote "$SCHEDULER_CHOICE"); export XDG_RUNTIME_DIR=$(early_shell_single_quote "$target_runtime_dir"); export DBUS_SESSION_BUS_ADDRESS=$(early_shell_single_quote "unix:path=$target_runtime_dir/bus"); curl -fsSL $(early_shell_single_quote "$GITHUB_RAW_URL/install.sh") | bash -s -- $(early_shell_single_quote "$AGENT_TOKEN") $(early_shell_single_quote "$UUID")"
    if [ -n "$SYSTEM_ALIAS" ]; then
        command_string="$command_string --alias $(early_shell_single_quote "$SYSTEM_ALIAS")"
    fi

    echo "[INFO] Re-running installer as no-root user: $target_user"
    exec su - "$target_user" -c "$command_string"
}

choose_install_mode_if_root() {
    local mode_reply target_user

    [ "$RUN_AS_ROOT" = "1" ] || return 0

    if [ -n "${RS_AGENT_INSTALL_MODE:-}" ]; then
        case "$RS_AGENT_INSTALL_MODE" in
            root) return 0 ;;
            no-root)
                target_user="${RS_AGENT_TARGET_USER:-${SUDO_USER:-}}"
                if [ -z "$target_user" ] || [ "$target_user" = "root" ]; then
                    echo "[ERROR] RS_AGENT_TARGET_USER is required for no-root mode when running as root."
                    exit 1
                fi
                reexec_as_no_root_user "$target_user"
                ;;
            *)
                echo "[ERROR] RS_AGENT_INSTALL_MODE must be root or no-root"
                exit 1
                ;;
        esac
    fi

    if [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then
        echo "[WARN] Running as root without an interactive terminal; continuing with root/system install."
        return 0
    fi

    echo "" > /dev/tty
    echo "Installation mode:" > /dev/tty
    echo "  1) Root/system install: uses /opt, /var/lib, system services; requires root." > /dev/tty
    echo "  2) No-root user install: installs under a regular user's home and configures privileged prerequisites before switching user." > /dev/tty
    printf "Choose install mode [1=root, 2=no-root] (1): " > /dev/tty
    IFS= read -r mode_reply < /dev/tty || mode_reply=""
    mode_reply=$(early_trim_string "$mode_reply")

    case "$mode_reply" in
        ""|1|root|r)
            return 0
            ;;
        2|no-root|user|u)
            target_user="${SUDO_USER:-}"
            if [ -z "$target_user" ] || [ "$target_user" = "root" ]; then
                printf "Target no-root user: " > /dev/tty
                IFS= read -r target_user < /dev/tty || target_user=""
                target_user=$(early_trim_string "$target_user")
            else
                printf "Target no-root user (%s): " "$target_user" > /dev/tty
                local target_reply=""
                IFS= read -r target_reply < /dev/tty || target_reply=""
                target_reply=$(early_trim_string "$target_reply")
                [ -n "$target_reply" ] && target_user="$target_reply"
            fi

            if [ -z "$target_user" ]; then
                echo "[ERROR] A target no-root user is required." > /dev/tty
                exit 1
            fi
            reexec_as_no_root_user "$target_user"
            ;;
        *)
            echo "[ERROR] Unknown install mode: $mode_reply" > /dev/tty
            exit 1
            ;;
    esac
}

choose_install_mode_if_root

# Installation directories
if [ "$RUN_AS_ROOT" = "1" ]; then
    INSTALL_DIR="${RS_AGENT_INSTALL_DIR:-/opt/rs-agent}"
    DATA_DIR="${RS_AGENT_DATA_DIR:-/var/lib/rs-agent}"
    LOG_FILE="${RS_AGENT_LOG_FILE:-/var/log/rs-agent.log}"
    PRIVATE_TMP_DIR="${RS_AGENT_TMP_DIR:-/run/rs-agent/tmp}"
    SYSTEMD_SERVICE_FILE="/etc/systemd/system/rs-agent.service"
    SYSTEMD_TIMER_FILE="/etc/systemd/system/rs-agent.timer"
    SYSTEMD_USER_DIR=""
    SYSTEMD_USER_SERVICE_FILE=""
    SYSTEMD_USER_TIMER_FILE=""
else
    INSTALL_DIR="${RS_AGENT_INSTALL_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/rs-agent}"
    DATA_DIR="${RS_AGENT_DATA_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/rs-agent}"
    LOG_FILE="${RS_AGENT_LOG_FILE:-$DATA_DIR/rs-agent.log}"
    PRIVATE_TMP_DIR="${RS_AGENT_TMP_DIR:-${XDG_RUNTIME_DIR:-$DATA_DIR}/rs-agent/tmp}"
    SYSTEMD_SERVICE_FILE=""
    SYSTEMD_TIMER_FILE=""
    SYSTEMD_USER_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
    SYSTEMD_USER_SERVICE_FILE="$SYSTEMD_USER_DIR/rs-agent.service"
    SYSTEMD_USER_TIMER_FILE="$SYSTEMD_USER_DIR/rs-agent.timer"
fi
CONFIG_FILE="$DATA_DIR/config.env"
RUNNER_FILE="$INSTALL_DIR/rs_agent_runner.sh"
SCHEDULER_TYPE=""

# RSM System lookup
RSM_ITEMS_GET_URL="https://rsm1.redsauce.net/AppController/commands_RSM/api/v2/items/get.php"
RSM_ITEMS_UPDATE_URL="https://rsm1.redsauce.net/AppController/commands_RSM/api/v2/items/update.php"
RSM_SYSTEM_HOSTNAME_PROPERTY_ID="1749"
RSM_SYSTEM_FQDN_PROPERTY_ID="1750"
RSM_SYSTEM_UUID_PROPERTY_ID="1780"
RSM_SYSTEM_HOSTNAME_STATUS_PROPERTY_ID="1751"
RSM_SYSTEM_ALIAS_PROPERTY_ID="1827"
RSM_SYSTEM_HOSTNAME_STATUS_ACTIVE_VALUE="Activo"
RSM_SYSTEM_ITEM_ID=""

# ============================================================================
# COLORES
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================================
# FUNCIONES
# ============================================================================

log() {
    echo -e "${GREEN}[OK]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

ensure_private_directory() {
    local directory="$1"

    if [ -L "$directory" ]; then
        error "Unsafe path: $directory is a symbolic link"
        return 1
    fi

    mkdir -p "$directory"

    if [ -L "$directory" ] || [ ! -d "$directory" ]; then
        error "Could not create a secure private directory: $directory"
        return 1
    fi

    chown root:root "$directory" 2>/dev/null || true
    chmod 700 "$directory"

    if [ ! -O "$directory" ]; then
        error "Unsafe directory: $directory is not owned by the current user"
        return 1
    fi
}

init_private_tmp_dir() {
    ensure_private_directory "$(dirname "$PRIVATE_TMP_DIR")"
    ensure_private_directory "$PRIVATE_TMP_DIR"
}

make_private_temp_file() {
    local prefix="$1"
    mktemp "$PRIVATE_TMP_DIR/${prefix}.XXXXXX"
}

banner() {
    echo ""
    echo "============================================================================"
    echo "  Firulai Inventory Agent - Installer v0.2.4"
    echo "  System analysis agent for vulnerability detection"
    echo "============================================================================"
    echo ""
}

check_root() {
    if [ "$RUN_AS_ROOT" = "1" ]; then
        warn "Root/system installation mode selected; system paths will be used."
    else
        info "No-root installation mode selected; the agent will be installed only for the current user."
        warn "The inventory may be less complete than root mode if the system restricts some commands."
    fi
}

trim_string() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

shell_single_quote() {
    printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

require_system_alias() {
    SYSTEM_ALIAS=$(trim_string "$SYSTEM_ALIAS")

    if [ -z "$SYSTEM_ALIAS" ]; then
        if [ -r /dev/tty ]; then
            echo ""
            info "This installer needs an alias to identify the system in Firulai."
            printf "System alias: " > /dev/tty
            IFS= read -r SYSTEM_ALIAS < /dev/tty || SYSTEM_ALIAS=""
            SYSTEM_ALIAS=$(trim_string "$SYSTEM_ALIAS")
        fi
    fi

    if [ -z "$SYSTEM_ALIAS" ]; then
        error "System alias is required."
        echo ""
        echo "Run the installer with the --alias option:"
        echo "  curl -fsSL https://raw.githubusercontent.com/Redsauce/firulai-linux-agent/experiment/non-root-install-from-main/install.sh | bash -s -- <AGENT_TOKEN> <UUID> --alias <ALIAS>"
        echo ""
        echo "If the alias contains spaces, wrap it in quotes."
        exit 1
    fi
}

prepare_systemd_user_environment() {
    local user_uid runtime_dir

    [ "$RUN_AS_ROOT" != "1" ] || return 1

    user_uid=$(id -u 2>/dev/null) || return 1
    runtime_dir="/run/user/$user_uid"

    if [ -z "${XDG_RUNTIME_DIR:-}" ] && [ -d "$runtime_dir" ]; then
        export XDG_RUNTIME_DIR="$runtime_dir"
    fi

    if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ] && [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -S "$XDG_RUNTIME_DIR/bus" ]; then
        export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
    fi

    [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -S "$XDG_RUNTIME_DIR/bus" ]
}

systemd_user_available() {
    [ "$RUN_AS_ROOT" != "1" ] || return 1
    command -v systemctl &> /dev/null || return 1
    prepare_systemd_user_environment || return 1
    systemctl --user show-environment >/dev/null 2>&1
}

user_linger_enabled() {
    [ "$RUN_AS_ROOT" != "1" ] || return 1
    command -v loginctl >/dev/null 2>&1 || return 1
    [ "$(loginctl show-user "$(id -un)" -p Linger --value 2>/dev/null || true)" = "yes" ]
}

has_interactive_tty() {
    [ -r /dev/tty ] && [ -w /dev/tty ]
}

ask_yes_no() {
    local prompt="$1"
    local reply

    has_interactive_tty || return 1
    printf "%s [y/N]: " "$prompt" > /dev/tty
    IFS= read -r reply < /dev/tty || reply=""
    case "$reply" in
        s|S|y|Y|yes|YES|si|SI) return 0 ;;
        *) return 1 ;;
    esac
}

run_privileged_command() {
    local command_string="$1"

    if [ "${EUID:-$(id -u)}" -eq 0 ]; then
        sh -c "$command_string"
        return $?
    fi

    has_interactive_tty || {
        error "No interactive terminal is available to request privileged access."
        return 1
    }

    info "This action needs privileged access."
    if command -v su >/dev/null 2>&1; then
        info "Trying root via su. su asks for the root password and requires root login to be allowed."
        if su -c "$command_string"; then
            return 0
        fi
        warn "The privileged action could not be completed with su/root."
    else
        warn "su was not found, so root access cannot be requested from this user."
    fi

    error "The privileged action was not completed. Run the installer as root and choose no-root mode, or run the required command from a root session."
    return 1
}

choose_scheduler_interactively() {
    if [ "$RUN_AS_ROOT" = "1" ] || [ -n "$SCHEDULER_CHOICE" ]; then
        return 0
    fi

    if [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then
        warn "No interactive terminal detected; user cron will be used by default."
        SCHEDULER_CHOICE="cron"
        return 0
    fi

    local reply
    echo "" > /dev/tty
    info "Automatic execution setup:"
    echo "  1) User cron" > /dev/tty
    echo "     + Does not require root and does not depend on an active user session." > /dev/tty
    echo "     - Requires cron/crontab installed, active, and allowed. If not, installation/activation will be attempted and will need privileged access." > /dev/tty
    echo "  2) systemd --user" > /dev/tty
    echo "     + Better integration with systemd and systemctl --user." > /dev/tty
    echo "     - Requires linger to run without an active session. If it is not active, it will be enabled and will need privileged access." > /dev/tty
    printf "Choose scheduler [1=cron, 2=systemd-user] (1): " > /dev/tty
    IFS= read -r reply < /dev/tty || reply=""
    reply=$(trim_string "$reply")

    case "$reply" in
        ""|cron|c|1)
            SCHEDULER_CHOICE="cron"
            ;;
        systemd|systemd-user|s|2)
            SCHEDULER_CHOICE="systemd-user"
            ;;
        *)
            error "Unknown scheduler: $reply"
            echo "Use 1/cron or 2/systemd-user." > /dev/tty
            exit 1
            ;;
    esac
}

detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
        VERSION=$VERSION_ID
    elif [ -f /etc/redhat-release ]; then
        DISTRO="rhel"
        VERSION=$(cat /etc/redhat-release | grep -oE '[0-9]+\.[0-9]+' | head -1)
    else
        DISTRO="unknown"
        VERSION="unknown"
    fi
    
    info "Distribution: $DISTRO $VERSION"
}

check_dependencies() {
    info "Checking dependencies..."

    # Verify curl (it should be available if we reached this point)
    if ! command -v curl &> /dev/null; then
        error "curl is not installed"
        exit 1
    fi
    log "curl found: $(curl --version | head -1)"

    # Verify bash 4+ (required by the agent for associative arrays)
    local bash_major
    bash_major=$(bash --version | grep -oE '[0-9]+\.[0-9]+' | head -1 | cut -d. -f1)
    if [ "${bash_major:-0}" -lt 4 ]; then
        error "bash 4 or higher is required (found: $bash_major)"
        exit 1
    fi
    log "bash ${bash_major} found"

    if ! command -v flock &> /dev/null; then
        error "flock is not installed (normally provided by the util-linux package)"
        exit 1
    fi
    log "flock found: $(command -v flock)"

    if ! command -v mktemp &> /dev/null; then
        error "mktemp is not installed"
        exit 1
    fi
    log "mktemp found: $(command -v mktemp)"
}

validate_uuid_format() {
    local uuid="$1"
    if [[ ! "$uuid" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
        error "'$uuid' is not a valid UUID"
        exit 1
    fi
}

json_extract_first_string_key() {
    local json="$1"
    local key="$2"

    printf '%s' "$json" \
        | tr -d '\n' \
        | sed 's/,"/\n"/g' \
        | sed -n "s/^.*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*$/\1/p" \
        | head -1
}

json_extract_first_scalar_key() {
    local json="$1"
    local key="$2"

    printf '%s' "$json" \
        | tr -d '\n' \
        | sed "s/\"$key\"[[:space:]]*:/\\n&/g" \
        | sed -n "s/^\"$key\"[[:space:]]*:[[:space:]]*\"\\{0,1\\}\\([^\",}]*\\).*$/\\1/p" \
        | head -1
}

json_extract_rsm_property() {
    local json="$1"
    local property_id="$2"
    local value

    value=$(json_extract_first_string_key "$json" "$property_id")
    if [ -n "$value" ]; then
        printf '%s' "$value"
        return 0
    fi

    json_extract_first_string_key "$json" "${property_id}trs"
}

local_system_hostname() {
    hostname -s 2>/dev/null || hostname 2>/dev/null || echo "unknown"
}

local_system_fqdn() {
    hostname -f 2>/dev/null || hostname 2>/dev/null || echo "unknown"
}

identity_matches_local_system() {
    local existing_hostname="$1"
    local existing_fqdn="$2"
    local current_hostname
    local current_fqdn

    current_hostname=$(local_system_hostname)
    current_fqdn=$(local_system_fqdn)

    [ -n "$existing_hostname" ] && [ "$existing_hostname" = "$current_hostname" ] && return 0
    [ -n "$existing_fqdn" ] && [ "$existing_fqdn" = "$current_fqdn" ] && return 0
    [ -n "$existing_hostname" ] && [ "$existing_hostname" = "$current_fqdn" ] && return 0
    [ -n "$existing_fqdn" ] && [ "$existing_fqdn" = "$current_hostname" ] && return 0

    return 1
}

check_uuid_available() {
    local payload response_file http_code exit_code response_body
    response_file=$(make_private_temp_file "rsm_install_uuid_check_response")
    payload="{\"propertyIDs\":[\"$RSM_SYSTEM_HOSTNAME_PROPERTY_ID\",\"$RSM_SYSTEM_FQDN_PROPERTY_ID\",\"$RSM_SYSTEM_UUID_PROPERTY_ID\",\"$RSM_SYSTEM_ALIAS_PROPERTY_ID\"],\"translateIDs\":true,\"filterRules\":[{\"propertyID\":\"$RSM_SYSTEM_UUID_PROPERTY_ID\",\"value\":\"$UUID\",\"operation\":\"=\"}]}"

    info "Validating UUID in RSM..."

    set +e
    http_code=$(curl \
        --silent \
        --show-error \
        --output "$response_file" \
        --write-out '%{http_code}' \
        --location \
        --request GET \
        "$RSM_ITEMS_GET_URL" \
        --header "Authorization: $AGENT_TOKEN" \
        --header "Content-Type: application/json" \
        --data "$payload" \
        --max-time 20)
    exit_code=$?
    set -e
    response_body=$(cat "$response_file" 2>/dev/null || true)
    rm -f "$response_file"

    if [ "$exit_code" -ne 0 ]; then
        error "Could not validate the UUID in RSM (curl exit: $exit_code)."
        error "For safety, installation will not continue without confirming that the UUID is available."
        exit 1
    fi

    if [ "$http_code" != "200" ] && [ "$http_code" != "201" ]; then
        error "RSM did not allow UUID validation (HTTP $http_code)."
        error "For safety, installation will not continue without confirming that the UUID is available."
        echo "Response: $response_body"
        exit 1
    fi

    if ! printf '%s' "$response_body" | grep -Fq "$UUID"; then
        error "Invalid UUID: it does not exist in RSM."
        error "The agent cannot be installed with a UUID that was not generated from Add New System."
        echo ""
        echo "UUID: $UUID"
        exit 1
    fi

    RSM_SYSTEM_ITEM_ID=$(json_extract_first_scalar_key "$response_body" "ID")
    [ -z "$RSM_SYSTEM_ITEM_ID" ] && RSM_SYSTEM_ITEM_ID=$(json_extract_first_scalar_key "$response_body" "id")
    if [ -z "$RSM_SYSTEM_ITEM_ID" ]; then
        error "Could not locate the RSM item associated with the UUID."
        error "For safety, installation will not continue without being able to update the status."
        exit 1
    fi

    local existing_hostname existing_fqdn
    existing_hostname=$(json_extract_rsm_property "$response_body" "$RSM_SYSTEM_HOSTNAME_PROPERTY_ID")
    existing_fqdn=$(json_extract_rsm_property "$response_body" "$RSM_SYSTEM_FQDN_PROPERTY_ID")

    if [ -z "$existing_hostname" ] && [ -z "$existing_fqdn" ]; then
        log "UUID reserved in RSM and available for installation"
        return 0
    fi

    if identity_matches_local_system "$existing_hostname" "$existing_fqdn"; then
        log "UUID already associated with this system in RSM; the agent will be reactivated and inventory updated"
        return 0
    fi

    echo ""
    error "This UUID already belongs to another system in RSM."
    error "This agent cannot be installed on the local machine with that UUID."
    exit 1
}

check_existing_installation() {
    if [ -f "$INSTALL_DIR/rs_agent.sh" ] || [ -f "$CONFIG_FILE" ]; then
        local manual_prefix=""
        [ "$RUN_AS_ROOT" = "1" ] && manual_prefix="sudo "
        warn "An existing agent installation was found on this system."
        warn "To install a new agent, uninstall the current one first:"
        warn "  ${manual_prefix}bash $INSTALL_DIR/uninstall.sh"
        exit 1
    fi
}

warn_about_parallel_root_installation() {
    if [ "$RUN_AS_ROOT" = "1" ]; then
        return 0
    fi

    if [ -f "/opt/rs-agent/rs_agent.sh" ] || [ -f "/var/lib/rs-agent/config.env" ]; then
        warn "An existing root installation was found in /opt/rs-agent or /var/lib/rs-agent."
        warn "The no-root installation will coexist with it using current-user paths."
        warn "For comparison, use a separate test UUID/alias."
    fi
}

check_local_agent_installation() {
    if [ -f "$INSTALL_DIR/rs_agent.sh" ] || [ -f "$CONFIG_FILE" ]; then
        local installed_uuid=""
        if [ -f "$CONFIG_FILE" ]; then
            installed_uuid=$(sed -n "s/^UUID='\([^']*\)'.*/\1/p" "$CONFIG_FILE" | head -1)
        fi

        if [ -n "$installed_uuid" ] && [ "$installed_uuid" = "$UUID" ]; then
            error "This system already has an agent installed with this UUID."
        else
            error "An agent is already installed on this system."
            if [ -n "$installed_uuid" ]; then
                echo "Currently installed UUID: $installed_uuid"
            fi
            echo "Requested UUID: $UUID"
        fi

        echo ""
        echo "To reinstall the agent, uninstall the current agent first:"
        if [ "$RUN_AS_ROOT" = "1" ]; then
            echo "  sudo bash $INSTALL_DIR/uninstall.sh"
        else
            echo "  bash $INSTALL_DIR/uninstall.sh"
        fi
        exit 1
    fi
}

update_rsm_system_on_install() {
    local payload response_file http_code exit_code response_body

    if [ -z "$RSM_SYSTEM_ITEM_ID" ]; then
        error "Could not update RSM because the UUID item was not found."
        exit 1
    fi

    response_file=$(make_private_temp_file "rsm_install_system_update_response")
    payload="[{\"ID\":\"$RSM_SYSTEM_ITEM_ID\",\"$RSM_SYSTEM_ALIAS_PROPERTY_ID\":\"$(json_escape "$SYSTEM_ALIAS")\",\"$RSM_SYSTEM_HOSTNAME_STATUS_PROPERTY_ID\":\"$RSM_SYSTEM_HOSTNAME_STATUS_ACTIVE_VALUE\"}]"

    info "Marking system as active in Firulai..."

    set +e
    http_code=$(curl \
        --silent \
        --show-error \
        --output "$response_file" \
        --write-out '%{http_code}' \
        --location \
        --request PATCH \
        "$RSM_ITEMS_UPDATE_URL" \
        --header "Authorization: $AGENT_TOKEN" \
        --header "Content-Type: application/json" \
        --data "$payload" \
        --max-time 20)
    exit_code=$?
    set -e
    response_body=$(cat "$response_file" 2>/dev/null || true)
    rm -f "$response_file"

    if [ "$exit_code" -ne 0 ]; then
        error "Could not activate the system in RSM (curl exit: $exit_code)."
        exit 1
    fi

    if [ "$http_code" != "200" ] && [ "$http_code" != "201" ]; then
        error "RSM did not allow system activation (HTTP $http_code)."
        echo "Response: $response_body"
        exit 1
    fi

    log "System marked as active in Firulai"
}

cron_daemon_active() {
    if command -v systemctl &> /dev/null && [ -d /run/systemd/system ]; then
        systemctl is-active --quiet cron.service 2>/dev/null && return 0
        systemctl is-active --quiet crond.service 2>/dev/null && return 0
        systemctl is-active --quiet cronie.service 2>/dev/null && return 0
    fi

    if command -v service &> /dev/null; then
        service cron status >/dev/null 2>&1 && return 0
        service crond status >/dev/null 2>&1 && return 0
    fi

    if command -v pgrep &> /dev/null; then
        pgrep -x cron >/dev/null 2>&1 && return 0
        pgrep -x crond >/dev/null 2>&1 && return 0
    fi

    return 1
}

cron_install_command() {
    if command -v apt-get >/dev/null 2>&1; then
        printf '%s' 'apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y cron'
        return 0
    fi

    if command -v dnf >/dev/null 2>&1; then
        printf '%s' 'dnf install -y cronie'
        return 0
    fi

    if command -v yum >/dev/null 2>&1; then
        printf '%s' 'yum install -y cronie'
        return 0
    fi

    if command -v zypper >/dev/null 2>&1; then
        printf '%s' 'zypper --non-interactive install cron'
        return 0
    fi

    return 1
}

cron_enable_command() {
    if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
        printf '%s' 'systemctl enable --now cron.service 2>/dev/null || systemctl enable --now crond.service 2>/dev/null || systemctl enable --now cronie.service'
        return 0
    fi

    if command -v service >/dev/null 2>&1; then
        printf '%s' 'service cron start 2>/dev/null || service crond start'
        return 0
    fi

    return 1
}

offer_install_cron() {
    local command_string

    command_string=$(cron_install_command) || {
        error "Could not determine how to install cron automatically on this distribution."
        error "Install cron manually or contact Firulai."
        return 1
    }

    warn "cron/crontab is not installed."
    if ! ask_yes_no "Do you want us to install cron now? This needs privileged access."; then
        error "Cannot continue with cron without crontab."
        return 1
    fi

    info "Attempting to install cron with privileged access..."
    run_privileged_command "$command_string"
}

offer_enable_cron_daemon() {
    local command_string

    command_string=$(cron_enable_command) || {
        error "Could not determine how to enable cron automatically on this distribution."
        error "Enable cron manually or contact Firulai."
        return 1
    }

    warn "cron/crond does not appear to be active."
    if ! ask_yes_no "Do you want us to enable it now? This needs privileged access."; then
        error "Cannot continue with cron if the daemon is not active."
        return 1
    fi

    info "Attempting to enable cron with privileged access..."
    run_privileged_command "$command_string"
}

check_cron_prerequisites() {
    local crontab_error_file

    if ! command -v crontab &> /dev/null; then
        if ! offer_install_cron || ! command -v crontab &> /dev/null; then
            error "Could not make crontab available. Contact Firulai if you need help."
            return 1
        fi
    fi

    crontab_error_file=$(make_private_temp_file "cron_access_check") || return 1
    if ! crontab -l >/dev/null 2>"$crontab_error_file"; then
        if ! grep -qi "no crontab" "$crontab_error_file"; then
            error "The current user cannot manage their crontab."
            error "An administrator must allow crontabs for this user and review cron policies."
            error "This may require privileged access. Contact Firulai if you need help."
            cat "$crontab_error_file" 2>/dev/null || true
            rm -f "$crontab_error_file"
            return 1
        fi
    fi
    rm -f "$crontab_error_file"

    if ! cron_daemon_active; then
        if ! offer_enable_cron_daemon || ! cron_daemon_active; then
            error "Could not confirm that cron is active. Contact Firulai if you need help."
            return 1
        fi
    fi
}

cron_scheduler_required() {
    if [ "$RUN_AS_ROOT" = "1" ]; then
        if command -v systemctl &> /dev/null && [ -d /run/systemd/system ]; then
            return 1
        fi
        return 0
    fi

    if [ "$SCHEDULER_CHOICE" = "systemd-user" ]; then
        return 1
    fi

    return 0
}

check_systemd_user_prerequisites() {
    if ! systemd_user_available; then
        error "systemd --user cannot be used: it is not available for this user/session."
        error "An administrator must review the user systemd setup, or you should choose cron."
        error "This may require privileged access. Contact Firulai if you need help."
        return 1
    fi

    if ! user_linger_enabled && [ "${RS_AGENT_ALLOW_USER_SYSTEMD_WITHOUT_LINGER:-0}" != "1" ]; then
        local username
        username=$(id -un)
        warn "linger is not enabled for $username."
        warn "systemd --user will not be reliable without an active session until linger is enabled."

        if ! ask_yes_no "Do you want us to enable linger now? This needs privileged access."; then
            error "Cannot continue with systemd --user without linger."
            error "You can choose user cron or contact Firulai."
            return 1
        fi

        info "Attempting to enable linger with privileged access..."
        if ! run_privileged_command "loginctl enable-linger $(shell_single_quote "$username")" || ! user_linger_enabled; then
            error "Could not enable linger for $username."
            error "Contact Firulai if you need help."
            return 1
        fi
    fi
}

check_automatic_execution_prerequisites() {
    if [ "$RUN_AS_ROOT" != "1" ] && [ "$SCHEDULER_CHOICE" = "systemd-user" ]; then
        info "Checking systemd --user requirements..."
        check_systemd_user_prerequisites
        return
    fi

    if cron_scheduler_required; then
        info "Checking cron requirements for automatic execution..."
        check_cron_prerequisites
    fi
}

cleanup_partial_installation() {
    warn "Cleaning partial installation..."
    if [ "$RUN_AS_ROOT" = "1" ] && command -v systemctl &> /dev/null; then
        systemctl disable --now rs-agent.timer >/dev/null 2>&1 || true
        systemctl stop rs-agent.service >/dev/null 2>&1 || true
    fi
    [ -n "$SYSTEMD_SERVICE_FILE" ] && rm -f "$SYSTEMD_SERVICE_FILE"
    [ -n "$SYSTEMD_TIMER_FILE" ] && rm -f "$SYSTEMD_TIMER_FILE"
    if [ "$RUN_AS_ROOT" = "1" ] && command -v systemctl &> /dev/null; then
        systemctl daemon-reload >/dev/null 2>&1 || true
    fi
    if [ "$RUN_AS_ROOT" != "1" ] && command -v systemctl &> /dev/null; then
        systemctl --user disable --now rs-agent.timer >/dev/null 2>&1 || true
        rm -f "$SYSTEMD_USER_SERVICE_FILE" "$SYSTEMD_USER_TIMER_FILE"
        systemctl --user daemon-reload >/dev/null 2>&1 || true
    fi
    if command -v crontab &> /dev/null; then
        ({ crontab -l 2>/dev/null || true; } | grep -Fv "$INSTALL_DIR/rs_agent" || true) | crontab - || true
    fi
    rm -rf "$INSTALL_DIR"
    rm -rf "$DATA_DIR"
    rm -f "$LOG_FILE"
    log "Partial installation removed"
}

create_directories() {
    info "Creating directories..."
    
    mkdir -p "$INSTALL_DIR"
    chown root:root "$INSTALL_DIR" 2>/dev/null || true
    chmod 755 "$INSTALL_DIR"
    ensure_private_directory "$DATA_DIR"
    touch "$LOG_FILE"
    chown root:root "$LOG_FILE" 2>/dev/null || true
    if [ "$RUN_AS_ROOT" = "1" ]; then
        chmod 644 "$LOG_FILE"
    else
        chmod 600 "$LOG_FILE"
    fi
    
    log "Directories created"
}

download_agent() {
    info "Downloading agent from GitHub..."

    AGENT_URL="${GITHUB_RAW_URL}/rs_agent.sh?ts=$(date +%s)"

    if curl -fsSL "$AGENT_URL" -o "$INSTALL_DIR/rs_agent.sh"; then
        chmod +x "$INSTALL_DIR/rs_agent.sh"
        log "Agent downloaded: $INSTALL_DIR/rs_agent.sh"
    else
        error "Could not download the agent from GitHub"
        error ""
        error "Attempted URL: $AGENT_URL"
        error ""
        error "Check that:"
        error "  - You have internet connectivity"
        error "  - GitHub is accessible from this server"
        exit 1
    fi
}

download_runner() {
    info "Downloading automatic execution runner..."

    RUNNER_URL="${GITHUB_RAW_URL}/rs_agent_runner.sh?ts=$(date +%s)"
    if curl -fsSL "$RUNNER_URL" -o "$RUNNER_FILE"; then
        chmod +x "$RUNNER_FILE"
        log "Runner downloaded: $RUNNER_FILE"
    else
        error "Could not download $RUNNER_URL"
        exit 1
    fi
}

download_uninstaller() {
    info "Downloading uninstaller from GitHub..."

    UNINSTALLER_URL="${GITHUB_RAW_URL}/uninstall.sh?ts=$(date +%s)"

    if curl -fsSL "$UNINSTALLER_URL" -o "$INSTALL_DIR/uninstall.sh"; then
        chmod +x "$INSTALL_DIR/uninstall.sh"
        log "Uninstaller downloaded: $INSTALL_DIR/uninstall.sh"
    else
        error "Could not download the uninstaller from GitHub"
        error ""
        error "Attempted URL: $UNINSTALLER_URL"
        error ""
        error "Check that:"
        error "  - You have internet connectivity"
        error "  - GitHub is accessible from this server"
        exit 1
    fi
}

write_agent_config() {
    local temporary_file

    info "Saving local agent configuration..."

    temporary_file=$(mktemp "$DATA_DIR/config.env.XXXXXX")
    chmod 600 "$temporary_file"
    cat > "$temporary_file" << CONFIG_EOF
AGENT_TOKEN=$(shell_single_quote "$AGENT_TOKEN")
UUID=$(shell_single_quote "$UUID")
SYSTEM_ALIAS=$(shell_single_quote "$SYSTEM_ALIAS")
CONFIG_EOF
    chown root:root "$temporary_file" 2>/dev/null || true
    mv -f "$temporary_file" "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"

    log "Configuration saved: $CONFIG_FILE"
}

setup_automatic_execution() {
    info "Configuring automatic execution..."

    if [ "$RUN_AS_ROOT" = "1" ] && command -v systemctl &> /dev/null && [ -d /run/systemd/system ]; then
        cat > "$SYSTEMD_SERVICE_FILE" << SERVICE_EOF
[Unit]
Description=Firulai Inventory Agent execution
Wants=network-online.target
After=network-online.target
ConditionPathExists=$RUNNER_FILE

[Service]
Type=oneshot
ExecStart=/bin/bash $RUNNER_FILE --if-due --trigger systemd-timer
Restart=on-failure
RestartSec=30min
TimeoutStartSec=30min
SyslogIdentifier=rs-agent
SERVICE_EOF

        cat > "$SYSTEMD_TIMER_FILE" << TIMER_EOF
[Unit]
Description=Firulai Inventory Agent daily schedule

[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true
AccuracySec=1min
Unit=rs-agent.service

[Install]
WantedBy=timers.target
TIMER_EOF

        chmod 644 "$SYSTEMD_SERVICE_FILE" "$SYSTEMD_TIMER_FILE"
        if ! systemctl daemon-reload; then
            error "systemd could not reload units"
            return 1
        fi
        if ! systemctl enable --now rs-agent.timer; then
            error "systemd could not enable rs-agent.timer"
            return 1
        fi
        SCHEDULER_TYPE="persistent systemd timer"
        log "systemd timer configured at 03:00 with boot recovery"
        return 0
    fi

    if [ "$RUN_AS_ROOT" != "1" ] && [ "$SCHEDULER_CHOICE" != "cron" ] && systemd_user_available; then
        if ! user_linger_enabled && [ "${RS_AGENT_ALLOW_USER_SYSTEMD_WITHOUT_LINGER:-0}" != "1" ]; then
            warn "systemd --user is available, but linger is not enabled for the current user."
            warn "User cron will be used to avoid depending on an active session."
        else
            mkdir -p "$SYSTEMD_USER_DIR"
            cat > "$SYSTEMD_USER_SERVICE_FILE" << SERVICE_EOF
[Unit]
Description=Firulai Inventory Agent execution
ConditionPathExists=$RUNNER_FILE

[Service]
Type=oneshot
ExecStart=/bin/bash $RUNNER_FILE --if-due --trigger systemd-user-timer
Restart=on-failure
RestartSec=30min
TimeoutStartSec=30min
SERVICE_EOF

            cat > "$SYSTEMD_USER_TIMER_FILE" << TIMER_EOF
[Unit]
Description=Firulai Inventory Agent daily schedule

[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true
AccuracySec=1min
Unit=rs-agent.service

[Install]
WantedBy=timers.target
TIMER_EOF

            chmod 644 "$SYSTEMD_USER_SERVICE_FILE" "$SYSTEMD_USER_TIMER_FILE"
            if systemctl --user daemon-reload && systemctl --user enable --now rs-agent.timer; then
                SCHEDULER_TYPE="persistent systemd --user timer"
                log "systemd --user timer configured at 03:00"
                return 0
            fi

            rm -f "$SYSTEMD_USER_SERVICE_FILE" "$SYSTEMD_USER_TIMER_FILE"
            systemctl --user daemon-reload >/dev/null 2>&1 || true
            if [ "$SCHEDULER_CHOICE" = "systemd-user" ]; then
                error "Could not enable systemd --user."
                return 1
            fi
            warn "Could not enable systemd --user; user cron will be tried instead."
        fi
    fi

    if ! check_cron_prerequisites; then
        error "Cannot complete installation with automatic execution."
        return 1
    fi

    local cron_watchdog cron_reboot
    cron_watchdog="*/30 * * * * /bin/bash $RUNNER_FILE --if-due --trigger cron-check >/dev/null 2>&1"
    cron_reboot="@reboot sleep 60; /bin/bash $RUNNER_FILE --if-due --trigger cron-boot >/dev/null 2>&1"

    # Checking every 30 minutes allows the 03:00 run and retries one missed
    # execution without duplicating it thanks to state.env and flock.
    if ! ({ crontab -l 2>/dev/null || true; } | grep -Fv "$INSTALL_DIR/rs_agent" || true; echo "$cron_watchdog"; echo "$cron_reboot") | crontab -; then
        if [ "$RUN_AS_ROOT" = "1" ]; then
            error "Could not update root crontab"
        else
            error "Could not update the current user's crontab"
        fi
        return 1
    fi

    if [ "$RUN_AS_ROOT" = "1" ]; then
        SCHEDULER_TYPE="root cron with boot recovery and 30-minute checks"
        log "Root cron configured with daily execution and automatic recovery"
    else
        SCHEDULER_TYPE="user cron with boot recovery and 30-minute checks"
        log "User cron configured with daily execution and automatic recovery"
    fi
}

test_agent() {
    info "Running initial collection..."

    set +e
    RS_AGENT_TRIGGER="initial-installation" /bin/bash "$INSTALL_DIR/rs_agent.sh" --token "$AGENT_TOKEN" --uuid "$UUID" --alias "$SYSTEM_ALIAS" 2>&1 | tee -a "$LOG_FILE"
    local agent_status=${PIPESTATUS[0]}
    set -e

    if [ "$agent_status" -eq 0 ]; then
        if [ -f "$DATA_DIR/inventory.json" ]; then
            INVENTORY_SIZE=$(stat -c%s "$DATA_DIR/inventory.json" 2>/dev/null || stat -f%z "$DATA_DIR/inventory.json" 2>/dev/null)
            log "Inventory generated successfully (${INVENTORY_SIZE} bytes)"
            return 0
        fi
    fi

    error "Could not generate and send the inventory during the initial run"
    info "Failure details were shown above."
    return 1
}

print_summary() {
    local manual_prefix=""
    [ "$RUN_AS_ROOT" = "1" ] && manual_prefix="sudo "

    echo ""
    echo "============================================================================"
    echo "  INSTALLATION COMPLETED"
    echo "============================================================================"
    echo ""
    echo "Locations:"
    echo "   - Agent:       $INSTALL_DIR/rs_agent.sh"
    echo "   - Inventory:   $DATA_DIR/inventory.json"
    echo "   - State:       $DATA_DIR/state.env"
    echo "   - Logs:        $LOG_FILE"
    echo ""
    echo "Execution:"
    echo "   - Automatic:   Daily at 3:00 AM ($SCHEDULER_TYPE)"
    echo "   - Recovery:    one pending execution when the system becomes operational again"
    echo "   - Manual:      ${manual_prefix}bash $INSTALL_DIR/rs_agent.sh --token <AGENT_TOKEN> --uuid <UUID> --alias <ALIAS>"
    echo ""
    echo "Alias:"
    echo "   - Current value: $SYSTEM_ALIAS"
    echo "   - This alias is saved in Firulai and can be changed from the interface."
    echo ""
    echo "View inventory:"
    echo "   cat $DATA_DIR/inventory.json"
    echo ""
    echo "Behavior:"
    echo "   - No Python or jq dependency (pure bash)"
    echo "   - Sends a complete inventory to RSM on every run"
    echo "   - RSM detects and manages changes"
    echo "   - System analysis agent for vulnerability detection"
    echo "   - Includes: OS, kernel, CPU, disk models, packages, critical software"
    echo ""
    echo "Uninstall:"
    echo "   ${manual_prefix}bash $INSTALL_DIR/uninstall.sh"
    echo ""
    echo "============================================================================"
    echo ""
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    banner
    
    # Verificaciones
    check_root
    detect_distro
    check_dependencies
    init_private_tmp_dir
    require_system_alias
    choose_scheduler_interactively
    validate_uuid_format "$UUID"
    check_local_agent_installation
    warn_about_parallel_root_installation
    check_automatic_execution_prerequisites
    check_uuid_available
    update_rsm_system_on_install
    
    # Instalacion
    create_directories
    download_agent
    download_runner
    download_uninstaller
    write_agent_config
    
    # Prueba
    echo ""
    if ! test_agent; then
        echo ""
        error "Installation cancelled because the initial agent run failed."
        error "If the UUID already belongs to another system, generate a new UUID from Add New System."
        cleanup_partial_installation
        exit 1
    fi

    if ! setup_automatic_execution; then
        error "Could not configure automatic execution"
        cleanup_partial_installation
        exit 1
    fi
    
    # Summary
    print_summary
    
    log "Installation successful"
}

# Ejecutar
main "$@"
