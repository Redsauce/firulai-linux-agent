#!/bin/bash
# -*- coding: utf-8 -*-
#
# Redsauce Inventory Agent
# Version: 0.3.0 - Reescrito en bash puro (sin Python, sin jq)
# Requiere: root, bash 4+, curl, lscpu, lsblk, uname
#

set -uo pipefail

# ============ CONFIGURACION ============

AGENT_VERSION="0.3.1"
GITHUB_API_URL="https://api.github.com/repos/redsauce/inventory-agent/releases/latest"
GITHUB_AGENT_URL="https://raw.githubusercontent.com/redsauce/inventory-agent/main/rs_agent.sh"
OUTPUT_DIR="/var/lib/rs-agent"
OUTPUT_FILE="inventory.json"
RSM_API_URL="https://rsm1.redsauce.net/AppController/commands_RSM/api/api.php"
RSM_ITEMS_GET_URL="https://rsm1.redsauce.net/AppController/commands_RSM/api/v2/items/get.php"
RSM_SYSTEM_HOSTNAME_PROPERTY_ID="1749"
RSM_SYSTEM_FQDN_PROPERTY_ID="1750"
RSM_SYSTEM_UUID_PROPERTY_ID="1780"
AGENT_TOKEN=""
RSTOKEN=""
UUID_VAL=""
SYSTEM_ALIAS=""

# ============ UTILIDADES ============

# Escapa un string para incrustarlo como valor JSON (sin jq).
# Orden de sustituciones: primero la barra invertida para no doble-escapar.
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

# Extrae el primer patron semver o X.Y de un string.
extract_version() {
    printf '%s' "$1" | grep -oE '[0-9]+\.[0-9]+(\.[0-9a-zA-Z_-]+)?' | head -1
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

# ============ VALIDACION Y ARGUMENTOS ============

check_root() {
    if [ "${EUID:-$(id -u)}" -ne 0 ]; then
        echo "ERROR: Este script requiere permisos de root"
        echo "   Ejecuta con: sudo bash rs_agent.sh --token TOKEN --rstoken RSTOKEN --uuid UUID --alias ALIAS"
        exit 1
    fi
}

validate_uuid() {
    local uuid="$1"
    if [[ ! "$uuid" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
        echo "ERROR: '$uuid' no es un UUID valido"
        exit 1
    fi
}

parse_args() {
    if [ $# -eq 0 ]; then
        echo "Uso: sudo bash rs_agent.sh --token <TOKEN> --rstoken <RSTOKEN> --uuid <UUID> --alias <ALIAS>"
        exit 1
    fi

    while [ $# -gt 0 ]; do
        case "$1" in
            --token)
                [ $# -ge 2 ] || { echo "ERROR: --token requiere un valor"; exit 1; }
                AGENT_TOKEN="$2"
                shift 2
                ;;
            --rstoken)
                [ $# -ge 2 ] || { echo "ERROR: --rstoken requiere un valor"; exit 1; }
                RSTOKEN="$2"
                shift 2
                ;;
            --uuid)
                [ $# -ge 2 ] || { echo "ERROR: --uuid requiere un valor"; exit 1; }
                UUID_VAL="$2"
                shift 2
                ;;
            --alias)
                [ $# -ge 2 ] || { echo "ERROR: --alias requiere un valor"; exit 1; }
                SYSTEM_ALIAS="$2"
                shift 2
                ;;
            *) echo "Argumento desconocido: $1"; exit 1 ;;
        esac
    done

    if [ -z "$AGENT_TOKEN" ] || [ -z "$RSTOKEN" ] || [ -z "$UUID_VAL" ] || [ -z "$SYSTEM_ALIAS" ]; then
        echo "ERROR: --token, --rstoken, --uuid y --alias son obligatorios"
        exit 1
    fi

    validate_uuid "$UUID_VAL"
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

validate_uuid_ownership() {
    local payload response_file http_code exit_code response_body
    response_file="/tmp/rsm_uuid_check_response.txt"
    payload="{\"propertyIDs\":[\"$RSM_SYSTEM_HOSTNAME_PROPERTY_ID\",\"$RSM_SYSTEM_FQDN_PROPERTY_ID\",\"$RSM_SYSTEM_UUID_PROPERTY_ID\"],\"translateIDs\":true,\"filterRules\":[{\"propertyID\":\"$RSM_SYSTEM_UUID_PROPERTY_ID\",\"value\":\"$UUID_VAL\",\"operation\":\"=\"}]}"

    echo "Validando que el UUID no pertenece a otro sistema..."

    http_code=$(curl \
        --silent \
        --show-error \
        --output "$response_file" \
        --write-out '%{http_code}' \
        --location "$RSM_ITEMS_GET_URL" \
        --request GET \
        --header "Authorization: $RSTOKEN" \
        --header "Content-Type: application/json" \
        --data "$payload" \
        --max-time 20)
    exit_code=$?
    response_body=$(cat "$response_file" 2>/dev/null || true)

    if [ "$exit_code" -ne 0 ]; then
        echo "ERROR: No se pudo validar el UUID antes de enviar inventario (curl exit: $exit_code)."
        echo "Por seguridad, la instalación no continuará sin confirmar que el UUID no pertenece a otro sistema."
        return 1
    fi

    if [ "$http_code" != "200" ] && [ "$http_code" != "201" ]; then
        echo "ERROR: RSM no permitió validar el UUID antes de enviar inventario (HTTP $http_code)."
        echo "Por seguridad, la instalación no continuará sin confirmar que el UUID no pertenece a otro sistema."
        echo "Respuesta: $response_body"
        return 1
    fi

    if ! printf '%s' "$response_body" | grep -Fq "$UUID_VAL"; then
        echo "ERROR: UUID inválido: no existe en RSM."
        echo "No se puede enviar inventario con un UUID que no haya sido generado desde Add New System."
        echo ""
        echo "UUID: $UUID_VAL"
        return 1
    fi

    local existing_hostname existing_fqdn
    existing_hostname=$(json_extract_rsm_property "$response_body" "$RSM_SYSTEM_HOSTNAME_PROPERTY_ID")
    existing_fqdn=$(json_extract_rsm_property "$response_body" "$RSM_SYSTEM_FQDN_PROPERTY_ID")

    if [ -z "$existing_hostname" ] && [ -z "$existing_fqdn" ]; then
        echo "   -> UUID reservado en RSM y listo para instalar"
        return 0
    fi

    if identity_matches_local_system "$existing_hostname" "$existing_fqdn"; then
        echo "   -> UUID ya asociado a este sistema, se actualizará su inventario"
        return 0
    fi

    echo ""
    echo "ERROR: Este UUID ya pertenece a otro sistema en RSM."
    echo "No se puede instalar este agente en el equipo local con ese UUID."
    return 1
}

# ============ RECOPILADORES ============

collect_system_info() {
    local timezone=""
    [ $# -gt 0 ] && timezone="$1"
    local hostname fqdn kernel arch
    local os_name="Unknown" os_version="Unknown" distro_id="unknown" distro_version="Unknown"

    hostname=$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo "unknown")
    fqdn=$(hostname -f 2>/dev/null || hostname 2>/dev/null || echo "unknown")
    kernel=$(uname -r 2>/dev/null || echo "unknown")
    arch=$(uname -m 2>/dev/null || echo "unknown")

    if [ -f /etc/os-release ]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        os_name="${NAME:-Unknown}"
        os_version="${VERSION:-Unknown}"
        distro_id="${ID:-unknown}"
        distro_version="${VERSION_ID:-Unknown}"
    elif [ -f /etc/redhat-release ]; then
        os_name=$(cat /etc/redhat-release 2>/dev/null || echo "Unknown")
        distro_id="rhel-based"
    elif [ -f /etc/debian_version ]; then
        os_name="Debian"
        os_version=$(cat /etc/debian_version 2>/dev/null || echo "Unknown")
        distro_id="debian"
        distro_version="$os_version"
    fi

    local collected_at
    collected_at=$(date '+%Y-%m-%d %H:%M:%S')

    printf '{"hostname":"%s","fqdn":"%s","uuid":"%s","alias":"%s","os":{"name":"%s","version":"%s","distro_id":"%s","distro_version":"%s","kernel":"%s","architecture":"%s"},"collected_at":"%s","timezone":"%s","agent_version":"%s"}' \
        "$(json_escape "$hostname")" \
        "$(json_escape "$fqdn")" \
        "$(json_escape "$UUID_VAL")" \
        "$(json_escape "$SYSTEM_ALIAS")" \
        "$(json_escape "$os_name")" \
        "$(json_escape "$os_version")" \
        "$(json_escape "$distro_id")" \
        "$(json_escape "$distro_version")" \
        "$(json_escape "$kernel")" \
        "$(json_escape "$arch")" \
        "$(json_escape "$collected_at")" \
        "$(json_escape "$timezone")" \
        "$(json_escape "$AGENT_VERSION")"
}

collect_timezone() {
    local timezone_name=""

    # Intentar con timedatectl
    if command -v timedatectl &>/dev/null; then
        timezone_name=$(timedatectl show -p Timezone --value 2>/dev/null) || true
    fi

    # Fallback: leer /etc/timezone
    if [ -z "$timezone_name" ] && [ -f "/etc/timezone" ]; then
        timezone_name=$(cat /etc/timezone 2>/dev/null) || true
    fi

    printf '%s' "$timezone_name"
}

collect_hardware() {
    local cpu_model firmware_json="" first=1

    # CPU: extraer "Model name" con awk para manejar espacios correctamente
    cpu_model=$(lscpu 2>/dev/null | awk -F':[[:space:]]+' '/^Model name/{print $2; exit}')
    [ -z "$cpu_model" ] && cpu_model="Unknown"

    # Discos: awk extrae NAME y MODEL (puede tener espacios), filtrando solo discos
    while IFS=$'\t' read -r dev model; do
        [ -z "$dev" ] && continue
        [ -z "$model" ] && model="Unknown"

        [ "$first" = "1" ] && first=0 || firmware_json+=","
        firmware_json+="{\"device\":\"/dev/$(json_escape "$dev")\",\"model\":\"$(json_escape "$model")\"}"
    done < <(lsblk -d -o NAME,TYPE,MODEL -n 2>/dev/null \
        | awk '$2=="disk" {
            dev=$1
            model=""
            for(i=3; i<=NF; i++) model=(model=="" ? $i : model" "$i)
            if(model=="") model="Unknown"
            print dev "\t" model
          }')

    printf '{"cpu_model":"%s","firmware":[%s]}' \
        "$(json_escape "$cpu_model")" \
        "$firmware_json"
}

collect_packages_dpkg() {
    local packages_json="" first=1

    while IFS=$'\t' read -r name version status; do
        [ -z "$name" ] && continue
        # Solo paquetes con estado "installed"
        case "$status" in *"installed"*) ;; *) continue ;; esac

        [ "$first" = "1" ] && first=0 || packages_json+=","
        packages_json+="{\"name\":\"$(json_escape "$name")\",\"version\":\"$(json_escape "$version")\",\"manager\":\"dpkg\"}"
    done < <(dpkg-query -W -f='${Package}\t${Version}\t${Status}\n' 2>/dev/null)

    printf '%s' "$packages_json"
}

collect_packages_rpm() {
    local packages_json="" first=1

    while IFS=$'\t' read -r name version; do
        [ -z "$name" ] && continue

        [ "$first" = "1" ] && first=0 || packages_json+=","
        packages_json+="{\"name\":\"$(json_escape "$name")\",\"version\":\"$(json_escape "$version")\",\"manager\":\"rpm\"}"
    done < <(rpm -qa --queryformat '%{NAME}\t%{VERSION}-%{RELEASE}\n' 2>/dev/null)

    printf '%s' "$packages_json"
}

collect_packages() {
    if command -v dpkg-query &>/dev/null; then
        collect_packages_dpkg
    elif command -v rpm &>/dev/null; then
        collect_packages_rpm
    fi
}

collect_pip_packages() {
    local packages_json="" first=1
    local pip_cmd=""

    command -v pip3 &>/dev/null && pip_cmd="pip3"
    { command -v pip &>/dev/null && [ -z "$pip_cmd" ]; } && pip_cmd="pip"
    [ -z "$pip_cmd" ] && return

    # --format=columns produce: "Package    Version" con 2 lineas de cabecera (nombre + separador)
    # tail -n +3 las elimina; el tercer campo (_rest) absorbe cualquier anotacion extra
    while read -r name version _rest; do
        [ -z "$name" ] && continue

        [ "$first" = "1" ] && first=0 || packages_json+=","
        packages_json+="{\"name\":\"$(json_escape "$name")\",\"version\":\"$(json_escape "$version")\",\"manager\":\"pip\"}"
    done < <("$pip_cmd" list --format=columns 2>/dev/null | tail -n +3)

    printf '%s' "$packages_json"
}

collect_npm_packages() {
    local packages_json="" first=1

    command -v npm &>/dev/null || return

    # "npm list -g --depth=0" produce lineas como:
    #   ├── package@1.2.3
    #   └── @scope/package@4.5.6
    # Se eliminan los prefijos de arbol con sed y se separa nombre/version
    # por el ultimo "@" (soporta scoped packages como @angular/cli@16.0.0)
    while IFS= read -r line; do
        # Quitar prefijo de arbol (caracteres hasta e incluyendo "── ")
        local pkg_ver
        pkg_ver=$(printf '%s' "$line" | sed 's/^.*── //' | tr -d ' ')
        [[ "$pkg_ver" == *"@"* ]] || continue

        local version="${pkg_ver##*@}"   # todo despues del ultimo @
        local name="${pkg_ver%@*}"       # todo antes del ultimo @

        # Limpiar anotaciones tipo " deduped" o " extraneous"
        version="${version%% *}"

        [ -z "$name" ] || [ -z "$version" ] && continue

        [ "$first" = "1" ] && first=0 || packages_json+=","
        packages_json+="{\"name\":\"$(json_escape "$name")\",\"version\":\"$(json_escape "$version")\",\"manager\":\"npm\"}"
    done < <(npm list -g --depth=0 2>/dev/null | grep -E '[├└]')

    printf '%s' "$packages_json"
}

collect_core_software() {
    local software_json="" first=1

    # Arrays paralelos: nombre | comando | capturar stderr (1=si, 0=no)
    # stderr=1 para programas que imprimen la version en stderr (nginx, java, ssh...)
    local names=("apache2"    "httpd"    "nginx"    "mysql"            "mysqld"            "postgresql"     "postgres"           "docker"            "php"            "node"            "java"          "openssh"  "openssl"           "git")
    local cmds=( "apache2 -v" "httpd -v" "nginx -v" "mysql --version"  "mysqld --version"  "psql --version" "postgres --version" "docker --version"  "php --version"  "node --version"  "java -version" "ssh -V"   "openssl version"   "git --version")
    local use_stderr=(1       1          1           0                  0                   0                0                    0                   0                0                 1               1          0                   0)

    local i
    for i in "${!names[@]}"; do
        local name="${names[$i]}"
        local cmd="${cmds[$i]}"
        local binary="${cmd%% *}"

        command -v "$binary" &>/dev/null || continue

        local raw_output=""
        if [ "${use_stderr[$i]}" = "1" ]; then
            raw_output=$(timeout 10 bash -c "$cmd" 2>&1 | head -1 || true)
        else
            raw_output=$(timeout 10 bash -c "$cmd" 2>/dev/null | head -1 || true)
        fi

        [ -z "$raw_output" ] && continue

        local version
        version=$(extract_version "$raw_output")
        [ -z "$version" ] && version="unknown"

        [ "$first" = "1" ] && first=0 || software_json+=","
        software_json+="{\"name\":\"$(json_escape "$name")\",\"version\":\"$(json_escape "$version")\",\"raw_output\":\"$(json_escape "$raw_output")\"}"
    done

    printf '%s' "$software_json"
}

# ============ AUTO-ACTUALIZACION ============

check_for_updates() {
    command -v curl &>/dev/null || return 0

    local response latest_version
    response=$(curl -sf --max-time 5 "$GITHUB_API_URL" 2>/dev/null) || return 0

    # Extraer "tag_name" del JSON sin jq: buscar el patron "tag_name":"vX.Y.Z"
    latest_version=$(printf '%s' "$response" \
        | grep -o '"tag_name":"[^"]*"' \
        | sed 's/"tag_name":"v\?//;s/"//')

    [ -z "$latest_version" ] && return 0
    [ "$latest_version" = "$AGENT_VERSION" ] && return 0

    echo "Nueva version disponible: $latest_version (actual: $AGENT_VERSION)"
    download_update
}

download_update() {
    local script_path="/opt/rs-agent/rs_agent.sh"
    local backup_path="${script_path}.backup"

    echo "Descargando actualización..."
    [ -f "$script_path" ] && cp "$script_path" "$backup_path"

    if curl -fsSL --max-time 10 "$GITHUB_AGENT_URL" -o "$script_path"; then
        chmod +x "$script_path"
        echo "Actualización completada. Reiniciando agente..."
        exec bash "$script_path" --token "$AGENT_TOKEN" --rstoken "$RSTOKEN" --uuid "$UUID_VAL" --alias "$SYSTEM_ALIAS"
    else
        echo "Error descargando actualización"
        [ -f "$backup_path" ] && mv "$backup_path" "$script_path"
    fi
}

# ============ ENVIO A RSM ============

send_to_rsm() {
    local inventory_json="$1"
    local debug_json_path="/tmp/rsm_debug_payload.json"

    echo ""
    echo "Enviando inventario a RSM..."

    printf '%s' "$inventory_json" > "$debug_json_path"
    printf 'JSON guardado en: %s\n' "$debug_json_path"
    printf 'Longitud: %d caracteres (%d KB aprox)\n' "${#inventory_json}" "$(( ${#inventory_json} / 1024 ))"

    echo ""
    echo "Configuración RSM:"
    echo "   - URL:   $RSM_API_URL"
    echo "   - Token agente: ${AGENT_TOKEN:0:10}..."
    echo "   - RSToken en RSdata: ${RSTOKEN:0:10}..."
    echo "   - Alias: $SYSTEM_ALIAS"
    echo ""
    echo "Ejecutando petición a RSM..."

    local response_file="/tmp/rsm_response.txt"
    local http_code
    http_code=$(curl \
        --silent \
        --show-error \
        --output "$response_file" \
        --write-out '%{http_code}' \
        --location "$RSM_API_URL" \
        --form "RStrigger=newServerData" \
        --form "RSdata=$inventory_json" \
        --form "RStoken=$AGENT_TOKEN" \
        --max-time 30)
    local exit_code=$?
    local response_body
    response_body=$(cat "$response_file" 2>/dev/null || true)

    if [ "$exit_code" -ne 0 ]; then
        echo ""
        echo "ERROR: Fallo al enviar inventario a RSM (curl exit: $exit_code)"
        echo "Respuesta: $response_body"
        return 1
    fi

    if [ "$http_code" = "409" ] || echo "$response_body" | grep -iqE 'uuid.*(exists|ya existe)|already exists|duplicate|pertenece a otro sistema'; then
        echo ""
        echo "ERROR: RSM indica que el UUID ya existe o pertenece a otro sistema."
        echo "No se puede instalar este agente en el equipo local con ese UUID."
        echo "Respuesta: $response_body"
        return 1
    fi

    if [ "$http_code" != "200" ] && [ "$http_code" != "201" ]; then
        echo ""
        echo "ERROR: RSM devolvió HTTP $http_code"
        echo "Respuesta: $response_body"
        return 1
    fi

    echo ""
    printf 'Inventario enviado correctamente (%d KB)\n' "$(( ${#inventory_json} / 1024 ))"
    return 0
}

# ============ MAIN ============

main() {
    parse_args "$@"

    echo ""
    echo "============================================================"
    printf  'Redsauce Inventory Agent v%s - Recopilando informacion\n' "$AGENT_VERSION"
    echo "============================================================"
    echo ""

    check_root
    check_for_updates
    validate_uuid_ownership
    mkdir -p "$OUTPUT_DIR"

    # --- Timezone ---
    echo "Recopilando información de timezone..."
    local timezone
    timezone=$(collect_timezone)
    [ -z "$timezone" ] && timezone=""
    echo "   -> Timezone: ${timezone:-desconocido}"

    # --- Sistema ---
    echo "Recopilando información del sistema..."
    local system_json
    system_json=$(collect_system_info "$timezone")
    if [ -z "$system_json" ]; then
        echo "ERROR: No se pudo recopilar la información del sistema"
        exit 1
    fi

    # --- Hardware ---
    echo "Recopilando información de hardware..."
    local hardware_json
    hardware_json=$(collect_hardware)
    local firmware_count
    firmware_count=$(printf '%s' "$hardware_json" | grep -o '"device"' | wc -l | tr -d ' ')
    echo "   -> ${firmware_count} firmware(s) detectado(s)"

    # --- Paquetes del sistema ---
    echo "Recopilando paquetes del sistema..."
    local sys_json sys_count=0
    sys_json=$(collect_packages)
    [ -n "$sys_json" ] && sys_count=$(printf '%s' "$sys_json" | grep -o '"manager"' | wc -l | tr -d ' ')
    echo "   -> ${sys_count} paquetes del sistema"

    # --- Paquetes Python ---
    echo "Recopilando paquetes Python..."
    local pip_json pip_count=0
    pip_json=$(collect_pip_packages)
    [ -n "$pip_json" ] && pip_count=$(printf '%s' "$pip_json" | grep -o '"manager":"pip"' | wc -l | tr -d ' ')
    echo "   -> ${pip_count} paquetes Python"

    # --- Paquetes Node.js ---
    echo "Recopilando paquetes Node.js..."
    local npm_json npm_count=0
    npm_json=$(collect_npm_packages)
    [ -n "$npm_json" ] && npm_count=$(printf '%s' "$npm_json" | grep -o '"manager":"npm"' | wc -l | tr -d ' ')
    echo "   -> ${npm_count} paquetes Node.js"

    # Unificar todos los paquetes en un array JSON
    local all_packages_json=""
    for part in "$sys_json" "$pip_json" "$npm_json"; do
        [ -z "$part" ] && continue
        [ -n "$all_packages_json" ] && all_packages_json+=","
        all_packages_json+="$part"
    done
    local total=$(( sys_count + pip_count + npm_count ))
    echo "   Total unificado: ${total} paquetes"

    # --- Software core ---
    echo "Detectando software core..."
    local core_json core_count=0
    core_json=$(collect_core_software)
    [ -n "$core_json" ] && core_count=$(printf '%s' "$core_json" | grep -o '"name"' | wc -l | tr -d ' ')
    echo "   -> ${core_count} aplicaciones detectadas"

    # --- Construir JSON final ---
    local inventory_json
    inventory_json="{\"RSToken\":\"$(json_escape "$RSTOKEN")\",\"system\":${system_json},\"hardware\":${hardware_json},\"packages\":[${all_packages_json}],\"core_software\":[${core_json}]}"

    # --- Guardar localmente ---
    local output_path="${OUTPUT_DIR}/${OUTPUT_FILE}"
    echo ""
    echo "Guardando inventario en ${output_path}..."
    printf '%s' "$inventory_json" > "$output_path"

    # --- Enviar a RSM ---
    if ! send_to_rsm "$inventory_json"; then
        echo ""
        echo "============================================================"
        echo "ERROR CRÍTICO: No se pudo enviar el inventario a RSM"
        echo "============================================================"
        echo ""
        echo "Verifica:"
        echo "   - Token agente: ${AGENT_TOKEN:0:10}..."
        echo "   - RSToken en RSdata: ${RSTOKEN:0:10}..."
        echo "   - UUID:  $UUID_VAL"
        echo "   - Alias: $SYSTEM_ALIAS"
        echo "   - URL:   $RSM_API_URL"
        echo "   - Conectividad de red"
        exit 1
    fi

    # --- Resumen final ---
    local file_size
    file_size=$(stat -c%s "$output_path" 2>/dev/null || stat -f%z "$output_path" 2>/dev/null || echo "?")

    echo ""
    echo "============================================================"
    echo "Inventario recopilado y enviado correctamente"
    echo "============================================================"
    echo ""
    echo "Resumen:"
    echo "   - Sistema:      $(printf '%s' "$system_json" | grep -o '"name":"[^"]*"' | head -1 | sed 's/"name":"//;s/"//')"
    echo "   - Hostname:     $(hostname -s 2>/dev/null || hostname)"
    echo "   - Firmware:     ${firmware_count}"
    echo "   - Total paquetes: ${total}"
    echo "   - Software core:  ${core_count}"
    echo "   - Archivo:      ${output_path}"
    echo "   - Tamano:       ${file_size} bytes"
    echo ""
}

main "$@"
