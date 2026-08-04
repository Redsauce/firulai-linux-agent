#!/bin/bash
# -*- coding: utf-8 -*-
#
# Firulai Inventory Agent
# Version: 0.3.4 - Persistent state and missed execution recovery
# Requires: bash 4+, curl, lscpu, lsblk, uname
#

set -uo pipefail

# ============ CONFIGURATION ============

AGENT_VERSION="0.3.4"
GITHUB_API_URL="https://api.github.com/repos/Redsauce/firulai-linux-agent/releases/latest"
GITHUB_AGENT_URL="${RS_AGENT_GITHUB_AGENT_URL:-https://raw.githubusercontent.com/Redsauce/firulai-linux-agent/main/rs_agent.sh}"

RUN_AS_ROOT=0
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    RUN_AS_ROOT=1
fi

if [ "$RUN_AS_ROOT" = "1" ]; then
    INSTALL_DIR="${RS_AGENT_INSTALL_DIR:-/opt/rs-agent}"
    OUTPUT_DIR="${RS_AGENT_DATA_DIR:-/var/lib/rs-agent}"
    LOCK_FILE="${RS_AGENT_LOCK_FILE:-/run/lock/rs-agent.lock}"
    PRIVATE_TMP_DIR="${RS_AGENT_TMP_DIR:-/run/rs-agent/tmp}"
else
    INSTALL_DIR="${RS_AGENT_INSTALL_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/rs-agent}"
    OUTPUT_DIR="${RS_AGENT_DATA_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/rs-agent}"
    LOCK_FILE="${RS_AGENT_LOCK_FILE:-$OUTPUT_DIR/rs-agent.lock}"
    PRIVATE_TMP_DIR="${RS_AGENT_TMP_DIR:-${XDG_RUNTIME_DIR:-$OUTPUT_DIR}/rs-agent/tmp}"
fi

OUTPUT_FILE="inventory.json"
STATE_FILE="$OUTPUT_DIR/state.env"
RSM_API_URL="https://rsm1.redsauce.net/AppController/commands_RSM/api/api.php"
RSM_ITEMS_GET_URL="https://rsm1.redsauce.net/AppController/commands_RSM/api/v2/items/get.php"
RSM_SYSTEM_HOSTNAME_PROPERTY_ID="1749"
RSM_SYSTEM_FQDN_PROPERTY_ID="1750"
RSM_SYSTEM_UUID_PROPERTY_ID="1780"
AGENT_TOKEN=""
UUID_VAL=""
SYSTEM_ALIAS=""
EXECUTION_TRIGGER="${RS_AGENT_TRIGGER:-manual}"
AGENT_LOCALE="${RS_AGENT_LOCALE:-}"

# ============ UTILITIES ============

normalize_locale() {
    local value
    value=$(printf '%s' "${1:-}" | tr '[:upper:]-' '[:lower:]_')
    case "$value" in
        es*) printf '%s' "es_ES" ;;
        ca*) printf '%s' "ca_ES" ;;
        eu*) printf '%s' "eu_ES" ;;
        gl*) printf '%s' "gl_ES" ;;
        fr*) printf '%s' "fr_FR" ;;
        de*) printf '%s' "de_DE" ;;
        it*) printf '%s' "it_IT" ;;
        ja*) printf '%s' "ja_JP" ;;
        zh*) printf '%s' "zh_CN" ;;
        *) printf '%s' "en_US" ;;
    esac
}

t() {
    local key="$1"
    case "$(normalize_locale "$AGENT_LOCALE"):$key" in
        es_ES:flock_missing) printf '%s' "ERROR: flock no esta disponible; instala el paquete util-linux." ;;
        es_ES:already_running) printf '%s' "INFO: Ya hay otra ejecucion del agente en curso; se omite esta solicitud." ;;
        es_ES:unsafe_symlink) printf '%s' "ERROR: Ruta no segura: es un enlace simbolico" ;;
        es_ES:private_dir_failed) printf '%s' "ERROR: No se pudo crear un directorio privado seguro" ;;
        es_ES:unsafe_owner) printf '%s' "ERROR: Directorio no seguro: no pertenece al usuario actual" ;;
        es_ES:mktemp_missing) printf '%s' "ERROR: mktemp no esta disponible." ;;
        es_ES:state_temp_failed) printf '%s' "ERROR: No se pudo escribir el archivo temporal de estado" ;;
        es_ES:state_update_failed) printf '%s' "ERROR: No se pudo actualizar el estado persistente" ;;
        es_ES:state_updated) printf '%s' "Estado actualizado: ultima ejecucion correcta" ;;
        es_ES:no_root_mode) printf '%s' "INFO: Modo sin root; el inventario puede ser menos completo si el sistema restringe algunos comandos." ;;
        es_ES:invalid_uuid) printf '%s' "ERROR: UUID no valido" ;;
        es_ES:usage) printf '%s' "Uso: bash rs_agent.sh --token <TOKEN> --uuid <UUID> --alias <ALIAS> [--locale <IDIOMA>]" ;;
        es_ES:token_requires_value) printf '%s' "ERROR: --token requiere un valor" ;;
        es_ES:uuid_requires_value) printf '%s' "ERROR: --uuid requiere un valor" ;;
        es_ES:alias_requires_value) printf '%s' "ERROR: --alias requiere un valor" ;;
        es_ES:locale_requires_value) printf '%s' "ERROR: --locale requiere un valor" ;;
        es_ES:unknown_argument) printf '%s' "Argumento desconocido" ;;
        es_ES:required_args) printf '%s' "ERROR: --token, --uuid y --alias son obligatorios" ;;
        es_ES:validating_uuid) printf '%s' "Validando que el UUID no pertenece a otro sistema..." ;;
        es_ES:uuid_validate_failed) printf '%s' "ERROR: No se pudo validar el UUID antes de enviar el inventario" ;;
        es_ES:uuid_validate_safety) printf '%s' "Por seguridad, la instalacion no continuara sin confirmar que el UUID no pertenece a otro sistema." ;;
        es_ES:uuid_validate_denied) printf '%s' "ERROR: RSM no permitio validar el UUID antes de enviar el inventario" ;;
        es_ES:response) printf '%s' "Respuesta" ;;
        es_ES:invalid_uuid_rsm) printf '%s' "ERROR: UUID invalido: no existe en RSM." ;;
        es_ES:uuid_not_generated) printf '%s' "El inventario no se puede enviar con un UUID que no se haya generado desde Add New System." ;;
        es_ES:uuid_reserved) printf '%s' "UUID reservado en RSM y listo para instalar" ;;
        es_ES:uuid_same_system) printf '%s' "UUID ya asociado con este sistema; se actualizara su inventario" ;;
        es_ES:uuid_other_system) printf '%s' "ERROR: Este UUID ya pertenece a otro sistema en RSM." ;;
        es_ES:uuid_other_system_local) printf '%s' "Este agente no se puede instalar en la maquina local con ese UUID." ;;
        es_ES:new_version) printf '%s' "Nueva version disponible" ;;
        es_ES:current_version) printf '%s' "actual" ;;
        es_ES:downloading_update) printf '%s' "Descargando actualizacion..." ;;
        es_ES:update_completed) printf '%s' "Actualizacion completada. Reiniciando agente..." ;;
        es_ES:update_failed) printf '%s' "Error al descargar la actualizacion" ;;
        es_ES:sending_inventory) printf '%s' "Enviando inventario a RSM..." ;;
        es_ES:json_saved) printf '%s' "JSON guardado en" ;;
        es_ES:length) printf '%s' "Longitud" ;;
        es_ES:agent_token) printf '%s' "Token del agente" ;;
        es_ES:configured_hidden) printf '%s' "configurado; valor oculto" ;;
        es_ES:alias_label) printf '%s' "Alias" ;;
        es_ES:method) printf '%s' "Metodo" ;;
        es_ES:endpoint) printf '%s' "Endpoint" ;;
        es_ES:flow) printf '%s' "Flujo" ;;
        es_ES:flow_new_server_data) printf '%s' "api.php recibe newServerData y RSM crea o encola trabajos y eventos" ;;
        es_ES:authorization_header) printf '%s' "Cabecera Authorization" ;;
        es_ES:hidden) printf '%s' "oculto" ;;
        es_ES:response_body_file) printf '%s' "Cuerpo de respuesta" ;;
        es_ES:response_headers) printf '%s' "Cabeceras de respuesta" ;;
        es_ES:curl_verbose) printf '%s' "Curl verbose" ;;
        es_ES:curl_exit) printf '%s' "Salida de curl" ;;
        es_ES:http_code) printf '%s' "Codigo HTTP" ;;
        es_ES:response_body_bytes) printf '%s' "Bytes del cuerpo de respuesta" ;;
        es_ES:rsm_configuration) printf '%s' "Configuracion de RSM:" ;;
        es_ES:request_to_send) printf '%s' "Solicitud a enviar:" ;;
        es_ES:executing_request) printf '%s' "Ejecutando solicitud a RSM..." ;;
        es_ES:http_result) printf '%s' "Resultado HTTP:" ;;
        es_ES:send_failed) printf '%s' "ERROR: No se pudo enviar el inventario a RSM" ;;
        es_ES:rsm_uuid_conflict) printf '%s' "ERROR: RSM indica que el UUID ya existe o pertenece a otro sistema." ;;
        es_ES:rsm_http_error) printf '%s' "ERROR: RSM devolvio HTTP" ;;
        es_ES:inventory_sent) printf '%s' "Inventario enviado correctamente" ;;
        es_ES:collecting_title) printf '%s' "Recopilando informacion del sistema" ;;
        es_ES:trigger) printf '%s' "Disparador de ejecucion" ;;
        es_ES:collecting_timezone) printf '%s' "Recopilando informacion de zona horaria..." ;;
        es_ES:timezone) printf '%s' "Zona horaria" ;;
        es_ES:collecting_system) printf '%s' "Recopilando informacion del sistema..." ;;
        es_ES:system_failed) printf '%s' "ERROR: No se pudo recopilar la informacion del sistema" ;;
        es_ES:collecting_hardware) printf '%s' "Recopilando informacion de hardware..." ;;
        es_ES:firmware_detected) printf '%s' "firmware detectado(s)" ;;
        es_ES:collecting_system_packages) printf '%s' "Recopilando paquetes del sistema..." ;;
        es_ES:system_components) printf '%s' "componentes del sistema" ;;
        es_ES:source_packages) printf '%s' "paquetes fuente" ;;
        es_ES:collecting_python) printf '%s' "Recopilando paquetes de Python..." ;;
        es_ES:python_packages) printf '%s' "paquetes de Python" ;;
        es_ES:collecting_node) printf '%s' "Recopilando paquetes de Node.js..." ;;
        es_ES:node_packages) printf '%s' "paquetes de Node.js" ;;
        es_ES:unified_total) printf '%s' "Total unificado" ;;
        es_ES:components) printf '%s' "componentes" ;;
        es_ES:saving_inventory) printf '%s' "Guardando inventario en" ;;
        es_ES:inventory_temp_failed) printf '%s' "ERROR: No se pudo crear el inventario temporal en" ;;
        es_ES:inventory_write_failed) printf '%s' "ERROR: No se pudo escribir el inventario temporal" ;;
        es_ES:critical_send_failed) printf '%s' "ERROR CRITICO: No se pudo enviar el inventario a RSM" ;;
        es_ES:check) printf '%s' "Comprueba:" ;;
        es_ES:network) printf '%s' "Conectividad de red" ;;
        es_ES:critical_state_failed) printf '%s' "ERROR CRITICO: El inventario se envio, pero no se pudo guardar el estado de ejecucion." ;;
        es_ES:inventory_success) printf '%s' "Inventario recopilado y enviado correctamente" ;;
        es_ES:summary) printf '%s' "Resumen:" ;;
        es_ES:system) printf '%s' "Sistema" ;;
        es_ES:hostname) printf '%s' "Hostname" ;;
        es_ES:firmware) printf '%s' "Firmware" ;;
        es_ES:total_components) printf '%s' "Componentes totales" ;;
        es_ES:total_packages) printf '%s' "Paquetes totales" ;;
        es_ES:file) printf '%s' "Archivo" ;;
        es_ES:size) printf '%s' "Tamano" ;;

        ca_ES:flock_missing) printf '%s' "ERROR: flock no esta disponible; instal.la el paquet util-linux." ;;
        ca_ES:already_running) printf '%s' "INFO: Ja hi ha una altra execucio de l'agent en curs; s'omet aquesta sol.licitud." ;;
        ca_ES:unsafe_symlink) printf '%s' "ERROR: Ruta no segura: es un enllac simbolic" ;;
        ca_ES:private_dir_failed) printf '%s' "ERROR: No s'ha pogut crear un directori privat segur" ;;
        ca_ES:unsafe_owner) printf '%s' "ERROR: Directori no segur: no pertany a l'usuari actual" ;;
        ca_ES:mktemp_missing) printf '%s' "ERROR: mktemp no esta disponible." ;;
        ca_ES:state_temp_failed) printf '%s' "ERROR: No s'ha pogut escriure el fitxer temporal d'estat" ;;
        ca_ES:state_update_failed) printf '%s' "ERROR: No s'ha pogut actualitzar l'estat persistent" ;;
        ca_ES:state_updated) printf '%s' "Estat actualitzat: ultima execucio correcta" ;;
        ca_ES:no_root_mode) printf '%s' "INFO: Mode sense root; l'inventari pot ser menys complet si el sistema restringeix algunes ordres." ;;
        ca_ES:invalid_uuid) printf '%s' "ERROR: UUID no valid" ;;
        ca_ES:usage) printf '%s' "Us: bash rs_agent.sh --token <TOKEN> --uuid <UUID> --alias <ALIAS> [--locale <IDIOMA>]" ;;
        ca_ES:token_requires_value) printf '%s' "ERROR: --token requereix un valor" ;;
        ca_ES:uuid_requires_value) printf '%s' "ERROR: --uuid requereix un valor" ;;
        ca_ES:alias_requires_value) printf '%s' "ERROR: --alias requereix un valor" ;;
        ca_ES:locale_requires_value) printf '%s' "ERROR: --locale requereix un valor" ;;
        ca_ES:unknown_argument) printf '%s' "Argument desconegut" ;;
        ca_ES:required_args) printf '%s' "ERROR: --token, --uuid i --alias son obligatoris" ;;
        ca_ES:validating_uuid) printf '%s' "Validant que l'UUID no pertany a un altre sistema..." ;;
        ca_ES:uuid_validate_failed) printf '%s' "ERROR: No s'ha pogut validar l'UUID abans d'enviar l'inventari" ;;
        ca_ES:uuid_validate_safety) printf '%s' "Per seguretat, la instal.lacio no continuara sense confirmar que l'UUID no pertany a un altre sistema." ;;
        ca_ES:uuid_validate_denied) printf '%s' "ERROR: RSM no ha permes validar l'UUID abans d'enviar l'inventari" ;;
        ca_ES:response) printf '%s' "Resposta" ;;
        ca_ES:invalid_uuid_rsm) printf '%s' "ERROR: UUID no valid: no existeix a RSM." ;;
        ca_ES:uuid_not_generated) printf '%s' "L'inventari no es pot enviar amb un UUID que no s'hagi generat des d'Add New System." ;;
        ca_ES:uuid_reserved) printf '%s' "UUID reservat a RSM i preparat per instal.lar" ;;
        ca_ES:uuid_same_system) printf '%s' "UUID ja associat amb aquest sistema; se n'actualitzara l'inventari" ;;
        ca_ES:uuid_other_system) printf '%s' "ERROR: Aquest UUID ja pertany a un altre sistema a RSM." ;;
        ca_ES:uuid_other_system_local) printf '%s' "Aquest agent no es pot instal.lar a la maquina local amb aquest UUID." ;;
        ca_ES:new_version) printf '%s' "Nova versio disponible" ;;
        ca_ES:current_version) printf '%s' "actual" ;;
        ca_ES:downloading_update) printf '%s' "Descarregant actualitzacio..." ;;
        ca_ES:update_completed) printf '%s' "Actualitzacio completada. Reiniciant agent..." ;;
        ca_ES:update_failed) printf '%s' "Error en descarregar l'actualitzacio" ;;
        ca_ES:sending_inventory) printf '%s' "Enviant inventari a RSM..." ;;
        ca_ES:json_saved) printf '%s' "JSON desat a" ;;
        ca_ES:length) printf '%s' "Longitud" ;;
        ca_ES:agent_token) printf '%s' "Token de l'agent" ;;
        ca_ES:configured_hidden) printf '%s' "configurat; valor ocult" ;;
        ca_ES:alias_label) printf '%s' "Alias" ;;
        ca_ES:method) printf '%s' "Metode" ;;
        ca_ES:endpoint) printf '%s' "Endpoint" ;;
        ca_ES:flow) printf '%s' "Flux" ;;
        ca_ES:flow_new_server_data) printf '%s' "api.php rep newServerData i RSM crea o encua treballs i esdeveniments" ;;
        ca_ES:authorization_header) printf '%s' "Capcalera Authorization" ;;
        ca_ES:hidden) printf '%s' "ocult" ;;
        ca_ES:response_body_file) printf '%s' "Cos de resposta" ;;
        ca_ES:response_headers) printf '%s' "Capcaleres de resposta" ;;
        ca_ES:curl_verbose) printf '%s' "Curl verbose" ;;
        ca_ES:curl_exit) printf '%s' "Sortida de curl" ;;
        ca_ES:http_code) printf '%s' "Codi HTTP" ;;
        ca_ES:response_body_bytes) printf '%s' "Bytes del cos de resposta" ;;
        ca_ES:rsm_configuration) printf '%s' "Configuracio de RSM:" ;;
        ca_ES:request_to_send) printf '%s' "Sol.licitud a enviar:" ;;
        ca_ES:executing_request) printf '%s' "Executant sol.licitud a RSM..." ;;
        ca_ES:http_result) printf '%s' "Resultat HTTP:" ;;
        ca_ES:send_failed) printf '%s' "ERROR: No s'ha pogut enviar l'inventari a RSM" ;;
        ca_ES:rsm_uuid_conflict) printf '%s' "ERROR: RSM indica que l'UUID ja existeix o pertany a un altre sistema." ;;
        ca_ES:rsm_http_error) printf '%s' "ERROR: RSM ha retornat HTTP" ;;
        ca_ES:inventory_sent) printf '%s' "Inventari enviat correctament" ;;
        ca_ES:collecting_title) printf '%s' "Recopilant informacio del sistema" ;;
        ca_ES:trigger) printf '%s' "Disparador d'execucio" ;;
        ca_ES:collecting_timezone) printf '%s' "Recopilant informacio de zona horaria..." ;;
        ca_ES:timezone) printf '%s' "Zona horaria" ;;
        ca_ES:collecting_system) printf '%s' "Recopilant informacio del sistema..." ;;
        ca_ES:system_failed) printf '%s' "ERROR: No s'ha pogut recopilar la informacio del sistema" ;;
        ca_ES:collecting_hardware) printf '%s' "Recopilant informacio de maquinari..." ;;
        ca_ES:firmware_detected) printf '%s' "firmware detectat(s)" ;;
        ca_ES:collecting_system_packages) printf '%s' "Recopilant paquets del sistema..." ;;
        ca_ES:system_components) printf '%s' "components del sistema" ;;
        ca_ES:source_packages) printf '%s' "paquets font" ;;
        ca_ES:collecting_python) printf '%s' "Recopilant paquets de Python..." ;;
        ca_ES:python_packages) printf '%s' "paquets de Python" ;;
        ca_ES:collecting_node) printf '%s' "Recopilant paquets de Node.js..." ;;
        ca_ES:node_packages) printf '%s' "paquets de Node.js" ;;
        ca_ES:unified_total) printf '%s' "Total unificat" ;;
        ca_ES:components) printf '%s' "components" ;;
        ca_ES:saving_inventory) printf '%s' "Desant inventari a" ;;
        ca_ES:inventory_temp_failed) printf '%s' "ERROR: No s'ha pogut crear l'inventari temporal a" ;;
        ca_ES:inventory_write_failed) printf '%s' "ERROR: No s'ha pogut escriure l'inventari temporal" ;;
        ca_ES:critical_send_failed) printf '%s' "ERROR CRITIC: No s'ha pogut enviar l'inventari a RSM" ;;
        ca_ES:check) printf '%s' "Comprova:" ;;
        ca_ES:network) printf '%s' "Connectivitat de xarxa" ;;
        ca_ES:critical_state_failed) printf '%s' "ERROR CRITIC: L'inventari s'ha enviat, pero no s'ha pogut desar l'estat d'execucio." ;;
        ca_ES:inventory_success) printf '%s' "Inventari recopilat i enviat correctament" ;;
        ca_ES:summary) printf '%s' "Resum:" ;;
        ca_ES:system) printf '%s' "Sistema" ;;
        ca_ES:hostname) printf '%s' "Hostname" ;;
        ca_ES:firmware) printf '%s' "Firmware" ;;
        ca_ES:total_components) printf '%s' "Components totals" ;;
        ca_ES:total_packages) printf '%s' "Paquets totals" ;;
        ca_ES:file) printf '%s' "Fitxer" ;;
        ca_ES:size) printf '%s' "Mida" ;;

        *:flock_missing) printf '%s' "ERROR: flock is not available; install the util-linux package." ;;
        *:already_running) printf '%s' "INFO: Another agent run is already in progress; this request is skipped." ;;
        *:unsafe_symlink) printf '%s' "ERROR: Unsafe path: is a symbolic link" ;;
        *:private_dir_failed) printf '%s' "ERROR: Could not create a secure private directory" ;;
        *:unsafe_owner) printf '%s' "ERROR: Unsafe directory: is not owned by the current user" ;;
        *:mktemp_missing) printf '%s' "ERROR: mktemp is not available." ;;
        *:state_temp_failed) printf '%s' "ERROR: Could not write temporary state file" ;;
        *:state_update_failed) printf '%s' "ERROR: Could not update persistent state" ;;
        *:state_updated) printf '%s' "State updated: last successful run" ;;
        *:no_root_mode) printf '%s' "INFO: No-root mode; inventory may be less complete if the system restricts some commands." ;;
        *:invalid_uuid) printf '%s' "ERROR: invalid UUID" ;;
        *:usage) printf '%s' "Usage: bash rs_agent.sh --token <TOKEN> --uuid <UUID> --alias <ALIAS> [--locale <LOCALE>]" ;;
        *:token_requires_value) printf '%s' "ERROR: --token requires a value" ;;
        *:uuid_requires_value) printf '%s' "ERROR: --uuid requires a value" ;;
        *:alias_requires_value) printf '%s' "ERROR: --alias requires a value" ;;
        *:locale_requires_value) printf '%s' "ERROR: --locale requires a value" ;;
        *:unknown_argument) printf '%s' "Unknown argument" ;;
        *:required_args) printf '%s' "ERROR: --token, --uuid, and --alias are required" ;;
        *:validating_uuid) printf '%s' "Validating that the UUID does not belong to another system..." ;;
        *:uuid_validate_failed) printf '%s' "ERROR: Could not validate the UUID before sending inventory" ;;
        *:uuid_validate_safety) printf '%s' "For safety, installation will not continue without confirming that the UUID does not belong to another system." ;;
        *:uuid_validate_denied) printf '%s' "ERROR: RSM did not allow UUID validation before sending inventory" ;;
        *:response) printf '%s' "Response" ;;
        *:invalid_uuid_rsm) printf '%s' "ERROR: Invalid UUID: it does not exist in RSM." ;;
        *:uuid_not_generated) printf '%s' "Inventory cannot be sent with a UUID that was not generated from Add New System." ;;
        *:uuid_reserved) printf '%s' "UUID reserved in RSM and ready to install" ;;
        *:uuid_same_system) printf '%s' "UUID already associated with this system; its inventory will be updated" ;;
        *:uuid_other_system) printf '%s' "ERROR: This UUID already belongs to another system in RSM." ;;
        *:uuid_other_system_local) printf '%s' "This agent cannot be installed on the local machine with that UUID." ;;
        *:new_version) printf '%s' "New version available" ;;
        *:current_version) printf '%s' "current" ;;
        *:downloading_update) printf '%s' "Downloading update..." ;;
        *:update_completed) printf '%s' "Update completed. Restarting agent..." ;;
        *:update_failed) printf '%s' "Error downloading update" ;;
        *:sending_inventory) printf '%s' "Sending inventory to RSM..." ;;
        *:json_saved) printf '%s' "JSON saved at" ;;
        *:length) printf '%s' "Length" ;;
        *:agent_token) printf '%s' "Agent token" ;;
        *:configured_hidden) printf '%s' "configured; value hidden" ;;
        *:alias_label) printf '%s' "Alias" ;;
        *:method) printf '%s' "Method" ;;
        *:endpoint) printf '%s' "Endpoint" ;;
        *:flow) printf '%s' "Flow" ;;
        *:flow_new_server_data) printf '%s' "api.php receives newServerData and RSM creates/queues jobs and events" ;;
        *:authorization_header) printf '%s' "Authorization header" ;;
        *:hidden) printf '%s' "hidden" ;;
        *:response_body_file) printf '%s' "Response body" ;;
        *:response_headers) printf '%s' "Response headers" ;;
        *:curl_verbose) printf '%s' "Curl verbose" ;;
        *:curl_exit) printf '%s' "curl exit" ;;
        *:http_code) printf '%s' "HTTP code" ;;
        *:response_body_bytes) printf '%s' "Response body bytes" ;;
        *:rsm_configuration) printf '%s' "RSM configuration:" ;;
        *:request_to_send) printf '%s' "Request to be sent:" ;;
        *:executing_request) printf '%s' "Executing request to RSM..." ;;
        *:http_result) printf '%s' "HTTP result:" ;;
        *:send_failed) printf '%s' "ERROR: Failed to send inventory to RSM" ;;
        *:rsm_uuid_conflict) printf '%s' "ERROR: RSM indicates that the UUID already exists or belongs to another system." ;;
        *:rsm_http_error) printf '%s' "ERROR: RSM returned HTTP" ;;
        *:inventory_sent) printf '%s' "Inventory sent successfully" ;;
        *:collecting_title) printf '%s' "Collecting system information" ;;
        *:trigger) printf '%s' "Execution trigger" ;;
        *:collecting_timezone) printf '%s' "Collecting timezone information..." ;;
        *:timezone) printf '%s' "Timezone" ;;
        *:collecting_system) printf '%s' "Collecting system information..." ;;
        *:system_failed) printf '%s' "ERROR: Could not collect system information" ;;
        *:collecting_hardware) printf '%s' "Collecting hardware information..." ;;
        *:firmware_detected) printf '%s' "firmware(s) detected" ;;
        *:collecting_system_packages) printf '%s' "Collecting system packages..." ;;
        *:system_components) printf '%s' "system components" ;;
        *:source_packages) printf '%s' "source packages" ;;
        *:collecting_python) printf '%s' "Collecting Python packages..." ;;
        *:python_packages) printf '%s' "Python packages" ;;
        *:collecting_node) printf '%s' "Collecting Node.js packages..." ;;
        *:node_packages) printf '%s' "Node.js packages" ;;
        *:unified_total) printf '%s' "Unified total" ;;
        *:components) printf '%s' "components" ;;
        *:saving_inventory) printf '%s' "Saving inventory to" ;;
        *:inventory_temp_failed) printf '%s' "ERROR: Could not create temporary inventory in" ;;
        *:inventory_write_failed) printf '%s' "ERROR: Could not write temporary inventory" ;;
        *:critical_send_failed) printf '%s' "CRITICAL ERROR: Could not send inventory to RSM" ;;
        *:check) printf '%s' "Check:" ;;
        *:network) printf '%s' "Network connectivity" ;;
        *:critical_state_failed) printf '%s' "CRITICAL ERROR: Inventory was sent, but execution state could not be saved." ;;
        *:inventory_success) printf '%s' "Inventory collected and sent successfully" ;;
        *:summary) printf '%s' "Summary:" ;;
        *:system) printf '%s' "System" ;;
        *:hostname) printf '%s' "Hostname" ;;
        *:firmware) printf '%s' "Firmware" ;;
        *:total_components) printf '%s' "Total components" ;;
        *:total_packages) printf '%s' "Total packages" ;;
        *:file) printf '%s' "File" ;;
        *:size) printf '%s' "Size" ;;
        *) printf '%s' "$key" ;;
    esac
}

acquire_execution_lock() {
    if ! command -v flock >/dev/null 2>&1; then
        echo "$(t flock_missing)"
        exit 1
    fi
    mkdir -p "$(dirname "$LOCK_FILE")"
    exec 9>"$LOCK_FILE"
    if ! flock -n 9; then
        echo "$(t already_running) Trigger=$EXECUTION_TRIGGER"
        # EX_TEMPFAIL lets systemd reschedule the automatic request.
        exit 75
    fi
}

ensure_private_directory() {
    local directory="$1"

    if [ -L "$directory" ]; then
        echo "$(t unsafe_symlink): $directory"
        return 1
    fi

    mkdir -p "$directory"

    if [ -L "$directory" ] || [ ! -d "$directory" ]; then
        echo "$(t private_dir_failed): $directory"
        return 1
    fi

    chown root:root "$directory" 2>/dev/null || true
    chmod 700 "$directory"

    if [ ! -O "$directory" ]; then
        echo "$(t unsafe_owner): $directory"
        return 1
    fi
}

init_private_tmp_dir() {
    if ! command -v mktemp >/dev/null 2>&1; then
        echo "$(t mktemp_missing)"
        return 1
    fi

    ensure_private_directory "$(dirname "$PRIVATE_TMP_DIR")"
    ensure_private_directory "$PRIVATE_TMP_DIR"
}

make_private_temp_file() {
    local prefix="$1"
    mktemp "$PRIVATE_TMP_DIR/${prefix}.XXXXXX"
}

record_success_state() {
    local completed_epoch completed_utc temporary_file
    completed_epoch=$(date +%s)
    completed_utc=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    temporary_file=$(mktemp "${STATE_FILE}.tmp.XXXXXX") || return 1

    if ! printf 'LAST_SUCCESS_EPOCH=%s\nLAST_SUCCESS_UTC=%s\n' "$completed_epoch" "$completed_utc" > "$temporary_file"; then
        echo "$(t state_temp_failed) $temporary_file"
        rm -f "$temporary_file"
        return 1
    fi
    chmod 600 "$temporary_file" 2>/dev/null || true
    if ! mv -f "$temporary_file" "$STATE_FILE"; then
        echo "$(t state_update_failed) $STATE_FILE"
        rm -f "$temporary_file"
        return 1
    fi

    echo "$(t state_updated)=$completed_utc ($completed_epoch)"
}

# Escapes a string to embed it as a JSON value (without jq).
# Replacement order: backslash first to avoid double escaping.
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
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

# ============ VALIDATION AND ARGUMENTS ============

check_root() {
    if [ "$RUN_AS_ROOT" != "1" ]; then
        echo "$(t no_root_mode)"
    fi
}

validate_uuid() {
    local uuid="$1"
    if [[ ! "$uuid" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
        echo "$(t invalid_uuid): '$uuid'"
        exit 1
    fi
}

parse_args() {
    if [ $# -eq 0 ]; then
        echo "$(t usage)"
        exit 1
    fi

    while [ $# -gt 0 ]; do
        case "$1" in
            --token)
                [ $# -ge 2 ] || { echo "$(t token_requires_value)"; exit 1; }
                AGENT_TOKEN="$2"
                shift 2
                ;;
            --uuid)
                [ $# -ge 2 ] || { echo "$(t uuid_requires_value)"; exit 1; }
                UUID_VAL="$2"
                shift 2
                ;;
            --alias)
                [ $# -ge 2 ] || { echo "$(t alias_requires_value)"; exit 1; }
                SYSTEM_ALIAS="$2"
                shift 2
                ;;
            --locale|--agent-locale)
                [ $# -ge 2 ] || { echo "$(t locale_requires_value)"; exit 1; }
                AGENT_LOCALE="$2"
                shift 2
                ;;
            *) echo "$(t unknown_argument): $1"; exit 1 ;;
        esac
    done
    AGENT_LOCALE=$(normalize_locale "$AGENT_LOCALE")

    if [ -z "$AGENT_TOKEN" ] || [ -z "$UUID_VAL" ] || [ -z "$SYSTEM_ALIAS" ]; then
        echo "$(t required_args)"
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
    response_file=$(make_private_temp_file "rsm_uuid_check_response") || return 1
    payload="{\"propertyIDs\":[\"$RSM_SYSTEM_HOSTNAME_PROPERTY_ID\",\"$RSM_SYSTEM_FQDN_PROPERTY_ID\",\"$RSM_SYSTEM_UUID_PROPERTY_ID\"],\"translateIDs\":true,\"filterRules\":[{\"propertyID\":\"$RSM_SYSTEM_UUID_PROPERTY_ID\",\"value\":\"$UUID_VAL\",\"operation\":\"=\"}]}"

    echo "$(t validating_uuid)"

    http_code=$(curl \
        --silent \
        --show-error \
        --output "$response_file" \
        --write-out '%{http_code}' \
        --location "$RSM_ITEMS_GET_URL" \
        --request GET \
        --header "Authorization: $AGENT_TOKEN" \
        --header "Content-Type: application/json" \
        --data "$payload" \
        --max-time 20)
    exit_code=$?
    response_body=$(cat "$response_file" 2>/dev/null || true)
    rm -f "$response_file"

    if [ "$exit_code" -ne 0 ]; then
        echo "$(t uuid_validate_failed) (curl exit: $exit_code)."
        echo "$(t uuid_validate_safety)"
        return 1
    fi

    if [ "$http_code" != "200" ] && [ "$http_code" != "201" ]; then
        echo "$(t uuid_validate_denied) (HTTP $http_code)."
        echo "$(t uuid_validate_safety)"
        echo "$(t response): $response_body"
        return 1
    fi

    if ! printf '%s' "$response_body" | grep -Fq "$UUID_VAL"; then
        echo "$(t invalid_uuid_rsm)"
        echo "$(t uuid_not_generated)"
        echo ""
        echo "UUID: $UUID_VAL"
        return 1
    fi

    local existing_hostname existing_fqdn
    existing_hostname=$(json_extract_rsm_property "$response_body" "$RSM_SYSTEM_HOSTNAME_PROPERTY_ID")
    existing_fqdn=$(json_extract_rsm_property "$response_body" "$RSM_SYSTEM_FQDN_PROPERTY_ID")

    if [ -z "$existing_hostname" ] && [ -z "$existing_fqdn" ]; then
        echo "   -> $(t uuid_reserved)"
        return 0
    fi

    if identity_matches_local_system "$existing_hostname" "$existing_fqdn"; then
        echo "   -> $(t uuid_same_system)"
        return 0
    fi

    echo ""
    echo "$(t uuid_other_system)"
    echo "$(t uuid_other_system_local)"
    return 1
}

# ============ COLLECTORS ============

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

    # Try timedatectl
    if command -v timedatectl &>/dev/null; then
        timezone_name=$(timedatectl show -p Timezone --value 2>/dev/null) || true
    fi

    # Fallback: read /etc/timezone
    if [ -z "$timezone_name" ] && [ -f "/etc/timezone" ]; then
        timezone_name=$(cat /etc/timezone 2>/dev/null) || true
    fi

    printf '%s' "$timezone_name"
}

collect_hardware() {
    local cpu_model firmware_json="" first=1

    # CPU: extract "Model name" with awk to handle spaces correctly
    cpu_model=$(lscpu 2>/dev/null | awk -F':[[:space:]]+' '/^Model name/{print $2; exit}')
    [ -z "$cpu_model" ] && cpu_model="Unknown"

    # Disks: awk extracts NAME and MODEL (may contain spaces), filtering disks only
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

select_source_package_version() {
    local component_version="$1"
    local source_version="$2"
    local upstream_version="$3"

    if [ -n "$source_version" ] && [ "$source_version" = "$component_version" ] && [ -n "$upstream_version" ] && [ "$upstream_version" != "unknown" ]; then
        printf '%s' "$upstream_version"
        return
    fi

    if [ -n "$source_version" ] && [ "$source_version" != "unknown" ]; then
        printf '%s' "$source_version"
        return
    fi

    if [ -n "$upstream_version" ] && [ "$upstream_version" != "unknown" ]; then
        printf '%s' "$upstream_version"
    fi
}

select_component_version() {
    local component_version="$1"
    local source_version="$2"
    local upstream_version="$3"

    if [ -n "$source_version" ] && [ "$source_version" = "$component_version" ] && [ -n "$upstream_version" ] && [ "$upstream_version" != "unknown" ]; then
        printf '%s' "$upstream_version"
        return
    fi

    printf '%s' "$component_version"
}

collect_packages_dpkg() {
    local components_json="" source_packages_json="" first_component=1 first_source=1
    local component_count=0 source_package_count=0
    declare -A seen_source_packages=()

    while IFS='|' read -r name version source_package source_version upstream_version status; do
        [ -z "$name" ] && continue
        # Only packages with "installed" status
        case "$status" in *"installed"*) ;; *) continue ;; esac

        if [ -n "$source_package" ]; then
            if [ -z "${seen_source_packages[$source_package]+x}" ]; then
                local selected_source_version source_json
                selected_source_version=$(select_source_package_version "$version" "$source_version" "$upstream_version")
                source_json="{\"name\":\"$(json_escape "$source_package")\",\"version\":\"$(json_escape "$selected_source_version")\"}"

                [ "$first_source" = "1" ] && first_source=0 || source_packages_json+=","
                source_packages_json+="$source_json"
                seen_source_packages[$source_package]=1
                source_package_count=$((source_package_count + 1))
            fi

            if [ "$name" = "$source_package" ]; then
                continue
            fi
        fi

        local component_json selected_component_version
        selected_component_version=$(select_component_version "$version" "$source_version" "$upstream_version")
        component_json="{\"name\":\"$(json_escape "$name")\",\"version\":\"$(json_escape "$selected_component_version")\",\"manager\":\"dpkg\""

        if [ -n "$source_package" ]; then
            component_json+=",\"source_package\":\"$(json_escape "$source_package")\""
            [ -n "$source_version" ] && component_json+=",\"source_version\":\"$(json_escape "$source_version")\""
            [ -n "$upstream_version" ] && component_json+=",\"upstream_version\":\"$(json_escape "$upstream_version")\""
        fi

        component_json+="}"

        [ "$first_component" = "1" ] && first_component=0 || components_json+=","
        components_json+="$component_json"
        component_count=$((component_count + 1))
    done < <(dpkg-query -W -f='${Package}|${Version}|${source:Package}|${source:Version}|${source:Upstream-Version}|${Status}\n' 2>/dev/null)

    SYSTEM_COMPONENTS_JSON="$components_json"
    SYSTEM_PACKAGES_JSON="$source_packages_json"
    SYSTEM_COMPONENTS_COUNT="$component_count"
    SYSTEM_PACKAGES_COUNT="$source_package_count"
}

collect_packages_rpm() {
    local components_json="" first=1 component_count=0

    while IFS=$'\t' read -r name version; do
        [ -z "$name" ] && continue

        [ "$first" = "1" ] && first=0 || components_json+=","
        components_json+="{\"name\":\"$(json_escape "$name")\",\"version\":\"$(json_escape "$version")\",\"manager\":\"rpm\"}"
        component_count=$((component_count + 1))
    done < <(rpm -qa --queryformat '%{NAME}\t%{VERSION}-%{RELEASE}\n' 2>/dev/null)

    SYSTEM_COMPONENTS_JSON="$components_json"
    SYSTEM_PACKAGES_JSON=""
    SYSTEM_COMPONENTS_COUNT="$component_count"
    SYSTEM_PACKAGES_COUNT=0
}

collect_packages() {
    SYSTEM_COMPONENTS_JSON=""
    SYSTEM_PACKAGES_JSON=""
    SYSTEM_COMPONENTS_COUNT=0
    SYSTEM_PACKAGES_COUNT=0

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

    # --format=columns produces: "Package    Version" with 2 header lines (name + separator)
    # tail -n +3 removes them; the third field (_rest) absorbs any extra annotation
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
        # Remove tree prefix (characters up to and including "── ")
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

# ============ AUTO UPDATE ============

check_for_updates() {
    command -v curl &>/dev/null || return 0

    local response latest_version
    response=$(curl -sf --max-time 5 "$GITHUB_API_URL" 2>/dev/null) || return 0

    # Extract "tag_name" from JSON without jq: find the "tag_name":"vX.Y.Z" pattern
    latest_version=$(printf '%s' "$response" \
        | grep -o '"tag_name":"[^"]*"' \
        | sed 's/"tag_name":"v\?//;s/"//')

    [ -z "$latest_version" ] && return 0
    [ "$latest_version" = "$AGENT_VERSION" ] && return 0

    echo "$(t new_version): $latest_version ($(t current_version): $AGENT_VERSION)"
    download_update
}

download_update() {
    local script_path="$INSTALL_DIR/rs_agent.sh"
    local backup_path="${script_path}.backup"

    echo "$(t downloading_update)"
    [ -f "$script_path" ] && cp "$script_path" "$backup_path"

    if curl -fsSL --max-time 10 "$GITHUB_AGENT_URL" -o "$script_path"; then
        chmod +x "$script_path"
        echo "$(t update_completed)"
        exec bash "$script_path" --token "$AGENT_TOKEN" --uuid "$UUID_VAL" --alias "$SYSTEM_ALIAS" --locale "$AGENT_LOCALE"
    else
        echo "$(t update_failed)"
        [ -f "$backup_path" ] && mv "$backup_path" "$script_path"
    fi
}

# ============ SEND TO RSM ============

send_to_rsm() {
    local inventory_json="$1"
    local inventory_json_path
    local response_file
    local response_headers_file
    local curl_trace_file=""
    local inventory_hash="unavailable"

    inventory_json_path=$(make_private_temp_file "rsm_inventory_payload") || return 1
    response_file=$(make_private_temp_file "rsm_response") || return 1
    response_headers_file=$(make_private_temp_file "rsm_response_headers") || return 1
    if [ "${RS_AGENT_DEBUG:-0}" = "1" ]; then
        curl_trace_file=$(make_private_temp_file "rsm_curl_verbose") || return 1
    fi

    echo ""
    echo "$(t sending_inventory)"

    printf '%s' "$inventory_json" > "$inventory_json_path"
    chmod 600 "$inventory_json_path" 2>/dev/null || true
    printf '%s: %s\n' "$(t json_saved)" "$inventory_json_path"
    printf '%s: %d characters (%d KB approx)\n' "$(t length)" "${#inventory_json}" "$(( ${#inventory_json} / 1024 ))"
    if command -v sha256sum >/dev/null 2>&1; then
        inventory_hash=$(printf '%s' "$inventory_json" | sha256sum | awk '{print $1}')
    elif command -v shasum >/dev/null 2>&1; then
        inventory_hash=$(printf '%s' "$inventory_json" | shasum -a 256 | awk '{print $1}')
    fi
    printf 'SHA256 RSdata: %s\n' "$inventory_hash"

    echo ""
    echo "$(t rsm_configuration)"
    echo "   - URL:   $RSM_API_URL"
    echo "   - $(t agent_token): <$(t configured_hidden)>"
    echo "   - $(t alias_label): $SYSTEM_ALIAS"
    echo "   - Debug: ${RS_AGENT_DEBUG:-0}"
    echo ""
    echo "$(t request_to_send)"
    echo "   - $(t method): POST multipart/form-data"
    echo "   - $(t endpoint): $RSM_API_URL"
    echo "   - $(t flow): $(t flow_new_server_data)"
    echo "   - $(t authorization_header): <$(t hidden)>"
    echo "   - Form RStrigger: newServerData"
    echo "   - Form RStoken: <$(t hidden)>"
    echo "   - Form RSdata: $inventory_json_path (${#inventory_json} chars)"
    echo "   - $(t response_body_file): $response_file"
    echo "   - $(t response_headers): $response_headers_file"
    if [ "${RS_AGENT_DEBUG:-0}" = "1" ]; then
        echo "   - $(t curl_verbose): $curl_trace_file"
    fi
    echo ""
    echo "$(t executing_request)"

    local curl_args=(
        --silent
        --show-error
        --output "$response_file"
        --dump-header "$response_headers_file"
        --write-out "%{http_code}"
        --location "$RSM_API_URL"
        --header "Authorization: $AGENT_TOKEN"
        --form "RStrigger=newServerData"
        --form "RSdata=<$inventory_json_path;type=application/json"
        --form "RStoken=$AGENT_TOKEN"
        --max-time 30
    )

    if [ "${RS_AGENT_DEBUG:-0}" = "1" ]; then
        curl_args=(--verbose "${curl_args[@]}")
    fi

    local http_code
    if [ "${RS_AGENT_DEBUG:-0}" = "1" ]; then
        http_code=$(curl "${curl_args[@]}" 2>"$curl_trace_file")
        sed -i "s/$AGENT_TOKEN/<AGENT_TOKEN>/g" "$curl_trace_file" 2>/dev/null || true
        chmod 600 "$curl_trace_file" 2>/dev/null || true
    else
        http_code=$(curl "${curl_args[@]}")
    fi
    local exit_code=$?
    local response_body
    response_body=$(cat "$response_file" 2>/dev/null || true)
    chmod 600 "$response_file" "$response_headers_file" 2>/dev/null || true

    echo ""
    echo "$(t http_result)"
    echo "   - $(t curl_exit): $exit_code"
    echo "   - $(t http_code): $http_code"
    echo "   - $(t response_body_bytes): $(wc -c < "$response_file" 2>/dev/null || echo 0)"
    echo "   - $(t response_body_file): $response_file"
    echo "   - $(t response_headers): $response_headers_file"
    if [ "${RS_AGENT_DEBUG:-0}" = "1" ]; then
        echo "   - $(t curl_verbose): $curl_trace_file"
    fi

    if [ "$exit_code" -ne 0 ]; then
        echo ""
        echo "$(t send_failed) (curl exit: $exit_code)"
        echo "$(t response): $response_body"
        return 1
    fi

    if [ "$http_code" = "409" ] || echo "$response_body" | grep -iqE 'uuid.*(exists|ya existe)|already exists|duplicate|pertenece a otro sistema'; then
        echo ""
        echo "$(t rsm_uuid_conflict)"
        echo "$(t uuid_other_system_local)"
        echo "$(t response): $response_body"
        return 1
    fi

    if [ "$http_code" != "200" ] && [ "$http_code" != "201" ]; then
        echo ""
        echo "$(t rsm_http_error) $http_code"
        echo "$(t response): $response_body"
        return 1
    fi

    echo ""
    printf '%s (%d KB)\n' "$(t inventory_sent)" "$(( ${#inventory_json} / 1024 ))"
    return 0
}

# ============ MAIN ============

main() {
    parse_args "$@"

    echo ""
    echo "============================================================"
    printf  'Firulai Inventory Agent v%s - %s\n' "$AGENT_VERSION" "$(t collecting_title)"
    echo "============================================================"
    echo ""

    check_root
    acquire_execution_lock
    if ! init_private_tmp_dir; then
        exit 1
    fi
    echo "$(t trigger): $EXECUTION_TRIGGER"
    check_for_updates
    if ! validate_uuid_ownership; then
        exit 1
    fi
    if ! ensure_private_directory "$OUTPUT_DIR"; then
        exit 1
    fi

    # --- Timezone ---
    echo "$(t collecting_timezone)"
    local timezone
    timezone=$(collect_timezone)
    [ -z "$timezone" ] && timezone=""
    echo "   -> $(t timezone): ${timezone:-unknown}"

    # --- System ---
    echo "$(t collecting_system)"
    local system_json
    system_json=$(collect_system_info "$timezone")
    if [ -z "$system_json" ]; then
        echo "$(t system_failed)"
        exit 1
    fi

    # --- Hardware ---
    echo "$(t collecting_hardware)"
    local hardware_json
    hardware_json=$(collect_hardware)
    local firmware_count
    firmware_count=$(printf '%s' "$hardware_json" | grep -o '"device"' | wc -l | tr -d ' ')
    echo "   -> ${firmware_count} $(t firmware_detected)"

    # --- System Packages ---
    echo "$(t collecting_system_packages)"
    collect_packages
    local sys_json="$SYSTEM_COMPONENTS_JSON"
    local source_packages_json="$SYSTEM_PACKAGES_JSON"
    local sys_count="$SYSTEM_COMPONENTS_COUNT"
    local source_package_count="$SYSTEM_PACKAGES_COUNT"
    echo "   -> ${sys_count} $(t system_components)"
    echo "   -> ${source_package_count} $(t source_packages)"

    # --- Python Packages ---
    echo "$(t collecting_python)"
    local pip_json pip_count=0
    pip_json=$(collect_pip_packages)
    [ -n "$pip_json" ] && pip_count=$(printf '%s' "$pip_json" | grep -o '"manager":"pip"' | wc -l | tr -d ' ')
    echo "   -> ${pip_count} $(t python_packages)"

    # --- Node.js Packages ---
    echo "$(t collecting_node)"
    local npm_json npm_count=0
    npm_json=$(collect_npm_packages)
    [ -n "$npm_json" ] && npm_count=$(printf '%s' "$npm_json" | grep -o '"manager":"npm"' | wc -l | tr -d ' ')
    echo "   -> ${npm_count} $(t node_packages)"

    # Merge all components into one JSON array
    local all_components_json=""
    for part in "$sys_json" "$pip_json" "$npm_json"; do
        [ -z "$part" ] && continue
        [ -n "$all_components_json" ] && all_components_json+=","
        all_components_json+="$part"
    done
    local total=$(( sys_count + pip_count + npm_count ))
    echo "   $(t unified_total): ${total} $(t components)"

    # --- Build Final JSON ---
    local inventory_json
    inventory_json="{\"RSToken\":\"$(json_escape "$AGENT_TOKEN")\",\"system\":${system_json},\"hardware\":${hardware_json},\"components\":[${all_components_json}],\"packages\":[${source_packages_json}]}"

    # --- Save Locally ---
    local output_path="${OUTPUT_DIR}/${OUTPUT_FILE}"
    local temporary_output_path
    echo ""
    echo "$(t saving_inventory) ${output_path}..."
    temporary_output_path=$(mktemp "$OUTPUT_DIR/${OUTPUT_FILE}.XXXXXX") || {
        echo "$(t inventory_temp_failed) $OUTPUT_DIR"
        exit 1
    }
    chmod 600 "$temporary_output_path" 2>/dev/null || true
    if ! printf '%s' "$inventory_json" > "$temporary_output_path"; then
        echo "$(t inventory_write_failed) $temporary_output_path"
        rm -f "$temporary_output_path"
        exit 1
    fi
    chown root:root "$temporary_output_path" 2>/dev/null || true
    mv -f "$temporary_output_path" "$output_path"
    chmod 600 "$output_path" 2>/dev/null || true

    # --- Send To RSM ---
    if ! send_to_rsm "$inventory_json"; then
        echo ""
        echo "============================================================"
        echo "$(t critical_send_failed)"
        echo "============================================================"
        echo ""
        echo "$(t check)"
        echo "   - $(t agent_token): <$(t configured_hidden)>"
        echo "   - UUID:  $UUID_VAL"
        echo "   - $(t alias_label): $SYSTEM_ALIAS"
        echo "   - URL:   $RSM_API_URL"
        echo "   - $(t network)"
        exit 1
    fi

    if ! record_success_state; then
        echo "$(t critical_state_failed)"
        exit 1
    fi

    # --- Final Summary ---
    local file_size
    file_size=$(stat -c%s "$output_path" 2>/dev/null || stat -f%z "$output_path" 2>/dev/null || echo "?")

    echo ""
    echo "============================================================"
    echo "$(t inventory_success)"
    echo "============================================================"
    echo ""
    echo "$(t summary)"
    echo "   - $(t system):       $(printf '%s' "$system_json" | grep -o '"name":"[^"]*"' | head -1 | sed 's/"name":"//;s/"//')"
    echo "   - $(t hostname):     $(hostname -s 2>/dev/null || hostname)"
    echo "   - $(t firmware):     ${firmware_count}"
    echo "   - $(t total_components): ${total}"
    echo "   - $(t total_packages):   ${source_package_count}"
    echo "   - $(t file):         ${output_path}"
    echo "   - $(t size):         ${file_size} bytes"
    echo ""
}

main "$@"
