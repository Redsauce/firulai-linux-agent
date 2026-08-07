#!/bin/bash
# -*- coding: utf-8 -*-
# Runs RSAgent only when the daily 03:00 execution is pending.

set -uo pipefail

RUN_AS_ROOT=0
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    RUN_AS_ROOT=1
fi

if [ "$RUN_AS_ROOT" = "1" ]; then
    INSTALL_DIR="${RS_AGENT_INSTALL_DIR:-/opt/rs-agent}"
    DATA_DIR="${RS_AGENT_DATA_DIR:-/var/lib/rs-agent}"
    LOG_FILE="${RS_AGENT_LOG_FILE:-/var/log/rs-agent.log}"
else
    INSTALL_DIR="${RS_AGENT_INSTALL_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/rs-agent}"
    DATA_DIR="${RS_AGENT_DATA_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/rs-agent}"
    LOG_FILE="${RS_AGENT_LOG_FILE:-$DATA_DIR/rs-agent.log}"
fi

CONFIG_FILE="$DATA_DIR/config.env"
STATE_FILE="$DATA_DIR/state.env"
AGENT_SCRIPT="$INSTALL_DIR/rs_agent.sh"
TRIGGER="automatic"
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
        es_ES:trigger_requires_value) printf '%s' "ERROR: --trigger requiere un valor" ;;
        es_ES:unknown_argument) printf '%s' "ERROR: Argumento desconocido" ;;
        es_ES:incomplete_installation) printf '%s' "Instalacion incompleta: falta el archivo de configuracion o el script del agente." ;;
        es_ES:invalid_config) printf '%s' "config.env no contiene valores validos de token y UUID." ;;
        es_ES:date_failed) printf '%s' "No se pudo calcular la ejecucion diaria de las 03:00 con date." ;;
        es_ES:pending_detected) printf '%s' "Ejecucion pendiente detectada." ;;
        es_ES:pending_failed) printf '%s' "La ejecucion pendiente fallo." ;;
        es_ES:pending_completed) printf '%s' "Ejecucion pendiente completada." ;;
        ca_ES:trigger_requires_value) printf '%s' "ERROR: --trigger requereix un valor" ;;
        ca_ES:unknown_argument) printf '%s' "ERROR: Argument desconegut" ;;
        ca_ES:incomplete_installation) printf '%s' "Instal.lacio incompleta: falta el fitxer de configuracio o el script de l'agent." ;;
        ca_ES:invalid_config) printf '%s' "config.env no conte valors valids de token i UUID." ;;
        ca_ES:date_failed) printf '%s' "No s'ha pogut calcular l'execucio diaria de les 03:00 amb date." ;;
        ca_ES:pending_detected) printf '%s' "Execucio pendent detectada." ;;
        ca_ES:pending_failed) printf '%s' "L'execucio pendent ha fallat." ;;
        ca_ES:pending_completed) printf '%s' "Execucio pendent completada." ;;
        eu_ES:date_failed) printf '%s' "Ezin izan da eguneko 03:00etako exekuzioa kalkulatu datarekin." ;;
        eu_ES:incomplete_installation) printf '%s' "Instalazioa osatu gabe: konfigurazio fitxategia edo agente scripta falta da." ;;
        eu_ES:invalid_config) printf '%s' "config.env-ek ez ditu baliozko token eta UUID baliorik." ;;
        eu_ES:pending_completed) printf '%s' "Burutzapenaren zain amaitu da." ;;
        eu_ES:pending_detected) printf '%s' "Exekuzioaren zain detektatu da." ;;
        eu_ES:pending_failed) printf '%s' "Ezin izan da exekutatzeko zain." ;;
        eu_ES:trigger_requires_value) printf '%s' "ERROREA: --trigger balio bat behar du" ;;
        eu_ES:unknown_argument) printf '%s' "ERROREA: argumentu ezezaguna" ;;
        gl_ES:date_failed) printf '%s' "Non se puido calcular a execución diaria das 03:00 coa data." ;;
        gl_ES:incomplete_installation) printf '%s' "Instalación incompleta: falta o ficheiro de configuración ou o script do axente." ;;
        gl_ES:invalid_config) printf '%s' "config.env non contén valores de token e UUID válidos." ;;
        gl_ES:pending_completed) printf '%s' "Pendente de execución rematada." ;;
        gl_ES:pending_detected) printf '%s' "Detectouse a execución pendente." ;;
        gl_ES:pending_failed) printf '%s' "Fallou a execución pendente." ;;
        gl_ES:trigger_requires_value) printf '%s' "ERRO: --trigger require un valor" ;;
        gl_ES:unknown_argument) printf '%s' "ERRO: argumento descoñecido" ;;
        fr_FR:date_failed) printf '%s' "Impossible de calculer l'exécution quotidienne à 03h00 avec la date." ;;
        fr_FR:incomplete_installation) printf '%s' "Installation incomplète : fichier de configuration ou script d'agent manquant." ;;
        fr_FR:invalid_config) printf '%s' "config.env ne contient pas de valeurs de jeton et d'UUID valides." ;;
        fr_FR:pending_completed) printf '%s' "En attente d'exécution terminée." ;;
        fr_FR:pending_detected) printf '%s' "En attente d'exécution détectée." ;;
        fr_FR:pending_failed) printf '%s' "L'exécution en attente a échoué." ;;
        fr_FR:trigger_requires_value) printf '%s' "ERREUR : --trigger nécessite une valeur" ;;
        fr_FR:unknown_argument) printf '%s' "ERREUR : argument inconnu" ;;
        de_DE:date_failed) printf '%s' "Die tägliche Ausführung um 03:00 Uhr konnte nicht mit Datum berechnet werden." ;;
        de_DE:incomplete_installation) printf '%s' "Unvollständige Installation: Konfigurationsdatei oder Agent-Skript fehlen." ;;
        de_DE:invalid_config) printf '%s' "config.env enthält keine gültigen Token- und UUID-Werte." ;;
        de_DE:pending_completed) printf '%s' "Ausstehende Ausführung abgeschlossen." ;;
        de_DE:pending_detected) printf '%s' "Ausstehende Ausführung erkannt." ;;
        de_DE:pending_failed) printf '%s' "Die ausstehende Ausführung ist fehlgeschlagen." ;;
        de_DE:trigger_requires_value) printf '%s' "FEHLER: --trigger erfordert einen Wert" ;;
        de_DE:unknown_argument) printf '%s' "FEHLER: Unbekanntes Argument" ;;
        it_IT:date_failed) printf '%s' "Impossibile calcolare l'esecuzione giornaliera alle 03:00 con la data." ;;
        it_IT:incomplete_installation) printf '%s' "Installazione incompleta: file di configurazione o script dell'agente mancante." ;;
        it_IT:invalid_config) printf '%s' "config.env non contiene valori token e UUID validi." ;;
        it_IT:pending_completed) printf '%s' "Esecuzione in attesa completata." ;;
        it_IT:pending_detected) printf '%s' "Rilevata esecuzione in sospeso." ;;
        it_IT:pending_failed) printf '%s' "L'esecuzione in sospeso non è riuscita." ;;
        it_IT:trigger_requires_value) printf '%s' "ERRORE: --trigger richiede un valore" ;;
        it_IT:unknown_argument) printf '%s' "ERRORE: argomento sconosciuto" ;;
        ja_JP:date_failed) printf '%s' "毎日の 03:00 の実行を日付付きで計算できませんでした。" ;;
        ja_JP:incomplete_installation) printf '%s' "インストールが不完全: 構成ファイルまたはエージェント スクリプトが欠落しています。" ;;
        ja_JP:invalid_config) printf '%s' "config.env には、有効なトークンと UUID の値が含まれていません。" ;;
        ja_JP:pending_completed) printf '%s' "保留中の実行が完了しました。" ;;
        ja_JP:pending_detected) printf '%s' "保留中の実行が検出されました。" ;;
        ja_JP:pending_failed) printf '%s' "保留中の実行が失敗しました。" ;;
        ja_JP:trigger_requires_value) printf '%s' "エラー: --trigger には値が必要です" ;;
        ja_JP:unknown_argument) printf '%s' "エラー: 不明な引数" ;;
        zh_CN:date_failed) printf '%s' "无法计算每日 03:00 执行日期。" ;;
        zh_CN:incomplete_installation) printf '%s' "安装不完整：缺少配置文件或代理脚本。" ;;
        zh_CN:invalid_config) printf '%s' "config.env 不包含有效的令牌和 UUID 值。" ;;
        zh_CN:pending_completed) printf '%s' "待执行已完成。" ;;
        zh_CN:pending_detected) printf '%s' "检测到待执行。" ;;
        zh_CN:pending_failed) printf '%s' "等待执行失败。" ;;
        zh_CN:trigger_requires_value) printf '%s' "错误：--trigger 需要一个值" ;;
        zh_CN:unknown_argument) printf '%s' "错误：未知参数" ;;
        *:trigger_requires_value) printf '%s' "ERROR: --trigger requires a value" ;;
        *:unknown_argument) printf '%s' "ERROR: Unknown argument" ;;
        *:incomplete_installation) printf '%s' "Incomplete installation: missing config file or agent script." ;;
        *:invalid_config) printf '%s' "config.env does not contain valid token and UUID values." ;;
        *:date_failed) printf '%s' "Could not calculate the daily 03:00 execution with date." ;;
        *:pending_detected) printf '%s' "Pending execution detected." ;;
        *:pending_failed) printf '%s' "Pending execution failed." ;;
        *:pending_completed) printf '%s' "Pending execution completed." ;;
        *) printf '%s' "$key" ;;
    esac
}

while [ $# -gt 0 ]; do
    case "$1" in
        --if-due) shift ;;
        --trigger)
            [ $# -ge 2 ] || { echo "$(t trigger_requires_value)" >&2; exit 2; }
            TRIGGER="$2"
            shift 2
            ;;
        *) echo "$(t unknown_argument): $1" >&2; exit 2 ;;
    esac
done

log_line() {
    printf '%s [INFO] %s\n' "$(date '+%Y-%m-%d %H:%M:%S %z')" "$1" | tee -a "$LOG_FILE"
}

error_line() {
    printf '%s [ERROR] %s\n' "$(date '+%Y-%m-%d %H:%M:%S %z')" "$1" | tee -a "$LOG_FILE" >&2
}

mkdir -p "$(dirname "$LOG_FILE")"

if [ ! -r "$CONFIG_FILE" ] || [ ! -x "$AGENT_SCRIPT" ]; then
    error_line "$(t incomplete_installation) ($CONFIG_FILE / $AGENT_SCRIPT)"
    exit 1
fi

# shellcheck source=/dev/null
. "$CONFIG_FILE"
AGENT_TOKEN="${AGENT_TOKEN:-}"
UUID="${UUID:-}"
AGENT_LOCALE=$(normalize_locale "${AGENT_LOCALE:-}")
if [ -z "$AGENT_TOKEN" ] || [ -z "$UUID" ]; then
    error_line "$(t invalid_config)"
    exit 1
fi

now_epoch=$(date +%s)
scheduled_epoch=$(date -d "$(date +%F) 03:00:00" +%s 2>/dev/null) || {
    error_line "$(t date_failed)"
    exit 1
}

last_success_epoch=0
if [ -r "$STATE_FILE" ]; then
    last_success_epoch=$(sed -n 's/^LAST_SUCCESS_EPOCH=\([0-9][0-9]*\)$/\1/p' "$STATE_FILE" | head -1)
    last_success_epoch="${last_success_epoch:-0}"
fi

# Before 03:00, or after a successful execution today, there is no work to do.
if [ "$now_epoch" -lt "$scheduled_epoch" ] || [ "$last_success_epoch" -ge "$scheduled_epoch" ]; then
    exit 0
fi

delay_seconds=$((now_epoch - scheduled_epoch))
log_line "$(t pending_detected) Trigger=$TRIGGER, scheduled=$(date -d "@$scheduled_epoch" '+%Y-%m-%d %H:%M:%S %z'), delaySeconds=$delay_seconds."

set +e
RS_AGENT_TRIGGER="$TRIGGER" /bin/bash "$AGENT_SCRIPT" \
    --token "$AGENT_TOKEN" \
    --uuid "$UUID" \
    --locale "$AGENT_LOCALE" 2>&1 | tee -a "$LOG_FILE"
agent_status=${PIPESTATUS[0]}
set -e

if [ "$agent_status" -ne 0 ]; then
    error_line "$(t pending_failed) Trigger=$TRIGGER, code=$agent_status."
    exit "$agent_status"
fi

log_line "$(t pending_completed) Trigger=$TRIGGER."
exit 0
