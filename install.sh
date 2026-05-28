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

create_uninstaller() {
    cat > "$INSTALL_DIR/uninstall.sh" << 'UNINSTALL_EOF'
#!/bin/bash
echo "Desinstalando Redsauce Inventory Agent..."

RSM_BASE_URL="https://rsm1.redsauce.net/AppController/commands_RSM/api/v2"
RSM_TOKEN="__AGENT_TOKEN__"
SYSTEM_UUID="__UUID__"
RSM_SYSTEM_ITEM_TYPE_ID="${RSM_SYSTEM_ITEM_TYPE_ID:-191}"
RSM_PACKAGES_ITEM_TYPE_ID="${RSM_PACKAGES_ITEM_TYPE_ID:-192}"
RSM_FIRMWARE_ITEM_TYPE_ID="${RSM_FIRMWARE_ITEM_TYPE_ID:-193}"
RSM_CORE_SOFTWARE_ITEM_TYPE_ID="${RSM_CORE_SOFTWARE_ITEM_TYPE_ID:-194}"
RSM_ISSUE_ITEM_TYPE_ID="${RSM_ISSUE_ITEM_TYPE_ID:-195}"
RSM_CUSTOM_SOFTWARE_ITEM_TYPE_ID="${RSM_CUSTOM_SOFTWARE_ITEM_TYPE_ID:-197}"
RSM_DELETE_BATCH_SIZE="${RSM_DELETE_BATCH_SIZE:-100}"

echo
echo "[WARN] Esta accion desinstalara el agente y borrara todo lo relacionado"
echo "       con este sistema en este servidor:"
echo "       - Entrada de cron"
echo "       - Directorio del agente: /opt/rs-agent"
echo "       - Datos de inventario: /var/lib/rs-agent"
echo "       - Log del agente: /var/log/rs-agent.log"
echo "       - Datos RSM: System, Vulnerabilidades, Packages, Firmware, Core Software y Custom Software"
echo
read -p "Si estas de acuerdo, escribe 's' para continuar: " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Ss]$ ]]; then
    echo "[OK] Desinstalacion cancelada"
    exit 0
fi

rsm_request() {
    local endpoint="$1"
    local method="$2"
    local payload="$3"

    curl -fsS --location "${RSM_BASE_URL}/${endpoint}" \
        --request "$method" \
        --header "Authorization: ${RSM_TOKEN}" \
        --header "Content-Type: application/json" \
        --data "$payload"
}

json_ids() {
    grep -oE '"ID"[[:space:]]*:[[:space:]]*"?[0-9]+"?' \
        | grep -oE '[0-9]+' \
        | paste -sd, -
}

json_first_item_type_id() {
    grep -oE '"(itemTypeID|itemTypeId|ItemTypeID|item_type_id)"[[:space:]]*:[[:space:]]*"?[0-9]+"?' \
        | head -1 \
        | grep -oE '[0-9]+' || true
}

json_array_from_csv() {
    local csv="$1"
    local result="" id
    IFS=',' read -ra ids <<< "$csv"
    for id in "${ids[@]}"; do
        [ -z "$id" ] && continue
        if [ -n "$result" ]; then
            result="${result},"
        fi
        result="${result}\"${id}\""
    done
    printf '[%s]' "$result"
}

csv_count() {
    local csv="$1"
    if [ -z "$csv" ]; then
        printf '0'
        return 0
    fi
    awk -F, '{print NF}' <<EOF
$csv
EOF
}

csv_preview() {
    local csv="$1"
    local count
    count=$(csv_count "$csv")
    if [ "$count" -le 10 ]; then
        printf '%s' "$csv"
    else
        printf '%s... (%s registros)' "$(printf '%s' "$csv" | cut -d, -f1-10)" "$count"
    fi
}

rsm_get_by_filter() {
    local property_ids="$1"
    local filter_property="$2"
    local filter_value="$3"
    local payload
    payload="{\"propertyIDs\":${property_ids},\"filterRules\":[{\"propertyID\":\"${filter_property}\",\"value\":\"${filter_value}\",\"operation\":\"=\"}]}"
    rsm_request "items/get.php" "GET" "$payload"
}

rsm_delete_ids() {
    local label="$1"
    local item_type_id="$2"
    local ids_csv="$3"
    local ids_label batch="" batch_count=0 total_count=0 had_errors=0 id ids_json payload response

    if [ -z "$ids_csv" ]; then
        echo "[OK] RSM ${label}: sin registros"
        return 0
    fi

    ids_label=$(csv_preview "$ids_csv")
    if [ -z "$item_type_id" ]; then
        echo "[WARN] RSM ${label}: no se pudo determinar itemTypeID; no se puede borrar (${ids_label})"
        return 1
    fi

    IFS=',' read -ra ids <<< "$ids_csv"
    for id in "${ids[@]}"; do
        [ -z "$id" ] && continue
        if [ -n "$batch" ]; then
            batch="${batch},${id}"
        else
            batch="$id"
        fi
        batch_count=$((batch_count + 1))
        total_count=$((total_count + 1))

        if [ "$batch_count" -ge "$RSM_DELETE_BATCH_SIZE" ]; then
            ids_json=$(json_array_from_csv "$batch")
            payload="[{\"itemTypeID\":\"${item_type_id}\",\"IDs\":${ids_json}}]"
            response=$(rsm_request "items/delete.php" "DELETE" "$payload" 2>&1)
            if [ $? -ne 0 ]; then
                echo "[WARN] RSM ${label}: fallo al borrar lote (${batch_count} registros)"
                [ -n "$response" ] && echo "[WARN] RSM ${label}: respuesta: ${response}"
                had_errors=1
            fi
            batch=""
            batch_count=0
        fi
    done

    if [ -n "$batch" ]; then
        ids_json=$(json_array_from_csv "$batch")
        payload="[{\"itemTypeID\":\"${item_type_id}\",\"IDs\":${ids_json}}]"
        response=$(rsm_request "items/delete.php" "DELETE" "$payload" 2>&1)
        if [ $? -ne 0 ]; then
            echo "[WARN] RSM ${label}: fallo al borrar lote (${batch_count} registros)"
            [ -n "$response" ] && echo "[WARN] RSM ${label}: respuesta: ${response}"
            had_errors=1
        fi
    fi

    if [ "$had_errors" -eq 0 ]; then
        echo "[OK] RSM ${label}: registros eliminados (${ids_label})"
        return 0
    fi

    echo "[WARN] RSM ${label}: fallo al borrar uno o mas lotes (${ids_label})"
    return 1
}

rsm_system_exists() {
    local system_id="$1"
    local response ids

    response=$(rsm_request "items/get.php" "GET" "{\"IDs\":[\"${system_id}\"],\"propertyIDs\":[\"1749\"]}" 2>/dev/null) || return 0
    ids=$(printf '%s' "$response" | json_ids)
    [ -n "$ids" ]
}

delete_rsm_inventory() {
    local response system_id system_type ids type had_errors=0

    if ! command -v curl >/dev/null 2>&1; then
        echo "[WARN] curl no esta disponible; no se pueden borrar datos en RSM"
        return 1
    fi

    echo "Eliminando datos del sistema en RSM..."

    response=$(rsm_get_by_filter '["1749"]' "1780" "$SYSTEM_UUID" 2>/dev/null) || {
        echo "[WARN] No se pudo consultar el System en RSM"
        return 1
    }

    system_id=$(printf '%s' "$response" | json_ids | cut -d, -f1)
    system_type=$(printf '%s' "$response" | json_first_item_type_id)
    [ -z "$system_type" ] && system_type="$RSM_SYSTEM_ITEM_TYPE_ID"

    if [ -z "$system_id" ]; then
        echo "[OK] RSM System: no existe System para UUID ${SYSTEM_UUID}"
        return 0
    fi

    echo "[OK] RSM System encontrado: ${system_id}"

    response=$(rsm_get_by_filter '["1776"]' "1776" "$system_id" 2>/dev/null || true)
    ids=$(printf '%s' "$response" | json_ids)
    type=$(printf '%s' "$response" | json_first_item_type_id)
    [ -z "$type" ] && type="$RSM_ISSUE_ITEM_TYPE_ID"
    rsm_delete_ids "Vulnerabilidades" "$type" "$ids" || had_errors=1

    response=$(rsm_get_by_filter '["1763"]' "1763" "$system_id" 2>/dev/null || true)
    ids=$(printf '%s' "$response" | json_ids)
    type=$(printf '%s' "$response" | json_first_item_type_id)
    [ -z "$type" ] && type="$RSM_PACKAGES_ITEM_TYPE_ID"
    rsm_delete_ids "Packages" "$type" "$ids" || had_errors=1

    response=$(rsm_get_by_filter '["1767"]' "1767" "$system_id" 2>/dev/null || true)
    ids=$(printf '%s' "$response" | json_ids)
    type=$(printf '%s' "$response" | json_first_item_type_id)
    [ -z "$type" ] && type="$RSM_FIRMWARE_ITEM_TYPE_ID"
    rsm_delete_ids "Firmware" "$type" "$ids" || had_errors=1

    response=$(rsm_get_by_filter '["1771"]' "1771" "$system_id" 2>/dev/null || true)
    ids=$(printf '%s' "$response" | json_ids)
    type=$(printf '%s' "$response" | json_first_item_type_id)
    [ -z "$type" ] && type="$RSM_CORE_SOFTWARE_ITEM_TYPE_ID"
    rsm_delete_ids "Core Software" "$type" "$ids" || had_errors=1

    response=$(rsm_get_by_filter '["1793"]' "1793" "$system_id" 2>/dev/null || true)
    ids=$(printf '%s' "$response" | json_ids)
    type=$(printf '%s' "$response" | json_first_item_type_id)
    [ -z "$type" ] && type="$RSM_CUSTOM_SOFTWARE_ITEM_TYPE_ID"
    rsm_delete_ids "Custom Software" "$type" "$ids" || had_errors=1

    rsm_delete_ids "System" "$system_type" "$system_id" || had_errors=1

    if rsm_system_exists "$system_id"; then
        echo "[ERROR] RSM System ${system_id} sigue existiendo; se cancela la desinstalacion local"
        return 1
    fi

    if [ "$had_errors" -ne 0 ]; then
        echo "[WARN] Hubo errores borrando registros relacionados, pero el System ya no existe en RSM"
    fi

    return 0
}

if ! delete_rsm_inventory; then
    echo "[ERROR] No se completo el borrado en RSM. No se eliminan archivos locales para poder reintentar."
    exit 1
fi

# Eliminar cron
crontab -l 2>/dev/null | grep -v "/opt/rs-agent/rs_agent.sh" | crontab -
echo "[OK] Entrada de cron eliminada"

rm -rf /var/lib/rs-agent
echo "[OK] Datos eliminados"
rm -rf /opt/rs-agent
rm -f /var/log/rs-agent.log

echo "[OK] Agente desinstalado"
UNINSTALL_EOF

    sed -i "s|__AGENT_TOKEN__|$AGENT_TOKEN|g" "$INSTALL_DIR/uninstall.sh"
    sed -i "s|__UUID__|$UUID|g" "$INSTALL_DIR/uninstall.sh"
    
    chmod +x "$INSTALL_DIR/uninstall.sh"
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
    
    # Instalacion
    create_directories
    download_agent
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
