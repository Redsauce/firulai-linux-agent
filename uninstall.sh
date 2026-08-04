#!/bin/bash
# -*- coding: utf-8 -*-
#
# Firulai Inventory Agent - Uninstaller
# Marks the system as inactive in RSM and removes the local installation.
#

set -uo pipefail

RUN_AS_ROOT=0
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    RUN_AS_ROOT=1
fi

if [ "$RUN_AS_ROOT" = "1" ]; then
    INSTALL_DIR="${RS_AGENT_INSTALL_DIR:-/opt/rs-agent}"
    DATA_DIR="${RS_AGENT_DATA_DIR:-/var/lib/rs-agent}"
    LOG_FILE="${RS_AGENT_LOG_FILE:-/var/log/rs-agent.log}"
    PRIVATE_TMP_DIR="${RS_AGENT_TMP_DIR:-/run/rs-agent/tmp}"
    SYSTEMD_USER_SERVICE_FILE=""
    SYSTEMD_USER_TIMER_FILE=""
else
    INSTALL_DIR="${RS_AGENT_INSTALL_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/rs-agent}"
    DATA_DIR="${RS_AGENT_DATA_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/rs-agent}"
    LOG_FILE="${RS_AGENT_LOG_FILE:-$DATA_DIR/rs-agent.log}"
    PRIVATE_TMP_DIR="${RS_AGENT_TMP_DIR:-${XDG_RUNTIME_DIR:-$DATA_DIR}/rs-agent/tmp}"
    SYSTEMD_USER_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
    SYSTEMD_USER_SERVICE_FILE="$SYSTEMD_USER_DIR/rs-agent.service"
    SYSTEMD_USER_TIMER_FILE="$SYSTEMD_USER_DIR/rs-agent.timer"
fi

CONFIG_FILE="$DATA_DIR/config.env"
RSM_ITEMS_GET_URL="https://rsm1.redsauce.net/AppController/commands_RSM/api/v2/items/get.php"
RSM_ITEMS_UPDATE_URL="https://rsm1.redsauce.net/AppController/commands_RSM/api/v2/items/update.php"
RSM_SYSTEM_UUID_PROPERTY_ID="1780"
RSM_SYSTEM_HOSTNAME_STATUS_PROPERTY_ID="1751"
RSM_SYSTEM_HOSTNAME_STATUS_DISCONNECTED_VALUE="Disconnected"
AGENT_TOKEN=""
UUID_VAL=""
AGENT_LOCALE="${RS_AGENT_LOCALE:-}"

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
        es_ES:no_root_uninstall) printf '%s' "Modo sin root: solo se eliminara la instalacion del usuario actual." ;;
        es_ES:unsafe_symlink) printf '%s' "Ruta no segura: es un enlace simbolico" ;;
        es_ES:private_dir_failed) printf '%s' "No se pudo crear un directorio privado seguro" ;;
        es_ES:unsafe_owner) printf '%s' "Directorio no seguro: no pertenece al usuario actual" ;;
        es_ES:mktemp_missing) printf '%s' "mktemp no esta disponible" ;;
        es_ES:invalid_uuid) printf '%s' "no es un UUID valido" ;;
        es_ES:unknown_argument) printf '%s' "Argumento desconocido" ;;
        es_ES:missing_token_uuid) printf '%s' "No se pudo encontrar token o UUID para notificar a RSM" ;;
        es_ES:manual_usage) printf '%s' "Uso manual: bash uninstall.sh --token <TOKEN> --uuid <UUID>" ;;
        es_ES:title) printf '%s' "Firulai Inventory Agent - Desinstalacion" ;;
        es_ES:local_only) printf '%s' "Esta accion solo eliminara la instalacion local del agente." ;;
        es_ES:rsm_not_deleted) printf '%s' "Los datos de RSM no se eliminaran." ;;
        es_ES:inactive_1) printf '%s' "El sistema se marcara como inactivo en Firulai. Desde Firulai podras" ;;
        es_ES:inactive_2) printf '%s' "eliminar sus datos permanentemente o reinstalar el agente mas tarde enlazandolo" ;;
        es_ES:inactive_3) printf '%s' "con el System y el inventario ya guardados." ;;
        es_ES:system_uuid) printf '%s' "UUID del sistema" ;;
        es_ES:confirm) printf '%s' "Aceptas desinstalar el agente local? (s/N): " ;;
        es_ES:cancelled) printf '%s' "Desinstalacion cancelada por el usuario" ;;
        es_ES:query_failed) printf '%s' "No se pudo consultar el sistema en RSM" ;;
        es_ES:query_denied) printf '%s' "RSM no permitio consultar el sistema" ;;
        es_ES:response) printf '%s' "Respuesta" ;;
        es_ES:marking_inactive) printf '%s' "Marcando sistema como inactivo en Firulai..." ;;
        es_ES:no_system) printf '%s' "No hay ningun System enlazado a este UUID en Firulai. La desinstalacion local continuara." ;;
        es_ES:mark_failed) printf '%s' "No se pudo marcar el sistema como inactivo en RSM" ;;
        es_ES:mark_denied) printf '%s' "RSM no permitio marcar el sistema como inactivo" ;;
        es_ES:marked) printf '%s' "Sistema marcado como inactivo en Firulai" ;;
        es_ES:removing_schedule) printf '%s' "Eliminando ejecucion automatica..." ;;
        es_ES:cron_removed) printf '%s' "Entradas de cron eliminadas" ;;
        es_ES:cron_update_failed) printf '%s' "No se pudo actualizar crontab o no habia entradas configuradas" ;;
        es_ES:schedule_removed) printf '%s' "Programacion automatica eliminada" ;;
        es_ES:removing_files) printf '%s' "Eliminando archivos locales..." ;;
        es_ES:files_removed) printf '%s' "Archivos locales eliminados" ;;
        es_ES:stopped_rsm) printf '%s' "Desinstalacion detenida: no se pudo actualizar el estado en RSM" ;;
        es_ES:success) printf '%s' "Agente desinstalado correctamente" ;;

        ca_ES:no_root_uninstall) printf '%s' "Mode sense root: nomes s'eliminara la instal.lacio de l'usuari actual." ;;
        ca_ES:unsafe_symlink) printf '%s' "Ruta no segura: es un enllac simbolic" ;;
        ca_ES:private_dir_failed) printf '%s' "No s'ha pogut crear un directori privat segur" ;;
        ca_ES:unsafe_owner) printf '%s' "Directori no segur: no pertany a l'usuari actual" ;;
        ca_ES:mktemp_missing) printf '%s' "mktemp no esta disponible" ;;
        ca_ES:invalid_uuid) printf '%s' "no es un UUID valid" ;;
        ca_ES:unknown_argument) printf '%s' "Argument desconegut" ;;
        ca_ES:missing_token_uuid) printf '%s' "No s'ha pogut trobar token o UUID per notificar RSM" ;;
        ca_ES:manual_usage) printf '%s' "Us manual: bash uninstall.sh --token <TOKEN> --uuid <UUID>" ;;
        ca_ES:title) printf '%s' "Firulai Inventory Agent - Desinstal.lacio" ;;
        ca_ES:local_only) printf '%s' "Aquesta accio nomes eliminara la instal.lacio local de l'agent." ;;
        ca_ES:rsm_not_deleted) printf '%s' "Les dades de RSM no s'eliminaran." ;;
        ca_ES:inactive_1) printf '%s' "El sistema es marcara com a inactiu a Firulai. Des de Firulai podras" ;;
        ca_ES:inactive_2) printf '%s' "eliminar-ne les dades permanentment o reinstal.lar l'agent mes tard enllacant-lo" ;;
        ca_ES:inactive_3) printf '%s' "amb el System i l'inventari ja desats." ;;
        ca_ES:system_uuid) printf '%s' "UUID del sistema" ;;
        ca_ES:confirm) printf '%s' "Acceptes desinstal.lar l'agent local? (s/N): " ;;
        ca_ES:cancelled) printf '%s' "Desinstal.lacio cancel.lada per l'usuari" ;;
        ca_ES:query_failed) printf '%s' "No s'ha pogut consultar el sistema a RSM" ;;
        ca_ES:query_denied) printf '%s' "RSM no ha permes consultar el sistema" ;;
        ca_ES:response) printf '%s' "Resposta" ;;
        ca_ES:marking_inactive) printf '%s' "Marcant sistema com a inactiu a Firulai..." ;;
        ca_ES:no_system) printf '%s' "No hi ha cap System enllacat a aquest UUID a Firulai. La desinstal.lacio local continuara." ;;
        ca_ES:mark_failed) printf '%s' "No s'ha pogut marcar el sistema com a inactiu a RSM" ;;
        ca_ES:mark_denied) printf '%s' "RSM no ha permes marcar el sistema com a inactiu" ;;
        ca_ES:marked) printf '%s' "Sistema marcat com a inactiu a Firulai" ;;
        ca_ES:removing_schedule) printf '%s' "Eliminant execucio automatica..." ;;
        ca_ES:cron_removed) printf '%s' "Entrades de cron eliminades" ;;
        ca_ES:cron_update_failed) printf '%s' "No s'ha pogut actualitzar crontab o no hi havia entrades configurades" ;;
        ca_ES:schedule_removed) printf '%s' "Programacio automatica eliminada" ;;
        ca_ES:removing_files) printf '%s' "Eliminant fitxers locals..." ;;
        ca_ES:files_removed) printf '%s' "Fitxers locals eliminats" ;;
        ca_ES:stopped_rsm) printf '%s' "Desinstal.lacio aturada: no s'ha pogut actualitzar l'estat a RSM" ;;
        ca_ES:success) printf '%s' "Agent desinstal.lat correctament" ;;
        eu_ES:cancelled) printf '%s' "Erabiltzaileak bertan behera utzi du desinstalazioa" ;;
        eu_ES:confirm) printf '%s' "Onartzen al zara tokiko agentea desinstalatzea? (y/N): " ;;
        eu_ES:cron_removed) printf '%s' "Cron sarrerak kendu dira" ;;
        eu_ES:cron_update_failed) printf '%s' "Ezin izan da crontab eguneratu edo ez da sarrerarik konfiguratu" ;;
        eu_ES:files_removed) printf '%s' "Tokiko fitxategiak kendu dira" ;;
        eu_ES:inactive_1) printf '%s' "Sistema inaktibo gisa markatuko da Firulai-n. Firulaitik dezakezu" ;;
        eu_ES:inactive_2) printf '%s' "ezabatu bere datuak betirako edo berriro instalatu agentea geroago estekatuz" ;;
        eu_ES:inactive_3) printf '%s' "dagoeneko gordetako Sistema eta inbentariora." ;;
        eu_ES:invalid_uuid) printf '%s' "ez da baliozko UUID bat" ;;
        eu_ES:local_only) printf '%s' "Ekintza honek agente lokalaren instalazioa bakarrik kenduko du." ;;
        eu_ES:manual_usage) printf '%s' "Eskuzko erabilera: bash uninstall.sh --token <TOKEN> --uuid <UUID>" ;;
        eu_ES:mark_denied) printf '%s' "RSM-k ez zuen sistema inaktibo gisa markatzea baimendu" ;;
        eu_ES:mark_failed) printf '%s' "Ezin izan da sistema inaktibo gisa markatu RSMn" ;;
        eu_ES:marked) printf '%s' "Sistema inaktibo gisa markatu da Firulai-n" ;;
        eu_ES:marking_inactive) printf '%s' "Firulai-n inaktibo gisa markatzeko sistema..." ;;
        eu_ES:missing_token_uuid) printf '%s' "Ezin izan da token edo UUID aurkitu RSM jakinarazteko" ;;
        eu_ES:mktemp_missing) printf '%s' "mktemp ez dago erabilgarri" ;;
        eu_ES:no_root_uninstall) printf '%s' "Errorik gabeko modua: oraingo erabiltzailearen instalazioa bakarrik kenduko da." ;;
        eu_ES:no_system) printf '%s' "Ez dago sistemarik UUID honekin loturik Firulai-n. Tokiko desinstalazioa jarraituko du." ;;
        eu_ES:private_dir_failed) printf '%s' "Ezin izan da direktorio pribatu seguru bat sortu" ;;
        eu_ES:query_denied) printf '%s' "RSM-k ez zuen sistemari kontsulta egitea baimendu" ;;
        eu_ES:query_failed) printf '%s' "Ezin izan da sistemari kontsultatu RSMn" ;;
        eu_ES:removing_files) printf '%s' "Fitxategi lokalak kentzen..." ;;
        eu_ES:removing_schedule) printf '%s' "Exekuzio automatikoa kentzen..." ;;
        eu_ES:response) printf '%s' "Erantzuna" ;;
        eu_ES:rsm_not_deleted) printf '%s' "RSM datuak ez dira ezabatuko." ;;
        eu_ES:schedule_removed) printf '%s' "Egitarau automatikoa kendu da" ;;
        eu_ES:stopped_rsm) printf '%s' "Desinstalazioa gelditu da: ezin izan da egoera eguneratu RSMn" ;;
        eu_ES:success) printf '%s' "Agentea behar bezala desinstalatu da" ;;
        eu_ES:system_uuid) printf '%s' "Sistemaren UUID" ;;
        eu_ES:title) printf '%s' "Firulai Inventory Agent - Desinstalatu" ;;
        eu_ES:unknown_argument) printf '%s' "Argumentu ezezaguna" ;;
        eu_ES:unsafe_owner) printf '%s' "Direktorio ez segurua: ez da uneko erabiltzailearen jabetzakoa" ;;
        eu_ES:unsafe_symlink) printf '%s' "Bide ez-segurua: lotura sinbolikoa da" ;;
        gl_ES:cancelled) printf '%s' "Desinstalación cancelada polo usuario" ;;
        gl_ES:confirm) printf '%s' "Estás de acordo en desinstalar o axente local? (s/n): " ;;
        gl_ES:cron_removed) printf '%s' "Elimináronse as entradas do cron" ;;
        gl_ES:cron_update_failed) printf '%s' "Non se puido actualizar crontab ou non se configurou ningunha entrada" ;;
        gl_ES:files_removed) printf '%s' "Ficheiros locais eliminados" ;;
        gl_ES:inactive_1) printf '%s' "O sistema marcarase como inactivo en Firulai. Desde Firulai podes" ;;
        gl_ES:inactive_2) printf '%s' "elimine os seus datos de forma permanente ou reinstale o axente máis tarde ligándoo" ;;
        gl_ES:inactive_3) printf '%s' "ao Sistema e ao inventario xa gardados." ;;
        gl_ES:invalid_uuid) printf '%s' "non é un UUID válido" ;;
        gl_ES:local_only) printf '%s' "Esta acción só eliminará a instalación do axente local." ;;
        gl_ES:manual_usage) printf '%s' "Uso manual: bash uninstall.sh --token <TOKEN> --uuid <UUID>" ;;
        gl_ES:mark_denied) printf '%s' "RSM non permitiu marcar o sistema como inactivo" ;;
        gl_ES:mark_failed) printf '%s' "Non se puido marcar o sistema como inactivo en RSM" ;;
        gl_ES:marked) printf '%s' "Sistema marcado como inactivo en Firulai" ;;
        gl_ES:marking_inactive) printf '%s' "Sistema de marcado como inactivo en Firulai..." ;;
        gl_ES:missing_token_uuid) printf '%s' "Non se puido atopar o token ou o UUID para notificar a RSM" ;;
        gl_ES:mktemp_missing) printf '%s' "mktemp non está dispoñible" ;;
        gl_ES:no_root_uninstall) printf '%s' "Modo sen root: só se eliminará a instalación do usuario actual." ;;
        gl_ES:no_system) printf '%s' "Ningún sistema está ligado a este UUID en Firulai. A desinstalación local continuará." ;;
        gl_ES:private_dir_failed) printf '%s' "Non se puido crear un directorio privado seguro" ;;
        gl_ES:query_denied) printf '%s' "RSM non permitiu consultar o sistema" ;;
        gl_ES:query_failed) printf '%s' "Non se puido consultar o sistema en RSM" ;;
        gl_ES:removing_files) printf '%s' "Eliminando ficheiros locais..." ;;
        gl_ES:removing_schedule) printf '%s' "Eliminando a execución automática..." ;;
        gl_ES:response) printf '%s' "Resposta" ;;
        gl_ES:rsm_not_deleted) printf '%s' "Os datos de RSM non se eliminarán." ;;
        gl_ES:schedule_removed) printf '%s' "Quitouse a programación automática" ;;
        gl_ES:stopped_rsm) printf '%s' "Desinstalación detida: non se puido actualizar o estado en RSM" ;;
        gl_ES:success) printf '%s' "O axente desinstalouse correctamente" ;;
        gl_ES:system_uuid) printf '%s' "UUID do sistema" ;;
        gl_ES:title) printf '%s' "Firulai Inventory Agent - Desinstalar" ;;
        gl_ES:unknown_argument) printf '%s' "Argumento descoñecido" ;;
        gl_ES:unsafe_owner) printf '%s' "Directorio non seguro: non é propiedade do usuario actual" ;;
        gl_ES:unsafe_symlink) printf '%s' "Camiño inseguro: é un enlace simbólico" ;;
        fr_FR:cancelled) printf '%s' "Désinstallation annulée par l'utilisateur" ;;
        fr_FR:confirm) printf '%s' "Acceptez-vous de désinstaller l'agent local ? (o/N) : " ;;
        fr_FR:cron_removed) printf '%s' "Entrées Cron supprimées" ;;
        fr_FR:cron_update_failed) printf '%s' "Impossible de mettre à jour crontab ou aucune entrée n'a été configurée" ;;
        fr_FR:files_removed) printf '%s' "Fichiers locaux supprimés" ;;
        fr_FR:inactive_1) printf '%s' "Le système sera marqué comme inactif à Firulai. Depuis Firulai, vous pouvez" ;;
        fr_FR:inactive_2) printf '%s' "supprimer définitivement ses données ou réinstaller l'agent ultérieurement en le liant" ;;
        fr_FR:inactive_3) printf '%s' "au système et à l'inventaire déjà enregistrés." ;;
        fr_FR:invalid_uuid) printf '%s' "n'est pas un UUID valide" ;;
        fr_FR:local_only) printf '%s' "Cette action supprimera uniquement l'installation de l'agent local." ;;
        fr_FR:manual_usage) printf '%s' "Utilisation manuelle : bash uninstall.sh --token <TOKEN> --uuid <UUID>" ;;
        fr_FR:mark_denied) printf '%s' "RSM n'a pas permis de marquer le système comme inactif" ;;
        fr_FR:mark_failed) printf '%s' "Impossible de marquer le système comme inactif dans RSM" ;;
        fr_FR:marked) printf '%s' "Système marqué comme inactif à Firulai" ;;
        fr_FR:marking_inactive) printf '%s' "Système de marquage comme inactif à Firulai..." ;;
        fr_FR:missing_token_uuid) printf '%s' "Impossible de trouver le jeton ou l'UUID pour informer RSM" ;;
        fr_FR:mktemp_missing) printf '%s' "mktemp n'est pas disponible" ;;
        fr_FR:no_root_uninstall) printf '%s' "Mode sans root : seule l'installation de l'utilisateur actuel sera supprimée." ;;
        fr_FR:no_system) printf '%s' "Aucun système n'est lié à cet UUID dans Firulai. La désinstallation locale continuera." ;;
        fr_FR:private_dir_failed) printf '%s' "Impossible de créer un répertoire privé sécurisé" ;;
        fr_FR:query_denied) printf '%s' "RSM n'a pas permis d'interroger le système" ;;
        fr_FR:query_failed) printf '%s' "Impossible d'interroger le système dans RSM" ;;
        fr_FR:removing_files) printf '%s' "Suppression des fichiers locaux..." ;;
        fr_FR:removing_schedule) printf '%s' "Suppression de l'exécution automatique..." ;;
        fr_FR:response) printf '%s' "Réponse" ;;
        fr_FR:rsm_not_deleted) printf '%s' "Les données RSM ne seront pas supprimées." ;;
        fr_FR:schedule_removed) printf '%s' "Planification automatique supprimée" ;;
        fr_FR:stopped_rsm) printf '%s' "Désinstallation arrêtée : impossible de mettre à jour l'état dans RSM" ;;
        fr_FR:success) printf '%s' "Agent désinstallé avec succès" ;;
        fr_FR:system_uuid) printf '%s' "UUID système" ;;
        fr_FR:title) printf '%s' "Agent d'inventaire Firulai - Désinstaller" ;;
        fr_FR:unknown_argument) printf '%s' "Argument inconnu" ;;
        fr_FR:unsafe_owner) printf '%s' "Répertoire non sécurisé : n'appartient pas à l'utilisateur actuel" ;;
        fr_FR:unsafe_symlink) printf '%s' "Chemin non sécurisé : est un lien symbolique" ;;
        de_DE:cancelled) printf '%s' "Deinstallation wurde vom Benutzer abgebrochen" ;;
        de_DE:confirm) printf '%s' "Sind Sie damit einverstanden, den lokalen Agenten zu deinstallieren? (j/N): " ;;
        de_DE:cron_removed) printf '%s' "Cron-Einträge entfernt" ;;
        de_DE:cron_update_failed) printf '%s' "Crontab konnte nicht aktualisiert werden oder es wurden keine Einträge konfiguriert" ;;
        de_DE:files_removed) printf '%s' "Lokale Dateien entfernt" ;;
        de_DE:inactive_1) printf '%s' "Das System wird in Firulai als inaktiv markiert. Von Firulai aus ist das möglich" ;;
        de_DE:inactive_2) printf '%s' "Löschen Sie seine Daten dauerhaft oder installieren Sie den Agenten später neu, indem Sie ihn verknüpfen" ;;
        de_DE:inactive_3) printf '%s' "zum bereits gespeicherten System und Inventar." ;;
        de_DE:invalid_uuid) printf '%s' "ist keine gültige UUID" ;;
        de_DE:local_only) printf '%s' "Durch diese Aktion wird nur die lokale Agenteninstallation entfernt." ;;
        de_DE:manual_usage) printf '%s' "Manuelle Verwendung: bash uninstall.sh --token <TOKEN> --uuid <UUID>" ;;
        de_DE:mark_denied) printf '%s' "RSM erlaubte nicht, das System als inaktiv zu markieren" ;;
        de_DE:mark_failed) printf '%s' "Das System konnte in RSM nicht als inaktiv markiert werden" ;;
        de_DE:marked) printf '%s' "System in Firulai als inaktiv markiert" ;;
        de_DE:marking_inactive) printf '%s' "System in Firulai als inaktiv markieren..." ;;
        de_DE:missing_token_uuid) printf '%s' "Token oder UUID zur Benachrichtigung von RSM konnten nicht gefunden werden" ;;
        de_DE:mktemp_missing) printf '%s' "mktemp ist nicht verfügbar" ;;
        de_DE:no_root_uninstall) printf '%s' "No-Root-Modus: Nur die Installation des aktuellen Benutzers wird entfernt." ;;
        de_DE:no_system) printf '%s' "In Firulai ist kein System mit dieser UUID verknüpft. Die lokale Deinstallation wird fortgesetzt." ;;
        de_DE:private_dir_failed) printf '%s' "Es konnte kein sicheres privates Verzeichnis erstellt werden" ;;
        de_DE:query_denied) printf '%s' "RSM erlaubte keine Abfrage des Systems" ;;
        de_DE:query_failed) printf '%s' "Das System konnte in RSM nicht abgefragt werden" ;;
        de_DE:removing_files) printf '%s' "Lokale Dateien werden entfernt..." ;;
        de_DE:removing_schedule) printf '%s' "Automatische Ausführung wird entfernt..." ;;
        de_DE:response) printf '%s' "Antwort" ;;
        de_DE:rsm_not_deleted) printf '%s' "RSM-Daten werden nicht gelöscht." ;;
        de_DE:schedule_removed) printf '%s' "Automatischer Zeitplan entfernt" ;;
        de_DE:stopped_rsm) printf '%s' "Deinstallation gestoppt: Der Status in RSM konnte nicht aktualisiert werden" ;;
        de_DE:success) printf '%s' "Der Agent wurde erfolgreich deinstalliert" ;;
        de_DE:system_uuid) printf '%s' "System-UUID" ;;
        de_DE:title) printf '%s' "Firulai Inventory Agent – Deinstallation" ;;
        de_DE:unknown_argument) printf '%s' "Unbekanntes Argument" ;;
        de_DE:unsafe_owner) printf '%s' "Unsicheres Verzeichnis: gehört nicht dem aktuellen Benutzer" ;;
        de_DE:unsafe_symlink) printf '%s' "Unsicherer Pfad: ist ein symbolischer Link" ;;
        it_IT:cancelled) printf '%s' "Disinstallazione annullata dall'utente" ;;
        it_IT:confirm) printf '%s' "Accetti di disinstallare l'agente locale? (sì/N): " ;;
        it_IT:cron_removed) printf '%s' "Voci cron rimosse" ;;
        it_IT:cron_update_failed) printf '%s' "Impossibile aggiornare crontab oppure non è stata configurata alcuna voce" ;;
        it_IT:files_removed) printf '%s' "File locali rimossi" ;;
        it_IT:inactive_1) printf '%s' "Il sistema sarà contrassegnato come inattivo a Firulai. Da Firulai puoi" ;;
        it_IT:inactive_2) printf '%s' "eliminare i suoi dati in modo permanente o reinstallare l'agente in un secondo momento collegandolo" ;;
        it_IT:inactive_3) printf '%s' "al sistema e all'inventario già salvati." ;;
        it_IT:invalid_uuid) printf '%s' "non è un UUID valido" ;;
        it_IT:local_only) printf '%s' "Questa azione rimuoverà solo l'installazione dell'agente locale." ;;
        it_IT:manual_usage) printf '%s' "Utilizzo manuale: bash uninstall.sh --token <TOKEN> --uuid <UUID>" ;;
        it_IT:mark_denied) printf '%s' "RSM non ha consentito di contrassegnare il sistema come inattivo" ;;
        it_IT:mark_failed) printf '%s' "Impossibile contrassegnare il sistema come inattivo in RSM" ;;
        it_IT:marked) printf '%s' "Sistema contrassegnato come inattivo a Firulai" ;;
        it_IT:marking_inactive) printf '%s' "Sistema di contrassegno come inattivo in Firulai..." ;;
        it_IT:missing_token_uuid) printf '%s' "Impossibile trovare il token o l'UUID per notificare RSM" ;;
        it_IT:mktemp_missing) printf '%s' "mktemp non è disponibile" ;;
        it_IT:no_root_uninstall) printf '%s' "Modalità no-root: verrà rimossa solo l'installazione dell'utente corrente." ;;
        it_IT:no_system) printf '%s' "Nessun sistema è collegato a questo UUID in Firulai. La disinstallazione locale continuerà." ;;
        it_IT:private_dir_failed) printf '%s' "Impossibile creare una directory privata sicura" ;;
        it_IT:query_denied) printf '%s' "RSM non ha consentito di interrogare il sistema" ;;
        it_IT:query_failed) printf '%s' "Impossibile interrogare il sistema in RSM" ;;
        it_IT:removing_files) printf '%s' "Rimozione dei file locali..." ;;
        it_IT:removing_schedule) printf '%s' "Rimozione dell'esecuzione automatica in corso..." ;;
        it_IT:response) printf '%s' "Risposta" ;;
        it_IT:rsm_not_deleted) printf '%s' "I dati RSM non verranno eliminati." ;;
        it_IT:schedule_removed) printf '%s' "Programmazione automatica rimossa" ;;
        it_IT:stopped_rsm) printf '%s' "Disinstallazione interrotta: impossibile aggiornare lo stato in RSM" ;;
        it_IT:success) printf '%s' "L'agente è stato disinstallato correttamente" ;;
        it_IT:system_uuid) printf '%s' "UUID del sistema" ;;
        it_IT:title) printf '%s' "Agente inventario Firulai: disinstalla" ;;
        it_IT:unknown_argument) printf '%s' "Argomento sconosciuto" ;;
        it_IT:unsafe_owner) printf '%s' "Directory non sicura: non è di proprietà dell'utente corrente" ;;
        it_IT:unsafe_symlink) printf '%s' "Percorso non sicuro: è un collegamento simbolico" ;;
        ja_JP:cancelled) printf '%s' "ユーザーによってアンインストールがキャンセルされました" ;;
        ja_JP:confirm) printf '%s' "ローカル エージェントをアンインストールすることに同意しますか? (y/N): " ;;
        ja_JP:cron_removed) printf '%s' "cron エントリが削除されました" ;;
        ja_JP:cron_update_failed) printf '%s' "crontab を更新できなかったか、エントリが構成されていませんでした" ;;
        ja_JP:files_removed) printf '%s' "ローカルファイルが削除されました" ;;
        ja_JP:inactive_1) printf '%s' "システムは、Firulai で非アクティブとしてマークされます。フィルライからは次のことができます" ;;
        ja_JP:inactive_2) printf '%s' "データを完全に削除するか、後でエージェントをリンクして再インストールしてください" ;;
        ja_JP:inactive_3) printf '%s' "すでに保存されているシステムとインベントリに。" ;;
        ja_JP:invalid_uuid) printf '%s' "有効な UUID ではありません" ;;
        ja_JP:local_only) printf '%s' "この操作では、ローカル エージェントのインストールのみが削除されます。" ;;
        ja_JP:manual_usage) printf '%s' "手動使用: bash uninstall.sh --token <TOKEN> --uuid <UUID>" ;;
        ja_JP:mark_denied) printf '%s' "RSM はシステムを非アクティブとしてマークすることを許可していませんでした" ;;
        ja_JP:mark_failed) printf '%s' "RSM でシステムを非アクティブとしてマークできませんでした" ;;
        ja_JP:marked) printf '%s' "Firulai でシステムが非アクティブとしてマークされている" ;;
        ja_JP:marking_inactive) printf '%s' "Firulai でシステムを非アクティブとしてマークしています..." ;;
        ja_JP:missing_token_uuid) printf '%s' "RSM に通知するトークンまたは UUID が見つかりませんでした" ;;
        ja_JP:mktemp_missing) printf '%s' "mktemp は使用できません" ;;
        ja_JP:no_root_uninstall) printf '%s' "ルートなしモード: 現在のユーザーのインストールのみが削除されます。" ;;
        ja_JP:no_system) printf '%s' "Firulai ではこの UUID にリンクされているシステムはありません。ローカルアンインストールは続行されます。" ;;
        ja_JP:private_dir_failed) printf '%s' "安全なプライベート ディレクトリを作成できませんでした" ;;
        ja_JP:query_denied) printf '%s' "RSM ではシステムへのクエリが許可されていませんでした" ;;
        ja_JP:query_failed) printf '%s' "RSM でシステムにクエリを実行できませんでした" ;;
        ja_JP:removing_files) printf '%s' "ローカルファイルを削除しています..." ;;
        ja_JP:removing_schedule) printf '%s' "自動実行を削除しています..." ;;
        ja_JP:response) printf '%s' "応答" ;;
        ja_JP:rsm_not_deleted) printf '%s' "RSM データは削除されません。" ;;
        ja_JP:schedule_removed) printf '%s' "自動スケジュールが削除されました" ;;
        ja_JP:stopped_rsm) printf '%s' "アンインストールが停止しました: RSM のステータスを更新できませんでした" ;;
        ja_JP:success) printf '%s' "エージェントは正常にアンインストールされました" ;;
        ja_JP:system_uuid) printf '%s' "システムUUID" ;;
        ja_JP:title) printf '%s' "Firulai インベントリ エージェント - アンインストール" ;;
        ja_JP:unknown_argument) printf '%s' "不明な引数" ;;
        ja_JP:unsafe_owner) printf '%s' "安全でないディレクトリ: 現在のユーザーが所有していません" ;;
        ja_JP:unsafe_symlink) printf '%s' "安全でないパス: シンボリック リンクです" ;;
        zh_CN:cancelled) printf '%s' "用户取消卸载" ;;
        zh_CN:confirm) printf '%s' "您同意卸载本地代理吗？ （是/否）： " ;;
        zh_CN:cron_removed) printf '%s' "已删除 Cron 条目" ;;
        zh_CN:cron_update_failed) printf '%s' "无法更新 crontab 或未配置任何条目" ;;
        zh_CN:files_removed) printf '%s' "本地文件已删除" ;;
        zh_CN:inactive_1) printf '%s' "该系统将在 Firulai 被标记为非活动状态。从菲鲁莱您可以" ;;
        zh_CN:inactive_2) printf '%s' "永久删除其数据或稍后通过链接重新安装代理" ;;
        zh_CN:inactive_3) printf '%s' "到已保存的系统和库存。" ;;
        zh_CN:invalid_uuid) printf '%s' "不是有效的 UUID" ;;
        zh_CN:local_only) printf '%s' "此操作只会删除本地代理安装。" ;;
        zh_CN:manual_usage) printf '%s' "手动使用：bash uninstall.sh --token <TOKEN> --uuid <UUID>" ;;
        zh_CN:mark_denied) printf '%s' "RSM 不允许将系统标记为非活动状态" ;;
        zh_CN:mark_failed) printf '%s' "无法在 RSM 中将系统标记为非活动状态" ;;
        zh_CN:marked) printf '%s' "系统在 Firulai 标记为非活动状态" ;;
        zh_CN:marking_inactive) printf '%s' "在 Firulai 中将系统标记为非活动状态..." ;;
        zh_CN:missing_token_uuid) printf '%s' "找不到用于通知 RSM 的令牌或 UUID" ;;
        zh_CN:mktemp_missing) printf '%s' "mktemp 不可用" ;;
        zh_CN:no_root_uninstall) printf '%s' "无root模式：仅删除当前用户的安装。" ;;
        zh_CN:no_system) printf '%s' "Firulai 中没有系统链接到此 UUID。本地卸载将继续。" ;;
        zh_CN:private_dir_failed) printf '%s' "无法创建安全的私有目录" ;;
        zh_CN:query_denied) printf '%s' "RSM 不允许查询系统" ;;
        zh_CN:query_failed) printf '%s' "无法在 RSM 中查询系统" ;;
        zh_CN:removing_files) printf '%s' "正在删除本地文件..." ;;
        zh_CN:removing_schedule) printf '%s' "正在删除自动执行..." ;;
        zh_CN:response) printf '%s' "回应" ;;
        zh_CN:rsm_not_deleted) printf '%s' "RSM 数据不会被删除。" ;;
        zh_CN:schedule_removed) printf '%s' "自动计划已删除" ;;
        zh_CN:stopped_rsm) printf '%s' "卸载已停止：无法更新 RSM 中的状态" ;;
        zh_CN:success) printf '%s' "代理卸载成功" ;;
        zh_CN:system_uuid) printf '%s' "系统UUID" ;;
        zh_CN:title) printf '%s' "Firulai 库存代理 - 卸载" ;;
        zh_CN:unknown_argument) printf '%s' "未知的论点" ;;
        zh_CN:unsafe_owner) printf '%s' "不安全目录：不属于当前用户" ;;
        zh_CN:unsafe_symlink) printf '%s' "不安全路径：是符号链接" ;;

        *:no_root_uninstall) printf '%s' "No-root mode: only the current user's installation will be removed." ;;
        *:unsafe_symlink) printf '%s' "Unsafe path: is a symbolic link" ;;
        *:private_dir_failed) printf '%s' "Could not create a secure private directory" ;;
        *:unsafe_owner) printf '%s' "Unsafe directory: is not owned by the current user" ;;
        *:mktemp_missing) printf '%s' "mktemp is not available" ;;
        *:invalid_uuid) printf '%s' "is not a valid UUID" ;;
        *:unknown_argument) printf '%s' "Unknown argument" ;;
        *:missing_token_uuid) printf '%s' "Could not find token or UUID to notify RSM" ;;
        *:manual_usage) printf '%s' "Manual usage: bash uninstall.sh --token <TOKEN> --uuid <UUID>" ;;
        *:title) printf '%s' "Firulai Inventory Agent - Uninstall" ;;
        *:local_only) printf '%s' "This action will only remove the local agent installation." ;;
        *:rsm_not_deleted) printf '%s' "RSM data will not be deleted." ;;
        *:inactive_1) printf '%s' "The system will be marked as inactive in Firulai. From Firulai you can" ;;
        *:inactive_2) printf '%s' "delete its data permanently or reinstall the agent later by linking it" ;;
        *:inactive_3) printf '%s' "to the already saved System and inventory." ;;
        *:system_uuid) printf '%s' "System UUID" ;;
        *:confirm) printf '%s' "Do you agree to uninstall the local agent? (y/N): " ;;
        *:cancelled) printf '%s' "Uninstall cancelled by user" ;;
        *:query_failed) printf '%s' "Could not query the system in RSM" ;;
        *:query_denied) printf '%s' "RSM did not allow querying the system" ;;
        *:response) printf '%s' "Response" ;;
        *:marking_inactive) printf '%s' "Marking system as inactive in Firulai..." ;;
        *:no_system) printf '%s' "No System is linked to this UUID in Firulai. Local uninstall will continue." ;;
        *:mark_failed) printf '%s' "Could not mark the system as inactive in RSM" ;;
        *:mark_denied) printf '%s' "RSM did not allow marking the system as inactive" ;;
        *:marked) printf '%s' "System marked as inactive in Firulai" ;;
        *:removing_schedule) printf '%s' "Removing automatic execution..." ;;
        *:cron_removed) printf '%s' "Cron entries removed" ;;
        *:cron_update_failed) printf '%s' "Could not update crontab or no entries were configured" ;;
        *:schedule_removed) printf '%s' "Automatic schedule removed" ;;
        *:removing_files) printf '%s' "Removing local files..." ;;
        *:files_removed) printf '%s' "Local files removed" ;;
        *:stopped_rsm) printf '%s' "Uninstall stopped: could not update the status in RSM" ;;
        *:success) printf '%s' "Agent uninstalled successfully" ;;
        *) printf '%s' "$key" ;;
    esac
}

log() {
    printf '[OK] %s\n' "$1"
}

info() {
    printf '[INFO] %s\n' "$1"
}

warn() {
    printf '[WARN] %s\n' "$1"
}

error() {
    printf '[ERROR] %s\n' "$1" >&2
}

check_root() {
    if [ "$RUN_AS_ROOT" != "1" ]; then
        warn "$(t no_root_uninstall)"
    fi
}

ensure_private_directory() {
    local directory="$1"

    if [ -L "$directory" ]; then
        error "$(t unsafe_symlink): $directory"
        return 1
    fi

    mkdir -p "$directory"

    if [ -L "$directory" ] || [ ! -d "$directory" ]; then
        error "$(t private_dir_failed): $directory"
        return 1
    fi

    chown root:root "$directory" 2>/dev/null || true
    chmod 700 "$directory"

    if [ ! -O "$directory" ]; then
        error "$(t unsafe_owner): $directory"
        return 1
    fi
}

init_private_tmp_dir() {
    if ! command -v mktemp >/dev/null 2>&1; then
        error "$(t mktemp_missing)"
        return 1
    fi

    ensure_private_directory "$(dirname "$PRIVATE_TMP_DIR")"
    ensure_private_directory "$PRIVATE_TMP_DIR"
}

make_private_temp_file() {
    local prefix="$1"
    mktemp "$PRIVATE_TMP_DIR/${prefix}.XXXXXX"
}

validate_uuid() {
    local uuid="$1"
    if [[ ! "$uuid" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
        error "'$uuid' $(t invalid_uuid)"
        exit 1
    fi
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

load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        # shellcheck source=/dev/null
        . "$CONFIG_FILE"
        AGENT_TOKEN="${AGENT_TOKEN:-}"
        UUID_VAL="${UUID_VAL:-${UUID:-}}"
        AGENT_LOCALE="${AGENT_LOCALE:-}"
    fi
    AGENT_LOCALE=$(normalize_locale "$AGENT_LOCALE")
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --token) AGENT_TOKEN="${2:-}"; shift 2 ;;
            --uuid) UUID_VAL="${2:-}"; shift 2 ;;
            *) error "$(t unknown_argument): $1"; exit 1 ;;
        esac
    done

    if [ -z "$AGENT_TOKEN" ] || [ -z "$UUID_VAL" ]; then
        error "$(t missing_token_uuid)"
        echo "$(t manual_usage)"
        exit 1
    fi

    validate_uuid "$UUID_VAL"
}

confirm_uninstall() {
    echo ""
    echo "============================================================"
    echo "$(t title)"
    echo "============================================================"
    echo ""
    echo "$(t local_only)"
    echo "$(t rsm_not_deleted)"
    echo ""
    echo "$(t inactive_1)"
    echo "$(t inactive_2)"
    echo "$(t inactive_3)"
    echo ""
    echo "$(t system_uuid): $UUID_VAL"
    echo ""
    read -rn 1 -p "$(t confirm)" reply
    echo
    case "$reply" in
        s|S|si|SI|sí|Sí|y|Y|yes|YES|o|O|oui|OUI|j|J|ja|JA|b|B|bai|BAI|是|は|ハ) ;;
        *)
            warn "$(t cancelled)"
            exit 0
            ;;
    esac
}

find_system_id_by_uuid() {
    local payload response_file http_code exit_code response_body system_id
    response_file=$(make_private_temp_file "rsm_uninstall_uuid_lookup") || return 1
    payload="{\"propertyIDs\":[\"$RSM_SYSTEM_UUID_PROPERTY_ID\"],\"translateIDs\":true,\"filterRules\":[{\"propertyID\":\"$RSM_SYSTEM_UUID_PROPERTY_ID\",\"value\":\"$UUID_VAL\",\"operation\":\"=\"}]}"

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
        error "$(t query_failed) (curl exit: $exit_code)"
        return 1
    fi

    if [ "$http_code" != "200" ] && [ "$http_code" != "201" ]; then
        error "$(t query_denied) (HTTP $http_code)"
        echo "$(t response): $response_body"
        return 1
    fi

    if ! printf '%s' "$response_body" | grep -Fq "$UUID_VAL"; then
        printf ''
        return 0
    fi

    system_id=$(json_extract_first_scalar_key "$response_body" "ID")
    [ -z "$system_id" ] && system_id=$(json_extract_first_scalar_key "$response_body" "id")
    printf '%s' "$system_id"
}

mark_system_disconnected_in_rsm() {
    local system_id payload response_file http_code exit_code response_body

    info "$(t marking_inactive)"
    system_id=$(find_system_id_by_uuid) || return 1

    if [ -z "$system_id" ]; then
        info "$(t no_system)"
        return 0
    fi

    response_file=$(make_private_temp_file "rsm_uninstall_status_update") || return 1
    payload="[{\"ID\":\"$system_id\",\"$RSM_SYSTEM_HOSTNAME_STATUS_PROPERTY_ID\":\"$RSM_SYSTEM_HOSTNAME_STATUS_DISCONNECTED_VALUE\"}]"

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
    response_body=$(cat "$response_file" 2>/dev/null || true)
    rm -f "$response_file"

    if [ "$exit_code" -ne 0 ]; then
        error "$(t mark_failed) (curl exit: $exit_code)"
        return 1
    fi

    if [ "$http_code" != "200" ] && [ "$http_code" != "201" ]; then
        error "$(t mark_denied) (HTTP $http_code)"
        echo "$(t response): $response_body"
        return 1
    fi

    log "$(t marked)"
    return 0
}

remove_automatic_execution() {
    info "$(t removing_schedule)"

    if [ "$RUN_AS_ROOT" = "1" ] && command -v systemctl &>/dev/null; then
        systemctl disable --now rs-agent.timer >/dev/null 2>&1 || true
        systemctl stop rs-agent.service >/dev/null 2>&1 || true
    fi
    if [ "$RUN_AS_ROOT" = "1" ]; then
        rm -f /etc/systemd/system/rs-agent.timer /etc/systemd/system/rs-agent.service
    fi
    if [ "$RUN_AS_ROOT" = "1" ] && command -v systemctl &>/dev/null; then
        systemctl daemon-reload >/dev/null 2>&1 || true
    fi
    if [ "$RUN_AS_ROOT" != "1" ] && command -v systemctl &>/dev/null; then
        systemctl --user disable --now rs-agent.timer >/dev/null 2>&1 || true
        rm -f "$SYSTEMD_USER_SERVICE_FILE" "$SYSTEMD_USER_TIMER_FILE"
        systemctl --user daemon-reload >/dev/null 2>&1 || true
    fi

    if command -v crontab &>/dev/null; then
        if ({ crontab -l 2>/dev/null || true; } | grep -Fv "$INSTALL_DIR/rs_agent" || true) | crontab -; then
            log "$(t cron_removed)"
        else
            warn "$(t cron_update_failed)"
        fi
    fi

    log "$(t schedule_removed)"
}

remove_local_files() {
    info "$(t removing_files)"

    rm -rf "$DATA_DIR"
    rm -rf "$INSTALL_DIR"
    rm -f "$LOG_FILE"

    log "$(t files_removed)"
}

main() {
    load_config
    check_root
    parse_args "$@"
    if ! init_private_tmp_dir; then
        exit 1
    fi
    confirm_uninstall

    if ! mark_system_disconnected_in_rsm; then
        error "$(t stopped_rsm)"
        exit 1
    fi

    remove_automatic_execution
    remove_local_files

    echo ""
    echo "============================================================"
    echo "$(t success)"
    echo "============================================================"
    echo ""
}

main "$@"
