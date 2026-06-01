#!/bin/bash
# ============================================================================
# Redsauce Inventory Agent - Instalador One-Liner
# Version 0.2.3 - Optimizado para deteccion CVE (modelo de disco sin tamaño)
# ============================================================================
#
# Uso:
#   curl -fsSL https://raw.githubusercontent.com/redsauce/inventory-agent/main/install.sh | sudo bash -s <AGENT_TOKEN> <UUID>
#

set -e

# ============================================================================
# PARAMETROS
# ============================================================================

AGENT_TOKEN=${1:-""}
UUID=${2:-""}

if [ -z "$AGENT_TOKEN" ] || [ -z "$UUID" ]; then
    echo "[ERROR] Uso: curl ... | sudo bash -s <AGENT_TOKEN> <UUID>"
    exit 1
fi

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
RSM_SYSTEM_ITEM_TYPE_ID="191"
RSM_SYSTEM_HOSTNAME_PROPERTY_ID="1749"
RSM_SYSTEM_FQDN_PROPERTY_ID="1750"
RSM_SYSTEM_UUID_PROPERTY_ID="1780"

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
    echo "  Optimizado para deteccion de vulnerabilidades CVE"
    echo "============================================================================"
    echo ""
}

check_root() {
    if [ "$EUID" -ne 0 ]; then 
        error "Este script debe ejecutarse como root"
        echo ""
        echo "Ejecuta:"
        echo "  curl -fsSL https://raw.githubusercontent.com/redsauce/inventory-agent/main/install.sh | sudo bash -s <AGENT_TOKEN> <UUID>
#"
        echo ""
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

check_uuid_available() {
    local payload response_file http_code exit_code response_body
    response_file="/tmp/rsm_install_uuid_check_response.txt"
    payload="{\"itemTypeID\":\"$RSM_SYSTEM_ITEM_TYPE_ID\",\"propertyIDs\":[\"$RSM_SYSTEM_HOSTNAME_PROPERTY_ID\",\"$RSM_SYSTEM_FQDN_PROPERTY_ID\",\"$RSM_SYSTEM_UUID_PROPERTY_ID\"],\"translateIDs\":true,\"filterRules\":[{\"propertyID\":\"$RSM_SYSTEM_UUID_PROPERTY_ID\",\"value\":\"$UUID\",\"operation\":\"=\"}]}"

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
        error "Por seguridad, la instalacion no continuara sin confirmar que el UUID esta disponible."
        exit 1
    fi

    if [ "$http_code" != "200" ] && [ "$http_code" != "201" ]; then
        error "RSM no permitio validar el UUID (HTTP $http_code)."
        error "Por seguridad, la instalacion no continuara sin confirmar que el UUID esta disponible."
        echo "Respuesta: $response_body"
        exit 1
    fi

    if ! printf '%s' "$response_body" | grep -Fq "$UUID"; then
        error "No se encontro este UUID en RSM o no se pudo validar con el token recibido."
        error "Por seguridad, la instalacion no continuara."
        echo ""
        echo "UUID: $UUID"
        echo "Genera un UUID nuevo desde Add New System y usa el comando que muestra Firulai."
        exit 1
    fi

    local existing_hostname existing_fqdn
    existing_hostname=$(json_extract_rsm_property "$response_body" "$RSM_SYSTEM_HOSTNAME_PROPERTY_ID")
    existing_fqdn=$(json_extract_rsm_property "$response_body" "$RSM_SYSTEM_FQDN_PROPERTY_ID")

    if [ -z "$existing_hostname" ] && [ -z "$existing_fqdn" ]; then
        log "UUID reservado en RSM y disponible para instalacion"
        return 0
    fi

    echo ""
    error "Este UUID ya pertenece a otro sistema en RSM."
    error "No se puede instalar este agente en el equipo local con ese UUID."
    echo ""
    echo "UUID: $UUID"
    echo "Sistema en RSM:"
    echo "   - Hostname: ${existing_hostname:-desconocido}"
    echo "   - FQDN:     ${existing_fqdn:-desconocido}"
    echo ""
    echo "Genera un UUID nuevo desde Add New System."
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

cleanup_partial_installation() {
    warn "Limpiando instalacion parcial..."
    if command -v crontab &> /dev/null; then
        ({ crontab -l 2>/dev/null || true; } | grep -v "$INSTALL_DIR/rs_agent.sh" || true) | crontab - || true
    fi
    rm -rf "$INSTALL_DIR"
    rm -rf "$DATA_DIR"
    rm -f "$LOG_FILE"
    log "Instalacion parcial eliminada"
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

    AGENT_URL="${GITHUB_RAW_URL}/rs_agent.sh"

    if curl -fsSL "$AGENT_URL" -o "$INSTALL_DIR/rs_agent.sh"; then
        chmod +x "$INSTALL_DIR/rs_agent.sh"
        log "Agente descargado: $INSTALL_DIR/rs_agent.sh"
    else
        error "No se pudo descargar el agente desde GitHub"
        error ""
        error "URL intentada: $AGENT_URL"
        error ""
        error "Verifica que:"
        error "  - Tienes conexion a internet"
        error "  - GitHub es accesible desde este servidor"
        exit 1
    fi
}

download_uninstaller() {
    info "Descargando desinstalador desde GitHub..."

    UNINSTALLER_URL="${GITHUB_RAW_URL}/uninstall.sh"

    if curl -fsSL "$UNINSTALLER_URL" -o "$INSTALL_DIR/uninstall.sh"; then
        chmod +x "$INSTALL_DIR/uninstall.sh"
        log "Desinstalador descargado: $INSTALL_DIR/uninstall.sh"
    else
        error "No se pudo descargar el desinstalador desde GitHub"
        error ""
        error "URL intentada: $UNINSTALLER_URL"
        error ""
        error "Verifica que:"
        error "  - Tienes conexion a internet"
        error "  - GitHub es accesible desde este servidor"
        exit 1
    fi
}

write_agent_config() {
    info "Guardando configuracion local del agente..."

    cat > "$CONFIG_FILE" << CONFIG_EOF
AGENT_TOKEN='${AGENT_TOKEN}'
UUID='${UUID}'
CONFIG_EOF
    chmod 600 "$CONFIG_FILE"

    log "Configuracion guardada: $CONFIG_FILE"
}

setup_cron() {
    info "Configurando ejecucion automatica..."

    CRON_JOB="0 3 * * * /bin/bash $INSTALL_DIR/rs_agent.sh --token $AGENT_TOKEN --uuid $UUID >> $LOG_FILE 2>&1"

    # Anadir a crontab de root evitando duplicados
    ({ crontab -l 2>/dev/null || true; } | grep -v "$INSTALL_DIR/rs_agent.sh" || true; echo "$CRON_JOB") | crontab -

    log "Cron configurado (ejecucion diaria a las 3:00 AM)"
}

test_agent() {
    info "Ejecutando primera recopilacion..."

    set +e
    /bin/bash "$INSTALL_DIR/rs_agent.sh" --token "$AGENT_TOKEN" --uuid "$UUID" 2>&1 | tee -a "$LOG_FILE"
    local agent_status=${PIPESTATUS[0]}
    set -e

    if [ "$agent_status" -eq 0 ]; then
        if [ -f "$DATA_DIR/inventory.json" ]; then
            INVENTORY_SIZE=$(stat -c%s "$DATA_DIR/inventory.json" 2>/dev/null || stat -f%z "$DATA_DIR/inventory.json" 2>/dev/null)
            log "Inventario generado correctamente (${INVENTORY_SIZE} bytes)"
            return 0
        fi
    fi

    error "No se pudo generar y enviar el inventario en la primera ejecucion"
    info "El detalle del fallo se ha mostrado arriba."
    return 1
}

print_summary() {
    echo ""
    echo "============================================================================"
    echo "  INSTALACION COMPLETADA"
    echo "============================================================================"
    echo ""
    echo "Ubicaciones:"
    echo "   - Agente:      $INSTALL_DIR/rs_agent.sh"
    echo "   - Inventario:  $DATA_DIR/inventory.json"
    echo "   - Logs:        $LOG_FILE"
    echo ""
    echo "Ejecucion:"
    echo "   - Automatica:  Diariamente a las 3:00 AM"
    echo "   - Manual:      sudo bash $INSTALL_DIR/rs_agent.sh --token <AGENT_TOKEN> --uuid <UUID>"
    echo ""
    echo "Ver inventario:"
    echo "   cat $DATA_DIR/inventory.json"
    echo ""
    echo "Funcionamiento:"
    echo "   - Sin dependencia de Python ni jq (bash puro)"
    echo "   - Envia inventario completo en cada ejecucion a RSM"
    echo "   - RSM detecta y gestiona los cambios"
    echo "   - Optimizado para deteccion de vulnerabilidades CVE"
    echo "   - Incluye: OS, kernel, CPU, modelo de discos, paquetes, software critico"
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
    validate_uuid_format "$UUID"
    check_uuid_available
    check_existing_installation
    
    # Instalacion
    create_directories
    download_agent
    download_uninstaller
    write_agent_config
    
    # Prueba
    echo ""
    if ! test_agent; then
        echo ""
        error "Instalacion cancelada porque la primera ejecucion del agente ha fallado."
        error "Si el UUID ya pertenece a otro sistema, genera un UUID nuevo desde Add New System."
        cleanup_partial_installation
        exit 1
    fi

    setup_cron
    
    # Resumen
    print_summary
    
    log "Instalacion exitosa"
}

# Ejecutar
main "$@"
