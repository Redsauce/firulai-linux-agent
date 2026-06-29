#!/bin/bash
# ============================================================================
# Redsauce Inventory Agent - Instalador One-Liner
# Version 0.2.3 - Optimizado para deteccion CVE (modelo de disco sin tamaño)
# ============================================================================
#
# Uso:
#   curl -fsSL https://raw.githubusercontent.com/redsauce/inventory-agent/main/install.sh | sudo bash -s -- <AGENT_TOKEN> <UUID> --alias <ALIAS>
#

set -e

# ============================================================================
# PARAMETROS
# ============================================================================

AGENT_TOKEN=${1:-""}
UUID=${2:-""}
SYSTEM_ALIAS=""

if [ -z "$AGENT_TOKEN" ] || [ -z "$UUID" ]; then
    echo "[ERROR] Uso: curl ... | sudo bash -s -- <AGENT_TOKEN> <UUID> --alias <ALIAS>"
    exit 1
fi

shift 2
while [ $# -gt 0 ]; do
    case "$1" in
        --alias)
            if [ $# -lt 2 ]; then
                echo "[ERROR] --alias requiere un valor"
                exit 1
            fi
            SYSTEM_ALIAS="$2"
            shift 2
            ;;
        *)
            echo "[ERROR] Argumento desconocido: $1"
            echo "[ERROR] Uso: curl ... | sudo bash -s -- <AGENT_TOKEN> <UUID> --alias <ALIAS>"
            exit 1
            ;;
    esac
done

# ============================================================================
# CONFIGURACION
# ============================================================================

# URL de GitHub donde esta el agente
GITHUB_RAW_URL="https://raw.githubusercontent.com/redsauce/inventory-agent/main"

# Directorios de instalacion
INSTALL_DIR="/opt/rs-agent"
DATA_DIR="/var/lib/rs-agent"
LOG_FILE="/var/log/rs-agent.log"
CONFIG_FILE="$DATA_DIR/config.env"

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

banner() {
    echo ""
    echo "============================================================================"
    echo "  Redsauce Inventory Agent - Instalador v0.2.3"
    echo "  Optimizado para detección de vulnerabilidades CVE"
    echo "============================================================================"
    echo ""
}

check_root() {
    if [ "$EUID" -ne 0 ]; then 
        error "Este script debe ejecutarse como root"
        echo ""
        echo "Ejecuta:"
        echo "  curl -fsSL https://raw.githubusercontent.com/redsauce/inventory-agent/main/install.sh | sudo bash -s -- <AGENT_TOKEN> <UUID> --alias <ALIAS>"
        echo ""
        exit 1
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
            info "Este instalador necesita un alias para identificar el sistema en Firulai."
            printf "Alias del sistema: " > /dev/tty
            IFS= read -r SYSTEM_ALIAS < /dev/tty || SYSTEM_ALIAS=""
            SYSTEM_ALIAS=$(trim_string "$SYSTEM_ALIAS")
        fi
    fi

    if [ -z "$SYSTEM_ALIAS" ]; then
        error "El alias del sistema es obligatorio."
        echo ""
        echo "Ejecuta el instalador indicando el alias con la opcion --alias:"
        echo "  curl -fsSL https://raw.githubusercontent.com/redsauce/inventory-agent/main/install.sh | sudo bash -s -- <AGENT_TOKEN> <UUID> --alias <ALIAS>"
        echo ""
        echo "Si el alias contiene espacios, envuélvelo entre comillas."
        exit 1
    fi
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
    
    info "Distribucion: $DISTRO $VERSION"
}

check_dependencies() {
    info "Verificando dependencias..."

    # Verificar curl (deberia estar si llegamos aqui)
    if ! command -v curl &> /dev/null; then
        error "curl no esta instalado"
        exit 1
    fi
    log "curl encontrado: $(curl --version | head -1)"

    # Verificar bash 4+ (requerido por el agente para arrays asociativos)
    local bash_major
    bash_major=$(bash --version | grep -oE '[0-9]+\.[0-9]+' | head -1 | cut -d. -f1)
    if [ "${bash_major:-0}" -lt 4 ]; then
        error "Se requiere bash 4 o superior (encontrado: $bash_major)"
        exit 1
    fi
    log "bash ${bash_major} encontrado"
}

validate_uuid_format() {
    local uuid="$1"
    if [[ ! "$uuid" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
        error "'$uuid' no es un UUID valido"
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
    response_file="/tmp/rsm_install_uuid_check_response.txt"
    payload="{\"propertyIDs\":[\"$RSM_SYSTEM_HOSTNAME_PROPERTY_ID\",\"$RSM_SYSTEM_FQDN_PROPERTY_ID\",\"$RSM_SYSTEM_UUID_PROPERTY_ID\",\"$RSM_SYSTEM_ALIAS_PROPERTY_ID\"],\"translateIDs\":true,\"filterRules\":[{\"propertyID\":\"$RSM_SYSTEM_UUID_PROPERTY_ID\",\"value\":\"$UUID\",\"operation\":\"=\"}]}"

    info "Validando UUID en RSM..."

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

    if [ "$exit_code" -ne 0 ]; then
        error "No se pudo validar el UUID en RSM (curl exit: $exit_code)."
        error "Por seguridad, la instalación no continuará sin confirmar que el UUID está disponible."
        exit 1
    fi

    if [ "$http_code" != "200" ] && [ "$http_code" != "201" ]; then
        error "RSM no permitió validar el UUID (HTTP $http_code)."
        error "Por seguridad, la instalación no continuará sin confirmar que el UUID está disponible."
        echo "Respuesta: $response_body"
        exit 1
    fi

    if ! printf '%s' "$response_body" | grep -Fq "$UUID"; then
        error "UUID inválido: no existe en RSM."
        error "No se puede instalar el agente con un UUID que no haya sido generado desde Add New System."
        echo ""
        echo "UUID: $UUID"
        exit 1
    fi

    RSM_SYSTEM_ITEM_ID=$(json_extract_first_scalar_key "$response_body" "ID")
    [ -z "$RSM_SYSTEM_ITEM_ID" ] && RSM_SYSTEM_ITEM_ID=$(json_extract_first_scalar_key "$response_body" "id")
    if [ -z "$RSM_SYSTEM_ITEM_ID" ]; then
        error "No se pudo localizar el item de RSM asociado al UUID."
        error "Por seguridad, la instalación no continuará sin poder actualizar el estado."
        exit 1
    fi

    local existing_hostname existing_fqdn
    existing_hostname=$(json_extract_rsm_property "$response_body" "$RSM_SYSTEM_HOSTNAME_PROPERTY_ID")
    existing_fqdn=$(json_extract_rsm_property "$response_body" "$RSM_SYSTEM_FQDN_PROPERTY_ID")

    if [ -z "$existing_hostname" ] && [ -z "$existing_fqdn" ]; then
        log "UUID reservado en RSM y disponible para instalación"
        return 0
    fi

    if identity_matches_local_system "$existing_hostname" "$existing_fqdn"; then
        log "UUID ya asociado a este sistema en RSM; se reactivará el agente y se actualizará el inventario"
        return 0
    fi

    echo ""
    error "Este UUID ya pertenece a otro sistema en RSM."
    error "No se puede instalar este agente en el equipo local con ese UUID."
    exit 1
}

check_existing_installation() {
    if [ -f "$INSTALL_DIR/rs_agent.sh" ] || [ -f "$CONFIG_FILE" ]; then
        warn "Ya existe una instalación previa del agente en este sistema."
        warn "Si deseas instalar un nuevo agente, desinstala el actual primero:"
        warn "  sudo bash $INSTALL_DIR/uninstall.sh"
        exit 1
    fi
}

check_local_agent_installation() {
    if [ -f "$INSTALL_DIR/rs_agent.sh" ] || [ -f "$CONFIG_FILE" ]; then
        local installed_uuid=""
        if [ -f "$CONFIG_FILE" ]; then
            installed_uuid=$(sed -n "s/^UUID='\([^']*\)'.*/\1/p" "$CONFIG_FILE" | head -1)
        fi

        if [ -n "$installed_uuid" ] && [ "$installed_uuid" = "$UUID" ]; then
            error "Este sistema ya tiene un agente instalado con este UUID."
        else
            error "Ya existe un agente instalado en este sistema."
            if [ -n "$installed_uuid" ]; then
                echo "UUID instalado actualmente: $installed_uuid"
            fi
            echo "UUID solicitado: $UUID"
        fi

        echo ""
        echo "Si necesitas reinstalar el agente, desinstala primero el agente actual:"
        echo "  sudo bash $INSTALL_DIR/uninstall.sh"
        exit 1
    fi
}

update_rsm_system_on_install() {
    local payload response_file http_code exit_code response_body

    if [ -z "$RSM_SYSTEM_ITEM_ID" ]; then
        error "No se pudo actualizar RSM porque no se encontro el item del UUID."
        exit 1
    fi

    response_file="/tmp/rsm_install_system_update_response.txt"
    payload="[{\"ID\":\"$RSM_SYSTEM_ITEM_ID\",\"$RSM_SYSTEM_ALIAS_PROPERTY_ID\":\"$(json_escape "$SYSTEM_ALIAS")\",\"$RSM_SYSTEM_HOSTNAME_STATUS_PROPERTY_ID\":\"$RSM_SYSTEM_HOSTNAME_STATUS_ACTIVE_VALUE\"}]"

    info "Marcando sistema como activo en Firulai..."

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
        error "No se pudo activar el sistema en RSM (curl exit: $exit_code)."
        exit 1
    fi

    if [ "$http_code" != "200" ] && [ "$http_code" != "201" ]; then
        error "RSM no permitió activar el sistema (HTTP $http_code)."
        echo "Respuesta: $response_body"
        exit 1
    fi

    log "Sistema marcado como activo en Firulai"
}

cleanup_partial_installation() {
    warn "Limpiando instalación parcial..."
    if command -v crontab &> /dev/null; then
        ({ crontab -l 2>/dev/null || true; } | grep -v "$INSTALL_DIR/rs_agent.sh" || true) | crontab - || true
    fi
    rm -rf "$INSTALL_DIR"
    rm -rf "$DATA_DIR"
    rm -f "$LOG_FILE"
    log "Instalación parcial eliminada"
}

create_directories() {
    info "Creando directorios..."
    
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$DATA_DIR"
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"
    
    log "Directorios creados"
}

download_agent() {
    info "Descargando agente desde GitHub..."

    AGENT_URL="${GITHUB_RAW_URL}/rs_agent.sh?ts=$(date +%s)"

    if curl -fsSL "$AGENT_URL" -o "$INSTALL_DIR/rs_agent.sh"; then
        chmod +x "$INSTALL_DIR/rs_agent.sh"
        log "Agente descargado: $INSTALL_DIR/rs_agent.sh"
    else
        error "No se pudo descargar el agente desde GitHub"
        error ""
        error "URL intentada: $AGENT_URL"
        error ""
        error "Verifica que:"
        error "  - Tienes conexión a internet"
        error "  - GitHub es accesible desde este servidor"
        exit 1
    fi
}

download_uninstaller() {
    info "Descargando desinstalador desde GitHub..."

    UNINSTALLER_URL="${GITHUB_RAW_URL}/uninstall.sh?ts=$(date +%s)"

    if curl -fsSL "$UNINSTALLER_URL" -o "$INSTALL_DIR/uninstall.sh"; then
        chmod +x "$INSTALL_DIR/uninstall.sh"
        log "Desinstalador descargado: $INSTALL_DIR/uninstall.sh"
    else
        error "No se pudo descargar el desinstalador desde GitHub"
        error ""
        error "URL intentada: $UNINSTALLER_URL"
        error ""
        error "Verifica que:"
        error "  - Tienes conexión a internet"
        error "  - GitHub es accesible desde este servidor"
        exit 1
    fi
}

write_agent_config() {
    info "Guardando configuración local del agente..."

    cat > "$CONFIG_FILE" << CONFIG_EOF
AGENT_TOKEN=$(shell_single_quote "$AGENT_TOKEN")
UUID=$(shell_single_quote "$UUID")
SYSTEM_ALIAS=$(shell_single_quote "$SYSTEM_ALIAS")
CONFIG_EOF
    chmod 600 "$CONFIG_FILE"

    log "Configuración guardada: $CONFIG_FILE"
}

setup_cron() {
    info "Configurando ejecución automática..."

    CRON_JOB="0 3 * * * /bin/bash $INSTALL_DIR/rs_agent.sh --token $(shell_single_quote "$AGENT_TOKEN") --uuid $(shell_single_quote "$UUID") --alias $(shell_single_quote "$SYSTEM_ALIAS") >> $LOG_FILE 2>&1"

    # Anadir a crontab de root evitando duplicados
    ({ crontab -l 2>/dev/null || true; } | grep -v "$INSTALL_DIR/rs_agent.sh" || true; echo "$CRON_JOB") | crontab -

    log "Cron configurado (ejecución diaria a las 3:00 AM)"
}

test_agent() {
    info "Ejecutando primera recopilación..."

    set +e
    /bin/bash "$INSTALL_DIR/rs_agent.sh" --token "$AGENT_TOKEN" --uuid "$UUID" --alias "$SYSTEM_ALIAS" 2>&1 | tee -a "$LOG_FILE"
    local agent_status=${PIPESTATUS[0]}
    set -e

    if [ "$agent_status" -eq 0 ]; then
        if [ -f "$DATA_DIR/inventory.json" ]; then
            INVENTORY_SIZE=$(stat -c%s "$DATA_DIR/inventory.json" 2>/dev/null || stat -f%z "$DATA_DIR/inventory.json" 2>/dev/null)
            log "Inventario generado correctamente (${INVENTORY_SIZE} bytes)"
            return 0
        fi
    fi

    error "No se pudo generar y enviar el inventario en la primera ejecución"
    info "El detalle del fallo se ha mostrado arriba."
    return 1
}

print_summary() {
    echo ""
    echo "============================================================================"
    echo "  INSTALACIÓN COMPLETADA"
    echo "============================================================================"
    echo ""
    echo "Ubicaciones:"
    echo "   - Agente:      $INSTALL_DIR/rs_agent.sh"
    echo "   - Inventario:  $DATA_DIR/inventory.json"
    echo "   - Logs:        $LOG_FILE"
    echo ""
    echo "Ejecución:"
    echo "   - Automática:  Diariamente a las 3:00 AM"
    echo "   - Manual:      sudo bash $INSTALL_DIR/rs_agent.sh --token <AGENT_TOKEN> --uuid <UUID> --alias <ALIAS>"
    echo ""
    echo "Alias:"
    echo "   - Valor actual: $SYSTEM_ALIAS"
    echo "   - Este alias se guarda en Firulai y podrá modificarse desde la interfaz."
    echo ""
    echo "Ver inventario:"
    echo "   cat $DATA_DIR/inventory.json"
    echo ""
    echo "Funcionamiento:"
    echo "   - Sin dependencia de Python ni jq (bash puro)"
    echo "   - Envia inventario completo en cada ejecución a RSM"
    echo "   - RSM detecta y gestiona los cambios"
    echo "   - Optimizado para detección de vulnerabilidades CVE"
    echo "   - Incluye: OS, kernel, CPU, modelo de discos, paquetes, software crítico"
    echo ""
    echo "Desinstalar:"
    echo "   sudo bash $INSTALL_DIR/uninstall.sh"
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
    require_system_alias
    validate_uuid_format "$UUID"
    check_local_agent_installation
    check_uuid_available
    update_rsm_system_on_install
    
    # Instalacion
    create_directories
    download_agent
    download_uninstaller
    write_agent_config
    
    # Prueba
    echo ""
    if ! test_agent; then
        echo ""
        error "Instalación cancelada porque la primera ejecución del agente ha fallado."
        error "Si el UUID ya pertenece a otro sistema, genera un UUID nuevo desde Add New System."
        cleanup_partial_installation
        exit 1
    fi

    setup_cron
    
    # Resumen
    print_summary
    
    log "Instalación exitosa"
}

# Ejecutar
main "$@"
