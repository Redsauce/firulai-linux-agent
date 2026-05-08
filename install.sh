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
    
    # Verificar Python 3
    if ! command -v python3 &> /dev/null; then
        warn "Python 3 no esta instalado, instalando..."
        install_python
    else
        log "Python 3 encontrado: $(python3 --version)"
    fi
}

install_python() {
    case $DISTRO in
        ubuntu|debian)
            apt-get update -qq
            apt-get install -y python3 python3-pip python3-requests lsb-release util-linux iproute2 > /dev/null 2>&1
            ;;
        rhel|centos|fedora|rocky|almalinux)
            if command -v dnf &> /dev/null; then
                dnf install -y python3 python3-pip python3-requests util-linux iproute > /dev/null 2>&1
            else
                yum install -y python3 python3-pip python3-requests util-linux iproute > /dev/null 2>&1
            fi
            ;;
        *)
            error "Distribucion no soportada: $DISTRO"
            exit 1
            ;;
    esac
    log "Dependencias instaladas"
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
    
    AGENT_URL="${GITHUB_RAW_URL}/rs_agent.py"
    
    # Descargar con curl
    if curl -fsSL "$AGENT_URL" -o "$INSTALL_DIR/rs_agent.py"; then
        chmod +x "$INSTALL_DIR/rs_agent.py"
        log "Agente descargado: $INSTALL_DIR/rs_agent.py"
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

download_analyzer() {
    info "Descargando herramienta de analisis..."
    
    ANALYZER_URL="${GITHUB_RAW_URL}/analyze_inventory.py"
    
    if curl -fsSL "$ANALYZER_URL" -o "$INSTALL_DIR/analyze_inventory.py"; then
        chmod +x "$INSTALL_DIR/analyze_inventory.py"
        log "Analizador descargado: $INSTALL_DIR/analyze_inventory.py"
    else
        warn "No se pudo descargar el analizador (opcional)"
    fi
}

setup_cron() {
    info "Configurando ejecucion automatica..."

    echo "DEBUG TOKEN: $AGENT_TOKEN"
    echo "DEBUG UUID: $UUID"
    echo "DEBUG INSTALL_DIR: $INSTALL_DIR"
    
    CRON_JOB="0 3 * * * /usr/bin/python3 $INSTALL_DIR/rs_agent.py --token $AGENT_TOKEN --uuid $UUID >> $LOG_FILE 2>&1"
    echo "DEBUG CRON_JOB: $CRON_JOB"
        
    # Anadir a crontab de root (evitar duplicados)
    ({ crontab -l 2>/dev/null || true; } | grep -v "$INSTALL_DIR/rs_agent.py" || true; echo "$CRON_JOB") | crontab -

    log "Cron configurado (ejecucion diaria a las 3:00 AM)"
}

test_agent() {
    info "Ejecutando primera recopilacion..."
    
    if /usr/bin/python3 "$INSTALL_DIR/rs_agent.py" --token "$AGENT_TOKEN" --uuid "$UUID" >> "$LOG_FILE" 2>&1; then
        if [ -f "$DATA_DIR/inventory.json" ]; then
            INVENTORY_SIZE=$(stat -f%z "$DATA_DIR/inventory.json" 2>/dev/null || stat -c%s "$DATA_DIR/inventory.json" 2>/dev/null)
            log "Inventario generado correctamente (${INVENTORY_SIZE} bytes)"
            return 0
        fi
    fi
    
    warn "No se pudo generar el inventario en la primera ejecucion"
    info "Revisa el log: tail -f $LOG_FILE"
    return 1
}

create_uninstaller() {
    cat > "$INSTALL_DIR/uninstall.sh" << 'UNINSTALL_EOF'
#!/bin/bash
echo "Desinstalando Redsauce Inventory Agent..."

# Eliminar cron
crontab -l 2>/dev/null | grep -v "/opt/rs-agent/rs_agent.py" | crontab -
echo "[OK] Entrada de cron eliminada"

# Preguntar antes de borrar datos
read -p "Eliminar datos de inventario? (s/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Ss]$ ]]; then
    rm -rf /var/lib/rs-agent
    echo "[OK] Datos eliminados"
fi

rm -rf /opt/rs-agent
rm -f /var/log/rs-agent.log

echo "[OK] Agente desinstalado"
UNINSTALL_EOF
    
    chmod +x "$INSTALL_DIR/uninstall.sh"
}

print_summary() {
    echo ""
    echo "============================================================================"
    echo "  INSTALACION COMPLETADA"
    echo "============================================================================"
    echo ""
    echo "Ubicaciones:"
    echo "   - Agente:      $INSTALL_DIR/rs_agent.py"
    echo "   - Analizador:  $INSTALL_DIR/analyze_inventory.py"
    echo "   - Inventario:  $DATA_DIR/inventory.json"
    echo "   - Logs:        $LOG_FILE"
    echo ""
    echo "Ejecucion:"
    echo "   - Automatica:  Diariamente a las 3:00 AM"
    echo "   - Manual:      sudo python3 $INSTALL_DIR/rs_agent.py --token <AGENT_TOKEN> --uuid <UUID>"
    echo ""
    echo "Ver inventario:"
    echo "   cat $DATA_DIR/inventory.json | python3 -m json.tool"
    echo ""
    echo "Analizar inventario:"
    echo "   sudo python3 $INSTALL_DIR/analyze_inventory.py"
    echo ""
    echo "Funcionamiento:"
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
    
    # Instalacion
    create_directories
    download_agent
    download_analyzer
    setup_cron
    create_uninstaller
    
    # Prueba
    echo ""
    test_agent
    
    # Resumen
    print_summary
    
    log "Instalacion exitosa"
}

# Ejecutar
main "$@"