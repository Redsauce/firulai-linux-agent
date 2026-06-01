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

check_existing_installation() {
    if [ -f "$INSTALL_DIR/rs_agent.sh" ] || [ -f "$CONFIG_FILE" ]; then
        warn "Ya existe una instalación previa del agente en este sistema."
        warn "Si deseas instalar un nuevo agente, desinstala el actual primero:"
        warn "  sudo bash $INSTALL_DIR/uninstall.sh"
        exit 1
    fi
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

    if /bin/bash "$INSTALL_DIR/rs_agent.sh" --token "$AGENT_TOKEN" --uuid "$UUID" >> "$LOG_FILE" 2>&1; then
        if [ -f "$DATA_DIR/inventory.json" ]; then
            INVENTORY_SIZE=$(stat -c%s "$DATA_DIR/inventory.json" 2>/dev/null || stat -f%z "$DATA_DIR/inventory.json" 2>/dev/null)
            log "Inventario generado correctamente (${INVENTORY_SIZE} bytes)"
            return 0
        fi
    fi

    warn "No se pudo generar el inventario en la primera ejecucion"
    info "Revisa el log: tail -f $LOG_FILE"
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
    check_existing_installation
    
    # Instalacion
    create_directories
    download_agent
    download_uninstaller
    write_agent_config
    setup_cron
    
    # Prueba
    echo ""
    test_agent
    
    # Resumen
    print_summary
    
    log "Instalacion exitosa"
}

# Ejecutar
main "$@"
