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
        es_ES:usage) printf '%s' "Uso: bash rs_agent.sh --token <TOKEN> --uuid <UUID> [--locale <IDIOMA>]" ;;
        es_ES:token_requires_value) printf '%s' "ERROR: --token requiere un valor" ;;
        es_ES:uuid_requires_value) printf '%s' "ERROR: --uuid requiere un valor" ;;
        es_ES:alias_requires_value) printf '%s' "ERROR: --alias requiere un valor" ;;
        es_ES:locale_requires_value) printf '%s' "ERROR: --locale requiere un valor" ;;
        es_ES:unknown_argument) printf '%s' "Argumento desconocido" ;;
        es_ES:required_args) printf '%s' "ERROR: --token y --uuid son obligatorios" ;;
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
        ca_ES:usage) printf '%s' "Us: bash rs_agent.sh --token <TOKEN> --uuid <UUID> [--locale <IDIOMA>]" ;;
        ca_ES:token_requires_value) printf '%s' "ERROR: --token requereix un valor" ;;
        ca_ES:uuid_requires_value) printf '%s' "ERROR: --uuid requereix un valor" ;;
        ca_ES:alias_requires_value) printf '%s' "ERROR: --alias requereix un valor" ;;
        ca_ES:locale_requires_value) printf '%s' "ERROR: --locale requereix un valor" ;;
        ca_ES:unknown_argument) printf '%s' "Argument desconegut" ;;
        ca_ES:required_args) printf '%s' "ERROR: --token i --uuid son obligatoris" ;;
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
        eu_ES:agent_token) printf '%s' "Agentearen tokena" ;;
        eu_ES:alias_requires_value) printf '%s' "ERROREA: --alias balio bat behar du" ;;
        eu_ES:already_running) printf '%s' "INFO: beste agente bat martxan dago jada; eskaera hau saltatu egiten da." ;;
        eu_ES:authorization_header) printf '%s' "Baimenaren goiburua" ;;
        eu_ES:check) printf '%s' "Egiaztatu:" ;;
        eu_ES:collecting_hardware) printf '%s' "Hardwarearen informazioa biltzen..." ;;
        eu_ES:collecting_node) printf '%s' "Node.js paketeak biltzen..." ;;
        eu_ES:collecting_python) printf '%s' "Python paketeak biltzen..." ;;
        eu_ES:collecting_system) printf '%s' "Sistemaren informazioa biltzen..." ;;
        eu_ES:collecting_system_packages) printf '%s' "Sistema paketeak biltzen..." ;;
        eu_ES:collecting_timezone) printf '%s' "Ordu-eremuaren informazioa biltzen..." ;;
        eu_ES:collecting_title) printf '%s' "Sistemaren informazioa biltzea" ;;
        eu_ES:components) printf '%s' "osagaiak" ;;
        eu_ES:configured_hidden) printf '%s' "konfiguratuta; balioa ezkutuan" ;;
        eu_ES:critical_send_failed) printf '%s' "ERRORE KRITIKOA: ezin izan da inbentarioa bidali RSMra" ;;
        eu_ES:critical_state_failed) printf '%s' "ERRORE KRITIKOA: inbentarioa bidali da, baina ezin izan da exekuzio-egoera gorde." ;;
        eu_ES:curl_exit) printf '%s' "kizkur irteera" ;;
        eu_ES:curl_verbose) printf '%s' "Kizkur hitza" ;;
        eu_ES:current_version) printf '%s' "egungoa" ;;
        eu_ES:downloading_update) printf '%s' "Eguneraketa deskargatzen..." ;;
        eu_ES:endpoint) printf '%s' "Amaiera" ;;
        eu_ES:executing_request) printf '%s' "RSMri eskaera exekutatzen..." ;;
        eu_ES:file) printf '%s' "Fitxategia" ;;
        eu_ES:firmware) printf '%s' "Firmwarea" ;;
        eu_ES:firmware_detected) printf '%s' "firmware(k) detektatu dira" ;;
        eu_ES:flock_missing) printf '%s' "ERROREA: artaldea ez dago erabilgarri; instalatu util-linux paketea." ;;
        eu_ES:flow) printf '%s' "Emaria" ;;
        eu_ES:flow_new_server_data) printf '%s' "api.php-ek ServerData berriak jasotzen ditu eta RSM-k lanpostuak eta gertaerak sortzen/ilaran jartzen ditu" ;;
        eu_ES:hidden) printf '%s' "ezkutuan" ;;
        eu_ES:hostname) printf '%s' "Ostalari izena" ;;
        eu_ES:http_code) printf '%s' "HTTP kodea" ;;
        eu_ES:http_result) printf '%s' "HTTP emaitza:" ;;
        eu_ES:invalid_uuid) printf '%s' "ERROREA: UUID baliogabea" ;;
        eu_ES:invalid_uuid_rsm) printf '%s' "ERROREA: UUID baliogabea: ez dago RSMn." ;;
        eu_ES:inventory_sent) printf '%s' "Inbentarioa behar bezala bidali da" ;;
        eu_ES:inventory_success) printf '%s' "Inbentarioa bildu eta behar bezala bidali da" ;;
        eu_ES:inventory_temp_failed) printf '%s' "ERROREA: ezin izan da aldi baterako inbentarioa sortu" ;;
        eu_ES:inventory_write_failed) printf '%s' "ERROREA: ezin izan da aldi baterako inbentarioa idatzi" ;;
        eu_ES:json_saved) printf '%s' "JSON helbidean gorde da" ;;
        eu_ES:length) printf '%s' "Luzera" ;;
        eu_ES:locale_requires_value) printf '%s' "ERROREA: --locale-k balio bat behar du" ;;
        eu_ES:method) printf '%s' "Metodoa" ;;
        eu_ES:mktemp_missing) printf '%s' "ERROREA: mktemp ez dago erabilgarri." ;;
        eu_ES:network) printf '%s' "Sare-konektibitatea" ;;
        eu_ES:new_version) printf '%s' "Bertsio berria eskuragarri" ;;
        eu_ES:no_root_mode) printf '%s' "INFO: Errorik gabeko modua; baliteke inbentarioa hain osoa izatea sistemak komando batzuk mugatzen baditu." ;;
        eu_ES:node_packages) printf '%s' "Node.js paketeak" ;;
        eu_ES:private_dir_failed) printf '%s' "ERROREA: Ezin izan da direktorio pribatu seguru bat sortu" ;;
        eu_ES:python_packages) printf '%s' "Python paketeak" ;;
        eu_ES:request_to_send) printf '%s' "Bidali beharreko eskaera:" ;;
        eu_ES:required_args) printf '%s' "ERROREA: --token eta --uuid behar dira" ;;
        eu_ES:response) printf '%s' "Erantzuna" ;;
        eu_ES:response_body_bytes) printf '%s' "Erantzunaren gorputzaren byteak" ;;
        eu_ES:response_body_file) printf '%s' "Erantzun-organoa" ;;
        eu_ES:response_headers) printf '%s' "Erantzunen goiburuak" ;;
        eu_ES:rsm_configuration) printf '%s' "RSM konfigurazioa:" ;;
        eu_ES:rsm_http_error) printf '%s' "ERROREA: RSM-k HTTP itzuli du" ;;
        eu_ES:rsm_uuid_conflict) printf '%s' "ERROREA: RSM-k adierazten du UUID dagoeneko existitzen dela edo beste sistema batekoa dela." ;;
        eu_ES:saving_inventory) printf '%s' "Inbentarioa gordetzen" ;;
        eu_ES:send_failed) printf '%s' "ERROREA: Ezin izan da inbentarioa RSMra bidali" ;;
        eu_ES:sending_inventory) printf '%s' "RSM-ra inbentarioa bidaltzen..." ;;
        eu_ES:size) printf '%s' "Tamaina" ;;
        eu_ES:source_packages) printf '%s' "iturburu paketeak" ;;
        eu_ES:state_temp_failed) printf '%s' "ERROREA: Ezin izan da aldi baterako egoera fitxategia idatzi" ;;
        eu_ES:state_update_failed) printf '%s' "ERROREA: ezin izan da egoera iraunkorra eguneratu" ;;
        eu_ES:state_updated) printf '%s' "Egoera eguneratua: azken exekuzio arrakastatsua" ;;
        eu_ES:summary) printf '%s' "Laburpena:" ;;
        eu_ES:system) printf '%s' "Sistema" ;;
        eu_ES:system_components) printf '%s' "sistemaren osagaiak" ;;
        eu_ES:system_failed) printf '%s' "ERROREA: Ezin izan da sistemaren informazioa bildu" ;;
        eu_ES:timezone) printf '%s' "Ordu-eremua" ;;
        eu_ES:token_requires_value) printf '%s' "ERROREA: --token-ek balio bat behar du" ;;
        eu_ES:total_components) printf '%s' "Osagaiak guztira" ;;
        eu_ES:total_packages) printf '%s' "Paketeak guztira" ;;
        eu_ES:trigger) printf '%s' "Exekuzio abiarazlea" ;;
        eu_ES:unified_total) printf '%s' "Guztira bateratua" ;;
        eu_ES:unknown_argument) printf '%s' "Argumentu ezezaguna" ;;
        eu_ES:unsafe_owner) printf '%s' "ERROREA: Direktorio ez segurua: ez da uneko erabiltzailearen jabetzakoa" ;;
        eu_ES:unsafe_symlink) printf '%s' "ERROREA: Bide ez-segurua: esteka sinbolikoa da" ;;
        eu_ES:update_completed) printf '%s' "Eguneraketa osatu da. Agentea berrabiarazten..." ;;
        eu_ES:update_failed) printf '%s' "Errore bat gertatu da eguneratzea deskargatzean" ;;
        eu_ES:usage) printf '%s' "Erabilera: bash rs_agent.sh --token <TOKEN> --uuid <UUID> [--locale <LOCALE>]" ;;
        eu_ES:uuid_not_generated) printf '%s' "Ezin da inbentarioa Gehitu sistema berritik sortu ez den UUID batekin bidali." ;;
        eu_ES:uuid_other_system) printf '%s' "ERROREA: UUID hau RSMko beste sistema batekoa da jada." ;;
        eu_ES:uuid_other_system_local) printf '%s' "Agente hau ezin da instalatu UUID horrekin makina lokalean." ;;
        eu_ES:uuid_requires_value) printf '%s' "ERROREA: --uuid-ek balio bat behar du" ;;
        eu_ES:uuid_reserved) printf '%s' "UUID RSMn gordeta eta instalatzeko prest" ;;
        eu_ES:uuid_same_system) printf '%s' "Sistema honekin dagoeneko lotuta dagoen UUID; bere inbentarioa eguneratuko da" ;;
        eu_ES:uuid_validate_denied) printf '%s' "ERROREA: RSM-k ez du baimendu UUID baliozkotzea inbentarioa bidali aurretik" ;;
        eu_ES:uuid_validate_failed) printf '%s' "ERROREA: Ezin izan da UUID balioztatu inbentarioa bidali aurretik" ;;
        eu_ES:uuid_validate_safety) printf '%s' "Segurtasunagatik, instalazioak ez du jarraituko UUIDa beste sistema batekoa ez dela baieztatu gabe." ;;
        eu_ES:validating_uuid) printf '%s' "UUID beste sistema batekoa ez dela balioztatzea..." ;;
        gl_ES:agent_token) printf '%s' "Token de axente" ;;
        gl_ES:alias_requires_value) printf '%s' "ERRO: --alias require un valor" ;;
        gl_ES:already_running) printf '%s' "INFORMACIÓN: Xa está en marcha outra execución do axente; esta solicitude omítase." ;;
        gl_ES:authorization_header) printf '%s' "Cabeceira de autorización" ;;
        gl_ES:check) printf '%s' "Comprobar:" ;;
        gl_ES:collecting_hardware) printf '%s' "Recopilando información de hardware..." ;;
        gl_ES:collecting_node) printf '%s' "Recollendo paquetes Node.js..." ;;
        gl_ES:collecting_python) printf '%s' "Recollendo paquetes de Python..." ;;
        gl_ES:collecting_system) printf '%s' "Recopilación de información do sistema..." ;;
        gl_ES:collecting_system_packages) printf '%s' "Recollendo paquetes do sistema..." ;;
        gl_ES:collecting_timezone) printf '%s' "Recopilando información da zona horaria..." ;;
        gl_ES:collecting_title) printf '%s' "Recopilación de información do sistema" ;;
        gl_ES:components) printf '%s' "compoñentes" ;;
        gl_ES:configured_hidden) printf '%s' "configurado; valor oculto" ;;
        gl_ES:critical_send_failed) printf '%s' "ERRO CRÍTICO: non se puido enviar o inventario a RSM" ;;
        gl_ES:critical_state_failed) printf '%s' "ERRO CRÍTICO: enviouse o inventario, pero non se puido gardar o estado de execución." ;;
        gl_ES:curl_exit) printf '%s' "saída de rizo" ;;
        gl_ES:curl_verbose) printf '%s' "Curl verboso" ;;
        gl_ES:current_version) printf '%s' "actual" ;;
        gl_ES:downloading_update) printf '%s' "Descargando actualización..." ;;
        gl_ES:endpoint) printf '%s' "Punto final" ;;
        gl_ES:executing_request) printf '%s' "Executando solicitude a RSM..." ;;
        gl_ES:file) printf '%s' "Arquivo" ;;
        gl_ES:firmware) printf '%s' "Firmware" ;;
        gl_ES:firmware_detected) printf '%s' "firmware(s) detectado(s)." ;;
        gl_ES:flock_missing) printf '%s' "ERRO: o rabaño non está dispoñible; instalar o paquete util-linux." ;;
        gl_ES:flow) printf '%s' "Fluxo" ;;
        gl_ES:flow_new_server_data) printf '%s' "api.php recibe newServerData e RSM crea/poñen en cola traballos e eventos" ;;
        gl_ES:hidden) printf '%s' "agochado" ;;
        gl_ES:hostname) printf '%s' "Nome de host" ;;
        gl_ES:http_code) printf '%s' "Código HTTP" ;;
        gl_ES:http_result) printf '%s' "Resultado HTTP:" ;;
        gl_ES:invalid_uuid) printf '%s' "ERRO: UUID non válido" ;;
        gl_ES:invalid_uuid_rsm) printf '%s' "ERRO: UUID non válido: non existe en RSM." ;;
        gl_ES:inventory_sent) printf '%s' "Inventario enviado correctamente" ;;
        gl_ES:inventory_success) printf '%s' "Inventario recompilado e enviado correctamente" ;;
        gl_ES:inventory_temp_failed) printf '%s' "ERRO: non se puido crear o inventario temporal" ;;
        gl_ES:inventory_write_failed) printf '%s' "ERRO: non se puido escribir o inventario temporal" ;;
        gl_ES:json_saved) printf '%s' "JSON gardouse en" ;;
        gl_ES:length) printf '%s' "Lonxitude" ;;
        gl_ES:locale_requires_value) printf '%s' "ERRO: --locale require un valor" ;;
        gl_ES:method) printf '%s' "Método" ;;
        gl_ES:mktemp_missing) printf '%s' "ERRO: mktemp non está dispoñible." ;;
        gl_ES:network) printf '%s' "Conectividade de rede" ;;
        gl_ES:new_version) printf '%s' "Nova versión dispoñible" ;;
        gl_ES:no_root_mode) printf '%s' "INFORMACIÓN: Modo sen root; o inventario pode estar menos completo se o sistema restrinxe algúns comandos." ;;
        gl_ES:node_packages) printf '%s' "Paquetes Node.js" ;;
        gl_ES:private_dir_failed) printf '%s' "ERRO: non se puido crear un directorio privado seguro" ;;
        gl_ES:python_packages) printf '%s' "Paquetes Python" ;;
        gl_ES:request_to_send) printf '%s' "Solicitude a enviar:" ;;
        gl_ES:required_args) printf '%s' "ERRO: son necesarios --token e --uuid" ;;
        gl_ES:response) printf '%s' "Resposta" ;;
        gl_ES:response_body_bytes) printf '%s' "Bytes do corpo da resposta" ;;
        gl_ES:response_body_file) printf '%s' "Corpo de resposta" ;;
        gl_ES:response_headers) printf '%s' "Cabeceiras de resposta" ;;
        gl_ES:rsm_configuration) printf '%s' "Configuración RSM:" ;;
        gl_ES:rsm_http_error) printf '%s' "ERRO: RSM devolveu HTTP" ;;
        gl_ES:rsm_uuid_conflict) printf '%s' "ERRO: RSM indica que o UUID xa existe ou pertence a outro sistema." ;;
        gl_ES:saving_inventory) printf '%s' "Gardando inventario en" ;;
        gl_ES:send_failed) printf '%s' "ERRO: non se puido enviar o inventario a RSM" ;;
        gl_ES:sending_inventory) printf '%s' "Enviando inventario a RSM..." ;;
        gl_ES:size) printf '%s' "Tamaño" ;;
        gl_ES:source_packages) printf '%s' "paquetes fonte" ;;
        gl_ES:state_temp_failed) printf '%s' "ERRO: non se puido escribir o ficheiro de estado temporal" ;;
        gl_ES:state_update_failed) printf '%s' "ERRO: non se puido actualizar o estado persistente" ;;
        gl_ES:state_updated) printf '%s' "Estado actualizado: última execución exitosa" ;;
        gl_ES:summary) printf '%s' "Resumo:" ;;
        gl_ES:system) printf '%s' "Sistema" ;;
        gl_ES:system_components) printf '%s' "compoñentes do sistema" ;;
        gl_ES:system_failed) printf '%s' "ERRO: non se puido recoller a información do sistema" ;;
        gl_ES:timezone) printf '%s' "Fuso horario" ;;
        gl_ES:token_requires_value) printf '%s' "ERRO: --token require un valor" ;;
        gl_ES:total_components) printf '%s' "Compoñentes totais" ;;
        gl_ES:total_packages) printf '%s' "Total de paquetes" ;;
        gl_ES:trigger) printf '%s' "Activador de execución" ;;
        gl_ES:unified_total) printf '%s' "Total unificado" ;;
        gl_ES:unknown_argument) printf '%s' "Argumento descoñecido" ;;
        gl_ES:unsafe_owner) printf '%s' "ERRO: directorio non seguro: non é propiedade do usuario actual" ;;
        gl_ES:unsafe_symlink) printf '%s' "ERRO: camiño non seguro: é unha ligazón simbólica" ;;
        gl_ES:update_completed) printf '%s' "Actualización completada. Axente de reinicio..." ;;
        gl_ES:update_failed) printf '%s' "Produciuse un erro ao descargar a actualización" ;;
        gl_ES:usage) printf '%s' "Uso: bash rs_agent.sh --token <TOKEN> --uuid <UUID> [--locale <LOCALE>]" ;;
        gl_ES:uuid_not_generated) printf '%s' "Non se pode enviar o inventario cun UUID que non se xerou desde Engadir novo sistema." ;;
        gl_ES:uuid_other_system) printf '%s' "ERRO: este UUID xa pertence a outro sistema en RSM." ;;
        gl_ES:uuid_other_system_local) printf '%s' "Este axente non se pode instalar na máquina local con ese UUID." ;;
        gl_ES:uuid_requires_value) printf '%s' "ERRO: --uuid require un valor" ;;
        gl_ES:uuid_reserved) printf '%s' "UUID reservado en RSM e listo para instalar" ;;
        gl_ES:uuid_same_system) printf '%s' "UUID xa asociado a este sistema; actualizarase o seu inventario" ;;
        gl_ES:uuid_validate_denied) printf '%s' "ERRO: RSM non permitiu a validación do UUID antes de enviar o inventario" ;;
        gl_ES:uuid_validate_failed) printf '%s' "ERRO: non se puido validar o UUID antes de enviar o inventario" ;;
        gl_ES:uuid_validate_safety) printf '%s' "Por seguridade, a instalación non continuará sen confirmar que o UUID non pertence a outro sistema." ;;
        gl_ES:validating_uuid) printf '%s' "Validando que o UUID non pertence a outro sistema..." ;;
        fr_FR:agent_token) printf '%s' "Jeton d'agent" ;;
        fr_FR:alias_requires_value) printf '%s' "ERREUR : --alias nécessite une valeur" ;;
        fr_FR:already_running) printf '%s' "INFO : Une autre exécution d'agent est déjà en cours ; cette demande est ignorée." ;;
        fr_FR:authorization_header) printf '%s' "En-tête d'autorisation" ;;
        fr_FR:check) printf '%s' "Vérifiez :" ;;
        fr_FR:collecting_hardware) printf '%s' "Collecte d'informations sur le matériel..." ;;
        fr_FR:collecting_node) printf '%s' "Collecte des packages Node.js..." ;;
        fr_FR:collecting_python) printf '%s' "Collecte de packages Python..." ;;
        fr_FR:collecting_system) printf '%s' "Collecte d'informations sur le système..." ;;
        fr_FR:collecting_system_packages) printf '%s' "Collecte des packages système..." ;;
        fr_FR:collecting_timezone) printf '%s' "Collecte d'informations sur le fuseau horaire..." ;;
        fr_FR:collecting_title) printf '%s' "Collecte d'informations sur le système" ;;
        fr_FR:components) printf '%s' "composants" ;;
        fr_FR:configured_hidden) printf '%s' "configuré ; valeur cachée" ;;
        fr_FR:critical_send_failed) printf '%s' "ERREUR CRITIQUE : Impossible d'envoyer l'inventaire à RSM" ;;
        fr_FR:critical_state_failed) printf '%s' "ERREUR CRITIQUE : l'inventaire a été envoyé, mais l'état d'exécution n'a pas pu être enregistré." ;;
        fr_FR:curl_exit) printf '%s' "boucle sortie" ;;
        fr_FR:curl_verbose) printf '%s' "Curl verbeux" ;;
        fr_FR:current_version) printf '%s' "courant" ;;
        fr_FR:downloading_update) printf '%s' "Téléchargement de la mise à jour..." ;;
        fr_FR:endpoint) printf '%s' "Point de terminaison" ;;
        fr_FR:executing_request) printf '%s' "Exécution de la requête vers RSM..." ;;
        fr_FR:file) printf '%s' "Fichier" ;;
        fr_FR:firmware) printf '%s' "Micrologiciel" ;;
        fr_FR:firmware_detected) printf '%s' "firmware(s) détecté(s)" ;;
        fr_FR:flock_missing) printf '%s' "ERREUR : le troupeau n'est pas disponible ; installez le paquet util-linux." ;;
        fr_FR:flow) printf '%s' "Flux" ;;
        fr_FR:flow_new_server_data) printf '%s' "api.php reçoit newServerData et RSM crée/met en file d'attente les tâches et les événements" ;;
        fr_FR:hidden) printf '%s' "caché" ;;
        fr_FR:hostname) printf '%s' "Nom d'hôte" ;;
        fr_FR:http_code) printf '%s' "Code HTTP" ;;
        fr_FR:http_result) printf '%s' "Résultat HTTP :" ;;
        fr_FR:invalid_uuid) printf '%s' "ERREUR : UUID invalide" ;;
        fr_FR:invalid_uuid_rsm) printf '%s' "ERREUR : UUID invalide : il n'existe pas dans RSM." ;;
        fr_FR:inventory_sent) printf '%s' "Inventaire envoyé avec succès" ;;
        fr_FR:inventory_success) printf '%s' "Inventaire collecté et envoyé avec succès" ;;
        fr_FR:inventory_temp_failed) printf '%s' "ERREUR : Impossible de créer un inventaire temporaire dans" ;;
        fr_FR:inventory_write_failed) printf '%s' "ERREUR : Impossible d'écrire l'inventaire temporaire" ;;
        fr_FR:json_saved) printf '%s' "JSON enregistré à" ;;
        fr_FR:length) printf '%s' "Longueur" ;;
        fr_FR:locale_requires_value) printf '%s' "ERREUR : --locale nécessite une valeur" ;;
        fr_FR:method) printf '%s' "Méthode" ;;
        fr_FR:mktemp_missing) printf '%s' "ERREUR : mktemp n'est pas disponible." ;;
        fr_FR:network) printf '%s' "Connectivité réseau" ;;
        fr_FR:new_version) printf '%s' "Nouvelle version disponible" ;;
        fr_FR:no_root_mode) printf '%s' "INFO : mode sans racine ; l'inventaire peut être moins complet si le système restreint certaines commandes." ;;
        fr_FR:node_packages) printf '%s' "Packages Node.js" ;;
        fr_FR:private_dir_failed) printf '%s' "ERREUR : Impossible de créer un répertoire privé sécurisé" ;;
        fr_FR:python_packages) printf '%s' "Paquets Python" ;;
        fr_FR:request_to_send) printf '%s' "Demande à envoyer :" ;;
        fr_FR:required_args) printf '%s' "ERREUR : --token et --uuid sont requis" ;;
        fr_FR:response) printf '%s' "Réponse" ;;
        fr_FR:response_body_bytes) printf '%s' "Octets du corps de la réponse" ;;
        fr_FR:response_body_file) printf '%s' "Corps de réponse" ;;
        fr_FR:response_headers) printf '%s' "En-têtes de réponse" ;;
        fr_FR:rsm_configuration) printf '%s' "Configuration RSM :" ;;
        fr_FR:rsm_http_error) printf '%s' "ERREUR : RSM a renvoyé HTTP" ;;
        fr_FR:rsm_uuid_conflict) printf '%s' "ERREUR : RSM indique que l'UUID existe déjà ou appartient à un autre système." ;;
        fr_FR:saving_inventory) printf '%s' "Enregistrer l'inventaire dans" ;;
        fr_FR:send_failed) printf '%s' "ERREUR : Échec de l'envoi de l'inventaire à RSM" ;;
        fr_FR:sending_inventory) printf '%s' "Envoi de l'inventaire à RSM..." ;;
        fr_FR:size) printf '%s' "Taille" ;;
        fr_FR:source_packages) printf '%s' "paquets sources" ;;
        fr_FR:state_temp_failed) printf '%s' "ERREUR : Impossible d'écrire le fichier d'état temporaire" ;;
        fr_FR:state_update_failed) printf '%s' "ERREUR : Impossible de mettre à jour l'état persistant" ;;
        fr_FR:state_updated) printf '%s' "État mis à jour : dernière exécution réussie" ;;
        fr_FR:summary) printf '%s' "Résumé :" ;;
        fr_FR:system) printf '%s' "Système" ;;
        fr_FR:system_components) printf '%s' "composants du système" ;;
        fr_FR:system_failed) printf '%s' "ERREUR : Impossible de collecter les informations système" ;;
        fr_FR:timezone) printf '%s' "Fuseau horaire" ;;
        fr_FR:token_requires_value) printf '%s' "ERREUR : --token nécessite une valeur" ;;
        fr_FR:total_components) printf '%s' "Composants totaux" ;;
        fr_FR:total_packages) printf '%s' "Total des forfaits" ;;
        fr_FR:trigger) printf '%s' "Déclencheur d'exécution" ;;
        fr_FR:unified_total) printf '%s' "Total unifié" ;;
        fr_FR:unknown_argument) printf '%s' "Argument inconnu" ;;
        fr_FR:unsafe_owner) printf '%s' "ERREUR : répertoire non sécurisé : n'appartient pas à l'utilisateur actuel" ;;
        fr_FR:unsafe_symlink) printf '%s' "ERREUR : Chemin non sécurisé : est un lien symbolique" ;;
        fr_FR:update_completed) printf '%s' "Mise à jour terminée. Agent de redémarrage..." ;;
        fr_FR:update_failed) printf '%s' "Erreur de téléchargement de la mise à jour" ;;
        fr_FR:usage) printf '%s' "Utilisation : bash rs_agent.sh --token <TOKEN> --uuid <UUID> [--locale <LOCALE>]" ;;
        fr_FR:uuid_not_generated) printf '%s' "L'inventaire ne peut pas être envoyé avec un UUID qui n'a pas été généré à partir de l'ajout d'un nouveau système." ;;
        fr_FR:uuid_other_system) printf '%s' "ERREUR : cet UUID appartient déjà à un autre système dans RSM." ;;
        fr_FR:uuid_other_system_local) printf '%s' "Cet agent ne peut pas être installé sur la machine locale avec cet UUID." ;;
        fr_FR:uuid_requires_value) printf '%s' "ERREUR : --uuid nécessite une valeur" ;;
        fr_FR:uuid_reserved) printf '%s' "UUID réservé dans RSM et prêt à installer" ;;
        fr_FR:uuid_same_system) printf '%s' "UUID déjà associé à ce système ; son inventaire sera mis à jour" ;;
        fr_FR:uuid_validate_denied) printf '%s' "ERREUR : RSM n'a pas autorisé la validation de l'UUID avant d'envoyer l'inventaire" ;;
        fr_FR:uuid_validate_failed) printf '%s' "ERREUR : Impossible de valider l'UUID avant d'envoyer l'inventaire" ;;
        fr_FR:uuid_validate_safety) printf '%s' "Pour des raisons de sécurité, l'installation ne continuera pas sans confirmer que l'UUID n'appartient pas à un autre système." ;;
        fr_FR:validating_uuid) printf '%s' "Vérifier que l'UUID n'appartient pas à un autre système..." ;;
        de_DE:agent_token) printf '%s' "Agent-Token" ;;
        de_DE:alias_requires_value) printf '%s' "FEHLER: --alias erfordert einen Wert" ;;
        de_DE:already_running) printf '%s' "INFO: Eine weitere Agentenausführung ist bereits im Gange; Diese Anfrage wird übersprungen." ;;
        de_DE:authorization_header) printf '%s' "Autorisierungsheader" ;;
        de_DE:check) printf '%s' "Überprüfen Sie:" ;;
        de_DE:collecting_hardware) printf '%s' "Hardwareinformationen werden gesammelt..." ;;
        de_DE:collecting_node) printf '%s' "Node.js-Pakete werden gesammelt..." ;;
        de_DE:collecting_python) printf '%s' "Python-Pakete sammeln..." ;;
        de_DE:collecting_system) printf '%s' "Systeminformationen werden gesammelt..." ;;
        de_DE:collecting_system_packages) printf '%s' "Systempakete sammeln..." ;;
        de_DE:collecting_timezone) printf '%s' "Zeitzoneninformationen werden gesammelt..." ;;
        de_DE:collecting_title) printf '%s' "Sammeln von Systeminformationen" ;;
        de_DE:components) printf '%s' "Komponenten" ;;
        de_DE:configured_hidden) printf '%s' "konfiguriert; Wert ausgeblendet" ;;
        de_DE:critical_send_failed) printf '%s' "KRITISCHER FEHLER: Inventar konnte nicht an RSM gesendet werden" ;;
        de_DE:critical_state_failed) printf '%s' "KRITISCHER FEHLER: Inventar wurde gesendet, aber der Ausführungsstatus konnte nicht gespeichert werden." ;;
        de_DE:curl_exit) printf '%s' "Curl-Ausgang" ;;
        de_DE:curl_verbose) printf '%s' "Curl ausführlich" ;;
        de_DE:current_version) printf '%s' "aktuell" ;;
        de_DE:downloading_update) printf '%s' "Update wird heruntergeladen..." ;;
        de_DE:endpoint) printf '%s' "Endpunkt" ;;
        de_DE:executing_request) printf '%s' "Anfrage an RSM wird ausgeführt..." ;;
        de_DE:file) printf '%s' "Datei" ;;
        de_DE:firmware) printf '%s' "Firmware" ;;
        de_DE:firmware_detected) printf '%s' "Firmware(s) erkannt" ;;
        de_DE:flock_missing) printf '%s' "FEHLER: Herde ist nicht verfügbar; Installieren Sie das util-linux-Paket." ;;
        de_DE:flow) printf '%s' "Fließen" ;;
        de_DE:flow_new_server_data) printf '%s' "api.php empfängt newServerData und RSM erstellt/stellt Jobs und Ereignisse in die Warteschlange" ;;
        de_DE:hidden) printf '%s' "versteckt" ;;
        de_DE:hostname) printf '%s' "Hostname" ;;
        de_DE:http_code) printf '%s' "HTTP-Code" ;;
        de_DE:http_result) printf '%s' "HTTP-Ergebnis:" ;;
        de_DE:invalid_uuid) printf '%s' "FEHLER: Ungültige UUID" ;;
        de_DE:invalid_uuid_rsm) printf '%s' "FEHLER: Ungültige UUID: Sie existiert nicht in RSM." ;;
        de_DE:inventory_sent) printf '%s' "Inventar erfolgreich gesendet" ;;
        de_DE:inventory_success) printf '%s' "Inventar wurde erfolgreich erfasst und versendet" ;;
        de_DE:inventory_temp_failed) printf '%s' "FEHLER: Das temporäre Inventar konnte nicht erstellt werden" ;;
        de_DE:inventory_write_failed) printf '%s' "FEHLER: Temporäres Inventar konnte nicht geschrieben werden" ;;
        de_DE:json_saved) printf '%s' "JSON gespeichert unter" ;;
        de_DE:length) printf '%s' "Länge" ;;
        de_DE:locale_requires_value) printf '%s' "FEHLER: --locale erfordert einen Wert" ;;
        de_DE:method) printf '%s' "Methode" ;;
        de_DE:mktemp_missing) printf '%s' "FEHLER: mktemp ist nicht verfügbar." ;;
        de_DE:network) printf '%s' "Netzwerkkonnektivität" ;;
        de_DE:new_version) printf '%s' "Neue Version verfügbar" ;;
        de_DE:no_root_mode) printf '%s' "INFO: No-Root-Modus; Die Inventarisierung ist möglicherweise weniger vollständig, wenn das System einige Befehle einschränkt." ;;
        de_DE:node_packages) printf '%s' "Node.js-Pakete" ;;
        de_DE:private_dir_failed) printf '%s' "FEHLER: Es konnte kein sicheres privates Verzeichnis erstellt werden" ;;
        de_DE:python_packages) printf '%s' "Python-Pakete" ;;
        de_DE:request_to_send) printf '%s' "Zu sendende Anfrage:" ;;
        de_DE:required_args) printf '%s' "FEHLER: --token und --uuid sind erforderlich" ;;
        de_DE:response) printf '%s' "Antwort" ;;
        de_DE:response_body_bytes) printf '%s' "Antworttextbytes" ;;
        de_DE:response_body_file) printf '%s' "Antwortkörper" ;;
        de_DE:response_headers) printf '%s' "Antwortheader" ;;
        de_DE:rsm_configuration) printf '%s' "RSM-Konfiguration:" ;;
        de_DE:rsm_http_error) printf '%s' "FEHLER: RSM hat HTTP zurückgegeben" ;;
        de_DE:rsm_uuid_conflict) printf '%s' "FEHLER: RSM gibt an, dass die UUID bereits existiert oder zu einem anderen System gehört." ;;
        de_DE:saving_inventory) printf '%s' "Lagerbestand speichern" ;;
        de_DE:send_failed) printf '%s' "FEHLER: Das Senden des Inventars an RSM ist fehlgeschlagen" ;;
        de_DE:sending_inventory) printf '%s' "Inventar wird an RSM gesendet..." ;;
        de_DE:size) printf '%s' "Größe" ;;
        de_DE:source_packages) printf '%s' "Quellpakete" ;;
        de_DE:state_temp_failed) printf '%s' "FEHLER: Temporäre Statusdatei konnte nicht geschrieben werden" ;;
        de_DE:state_update_failed) printf '%s' "FEHLER: Der persistente Status konnte nicht aktualisiert werden" ;;
        de_DE:state_updated) printf '%s' "Status aktualisiert: letzter erfolgreicher Lauf" ;;
        de_DE:summary) printf '%s' "Zusammenfassung:" ;;
        de_DE:system) printf '%s' "System" ;;
        de_DE:system_components) printf '%s' "Systemkomponenten" ;;
        de_DE:system_failed) printf '%s' "FEHLER: Systeminformationen konnten nicht erfasst werden" ;;
        de_DE:timezone) printf '%s' "Zeitzone" ;;
        de_DE:token_requires_value) printf '%s' "FEHLER: --token erfordert einen Wert" ;;
        de_DE:total_components) printf '%s' "Gesamtkomponenten" ;;
        de_DE:total_packages) printf '%s' "Gesamtpakete" ;;
        de_DE:trigger) printf '%s' "Ausführungsauslöser" ;;
        de_DE:unified_total) printf '%s' "Einheitliche Summe" ;;
        de_DE:unknown_argument) printf '%s' "Unbekanntes Argument" ;;
        de_DE:unsafe_owner) printf '%s' "FEHLER: Unsicheres Verzeichnis: gehört nicht dem aktuellen Benutzer" ;;
        de_DE:unsafe_symlink) printf '%s' "FEHLER: Unsicherer Pfad: ist ein symbolischer Link" ;;
        de_DE:update_completed) printf '%s' "Aktualisierung abgeschlossen. Agent wird neu gestartet..." ;;
        de_DE:update_failed) printf '%s' "Fehler beim Herunterladen des Updates" ;;
        de_DE:usage) printf '%s' "Verwendung: bash rs_agent.sh --token <TOKEN> --uuid <UUID> [--locale <LOCALE>]" ;;
        de_DE:uuid_not_generated) printf '%s' "Inventar kann nicht mit einer UUID gesendet werden, die nicht durch „Neues System hinzufügen“ generiert wurde." ;;
        de_DE:uuid_other_system) printf '%s' "FEHLER: Diese UUID gehört bereits zu einem anderen System in RSM." ;;
        de_DE:uuid_other_system_local) printf '%s' "Dieser Agent kann mit dieser UUID nicht auf dem lokalen Computer installiert werden." ;;
        de_DE:uuid_requires_value) printf '%s' "FEHLER: --uuid erfordert einen Wert" ;;
        de_DE:uuid_reserved) printf '%s' "UUID im RSM reserviert und zur Installation bereit" ;;
        de_DE:uuid_same_system) printf '%s' "UUID ist diesem System bereits zugeordnet; sein Inventar wird aktualisiert" ;;
        de_DE:uuid_validate_denied) printf '%s' "FEHLER: RSM hat vor dem Senden des Inventars keine UUID-Validierung zugelassen" ;;
        de_DE:uuid_validate_failed) printf '%s' "FEHLER: Die UUID konnte vor dem Senden des Inventars nicht validiert werden" ;;
        de_DE:uuid_validate_safety) printf '%s' "Aus Sicherheitsgründen wird die Installation nicht fortgesetzt, ohne zu bestätigen, dass die UUID nicht zu einem anderen System gehört." ;;
        de_DE:validating_uuid) printf '%s' "Es wird überprüft, ob die UUID nicht zu einem anderen System gehört ..." ;;
        it_IT:agent_token) printf '%s' "Gettone dell'agente" ;;
        it_IT:alias_requires_value) printf '%s' "ERRORE: --alias richiede un valore" ;;
        it_IT:already_running) printf '%s' "INFORMAZIONI: un'altra esecuzione dell'agente è già in corso; questa richiesta viene saltata." ;;
        it_IT:authorization_header) printf '%s' "Intestazione dell'autorizzazione" ;;
        it_IT:check) printf '%s' "Controlla:" ;;
        it_IT:collecting_hardware) printf '%s' "Raccolta delle informazioni sull'hardware in corso..." ;;
        it_IT:collecting_node) printf '%s' "Raccolta dei pacchetti Node.js in corso..." ;;
        it_IT:collecting_python) printf '%s' "Raccolta dei pacchetti Python..." ;;
        it_IT:collecting_system) printf '%s' "Raccolta informazioni di sistema..." ;;
        it_IT:collecting_system_packages) printf '%s' "Raccolta dei pacchetti di sistema in corso..." ;;
        it_IT:collecting_timezone) printf '%s' "Raccolta delle informazioni sul fuso orario in corso..." ;;
        it_IT:collecting_title) printf '%s' "Raccolta delle informazioni di sistema" ;;
        it_IT:components) printf '%s' "componenti" ;;
        it_IT:configured_hidden) printf '%s' "configurato; valore nascosto" ;;
        it_IT:critical_send_failed) printf '%s' "ERRORE CRITICO: impossibile inviare l'inventario a RSM" ;;
        it_IT:critical_state_failed) printf '%s' "ERRORE CRITICO: l'inventario è stato inviato, ma non è stato possibile salvare lo stato di esecuzione." ;;
        it_IT:curl_exit) printf '%s' "uscita dell'arricciatura" ;;
        it_IT:curl_verbose) printf '%s' "Ricciolo verboso" ;;
        it_IT:current_version) printf '%s' "corrente" ;;
        it_IT:downloading_update) printf '%s' "Download dell'aggiornamento in corso..." ;;
        it_IT:endpoint) printf '%s' "Punto finale" ;;
        it_IT:executing_request) printf '%s' "Esecuzione della richiesta a RSM..." ;;
        it_IT:file) printf '%s' "Archivio" ;;
        it_IT:firmware) printf '%s' "Firmware" ;;
        it_IT:firmware_detected) printf '%s' "firmware(i) rilevati" ;;
        it_IT:flock_missing) printf '%s' "ERRORE: il gregge non è disponibile; installare il pacchetto util-linux." ;;
        it_IT:flow) printf '%s' "Flusso" ;;
        it_IT:flow_new_server_data) printf '%s' "api.php riceve newServerData e RSM crea/accoda lavori ed eventi" ;;
        it_IT:hidden) printf '%s' "nascosto" ;;
        it_IT:hostname) printf '%s' "Nome host" ;;
        it_IT:http_code) printf '%s' "Codice HTTP" ;;
        it_IT:http_result) printf '%s' "Risultato HTTP:" ;;
        it_IT:invalid_uuid) printf '%s' "ERRORE: UUID non valido" ;;
        it_IT:invalid_uuid_rsm) printf '%s' "ERRORE: UUID non valido: non esiste in RSM." ;;
        it_IT:inventory_sent) printf '%s' "Inventario inviato con successo" ;;
        it_IT:inventory_success) printf '%s' "Inventario raccolto e inviato correttamente" ;;
        it_IT:inventory_temp_failed) printf '%s' "ERRORE: impossibile creare un inventario temporaneo in" ;;
        it_IT:inventory_write_failed) printf '%s' "ERRORE: impossibile scrivere l'inventario temporaneo" ;;
        it_IT:json_saved) printf '%s' "JSON salvato in" ;;
        it_IT:length) printf '%s' "Lunghezza" ;;
        it_IT:locale_requires_value) printf '%s' "ERRORE: --locale richiede un valore" ;;
        it_IT:method) printf '%s' "Metodo" ;;
        it_IT:mktemp_missing) printf '%s' "ERRORE: mktemp non è disponibile." ;;
        it_IT:network) printf '%s' "Connettività di rete" ;;
        it_IT:new_version) printf '%s' "Nuova versione disponibile" ;;
        it_IT:no_root_mode) printf '%s' "INFORMAZIONI: modalità senza root; l'inventario potrebbe essere meno completo se il sistema limita alcuni comandi." ;;
        it_IT:node_packages) printf '%s' "Pacchetti Node.js" ;;
        it_IT:private_dir_failed) printf '%s' "ERRORE: impossibile creare una directory privata sicura" ;;
        it_IT:python_packages) printf '%s' "Pacchetti Python" ;;
        it_IT:request_to_send) printf '%s' "Richiesta da inviare:" ;;
        it_IT:required_args) printf '%s' "ERRORE: --token e --uuid sono obbligatori" ;;
        it_IT:response) printf '%s' "Risposta" ;;
        it_IT:response_body_bytes) printf '%s' "Byte del corpo della risposta" ;;
        it_IT:response_body_file) printf '%s' "Corpo della risposta" ;;
        it_IT:response_headers) printf '%s' "Intestazioni di risposta" ;;
        it_IT:rsm_configuration) printf '%s' "Configurazione RSM:" ;;
        it_IT:rsm_http_error) printf '%s' "ERRORE: RSM ha restituito HTTP" ;;
        it_IT:rsm_uuid_conflict) printf '%s' "ERRORE: RSM indica che l'UUID esiste già o appartiene a un altro sistema." ;;
        it_IT:saving_inventory) printf '%s' "Salvataggio dell'inventario in" ;;
        it_IT:send_failed) printf '%s' "ERRORE: impossibile inviare l'inventario a RSM" ;;
        it_IT:sending_inventory) printf '%s' "Invio dell'inventario a RSM..." ;;
        it_IT:size) printf '%s' "Dimensioni" ;;
        it_IT:source_packages) printf '%s' "pacchetti sorgente" ;;
        it_IT:state_temp_failed) printf '%s' "ERRORE: impossibile scrivere il file di stato temporaneo" ;;
        it_IT:state_update_failed) printf '%s' "ERRORE: impossibile aggiornare lo stato persistente" ;;
        it_IT:state_updated) printf '%s' "Stato aggiornato: ultima esecuzione riuscita" ;;
        it_IT:summary) printf '%s' "Sommario:" ;;
        it_IT:system) printf '%s' "Sistema" ;;
        it_IT:system_components) printf '%s' "componenti del sistema" ;;
        it_IT:system_failed) printf '%s' "ERRORE: impossibile raccogliere informazioni sul sistema" ;;
        it_IT:timezone) printf '%s' "Fuso orario" ;;
        it_IT:token_requires_value) printf '%s' "ERRORE: --token richiede un valore" ;;
        it_IT:total_components) printf '%s' "Componenti totali" ;;
        it_IT:total_packages) printf '%s' "Pacchetti totali" ;;
        it_IT:trigger) printf '%s' "Trigger di esecuzione" ;;
        it_IT:unified_total) printf '%s' "Totale unificato" ;;
        it_IT:unknown_argument) printf '%s' "Argomento sconosciuto" ;;
        it_IT:unsafe_owner) printf '%s' "ERRORE: directory non sicura: non è di proprietà dell'utente corrente" ;;
        it_IT:unsafe_symlink) printf '%s' "ERRORE: percorso non sicuro: è un collegamento simbolico" ;;
        it_IT:update_completed) printf '%s' "Aggiornamento completato. Riavvio dell'agente..." ;;
        it_IT:update_failed) printf '%s' "Errore durante il download dell'aggiornamento" ;;
        it_IT:usage) printf '%s' "Utilizzo: bash rs_agent.sh --token <TOKEN> --uuid <UUID> [--locale <LOCALE>]" ;;
        it_IT:uuid_not_generated) printf '%s' "Non è possibile inviare l'inventario con un UUID che non è stato generato da Aggiungi nuovo sistema." ;;
        it_IT:uuid_other_system) printf '%s' "ERRORE: questo UUID appartiene già a un altro sistema in RSM." ;;
        it_IT:uuid_other_system_local) printf '%s' "Questo agente non può essere installato sul computer locale con quell'UUID." ;;
        it_IT:uuid_requires_value) printf '%s' "ERRORE: --uuid richiede un valore" ;;
        it_IT:uuid_reserved) printf '%s' "UUID riservato in RSM e pronto per l'installazione" ;;
        it_IT:uuid_same_system) printf '%s' "UUID già associato a questo sistema; il suo inventario verrà aggiornato" ;;
        it_IT:uuid_validate_denied) printf '%s' "ERRORE: RSM non ha consentito la convalida UUID prima dell'invio dell'inventario" ;;
        it_IT:uuid_validate_failed) printf '%s' "ERRORE: impossibile convalidare l'UUID prima di inviare l'inventario" ;;
        it_IT:uuid_validate_safety) printf '%s' "Per motivi di sicurezza, l'installazione non proseguirà senza la conferma che l'UUID non appartiene a un altro sistema." ;;
        it_IT:validating_uuid) printf '%s' "Verifica che l'UUID non appartenga a un altro sistema..." ;;
        ja_JP:agent_token) printf '%s' "エージェントトークン" ;;
        ja_JP:alias_requires_value) printf '%s' "エラー: --alias には値が必要です" ;;
        ja_JP:already_running) printf '%s' "情報: 別のエージェントの実行がすでに進行中です。このリクエストはスキップされます。" ;;
        ja_JP:authorization_header) printf '%s' "認可ヘッダー" ;;
        ja_JP:check) printf '%s' "確認してください:" ;;
        ja_JP:collecting_hardware) printf '%s' "ハードウェア情報を収集しています..." ;;
        ja_JP:collecting_node) printf '%s' "Node.js パッケージを収集しています..." ;;
        ja_JP:collecting_python) printf '%s' "Python パッケージを収集しています..." ;;
        ja_JP:collecting_system) printf '%s' "システム情報を収集しています..." ;;
        ja_JP:collecting_system_packages) printf '%s' "システム パッケージを収集しています..." ;;
        ja_JP:collecting_timezone) printf '%s' "タイムゾーン情報を収集しています..." ;;
        ja_JP:collecting_title) printf '%s' "システム情報の収集" ;;
        ja_JP:components) printf '%s' "コンポーネント" ;;
        ja_JP:configured_hidden) printf '%s' "構成されています。隠された値" ;;
        ja_JP:critical_send_failed) printf '%s' "重大なエラー: 在庫を RSM に送信できませんでした" ;;
        ja_JP:critical_state_failed) printf '%s' "重大なエラー: インベントリは送信されましたが、実行状態を保存できませんでした。" ;;
        ja_JP:curl_exit) printf '%s' "カール出口" ;;
        ja_JP:curl_verbose) printf '%s' "カール冗長" ;;
        ja_JP:current_version) printf '%s' "現在の" ;;
        ja_JP:downloading_update) printf '%s' "アップデートをダウンロード中..." ;;
        ja_JP:endpoint) printf '%s' "エンドポイント" ;;
        ja_JP:executing_request) printf '%s' "RSM へのリクエストを実行しています..." ;;
        ja_JP:file) printf '%s' "ファイル" ;;
        ja_JP:firmware) printf '%s' "ファームウェア" ;;
        ja_JP:firmware_detected) printf '%s' "ファームウェアが検出されました" ;;
        ja_JP:flock_missing) printf '%s' "エラー: フロックは利用できません。 util-linux パッケージをインストールします。" ;;
        ja_JP:flow) printf '%s' "流れ" ;;
        ja_JP:flow_new_server_data) printf '%s' "api.php は newServerData を受け取り、RSM はジョブとイベントを作成/キューに入れます" ;;
        ja_JP:hidden) printf '%s' "隠された" ;;
        ja_JP:hostname) printf '%s' "ホスト名" ;;
        ja_JP:http_code) printf '%s' "HTTPコード" ;;
        ja_JP:http_result) printf '%s' "HTTP 結果:" ;;
        ja_JP:invalid_uuid) printf '%s' "エラー: 無効な UUID" ;;
        ja_JP:invalid_uuid_rsm) printf '%s' "エラー: 無効な UUID: RSM に存在しません。" ;;
        ja_JP:inventory_sent) printf '%s' "在庫は正常に送信されました" ;;
        ja_JP:inventory_success) printf '%s' "在庫が正常に収集され、送信されました" ;;
        ja_JP:inventory_temp_failed) printf '%s' "エラー: に一時在庫を作成できませんでした" ;;
        ja_JP:inventory_write_failed) printf '%s' "エラー: 一時的なインベントリを書き込めませんでした" ;;
        ja_JP:json_saved) printf '%s' "JSON の保存場所" ;;
        ja_JP:length) printf '%s' "長さ" ;;
        ja_JP:locale_requires_value) printf '%s' "エラー: --locale には値が必要です" ;;
        ja_JP:method) printf '%s' "方法" ;;
        ja_JP:mktemp_missing) printf '%s' "エラー: mktemp は使用できません。" ;;
        ja_JP:network) printf '%s' "ネットワーク接続" ;;
        ja_JP:new_version) printf '%s' "新しいバージョンが利用可能になりました" ;;
        ja_JP:no_root_mode) printf '%s' "情報: ルートなしモード。システムが一部のコマンドを制限している場合、インベントリは完全ではなくなる可能性があります。" ;;
        ja_JP:node_packages) printf '%s' "Node.js パッケージ" ;;
        ja_JP:private_dir_failed) printf '%s' "エラー: 安全なプライベート ディレクトリを作成できませんでした" ;;
        ja_JP:python_packages) printf '%s' "Python パッケージ" ;;
        ja_JP:request_to_send) printf '%s' "送信するリクエスト:" ;;
        ja_JP:required_args) printf '%s' "エラー: --token と --uuid が必要です" ;;
        ja_JP:response) printf '%s' "応答" ;;
        ja_JP:response_body_bytes) printf '%s' "応答本文のバイト数" ;;
        ja_JP:response_body_file) printf '%s' "レスポンスボディ" ;;
        ja_JP:response_headers) printf '%s' "応答ヘッダー" ;;
        ja_JP:rsm_configuration) printf '%s' "RSM 構成:" ;;
        ja_JP:rsm_http_error) printf '%s' "エラー: RSM が HTTP を返しました" ;;
        ja_JP:rsm_uuid_conflict) printf '%s' "エラー: RSM は、UUID がすでに存在するか、別のシステムに属していることを示しています。" ;;
        ja_JP:saving_inventory) printf '%s' "在庫の保存先" ;;
        ja_JP:send_failed) printf '%s' "エラー: 在庫を RSM に送信できませんでした" ;;
        ja_JP:sending_inventory) printf '%s' "在庫を RSM に送信しています..." ;;
        ja_JP:size) printf '%s' "サイズ" ;;
        ja_JP:source_packages) printf '%s' "ソースパッケージ" ;;
        ja_JP:state_temp_failed) printf '%s' "エラー: 一時状態ファイルを書き込めませんでした" ;;
        ja_JP:state_update_failed) printf '%s' "エラー: 永続的な状態を更新できませんでした" ;;
        ja_JP:state_updated) printf '%s' "状態が更新されました: 最後に成功した実行" ;;
        ja_JP:summary) printf '%s' "概要:" ;;
        ja_JP:system) printf '%s' "システム" ;;
        ja_JP:system_components) printf '%s' "システムコンポーネント" ;;
        ja_JP:system_failed) printf '%s' "エラー: システム情報を収集できませんでした" ;;
        ja_JP:timezone) printf '%s' "タイムゾーン" ;;
        ja_JP:token_requires_value) printf '%s' "エラー: --token には値が必要です" ;;
        ja_JP:total_components) printf '%s' "総コンポーネント" ;;
        ja_JP:total_packages) printf '%s' "パッケージの合計" ;;
        ja_JP:trigger) printf '%s' "実行トリガー" ;;
        ja_JP:unified_total) printf '%s' "統一合計" ;;
        ja_JP:unknown_argument) printf '%s' "不明な引数" ;;
        ja_JP:unsafe_owner) printf '%s' "エラー: 安全でないディレクトリ: 現在のユーザーが所有していません" ;;
        ja_JP:unsafe_symlink) printf '%s' "エラー: 安全でないパス: はシンボリック リンクです" ;;
        ja_JP:update_completed) printf '%s' "アップデートが完了しました。エージェントを再起動しています..." ;;
        ja_JP:update_failed) printf '%s' "アップデートのダウンロード中にエラーが発生しました" ;;
        ja_JP:usage) printf '%s' "使用法: bash rs_agent.sh --token <TOKEN> --uuid <UUID> [--locale <LOCALE>]" ;;
        ja_JP:uuid_not_generated) printf '%s' "新しいシステムの追加から生成されていない UUID を使用してインベントリを送信することはできません。" ;;
        ja_JP:uuid_other_system) printf '%s' "エラー: この UUID はすでに RSM の別のシステムに属しています。" ;;
        ja_JP:uuid_other_system_local) printf '%s' "このエージェントは、その UUID ではローカル マシンにインストールできません。" ;;
        ja_JP:uuid_requires_value) printf '%s' "エラー: --uuid には値が必要です" ;;
        ja_JP:uuid_reserved) printf '%s' "UUID は RSM で予約されており、インストールする準備ができています" ;;
        ja_JP:uuid_same_system) printf '%s' "UUID はすでにこのシステムに関連付けられています。在庫は更新されます" ;;
        ja_JP:uuid_validate_denied) printf '%s' "エラー: RSM はインベントリを送信する前に UUID 検証を許可しませんでした" ;;
        ja_JP:uuid_validate_failed) printf '%s' "エラー: インベントリを送信する前に UUID を検証できませんでした" ;;
        ja_JP:uuid_validate_safety) printf '%s' "安全のため、UUID が別のシステムに属していないことを確認しない限り、インストールは続行されません。" ;;
        ja_JP:validating_uuid) printf '%s' "UUID が別のシステムに属していないことを検証しています..." ;;
        zh_CN:agent_token) printf '%s' "代理令牌" ;;
        zh_CN:alias_requires_value) printf '%s' "错误：--alias 需要一个值" ;;
        zh_CN:already_running) printf '%s' "信息：另一个代理运行已经在进行中；该请求被跳过。" ;;
        zh_CN:authorization_header) printf '%s' "授权标头" ;;
        zh_CN:check) printf '%s' "检查：" ;;
        zh_CN:collecting_hardware) printf '%s' "正在收集硬件信息..." ;;
        zh_CN:collecting_node) printf '%s' "收集 Node.js 包..." ;;
        zh_CN:collecting_python) printf '%s' "收集Python包..." ;;
        zh_CN:collecting_system) printf '%s' "正在收集系统信息..." ;;
        zh_CN:collecting_system_packages) printf '%s' "正在收集系统包..." ;;
        zh_CN:collecting_timezone) printf '%s' "正在收集时区信息..." ;;
        zh_CN:collecting_title) printf '%s' "收集系统信息" ;;
        zh_CN:components) printf '%s' "组件" ;;
        zh_CN:configured_hidden) printf '%s' "配置；价值隐藏" ;;
        zh_CN:critical_send_failed) printf '%s' "严重错误：无法将库存发送至 RSM" ;;
        zh_CN:critical_state_failed) printf '%s' "严重错误：清单已发送，但无法保存执行状态。" ;;
        zh_CN:curl_exit) printf '%s' "卷曲退出" ;;
        zh_CN:curl_verbose) printf '%s' "卷曲详细" ;;
        zh_CN:current_version) printf '%s' "当前" ;;
        zh_CN:downloading_update) printf '%s' "正在下载更新..." ;;
        zh_CN:endpoint) printf '%s' "端点" ;;
        zh_CN:executing_request) printf '%s' "正在执行对 RSM 的请求..." ;;
        zh_CN:file) printf '%s' "文件" ;;
        zh_CN:firmware) printf '%s' "固件" ;;
        zh_CN:firmware_detected) printf '%s' "检测到固件" ;;
        zh_CN:flock_missing) printf '%s' "错误：羊群不可用；安装 util-linux 软件包。" ;;
        zh_CN:flow) printf '%s' "流量" ;;
        zh_CN:flow_new_server_data) printf '%s' "api.php 接收 newServerData 并且 RSM 创建/排队作业和事件" ;;
        zh_CN:hidden) printf '%s' "隐藏的" ;;
        zh_CN:hostname) printf '%s' "主机名" ;;
        zh_CN:http_code) printf '%s' "HTTP 代码" ;;
        zh_CN:http_result) printf '%s' "HTTP 结果：" ;;
        zh_CN:invalid_uuid) printf '%s' "错误：UUID 无效" ;;
        zh_CN:invalid_uuid_rsm) printf '%s' "错误：UUID 无效：RSM 中不存在。" ;;
        zh_CN:inventory_sent) printf '%s' "库存发送成功" ;;
        zh_CN:inventory_success) printf '%s' "库存已收集并已成功发送" ;;
        zh_CN:inventory_temp_failed) printf '%s' "错误：无法创建临时库存" ;;
        zh_CN:inventory_write_failed) printf '%s' "错误：无法写入临时库存" ;;
        zh_CN:json_saved) printf '%s' "JSON 保存在" ;;
        zh_CN:length) printf '%s' "长度" ;;
        zh_CN:locale_requires_value) printf '%s' "错误：--locale 需要一个值" ;;
        zh_CN:method) printf '%s' "方法" ;;
        zh_CN:mktemp_missing) printf '%s' "错误：mktemp 不可用。" ;;
        zh_CN:network) printf '%s' "网络连接" ;;
        zh_CN:new_version) printf '%s' "新版本可用" ;;
        zh_CN:no_root_mode) printf '%s' "信息：免root模式；如果系统限制某些命令，清单可能会不太完整。" ;;
        zh_CN:node_packages) printf '%s' "Node.js 包" ;;
        zh_CN:private_dir_failed) printf '%s' "错误：无法创建安全的私有目录" ;;
        zh_CN:python_packages) printf '%s' "Python 包" ;;
        zh_CN:request_to_send) printf '%s' "需要发送的请求：" ;;
        zh_CN:required_args) printf '%s' "错误：需要 --token 和 --uuid" ;;
        zh_CN:response) printf '%s' "回应" ;;
        zh_CN:response_body_bytes) printf '%s' "响应主体字节" ;;
        zh_CN:response_body_file) printf '%s' "响应体" ;;
        zh_CN:response_headers) printf '%s' "响应标头" ;;
        zh_CN:rsm_configuration) printf '%s' "RSM配置：" ;;
        zh_CN:rsm_http_error) printf '%s' "错误：RSM 返回 HTTP" ;;
        zh_CN:rsm_uuid_conflict) printf '%s' "错误：RSM 指示 UUID 已存在或属于另一个系统。" ;;
        zh_CN:saving_inventory) printf '%s' "将库存保存至" ;;
        zh_CN:send_failed) printf '%s' "错误：无法将库存发送至 RSM" ;;
        zh_CN:sending_inventory) printf '%s' "正在将库存发送至 RSM..." ;;
        zh_CN:size) printf '%s' "尺寸" ;;
        zh_CN:source_packages) printf '%s' "源码包" ;;
        zh_CN:state_temp_failed) printf '%s' "错误：无法写入临时状态文件" ;;
        zh_CN:state_update_failed) printf '%s' "错误：无法更新持久状态" ;;
        zh_CN:state_updated) printf '%s' "状态更新：上次成功运行" ;;
        zh_CN:summary) printf '%s' "摘要：" ;;
        zh_CN:system) printf '%s' "系统" ;;
        zh_CN:system_components) printf '%s' "系统组件" ;;
        zh_CN:system_failed) printf '%s' "错误：无法收集系统信息" ;;
        zh_CN:timezone) printf '%s' "时区" ;;
        zh_CN:token_requires_value) printf '%s' "错误：--token 需要一个值" ;;
        zh_CN:total_components) printf '%s' "总成分" ;;
        zh_CN:total_packages) printf '%s' "总包数" ;;
        zh_CN:trigger) printf '%s' "执行触发器" ;;
        zh_CN:unified_total) printf '%s' "统一总计" ;;
        zh_CN:unknown_argument) printf '%s' "未知的论点" ;;
        zh_CN:unsafe_owner) printf '%s' "错误：不安全目录：不属于当前用户" ;;
        zh_CN:unsafe_symlink) printf '%s' "错误：不安全路径：是符号链接" ;;
        zh_CN:update_completed) printf '%s' "更新完成。正在重启代理..." ;;
        zh_CN:update_failed) printf '%s' "下载更新时出错" ;;
        zh_CN:usage) printf '%s' "用法：bash rs_agent.sh --token <TOKEN> --uuid <UUID> [--locale <LOCALE>]" ;;
        zh_CN:uuid_not_generated) printf '%s' "无法使用不是从“添加新系统”生成的 UUID 发送清单。" ;;
        zh_CN:uuid_other_system) printf '%s' "错误：此 UUID 已属于 RSM 中的另一个系统。" ;;
        zh_CN:uuid_other_system_local) printf '%s' "该代理无法安装在具有该 UUID 的本地计算机上。" ;;
        zh_CN:uuid_requires_value) printf '%s' "错误：--uuid 需要一个值" ;;
        zh_CN:uuid_reserved) printf '%s' "RSM 中保留 UUID 并准备安装" ;;
        zh_CN:uuid_same_system) printf '%s' "UUID 已与该系统关联；其库存将被更新" ;;
        zh_CN:uuid_validate_denied) printf '%s' "错误：RSM 在发送库存之前不允许 UUID 验证" ;;
        zh_CN:uuid_validate_failed) printf '%s' "错误：发送库存前无法验证 UUID" ;;
        zh_CN:uuid_validate_safety) printf '%s' "为了安全起见，在未确认 UUID 不属于其他系统的情况下，安装不会继续。" ;;
        zh_CN:validating_uuid) printf '%s' "验证 UUID 不属于另一个系统..." ;;

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
        *:usage) printf '%s' "Usage: bash rs_agent.sh --token <TOKEN> --uuid <UUID> [--locale <LOCALE>]" ;;
        *:token_requires_value) printf '%s' "ERROR: --token requires a value" ;;
        *:uuid_requires_value) printf '%s' "ERROR: --uuid requires a value" ;;
        *:alias_requires_value) printf '%s' "ERROR: --alias requires a value" ;;
        *:locale_requires_value) printf '%s' "ERROR: --locale requires a value" ;;
        *:unknown_argument) printf '%s' "Unknown argument" ;;
        *:required_args) printf '%s' "ERROR: --token and --uuid are required" ;;
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
                # Backward-compatible no-op: aliases are now managed only from the UI.
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

    if [ -z "$AGENT_TOKEN" ] || [ -z "$UUID_VAL" ]; then
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

    printf '{"hostname":"%s","fqdn":"%s","uuid":"%s","os":{"name":"%s","version":"%s","distro_id":"%s","distro_version":"%s","kernel":"%s","architecture":"%s"},"collected_at":"%s","timezone":"%s","agent_version":"%s"}' \
        "$(json_escape "$hostname")" \
        "$(json_escape "$fqdn")" \
        "$(json_escape "$UUID_VAL")" \
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
        exec bash "$script_path" --token "$AGENT_TOKEN" --uuid "$UUID_VAL" --locale "$AGENT_LOCALE"
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
