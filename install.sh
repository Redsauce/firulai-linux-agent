#!/bin/bash
# ============================================================================
# Firulai Inventory Agent - One-liner installer
# Version 0.2.4 - Missed execution recovery with systemd/cron
# ============================================================================
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Redsauce/firulai-linux-agent/main/install.sh | bash -s -- <AGENT_TOKEN> <UUID> --alias <ALIAS>
#

set -e

# ============================================================================
# PARAMETERS
# ============================================================================

AGENT_TOKEN=${1:-""}
UUID=${2:-""}
SYSTEM_ALIAS=""
SCHEDULER_CHOICE="${RS_AGENT_SCHEDULER:-}"
AGENT_LOCALE="${RS_AGENT_LOCALE:-}"

early_locale_prefix() {
    local value
    value=$(printf '%s' "${AGENT_LOCALE:-}" | tr '[:upper:]-' '[:lower:]_')
    case "$value" in
        es*) printf '%s' "es" ;;
        ca*) printf '%s' "ca" ;;
        eu*) printf '%s' "eu" ;;
        gl*) printf '%s' "gl" ;;
        fr*) printf '%s' "fr" ;;
        de*) printf '%s' "de" ;;
        it*) printf '%s' "it" ;;
        ja*) printf '%s' "ja" ;;
        zh*) printf '%s' "zh" ;;
        *) printf '%s' "en" ;;
    esac
}

early_t() {
    local key="$1"
    case "$(early_locale_prefix):$key" in
        es:usage) printf '%s' "Uso: curl ... | bash -s -- <AGENT_TOKEN> <UUID> --alias <ALIAS>" ;;
        ca:usage) printf '%s' "Us: curl ... | bash -s -- <AGENT_TOKEN> <UUID> --alias <ALIAS>" ;;
        eu:usage) printf '%s' "Erabilera: curl ... | bash -s -- <AGENT_TOKEN> <UUID> --alias <ALIAS>" ;;
        gl:usage) printf '%s' "Uso: curl ... | bash -s -- <AGENT_TOKEN> <UUID> --alias <ALIAS>" ;;
        fr:usage) printf '%s' "Utilisation : curl ... | bash -s -- <AGENT_TOKEN> <UUID> --alias <ALIAS>" ;;
        de:usage) printf '%s' "Verwendung: curl ... | bash -s -- <AGENT_TOKEN> <UUID> --alias <ALIAS>" ;;
        it:usage) printf '%s' "Uso: curl ... | bash -s -- <AGENT_TOKEN> <UUID> --alias <ALIAS>" ;;
        ja:usage) printf '%s' "使用方法: curl ... | bash -s -- <AGENT_TOKEN> <UUID> --alias <ALIAS>" ;;
        zh:usage) printf '%s' "用法: curl ... | bash -s -- <AGENT_TOKEN> <UUID> --alias <ALIAS>" ;;
        es:usage_locale) printf '%s' "Uso: curl ... | bash -s -- <AGENT_TOKEN> <UUID> --alias <ALIAS> [--locale <IDIOMA>]" ;;
        ca:usage_locale) printf '%s' "Us: curl ... | bash -s -- <AGENT_TOKEN> <UUID> --alias <ALIAS> [--locale <IDIOMA>]" ;;
        eu:usage_locale) printf '%s' "Erabilera: curl ... | bash -s -- <AGENT_TOKEN> <UUID> --alias <ALIAS> [--locale <HIZKUNTZA>]" ;;
        gl:usage_locale) printf '%s' "Uso: curl ... | bash -s -- <AGENT_TOKEN> <UUID> --alias <ALIAS> [--locale <IDIOMA>]" ;;
        fr:usage_locale) printf '%s' "Utilisation : curl ... | bash -s -- <AGENT_TOKEN> <UUID> --alias <ALIAS> [--locale <LANGUE>]" ;;
        de:usage_locale) printf '%s' "Verwendung: curl ... | bash -s -- <AGENT_TOKEN> <UUID> --alias <ALIAS> [--locale <SPRACHE>]" ;;
        it:usage_locale) printf '%s' "Uso: curl ... | bash -s -- <AGENT_TOKEN> <UUID> --alias <ALIAS> [--locale <LINGUA>]" ;;
        ja:usage_locale) printf '%s' "使用方法: curl ... | bash -s -- <AGENT_TOKEN> <UUID> --alias <ALIAS> [--locale <言語>]" ;;
        zh:usage_locale) printf '%s' "用法: curl ... | bash -s -- <AGENT_TOKEN> <UUID> --alias <ALIAS> [--locale <语言>]" ;;
        es:alias_requires_value) printf '%s' "--alias requiere un valor" ;;
        ca:alias_requires_value) printf '%s' "--alias requereix un valor" ;;
        eu:alias_requires_value) printf '%s' "--alias aukerak balio bat behar du" ;;
        gl:alias_requires_value) printf '%s' "--alias require un valor" ;;
        fr:alias_requires_value) printf '%s' "--alias necessite une valeur" ;;
        de:alias_requires_value) printf '%s' "--alias erfordert einen Wert" ;;
        it:alias_requires_value) printf '%s' "--alias richiede un valore" ;;
        ja:alias_requires_value) printf '%s' "--alias には値が必要です" ;;
        zh:alias_requires_value) printf '%s' "--alias 需要一个值" ;;
        es:locale_requires_value) printf '%s' "--locale requiere un valor" ;;
        ca:locale_requires_value) printf '%s' "--locale requereix un valor" ;;
        eu:locale_requires_value) printf '%s' "--locale aukerak balio bat behar du" ;;
        gl:locale_requires_value) printf '%s' "--locale require un valor" ;;
        fr:locale_requires_value) printf '%s' "--locale necessite une valeur" ;;
        de:locale_requires_value) printf '%s' "--locale erfordert einen Wert" ;;
        it:locale_requires_value) printf '%s' "--locale richiede un valore" ;;
        ja:locale_requires_value) printf '%s' "--locale には値が必要です" ;;
        zh:locale_requires_value) printf '%s' "--locale 需要一个值" ;;
        es:unknown_argument) printf '%s' "Argumento desconocido" ;;
        ca:unknown_argument) printf '%s' "Argument desconegut" ;;
        eu:unknown_argument) printf '%s' "Argumentu ezezaguna" ;;
        gl:unknown_argument) printf '%s' "Argumento descoñecido" ;;
        fr:unknown_argument) printf '%s' "Argument inconnu" ;;
        de:unknown_argument) printf '%s' "Unbekanntes Argument" ;;
        it:unknown_argument) printf '%s' "Argomento sconosciuto" ;;
        ja:unknown_argument) printf '%s' "不明な引数" ;;
        zh:unknown_argument) printf '%s' "未知参数" ;;
        es:scheduler_env_invalid) printf '%s' "RS_AGENT_SCHEDULER debe ser: cron o systemd-user" ;;
        ca:scheduler_env_invalid) printf '%s' "RS_AGENT_SCHEDULER ha de ser: cron o systemd-user" ;;
        eu:scheduler_env_invalid) printf '%s' "RS_AGENT_SCHEDULER balioa cron edo systemd-user izan behar da" ;;
        gl:scheduler_env_invalid) printf '%s' "RS_AGENT_SCHEDULER debe ser: cron ou systemd-user" ;;
        fr:scheduler_env_invalid) printf '%s' "RS_AGENT_SCHEDULER doit etre : cron ou systemd-user" ;;
        de:scheduler_env_invalid) printf '%s' "RS_AGENT_SCHEDULER muss cron oder systemd-user sein" ;;
        it:scheduler_env_invalid) printf '%s' "RS_AGENT_SCHEDULER deve essere: cron o systemd-user" ;;
        ja:scheduler_env_invalid) printf '%s' "RS_AGENT_SCHEDULER は cron または systemd-user である必要があります" ;;
        zh:scheduler_env_invalid) printf '%s' "RS_AGENT_SCHEDULER 必须是 cron 或 systemd-user" ;;
        es:no_interactive_cron_default) printf '%s' "No se ha detectado terminal interactivo; se usara cron de usuario por defecto." ;;
        ca:no_interactive_cron_default) printf '%s' "No s'ha detectat cap terminal interactiu; s'usara cron d'usuari per defecte." ;;
        eu:no_interactive_cron_default) printf '%s' "Ez da terminal interaktiborik detektatu; erabiltzailearen cron erabiliko da lehenespenez." ;;
        gl:no_interactive_cron_default) printf '%s' "Non se detectou terminal interactivo; usarase cron de usuario por defecto." ;;
        fr:no_interactive_cron_default) printf '%s' "Aucun terminal interactif detecte ; cron utilisateur sera utilise par defaut." ;;
        de:no_interactive_cron_default) printf '%s' "Kein interaktives Terminal erkannt; Benutzer-Cron wird standardmaessig verwendet." ;;
        it:no_interactive_cron_default) printf '%s' "Nessun terminale interattivo rilevato; verra usato cron utente per impostazione predefinita." ;;
        ja:no_interactive_cron_default) printf '%s' "対話型端末が検出されません。既定でユーザー cron を使用します。" ;;
        zh:no_interactive_cron_default) printf '%s' "未检测到交互式终端；默认使用用户 cron。" ;;
        es:automatic_execution_setup) printf '%s' "Configuracion de ejecucion automatica:" ;;
        ca:automatic_execution_setup) printf '%s' "Configuracio d'execucio automatica:" ;;
        eu:automatic_execution_setup) printf '%s' "Exekuzio automatikoaren konfigurazioa:" ;;
        gl:automatic_execution_setup) printf '%s' "Configuracion de execucion automatica:" ;;
        fr:automatic_execution_setup) printf '%s' "Configuration de l'execution automatique :" ;;
        de:automatic_execution_setup) printf '%s' "Konfiguration der automatischen Ausfuehrung:" ;;
        it:automatic_execution_setup) printf '%s' "Configurazione dell'esecuzione automatica:" ;;
        ja:automatic_execution_setup) printf '%s' "自動実行の設定:" ;;
        zh:automatic_execution_setup) printf '%s' "自动执行设置:" ;;
        es:scheduler_cron_title) printf '%s' "1) Cron de usuario" ;;
        ca:scheduler_cron_title) printf '%s' "1) Cron d'usuari" ;;
        eu:scheduler_cron_title) printf '%s' "1) Erabiltzailearen cron" ;;
        gl:scheduler_cron_title) printf '%s' "1) Cron de usuario" ;;
        fr:scheduler_cron_title) printf '%s' "1) Cron utilisateur" ;;
        de:scheduler_cron_title) printf '%s' "1) Benutzer-Cron" ;;
        it:scheduler_cron_title) printf '%s' "1) Cron utente" ;;
        ja:scheduler_cron_title) printf '%s' "1) ユーザー cron" ;;
        zh:scheduler_cron_title) printf '%s' "1) 用户 cron" ;;
        es:scheduler_cron_plus) printf '%s' "+ No requiere root para ejecutar el agente y no depende de una sesion de usuario activa." ;;
        ca:scheduler_cron_plus) printf '%s' "+ No requereix root per executar l'agent i no depen d'una sessio d'usuari activa." ;;
        eu:scheduler_cron_plus) printf '%s' "+ Ez du root behar agentea exekutatzeko eta ez dago erabiltzaile-saio aktibo baten mende." ;;
        gl:scheduler_cron_plus) printf '%s' "+ Non require root para executar o axente e non depende dunha sesion de usuario activa." ;;
        fr:scheduler_cron_plus) printf '%s' "+ Ne requiert pas root pour executer l'agent et ne depend pas d'une session utilisateur active." ;;
        de:scheduler_cron_plus) printf '%s' "+ Benoetigt fuer die Agent-Ausfuehrung kein root und keine aktive Benutzersitzung." ;;
        it:scheduler_cron_plus) printf '%s' "+ Non richiede root per eseguire l'agente e non dipende da una sessione utente attiva." ;;
        ja:scheduler_cron_plus) printf '%s' "+ エージェント実行に root は不要で、アクティブなユーザー セッションに依存しません。" ;;
        zh:scheduler_cron_plus) printf '%s' "+ 执行代理不需要 root，也不依赖活动用户会话。" ;;
        es:scheduler_cron_minus) printf '%s' "- Requiere cron/crontab instalado, activo y permitido." ;;
        ca:scheduler_cron_minus) printf '%s' "- Requereix cron/crontab instal.lat, actiu i permes." ;;
        eu:scheduler_cron_minus) printf '%s' "- cron/crontab instalatuta, aktibo eta baimenduta egotea eskatzen du." ;;
        gl:scheduler_cron_minus) printf '%s' "- Require cron/crontab instalado, activo e permitido." ;;
        fr:scheduler_cron_minus) printf '%s' "- Requiert cron/crontab installe, actif et autorise." ;;
        de:scheduler_cron_minus) printf '%s' "- Erfordert installiertes, aktives und erlaubtes cron/crontab." ;;
        it:scheduler_cron_minus) printf '%s' "- Richiede cron/crontab installato, attivo e consentito." ;;
        ja:scheduler_cron_minus) printf '%s' "- cron/crontab がインストール済み、有効、許可済みである必要があります。" ;;
        zh:scheduler_cron_minus) printf '%s' "- 需要已安装、已启用且允许使用的 cron/crontab。" ;;
        es:scheduler_systemd_title) printf '%s' "2) systemd --user" ;;
        ca:scheduler_systemd_title) printf '%s' "2) systemd --user" ;;
        eu:scheduler_systemd_title) printf '%s' "2) systemd --user" ;;
        gl:scheduler_systemd_title) printf '%s' "2) systemd --user" ;;
        fr:scheduler_systemd_title) printf '%s' "2) systemd --user" ;;
        de:scheduler_systemd_title) printf '%s' "2) systemd --user" ;;
        it:scheduler_systemd_title) printf '%s' "2) systemd --user" ;;
        ja:scheduler_systemd_title) printf '%s' "2) systemd --user" ;;
        zh:scheduler_systemd_title) printf '%s' "2) systemd --user" ;;
        es:scheduler_systemd_plus) printf '%s' "+ Mejor integracion con systemd y systemctl --user." ;;
        ca:scheduler_systemd_plus) printf '%s' "+ Millor integracio amb systemd i systemctl --user." ;;
        eu:scheduler_systemd_plus) printf '%s' "+ Integrazio hobea systemd eta systemctl --user-ekin." ;;
        gl:scheduler_systemd_plus) printf '%s' "+ Mellor integracion con systemd e systemctl --user." ;;
        fr:scheduler_systemd_plus) printf '%s' "+ Meilleure integration avec systemd et systemctl --user." ;;
        de:scheduler_systemd_plus) printf '%s' "+ Bessere Integration mit systemd und systemctl --user." ;;
        it:scheduler_systemd_plus) printf '%s' "+ Migliore integrazione con systemd e systemctl --user." ;;
        ja:scheduler_systemd_plus) printf '%s' "+ systemd および systemctl --user とより良く統合されます。" ;;
        zh:scheduler_systemd_plus) printf '%s' "+ 与 systemd 和 systemctl --user 更好集成。" ;;
        es:scheduler_systemd_minus) printf '%s' "- Requiere linger para ejecutarse sin una sesion activa; se habilitara como root si hace falta." ;;
        ca:scheduler_systemd_minus) printf '%s' "- Requereix linger per executar-se sense una sessio activa; s'habilitara com a root si cal." ;;
        eu:scheduler_systemd_minus) printf '%s' "- Saio aktiborik gabe exekutatzeko linger behar du; behar bada root gisa gaituko da." ;;
        gl:scheduler_systemd_minus) printf '%s' "- Require linger para executarse sen unha sesion activa; habilitarase como root se fai falta." ;;
        fr:scheduler_systemd_minus) printf '%s' "- Requiert linger pour fonctionner sans session active ; il sera active en root si necessaire." ;;
        de:scheduler_systemd_minus) printf '%s' "- Erfordert linger fuer Ausfuehrung ohne aktive Sitzung; wird bei Bedarf als root aktiviert." ;;
        it:scheduler_systemd_minus) printf '%s' "- Richiede linger per funzionare senza sessione attiva; verra abilitato come root se necessario." ;;
        ja:scheduler_systemd_minus) printf '%s' "- アクティブなセッションなしで実行するには linger が必要です。必要なら root で有効化します。" ;;
        zh:scheduler_systemd_minus) printf '%s' "- 无活动会话运行需要 linger；必要时会以 root 启用。" ;;
        es:scheduler_prompt) printf '%s' "Elige programador [1=cron, 2=systemd-user] (1): " ;;
        ca:scheduler_prompt) printf '%s' "Tria programador [1=cron, 2=systemd-user] (1): " ;;
        eu:scheduler_prompt) printf '%s' "Aukeratu programatzailea [1=cron, 2=systemd-user] (1): " ;;
        gl:scheduler_prompt) printf '%s' "Escolle programador [1=cron, 2=systemd-user] (1): " ;;
        fr:scheduler_prompt) printf '%s' "Choisissez le planificateur [1=cron, 2=systemd-user] (1) : " ;;
        de:scheduler_prompt) printf '%s' "Scheduler waehlen [1=cron, 2=systemd-user] (1): " ;;
        it:scheduler_prompt) printf '%s' "Scegli scheduler [1=cron, 2=systemd-user] (1): " ;;
        ja:scheduler_prompt) printf '%s' "スケジューラーを選択 [1=cron, 2=systemd-user] (1): " ;;
        zh:scheduler_prompt) printf '%s' "选择调度器 [1=cron, 2=systemd-user] (1): " ;;
        es:unknown_scheduler) printf '%s' "Programador desconocido" ;;
        ca:unknown_scheduler) printf '%s' "Programador desconegut" ;;
        eu:unknown_scheduler) printf '%s' "Programatzaile ezezaguna" ;;
        gl:unknown_scheduler) printf '%s' "Programador descoñecido" ;;
        fr:unknown_scheduler) printf '%s' "Planificateur inconnu" ;;
        de:unknown_scheduler) printf '%s' "Unbekannter Scheduler" ;;
        it:unknown_scheduler) printf '%s' "Scheduler sconosciuto" ;;
        ja:unknown_scheduler) printf '%s' "不明なスケジューラー" ;;
        zh:unknown_scheduler) printf '%s' "未知调度器" ;;
        es:scheduler_usage) printf '%s' "Usa 1/cron o 2/systemd-user." ;;
        ca:scheduler_usage) printf '%s' "Usa 1/cron o 2/systemd-user." ;;
        eu:scheduler_usage) printf '%s' "Erabili 1/cron edo 2/systemd-user." ;;
        gl:scheduler_usage) printf '%s' "Usa 1/cron ou 2/systemd-user." ;;
        fr:scheduler_usage) printf '%s' "Utilisez 1/cron ou 2/systemd-user." ;;
        de:scheduler_usage) printf '%s' "Verwenden Sie 1/cron oder 2/systemd-user." ;;
        it:scheduler_usage) printf '%s' "Usa 1/cron o 2/systemd-user." ;;
        ja:scheduler_usage) printf '%s' "1/cron または 2/systemd-user を使用してください。" ;;
        zh:scheduler_usage) printf '%s' "请使用 1/cron 或 2/systemd-user。" ;;
        es:cron_enable_unknown) printf '%s' "No se pudo determinar cómo habilitar cron automáticamente en esta distribución." ;;
        ca:cron_enable_unknown) printf '%s' "No s'ha pogut determinar com habilitar cron automàticament en aquesta distribució." ;;
        eu:cron_enable_unknown) printf '%s' "Ezin izan da zehaztu nola gaitu automatikoki cron banaketa honetan." ;;
        gl:cron_enable_unknown) printf '%s' "Non se puido determinar como activar cron automaticamente nesta distribución." ;;
        fr:cron_enable_unknown) printf '%s' "Impossible de déterminer comment activer automatiquement cron sur cette distribution." ;;
        de:cron_enable_unknown) printf '%s' "Es konnte nicht ermittelt werden, wie Cron auf dieser Distribution automatisch aktiviert werden kann." ;;
        it:cron_enable_unknown) printf '%s' "Impossibile determinare come abilitare automaticamente cron su questa distribuzione." ;;
        ja:cron_enable_unknown) printf '%s' "このディストリビューションで cron を自動的に有効にする方法を特定できませんでした。" ;;
        zh:cron_enable_unknown) printf '%s' "无法确定如何在此发行版上自动启用 cron。" ;;
        es:cron_install_unknown) printf '%s' "No se pudo determinar cómo instalar cron automáticamente en esta distribución." ;;
        ca:cron_install_unknown) printf '%s' "No s'ha pogut determinar com instal·lar cron automàticament en aquesta distribució." ;;
        eu:cron_install_unknown) printf '%s' "Ezin izan da zehaztu nola instalatu automatikoki cron banaketa honetan." ;;
        gl:cron_install_unknown) printf '%s' "Non se puido determinar como instalar cron automaticamente nesta distribución." ;;
        fr:cron_install_unknown) printf '%s' "Impossible de déterminer comment installer automatiquement cron sur cette distribution." ;;
        de:cron_install_unknown) printf '%s' "Es konnte nicht ermittelt werden, wie cron auf dieser Distribution automatisch installiert wird." ;;
        it:cron_install_unknown) printf '%s' "Impossibile determinare come installare automaticamente cron su questa distribuzione." ;;
        ja:cron_install_unknown) printf '%s' "このディストリビューションに cron を自動的にインストールする方法を決定できませんでした。" ;;
        zh:cron_install_unknown) printf '%s' "无法确定如何在此发行版上自动安装 cron。" ;;
        es:cron_still_inactive) printf '%s' "cron no parece estar activo después de habilitarlo." ;;
        ca:cron_still_inactive) printf '%s' "cron no sembla estar actiu després d'habilitar-lo." ;;
        eu:cron_still_inactive) printf '%s' "cron ez dirudi aktibo dagoenik gaitu ondoren." ;;
        gl:cron_still_inactive) printf '%s' "cron non parece estar activo despois de activalo." ;;
        fr:cron_still_inactive) printf '%s' "cron ne semble pas être actif après l'avoir activé." ;;
        de:cron_still_inactive) printf '%s' "Cron scheint nach der Aktivierung nicht aktiv zu sein." ;;
        it:cron_still_inactive) printf '%s' "cron non sembra essere attivo dopo averlo abilitato." ;;
        ja:cron_still_inactive) printf '%s' "cron を有効にしてもアクティブになっていないように見えます。" ;;
        zh:cron_still_inactive) printf '%s' "启用后 cron 似乎并未处于活动状态。" ;;
        es:crontab_still_missing) printf '%s' "cron/crontab todavía no está disponible después de la instalación." ;;
        ca:crontab_still_missing) printf '%s' "cron/crontab encara no està disponible després de la instal·lació." ;;
        eu:crontab_still_missing) printf '%s' "cron/crontab oraindik ez dago erabilgarri instalatu ondoren." ;;
        gl:crontab_still_missing) printf '%s' "cron/crontab aínda non está dispoñible despois da instalación." ;;
        fr:crontab_still_missing) printf '%s' "cron/crontab n'est toujours pas disponible après l'installation." ;;
        de:crontab_still_missing) printf '%s' "cron/crontab ist nach der Installation immer noch nicht verfügbar." ;;
        it:crontab_still_missing) printf '%s' "cron/crontab non è ancora disponibile dopo l'installazione." ;;
        ja:crontab_still_missing) printf '%s' "cron/crontab はインストール後も使用できません。" ;;
        zh:crontab_still_missing) printf '%s' "安装后 cron/crontab 仍然不可用。" ;;
        es:enabling_cron_root) printf '%s' "Habilitando cron como root..." ;;
        ca:enabling_cron_root) printf '%s' "S'està habilitant cron com a root..." ;;
        eu:enabling_cron_root) printf '%s' "Cron root gisa gaitzen..." ;;
        gl:enabling_cron_root) printf '%s' "Activando cron como root..." ;;
        fr:enabling_cron_root) printf '%s' "Activation de cron en tant que root..." ;;
        de:enabling_cron_root) printf '%s' "Cron als Root aktivieren..." ;;
        it:enabling_cron_root) printf '%s' "Abilitazione di cron come root..." ;;
        ja:enabling_cron_root) printf '%s' "root として cron を有効にしています..." ;;
        zh:enabling_cron_root) printf '%s' "以 root 身份启用 cron..." ;;
        es:enabling_linger_for) printf '%s' "Habilitar la permanencia como raíz para" ;;
        ca:enabling_linger_for) printf '%s' "Habilitant linger com a root per" ;;
        eu:enabling_linger_for) printf '%s' "Linger root gisa gaitzea" ;;
        gl:enabling_linger_for) printf '%s' "Habilitando linger como root para" ;;
        fr:enabling_linger_for) printf '%s' "Activation de Linger en tant que root pour" ;;
        de:enabling_linger_for) printf '%s' "Linger als Root aktivieren für" ;;
        it:enabling_linger_for) printf '%s' "Abilitazione di indugio come root per" ;;
        ja:enabling_linger_for) printf '%s' "root として linger を有効にする" ;;
        zh:enabling_linger_for) printf '%s' "以 root 身份启用 linger" ;;
        es:install_mode_env_invalid) printf '%s' "RS_AGENT_INSTALL_MODE debe ser root o no root" ;;
        ca:install_mode_env_invalid) printf '%s' "RS_AGENT_INSTALL_MODE ha de ser root o no root" ;;
        eu:install_mode_env_invalid) printf '%s' "RS_AGENT_INSTALL_MODE root edo ez-root izan behar du" ;;
        gl:install_mode_env_invalid) printf '%s' "RS_AGENT_INSTALL_MODE debe ser root ou non root" ;;
        fr:install_mode_env_invalid) printf '%s' "RS_AGENT_INSTALL_MODE doit être root ou non-root" ;;
        de:install_mode_env_invalid) printf '%s' "RS_AGENT_INSTALL_MODE muss Root oder No-Root sein" ;;
        it:install_mode_env_invalid) printf '%s' "RS_AGENT_INSTALL_MODE deve essere root o no root" ;;
        ja:install_mode_env_invalid) printf '%s' "RS_AGENT_INSTALL_MODE は root または no-root である必要があります" ;;
        zh:install_mode_env_invalid) printf '%s' "RS_AGENT_INSTALL_MODE 必须是 root 或 no-root" ;;
        es:install_mode_no_root) printf '%s' "2) Instalación de usuario sin root: se instala en la casa de un usuario normal y configura requisitos previos privilegiados antes de cambiar de usuario." ;;
        ca:install_mode_no_root) printf '%s' "2) Instal·lació d'usuari sense root: s'instal·la a la casa d'un usuari normal i configura els requisits previs abans de canviar d'usuari." ;;
        eu:install_mode_no_root) printf '%s' "2) Errorik gabeko erabiltzaileen instalazioa: erabiltzaile arrunt baten etxean instalatzen da eta pribilegiozko aurrebaldintzak konfiguratzen ditu erabiltzailea aldatu aurretik." ;;
        gl:install_mode_no_root) printf '%s' "2) Instalación sen root: instálase na casa dun usuario normal e configura os requisitos previos con privilexios antes de cambiar de usuario." ;;
        fr:install_mode_no_root) printf '%s' "2) Installation sans utilisateur root : s'installe sous l'accueil d'un utilisateur régulier et configure les prérequis privilégiés avant de changer d'utilisateur." ;;
        de:install_mode_no_root) printf '%s' "2) No-Root-Benutzerinstallation: Installiert unter der Startseite eines regulären Benutzers und konfiguriert die privilegierten Voraussetzungen, bevor der Benutzer gewechselt wird." ;;
        it:install_mode_no_root) printf '%s' "2) Installazione senza utente root: si installa nella home di un utente normale e configura i prerequisiti privilegiati prima di cambiare utente." ;;
        ja:install_mode_no_root) printf '%s' "2) root ユーザーなしのインストール: 通常のユーザーのホームにインストールし、ユーザーを切り替える前に特権の前提条件を構成します。" ;;
        zh:install_mode_no_root) printf '%s' "2) 无 root 用户安装：在普通用户家中安装并在切换用户之前配置特权先决条件。" ;;
        es:install_mode_prompt) printf '%s' "Elija el modo de instalación [1=root, 2=no-root] (1): " ;;
        ca:install_mode_prompt) printf '%s' "Trieu el mode d'instal·lació [1=root, 2=no-root] (1): " ;;
        eu:install_mode_prompt) printf '%s' "Aukeratu instalazio modua [1=root, 2=no-root] (1): " ;;
        gl:install_mode_prompt) printf '%s' "Escolla o modo de instalación [1=root, 2=sen root] (1): " ;;
        fr:install_mode_prompt) printf '%s' "Choisissez le mode d'installation [1=root, 2=no-root] (1): " ;;
        de:install_mode_prompt) printf '%s' "Wählen Sie den Installationsmodus [1=root, 2=no-root] (1): " ;;
        it:install_mode_prompt) printf '%s' "Scegli la modalità di installazione [1=root, 2=no-root] (1): " ;;
        ja:install_mode_prompt) printf '%s' "インストール モードを選択 [1=root、2=no-root] (1): " ;;
        zh:install_mode_prompt) printf '%s' "选择安装模式 [1=root, 2=no-root] (1): " ;;
        es:install_mode_root) printf '%s' "1) Instalación raíz/sistema: utiliza /opt, /var/lib, servicios del sistema; requiere raíz." ;;
        ca:install_mode_root) printf '%s' "1) Instal·lació arrel/del sistema: utilitza /opt, /var/lib, serveis del sistema; requereix arrel." ;;
        eu:install_mode_root) printf '%s' "1) Erro/sistemaren instalazioa: /opt, /var/lib, sistema zerbitzuak erabiltzen ditu; root eskatzen du." ;;
        gl:install_mode_root) printf '%s' "1) Instalación raíz/sistema: usa /opt, /var/lib, servizos do sistema; require root." ;;
        fr:install_mode_root) printf '%s' "1) Installation racine/système : utilise /opt, /var/lib, les services système ; nécessite root." ;;
        de:install_mode_root) printf '%s' "1) Root-/Systeminstallation: verwendet /opt, /var/lib, Systemdienste; erfordert root." ;;
        it:install_mode_root) printf '%s' "1) Installazione root/sistema: utilizza /opt, /var/lib, servizi di sistema; richiede root." ;;
        ja:install_mode_root) printf '%s' "1) ルート/システム インストール: /opt、/var/lib、システム サービスを使用します。 rootが必要です。" ;;
        zh:install_mode_root) printf '%s' "1) root/系统安装：使用/opt、/var/lib、系统服务；需要root。" ;;
        es:install_mode_title) printf '%s' "Modo de instalación:" ;;
        ca:install_mode_title) printf '%s' "Mode d'instal·lació:" ;;
        eu:install_mode_title) printf '%s' "Instalazio modua:" ;;
        gl:install_mode_title) printf '%s' "Modo de instalación:" ;;
        fr:install_mode_title) printf '%s' "Mode d'installation :" ;;
        de:install_mode_title) printf '%s' "Installationsmodus:" ;;
        it:install_mode_title) printf '%s' "Modalità di installazione:" ;;
        ja:install_mode_title) printf '%s' "インストールモード:" ;;
        zh:install_mode_title) printf '%s' "安装方式：" ;;
        es:installing_cron_root) printf '%s' "Instalando cron como root..." ;;
        ca:installing_cron_root) printf '%s' "S'està instal·lant cron com a root..." ;;
        eu:installing_cron_root) printf '%s' "Cron root gisa instalatzen..." ;;
        gl:installing_cron_root) printf '%s' "Instalando cron como root..." ;;
        fr:installing_cron_root) printf '%s' "Installer cron en tant que root..." ;;
        de:installing_cron_root) printf '%s' "Cron als Root installieren..." ;;
        it:installing_cron_root) printf '%s' "Installazione di cron come root..." ;;
        ja:installing_cron_root) printf '%s' "root として cron をインストールしています..." ;;
        zh:installing_cron_root) printf '%s' "以 root 身份安装 cron..." ;;
        es:linger_already_enabled) printf '%s' "La permanencia ya está habilitada para" ;;
        ca:linger_already_enabled) printf '%s' "Linger ja està habilitat" ;;
        eu:linger_already_enabled) printf '%s' "linger dagoeneko gaituta dago" ;;
        gl:linger_already_enabled) printf '%s' "Linger xa está habilitado para" ;;
        fr:linger_already_enabled) printf '%s' "Linger est déjà activé pour" ;;
        de:linger_already_enabled) printf '%s' "Verweilen ist bereits aktiviert" ;;
        it:linger_already_enabled) printf '%s' "il ritardo è già abilitato per" ;;
        ja:linger_already_enabled) printf '%s' "リンガーはすでに有効になっています" ;;
        zh:linger_already_enabled) printf '%s' "linger 已启用" ;;
        es:linger_enable_failed) printf '%s' "No se pudo habilitar la permanencia durante" ;;
        ca:linger_enable_failed) printf '%s' "No s'ha pogut activar la permanència" ;;
        eu:linger_enable_failed) printf '%s' "Ezin izan da etenaldia gaitu" ;;
        gl:linger_enable_failed) printf '%s' "Non se puido activar a permanencia" ;;
        fr:linger_enable_failed) printf '%s' "Impossible de s'attarder pendant" ;;
        de:linger_enable_failed) printf '%s' "Verweildauer konnte nicht aktiviert werden" ;;
        it:linger_enable_failed) printf '%s' "Impossibile abilitare il ritardo per" ;;
        ja:linger_enable_failed) printf '%s' "リンガーを有効にできませんでした" ;;
        zh:linger_enable_failed) printf '%s' "无法启用延迟" ;;
        es:linger_enabled_for) printf '%s' "permanecer habilitado para" ;;
        ca:linger_enabled_for) printf '%s' "perdurar habilitat per" ;;
        eu:linger_enabled_for) printf '%s' "linger gaituta" ;;
        gl:linger_enabled_for) printf '%s' "permanecer habilitado para" ;;
        fr:linger_enabled_for) printf '%s' "s'attarder activé pour" ;;
        de:linger_enabled_for) printf '%s' "Verweilen aktiviert für" ;;
        it:linger_enabled_for) printf '%s' "rimanere abilitato per" ;;
        ja:linger_enabled_for) printf '%s' "残留が有効になっている" ;;
        zh:linger_enabled_for) printf '%s' "逗留已启用" ;;
        es:loginctl_required) printf '%s' "Se requiere loginctl para habilitar la permanencia en systemd --user." ;;
        ca:loginctl_required) printf '%s' "loginctl és necessari per habilitar linger per a systemd --user." ;;
        eu:loginctl_required) printf '%s' "loginctl beharrezkoa da systemd --user linger gaitzeko." ;;
        gl:loginctl_required) printf '%s' "loginctl é necesario para habilitar linger para systemd --user." ;;
        fr:loginctl_required) printf '%s' "loginctl est requis pour activer Linger pour systemd --user." ;;
        de:loginctl_required) printf '%s' "loginctl ist erforderlich, um Linger für systemd --user zu aktivieren." ;;
        it:loginctl_required) printf '%s' "loginctl è necessario per abilitare il persistente per systemd --user." ;;
        ja:loginctl_required) printf '%s' "systemd --user のリンガーを有効にするには、loginctl が必要です。" ;;
        zh:loginctl_required) printf '%s' "需要 loginctl 才能为 systemd --user 启用 linger。" ;;
        es:no_interactive_root_default) printf '%s' "Ejecutándose como root sin terminal interactivo; continuando con la instalación raíz/sistema." ;;
        ca:no_interactive_root_default) printf '%s' "S'executa com a root sense un terminal interactiu; continuant amb la instal·lació d'arrel/sistema." ;;
        eu:no_interactive_root_default) printf '%s' "Terminal interaktiborik gabe root gisa exekutatzen; root/sistemaren instalazioarekin jarraituz." ;;
        gl:no_interactive_root_default) printf '%s' "Executándose como root sen un terminal interactivo; continuando coa instalación de root/sistema." ;;
        fr:no_interactive_root_default) printf '%s' "Exécuté en tant que root sans terminal interactif ; continuer avec l'installation racine/système." ;;
        de:no_interactive_root_default) printf '%s' "Als Root ohne interaktives Terminal ausführen; Fahren Sie mit der Root-/Systeminstallation fort." ;;
        it:no_interactive_root_default) printf '%s' "In esecuzione come root senza un terminale interattivo; continuando con l'installazione root/sistema." ;;
        ja:no_interactive_root_default) printf '%s' "対話型ターミナルを使用せずに root として実行します。ルート/システムのインストールを続行します。" ;;
        zh:no_interactive_root_default) printf '%s' "在没有交互式终端的情况下以 root 身份运行；继续根/系统安装。" ;;
        es:no_root_user_cannot_be_root) printf '%s' "El usuario no root seleccionado no puede ser root." ;;
        ca:no_root_user_cannot_be_root) printf '%s' "L'usuari no root seleccionat no pot ser root." ;;
        eu:no_root_user_cannot_be_root) printf '%s' "Hautatutako errorik gabeko erabiltzailea ezin da root izan." ;;
        gl:no_root_user_cannot_be_root) printf '%s' "O usuario non root seleccionado non pode ser root." ;;
        fr:no_root_user_cannot_be_root) printf '%s' "L'utilisateur non root sélectionné ne peut pas être root." ;;
        de:no_root_user_cannot_be_root) printf '%s' "Der ausgewählte Nicht-Root-Benutzer kann kein Root sein." ;;
        it:no_root_user_cannot_be_root) printf '%s' "L'utente no-root selezionato non può essere root." ;;
        ja:no_root_user_cannot_be_root) printf '%s' "選択した root 以外のユーザーを root にすることはできません。" ;;
        zh:no_root_user_cannot_be_root) printf '%s' "所选的非 root 用户不能是 root。" ;;
        es:rerunning_as_no_root) printf '%s' "Volver a ejecutar el instalador como usuario no root" ;;
        ca:rerunning_as_no_root) printf '%s' "Torna a executar l'instal·lador com a usuari sense root" ;;
        eu:rerunning_as_no_root) printf '%s' "Berriro exekutatzen instalatzailea errorik gabeko erabiltzaile gisa" ;;
        gl:rerunning_as_no_root) printf '%s' "Volve executar o instalador como usuario sen root" ;;
        fr:rerunning_as_no_root) printf '%s' "Réexécution du programme d'installation en tant qu'utilisateur non root" ;;
        de:rerunning_as_no_root) printf '%s' "Führen Sie das Installationsprogramm als Benutzer ohne Rootberechtigung erneut aus" ;;
        it:rerunning_as_no_root) printf '%s' "Rieseguire il programma di installazione come utente no-root" ;;
        ja:rerunning_as_no_root) printf '%s' "root 以外のユーザーとしてインストーラーを再実行する" ;;
        zh:rerunning_as_no_root) printf '%s' "以非 root 用户身份重新运行安装程序" ;;
        es:starting_user_manager_for) printf '%s' "Iniciando el administrador de usuarios systemd para" ;;
        ca:starting_user_manager_for) printf '%s' "S'està iniciant el gestor d'usuaris de systemd per" ;;
        eu:starting_user_manager_for) printf '%s' "Systemd erabiltzaile-kudeatzailea abiarazten" ;;
        gl:starting_user_manager_for) printf '%s' "Iniciando o xestor de usuarios de systemd para" ;;
        fr:starting_user_manager_for) printf '%s' "Démarrage du gestionnaire d'utilisateurs systemd pour" ;;
        de:starting_user_manager_for) printf '%s' "Systemd-Benutzermanager starten für" ;;
        it:starting_user_manager_for) printf '%s' "Avvio del gestore utenti systemd per" ;;
        ja:starting_user_manager_for) printf '%s' "systemd ユーザーマネージャーの起動" ;;
        zh:starting_user_manager_for) printf '%s' "启动 systemd 用户管理器" ;;
        es:systemd_bus_unavailable_for) printf '%s' "El bus de usuario systemd no estaba disponible después de habilitar la permanencia para" ;;
        ca:systemd_bus_unavailable_for) printf '%s' "El bus d'usuari systemd no estava disponible després d'habilitar Linger per" ;;
        eu:systemd_bus_unavailable_for) printf '%s' "systemd erabiltzaile-busa ez zegoen erabilgarri linger-rako gaitu ondoren" ;;
        gl:systemd_bus_unavailable_for) printf '%s' "O bus de usuario systemd non estaba dispoñible despois de activar Linger para" ;;
        fr:systemd_bus_unavailable_for) printf '%s' "Le bus utilisateur systemd n'était pas disponible après l'activation de Linger pendant" ;;
        de:systemd_bus_unavailable_for) printf '%s' "Der systemd-Benutzerbus war nach der Aktivierung von Linger für nicht verfügbar" ;;
        it:systemd_bus_unavailable_for) printf '%s' "Il bus utente systemd non era disponibile dopo aver abilitato il ritardo" ;;
        ja:systemd_bus_unavailable_for) printf '%s' "linger を有効にした後、systemd ユーザー バスが利用できなくなりました" ;;
        zh:systemd_bus_unavailable_for) printf '%s' "启用 linger 后，systemd 用户总线不可用" ;;
        es:systemd_manager_available_for) printf '%s' "El administrador de usuarios systemd está disponible para" ;;
        ca:systemd_manager_available_for) printf '%s' "El gestor d'usuaris de systemd està disponible per a" ;;
        eu:systemd_manager_available_for) printf '%s' "systemd erabiltzaile kudeatzailea eskuragarri dago" ;;
        gl:systemd_manager_available_for) printf '%s' "Systemd User Manager está dispoñible para" ;;
        fr:systemd_manager_available_for) printf '%s' "Le gestionnaire d'utilisateurs systemd est disponible pour" ;;
        de:systemd_manager_available_for) printf '%s' "Der systemd-Benutzermanager ist verfügbar für" ;;
        it:systemd_manager_available_for) printf '%s' "Il gestore utenti systemd è disponibile per" ;;
        ja:systemd_manager_available_for) printf '%s' "systemd ユーザーマネージャーは次の目的で使用できます。" ;;
        zh:systemd_manager_available_for) printf '%s' "systemd 用户管理器可用于" ;;
        es:target_no_root_user) printf '%s' "Dirigirse a usuarios no root" ;;
        ca:target_no_root_user) printf '%s' "Objectiu a l'usuari sense root" ;;
        eu:target_no_root_user) printf '%s' "Helburua errorik gabeko erabiltzailea" ;;
        gl:target_no_root_user) printf '%s' "Destino usuario sen root" ;;
        fr:target_no_root_user) printf '%s' "Cibler l'utilisateur non root" ;;
        de:target_no_root_user) printf '%s' "Zielbenutzer ohne Rootberechtigung" ;;
        it:target_no_root_user) printf '%s' "Scegli come target l'utente non root" ;;
        ja:target_no_root_user) printf '%s' "非rootユーザーを対象とする" ;;
        zh:target_no_root_user) printf '%s' "目标非 root 用户" ;;
        es:target_no_root_user_prompt) printf '%s' "Usuario no root de destino: " ;;
        ca:target_no_root_user_prompt) printf '%s' "Usuari no root objectiu: " ;;
        eu:target_no_root_user_prompt) printf '%s' "Helburua errorik gabeko erabiltzailea: " ;;
        gl:target_no_root_user_prompt) printf '%s' "Destino usuario sen root: " ;;
        fr:target_no_root_user_prompt) printf '%s' "Cibler l'utilisateur non root : " ;;
        de:target_no_root_user_prompt) printf '%s' "Zielbenutzer ohne Rootberechtigung: " ;;
        it:target_no_root_user_prompt) printf '%s' "Scegli come target l'utente non root: " ;;
        ja:target_no_root_user_prompt) printf '%s' "ターゲットの非 root ユーザー: " ;;
        zh:target_no_root_user_prompt) printf '%s' "目标非root用户： " ;;
        es:target_user_required) printf '%s' "Se requiere un usuario objetivo no root." ;;
        ca:target_user_required) printf '%s' "Es requereix un usuari objectiu sense root." ;;
        eu:target_user_required) printf '%s' "Root gabeko helburuko erabiltzaile bat behar da." ;;
        gl:target_user_required) printf '%s' "Requírese un usuario de destino sen root." ;;
        fr:target_user_required) printf '%s' "Un utilisateur cible non root est requis." ;;
        de:target_user_required) printf '%s' "Es ist ein Zielbenutzer ohne Rootberechtigung erforderlich." ;;
        it:target_user_required) printf '%s' "È richiesto un utente di destinazione non root." ;;
        ja:target_user_required) printf '%s' "ターゲットの非 root ユーザーが必要です。" ;;
        zh:target_user_required) printf '%s' "需要目标非 root 用户。" ;;
        es:target_user_required_env) printf '%s' "Se requiere RS_AGENT_TARGET_USER para el modo sin raíz cuando se ejecuta como raíz." ;;
        ca:target_user_required_env) printf '%s' "RS_AGENT_TARGET_USER és necessari per al mode sense root quan s'executa com a root." ;;
        eu:target_user_required_env) printf '%s' "RS_AGENT_TARGET_USER beharrezkoa da errorik gabeko modurako root gisa exekutatzen denean." ;;
        gl:target_user_required_env) printf '%s' "RS_AGENT_TARGET_USER é necesario para o modo sen root cando se executa como root." ;;
        fr:target_user_required_env) printf '%s' "RS_AGENT_TARGET_USER est requis pour le mode sans root lors de l'exécution en tant que root." ;;
        de:target_user_required_env) printf '%s' "RS_AGENT_TARGET_USER ist für den No-Root-Modus erforderlich, wenn es als Root ausgeführt wird." ;;
        it:target_user_required_env) printf '%s' "RS_AGENT_TARGET_USER è richiesto per la modalità no-root quando si esegue come root." ;;
        ja:target_user_required_env) printf '%s' "RS_AGENT_TARGET_USER は、root として実行する場合の no-root モードに必要です。" ;;
        zh:target_user_required_env) printf '%s' "当以 root 身份运行时，无 root 模式需要 RS_AGENT_TARGET_USER。" ;;
        es:unknown_install_mode) printf '%s' "Modo de instalación desconocido" ;;
        ca:unknown_install_mode) printf '%s' "Mode d'instal·lació desconegut" ;;
        eu:unknown_install_mode) printf '%s' "Instalazio modu ezezaguna" ;;
        gl:unknown_install_mode) printf '%s' "Modo de instalación descoñecido" ;;
        fr:unknown_install_mode) printf '%s' "Mode d'installation inconnu" ;;
        de:unknown_install_mode) printf '%s' "Unbekannter Installationsmodus" ;;
        it:unknown_install_mode) printf '%s' "Modalità di installazione sconosciuta" ;;
        ja:unknown_install_mode) printf '%s' "不明なインストールモード" ;;
        zh:unknown_install_mode) printf '%s' "未知的安装模式" ;;
        es:user_not_exists) printf '%s' "El usuario no existe" ;;
        ca:user_not_exists) printf '%s' "L'usuari no existeix" ;;
        eu:user_not_exists) printf '%s' "Erabiltzailea ez da existitzen" ;;
        gl:user_not_exists) printf '%s' "O usuario non existe" ;;
        fr:user_not_exists) printf '%s' "L'utilisateur n'existe pas" ;;
        de:user_not_exists) printf '%s' "Benutzer existiert nicht" ;;
        it:user_not_exists) printf '%s' "L'utente non esiste" ;;
        ja:user_not_exists) printf '%s' "ユーザーが存在しません" ;;
        zh:user_not_exists) printf '%s' "用户不存在" ;;
        *:usage) printf '%s' "Usage: curl ... | bash -s -- <AGENT_TOKEN> <UUID> --alias <ALIAS>" ;;
        *:usage_locale) printf '%s' "Usage: curl ... | bash -s -- <AGENT_TOKEN> <UUID> --alias <ALIAS> [--locale <LOCALE>]" ;;
        *:alias_requires_value) printf '%s' "--alias requires a value" ;;
        *:locale_requires_value) printf '%s' "--locale requires a value" ;;
        *:unknown_argument) printf '%s' "Unknown argument" ;;
        *:scheduler_env_invalid) printf '%s' "RS_AGENT_SCHEDULER must be: cron or systemd-user" ;;
        *:no_interactive_cron_default) printf '%s' "No interactive terminal detected; user cron will be used by default." ;;
        *:automatic_execution_setup) printf '%s' "Automatic execution setup:" ;;
        *:scheduler_cron_title) printf '%s' "1) User cron" ;;
        *:scheduler_cron_plus) printf '%s' "+ Does not require root for agent execution and does not depend on an active user session." ;;
        *:scheduler_cron_minus) printf '%s' "- Requires cron/crontab installed, active, and allowed." ;;
        *:scheduler_systemd_title) printf '%s' "2) systemd --user" ;;
        *:scheduler_systemd_plus) printf '%s' "+ Better integration with systemd and systemctl --user." ;;
        *:scheduler_systemd_minus) printf '%s' "- Requires linger to run without an active session; it will be enabled as root if needed." ;;
        *:scheduler_prompt) printf '%s' "Choose scheduler [1=cron, 2=systemd-user] (1): " ;;
        *:unknown_scheduler) printf '%s' "Unknown scheduler" ;;
        *:scheduler_usage) printf '%s' "Use 1/cron or 2/systemd-user." ;;
        *:cron_enable_unknown) printf '%s' "Could not determine how to enable cron automatically on this distribution." ;;
        *:cron_install_unknown) printf '%s' "Could not determine how to install cron automatically on this distribution." ;;
        *:cron_still_inactive) printf '%s' "cron does not appear to be active after enabling it." ;;
        *:crontab_still_missing) printf '%s' "cron/crontab is still not available after installation." ;;
        *:enabling_cron_root) printf '%s' "Enabling cron as root..." ;;
        *:enabling_linger_for) printf '%s' "Enabling linger as root for" ;;
        *:install_mode_env_invalid) printf '%s' "RS_AGENT_INSTALL_MODE must be root or no-root" ;;
        *:install_mode_no_root) printf '%s' "2) No-root user install: installs under a regular user's home and configures privileged prerequisites before switching user." ;;
        *:install_mode_prompt) printf '%s' "Choose install mode [1=root, 2=no-root] (1): " ;;
        *:install_mode_root) printf '%s' "1) Root/system install: uses /opt, /var/lib, system services; requires root." ;;
        *:install_mode_title) printf '%s' "Installation mode:" ;;
        *:installing_cron_root) printf '%s' "Installing cron as root..." ;;
        *:linger_already_enabled) printf '%s' "linger is already enabled for" ;;
        *:linger_enable_failed) printf '%s' "Could not enable linger for" ;;
        *:linger_enabled_for) printf '%s' "linger enabled for" ;;
        *:loginctl_required) printf '%s' "loginctl is required to enable linger for systemd --user." ;;
        *:no_interactive_root_default) printf '%s' "Running as root without an interactive terminal; continuing with root/system install." ;;
        *:no_root_user_cannot_be_root) printf '%s' "The selected no-root user cannot be root." ;;
        *:rerunning_as_no_root) printf '%s' "Re-running installer as no-root user" ;;
        *:starting_user_manager_for) printf '%s' "Starting systemd user manager for" ;;
        *:systemd_bus_unavailable_for) printf '%s' "systemd user bus was not available after enabling linger for" ;;
        *:systemd_manager_available_for) printf '%s' "systemd user manager is available for" ;;
        *:target_no_root_user) printf '%s' "Target no-root user" ;;
        *:target_no_root_user_prompt) printf '%s' "Target no-root user: " ;;
        *:target_user_required) printf '%s' "A target no-root user is required." ;;
        *:target_user_required_env) printf '%s' "RS_AGENT_TARGET_USER is required for no-root mode when running as root." ;;
        *:unknown_install_mode) printf '%s' "Unknown install mode" ;;
        *:user_not_exists) printf '%s' "User does not exist" ;;
        *) printf '%s' "$key" ;;
    esac
}

if [ -z "$AGENT_TOKEN" ] || [ -z "$UUID" ]; then
    echo "[ERROR] $(early_t usage)"
    exit 1
fi

shift 2
while [ $# -gt 0 ]; do
    case "$1" in
        --alias)
            if [ $# -lt 2 ]; then
                echo "[ERROR] $(early_t alias_requires_value)"
                exit 1
            fi
            SYSTEM_ALIAS="$2"
            shift 2
            ;;
        --locale|--agent-locale)
            if [ $# -lt 2 ]; then
                echo "[ERROR] $(early_t locale_requires_value)"
                exit 1
            fi
            AGENT_LOCALE="$2"
            shift 2
            ;;
        *)
            echo "[ERROR] $(early_t unknown_argument): $1"
            echo "[ERROR] $(early_t usage_locale)"
            exit 1
            ;;
    esac
done

if [ -n "$SCHEDULER_CHOICE" ]; then
    case "$SCHEDULER_CHOICE" in
        cron|systemd-user) ;;
        *)
            echo "[ERROR] $(early_t scheduler_env_invalid)"
            exit 1
            ;;
    esac
fi

# ============================================================================
# CONFIGURATION
# ============================================================================

# GitHub URL where the agent is hosted. In this experimental branch it points to
# the same branch to test no-root installation without mixing it with main.
GITHUB_RAW_URL="${RS_AGENT_GITHUB_RAW_URL:-https://raw.githubusercontent.com/Redsauce/firulai-linux-agent/main}"

RUN_AS_ROOT=0
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    RUN_AS_ROOT=1
fi

early_trim_string() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

early_shell_single_quote() {
    printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

early_json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

early_json_extract_first_string_key() {
    local json="$1"
    local key="$2"

    printf '%s' "$json" \
        | tr -d '\n' \
        | sed 's/,"/\n"/g' \
        | sed -n "s/^.*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*$/\1/p" \
        | head -1
}

early_json_extract_rsm_property() {
    local json="$1"
    local property_id="$2"
    local value

    value=$(early_json_extract_first_string_key "$json" "$property_id")
    if [ -n "$value" ]; then
        printf '%s' "$value"
        return 0
    fi

    early_json_extract_first_string_key "$json" "${property_id}trs"
}

early_normalize_locale() {
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

early_resolve_locale_from_rsm() {
    local token="$1"
    local payload response_body locale
    local items_get_url="https://rsm1.redsauce.net/AppController/commands_RSM/api/v2/items/get.php"
    local app_user_agent_token_property_id="1821"
    local app_user_locale_property_id="1824"

    [ -n "$token" ] || return 1
    command -v curl >/dev/null 2>&1 || return 1

    payload="{\"propertyIDs\":[\"$app_user_agent_token_property_id\",\"$app_user_locale_property_id\"],\"translateIDs\":true,\"filterRules\":[{\"propertyID\":\"$app_user_agent_token_property_id\",\"value\":\"$(early_json_escape "$token")\",\"operation\":\"=\"}]}"
    response_body=$(curl --silent --show-error --location --request GET "$items_get_url" --header "Authorization: $token" --header "Content-Type: application/json" --data "$payload" --max-time 20 2>/dev/null) || return 1
    locale=$(early_json_extract_rsm_property "$response_body" "$app_user_locale_property_id")
    [ -n "$locale" ] || return 1
    early_normalize_locale "$locale"
}

early_user_linger_enabled_for() {
    local username="$1"
    command -v loginctl >/dev/null 2>&1 || return 1
    [ "$(loginctl show-user "$username" -p Linger --value 2>/dev/null || true)" = "yes" ]
}

early_user_runtime_dir_for() {
    local username="$1"
    local user_uid
    user_uid=$(id -u "$username" 2>/dev/null) || return 1
    printf '/run/user/%s' "$user_uid"
}

early_wait_for_user_systemd_bus_for() {
    local username="$1"
    local runtime_dir attempts=0
    runtime_dir=$(early_user_runtime_dir_for "$username") || return 1

    while [ "$attempts" -lt 10 ]; do
        [ -S "$runtime_dir/bus" ] && return 0
        sleep 1
        attempts=$((attempts + 1))
    done

    return 1
}

early_start_user_systemd_manager_for() {
    local username="$1"
    local user_uid
    user_uid=$(id -u "$username" 2>/dev/null) || return 1

    if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
        systemctl start "user@${user_uid}.service" 2>/dev/null || true
    fi

    early_wait_for_user_systemd_bus_for "$username"
}

early_cron_daemon_active() {
    if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
        systemctl is-active --quiet cron.service 2>/dev/null && return 0
        systemctl is-active --quiet crond.service 2>/dev/null && return 0
        systemctl is-active --quiet cronie.service 2>/dev/null && return 0
    fi

    if command -v service >/dev/null 2>&1; then
        service cron status >/dev/null 2>&1 && return 0
        service crond status >/dev/null 2>&1 && return 0
    fi

    if command -v pgrep >/dev/null 2>&1; then
        pgrep -x cron >/dev/null 2>&1 && return 0
        pgrep -x crond >/dev/null 2>&1 && return 0
    fi

    return 1
}

early_cron_install_command() {
    if command -v apt-get >/dev/null 2>&1; then
        printf '%s' 'apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y cron'
        return 0
    fi

    if command -v dnf >/dev/null 2>&1; then
        printf '%s' 'dnf install -y cronie'
        return 0
    fi

    if command -v yum >/dev/null 2>&1; then
        printf '%s' 'yum install -y cronie'
        return 0
    fi

    if command -v zypper >/dev/null 2>&1; then
        printf '%s' 'zypper --non-interactive install cron'
        return 0
    fi

    return 1
}

early_cron_enable_command() {
    if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
        printf '%s' 'systemctl enable --now cron.service 2>/dev/null || systemctl enable --now crond.service 2>/dev/null || systemctl enable --now cronie.service'
        return 0
    fi

    if command -v service >/dev/null 2>&1; then
        printf '%s' 'service cron start 2>/dev/null || service crond start'
        return 0
    fi

    return 1
}

early_choose_no_root_scheduler() {
    local reply

    if [ -n "$SCHEDULER_CHOICE" ]; then
        return 0
    fi

    if [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then
        echo "[WARN] $(early_t no_interactive_cron_default)"
        SCHEDULER_CHOICE="cron"
        return 0
    fi

    echo "" > /dev/tty
    echo "$(early_t automatic_execution_setup)" > /dev/tty
    echo "  $(early_t scheduler_cron_title)" > /dev/tty
    echo "     $(early_t scheduler_cron_plus)" > /dev/tty
    echo "     $(early_t scheduler_cron_minus)" > /dev/tty
    echo "  $(early_t scheduler_systemd_title)" > /dev/tty
    echo "     $(early_t scheduler_systemd_plus)" > /dev/tty
    echo "     $(early_t scheduler_systemd_minus)" > /dev/tty
    printf "%s" "$(early_t scheduler_prompt)" > /dev/tty
    IFS= read -r reply < /dev/tty || reply=""
    reply=$(early_trim_string "$reply")

    case "$reply" in
        ""|cron|c|1)
            SCHEDULER_CHOICE="cron"
            ;;
        systemd|systemd-user|s|2)
            SCHEDULER_CHOICE="systemd-user"
            ;;
        *)
            echo "[ERROR] $(early_t unknown_scheduler): $reply" > /dev/tty
            echo "[ERROR] $(early_t scheduler_usage)" > /dev/tty
            exit 1
            ;;
    esac
}

early_preconfigure_no_root_privileged_requirements() {
    local target_user="$1"

    early_choose_no_root_scheduler

    if [ "$SCHEDULER_CHOICE" = "cron" ]; then
        local cron_command

        if ! command -v crontab >/dev/null 2>&1; then
            cron_command=$(early_cron_install_command) || {
                echo "[ERROR] $(early_t cron_install_unknown)" >&2
                exit 1
            }
            echo "[INFO] $(early_t installing_cron_root)"
            sh -c "$cron_command"
            if ! command -v crontab >/dev/null 2>&1; then
                echo "[ERROR] $(early_t crontab_still_missing)" >&2
                exit 1
            fi
        fi

        if ! early_cron_daemon_active; then
            cron_command=$(early_cron_enable_command) || {
                echo "[ERROR] $(early_t cron_enable_unknown)" >&2
                exit 1
            }
            echo "[INFO] $(early_t enabling_cron_root)"
            sh -c "$cron_command"
            if ! early_cron_daemon_active; then
                echo "[ERROR] $(early_t cron_still_inactive)" >&2
                exit 1
            fi
        fi
    elif [ "$SCHEDULER_CHOICE" = "systemd-user" ]; then
        if ! command -v loginctl >/dev/null 2>&1; then
            echo "[ERROR] $(early_t loginctl_required)" >&2
            exit 1
        fi

        if early_user_linger_enabled_for "$target_user"; then
            echo "[OK] $(early_t linger_already_enabled) $target_user"
        else
            echo "[INFO] $(early_t enabling_linger_for) $target_user"
            loginctl enable-linger "$target_user"
            if ! early_user_linger_enabled_for "$target_user"; then
                echo "[ERROR] $(early_t linger_enable_failed) $target_user." >&2
                exit 1
            fi
            echo "[OK] $(early_t linger_enabled_for) $target_user"
        fi

        echo "[INFO] $(early_t starting_user_manager_for) $target_user..."
        if ! early_start_user_systemd_manager_for "$target_user"; then
            echo "[ERROR] $(early_t systemd_bus_unavailable_for) $target_user." >&2
            exit 1
        fi
        echo "[OK] $(early_t systemd_manager_available_for) $target_user"
    fi
}

reexec_as_no_root_user() {
    local target_user="$1"
    local command_string

    if ! id "$target_user" >/dev/null 2>&1; then
        echo "[ERROR] $(early_t user_not_exists): $target_user"
        exit 1
    fi

    if [ "$(id -u "$target_user")" -eq 0 ]; then
        echo "[ERROR] $(early_t no_root_user_cannot_be_root)"
        exit 1
    fi

    early_preconfigure_no_root_privileged_requirements "$target_user"

    local target_uid target_runtime_dir
    target_uid=$(id -u "$target_user")
    target_runtime_dir="/run/user/$target_uid"

    command_string="export RS_AGENT_SCHEDULER=$(early_shell_single_quote "$SCHEDULER_CHOICE"); export XDG_RUNTIME_DIR=$(early_shell_single_quote "$target_runtime_dir"); export DBUS_SESSION_BUS_ADDRESS=$(early_shell_single_quote "unix:path=$target_runtime_dir/bus"); curl -fsSL $(early_shell_single_quote "$GITHUB_RAW_URL/install.sh") | bash -s -- $(early_shell_single_quote "$AGENT_TOKEN") $(early_shell_single_quote "$UUID")"
    if [ -n "$SYSTEM_ALIAS" ]; then
        command_string="$command_string --alias $(early_shell_single_quote "$SYSTEM_ALIAS")"
    fi
    if [ -n "$AGENT_LOCALE" ]; then
        command_string="$command_string --locale $(early_shell_single_quote "$AGENT_LOCALE")"
    fi

    echo "[INFO] $(early_t rerunning_as_no_root): $target_user"
    exec su - "$target_user" -c "$command_string"
}

choose_install_mode_if_root() {
    local mode_reply target_user

    [ "$RUN_AS_ROOT" = "1" ] || return 0

    if [ -n "${RS_AGENT_INSTALL_MODE:-}" ]; then
        case "$RS_AGENT_INSTALL_MODE" in
            root) return 0 ;;
            no-root)
                target_user="${RS_AGENT_TARGET_USER:-${SUDO_USER:-}}"
                if [ -z "$target_user" ] || [ "$target_user" = "root" ]; then
                    echo "[ERROR] $(early_t target_user_required_env)"
                    exit 1
                fi
                reexec_as_no_root_user "$target_user"
                ;;
            *)
                echo "[ERROR] $(early_t install_mode_env_invalid)"
                exit 1
                ;;
        esac
    fi

    if [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then
        echo "[WARN] $(early_t no_interactive_root_default)"
        return 0
    fi

    echo "" > /dev/tty
    echo "$(early_t install_mode_title)" > /dev/tty
    echo "  $(early_t install_mode_root)" > /dev/tty
    echo "  $(early_t install_mode_no_root)" > /dev/tty
    printf "%s" "$(early_t install_mode_prompt)" > /dev/tty
    IFS= read -r mode_reply < /dev/tty || mode_reply=""
    mode_reply=$(early_trim_string "$mode_reply")

    case "$mode_reply" in
        ""|1|root|r)
            return 0
            ;;
        2|no-root|user|u)
            target_user="${SUDO_USER:-}"
            if [ -z "$target_user" ] || [ "$target_user" = "root" ]; then
                printf "%s" "$(early_t target_no_root_user_prompt)" > /dev/tty
                IFS= read -r target_user < /dev/tty || target_user=""
                target_user=$(early_trim_string "$target_user")
            else
                printf "%s (%s): " "$(early_t target_no_root_user)" "$target_user" > /dev/tty
                local target_reply=""
                IFS= read -r target_reply < /dev/tty || target_reply=""
                target_reply=$(early_trim_string "$target_reply")
                [ -n "$target_reply" ] && target_user="$target_reply"
            fi

            if [ -z "$target_user" ]; then
                echo "[ERROR] $(early_t target_user_required)" > /dev/tty
                exit 1
            fi
            reexec_as_no_root_user "$target_user"
            ;;
        *)
            echo "[ERROR] $(early_t unknown_install_mode): $mode_reply" > /dev/tty
            exit 1
            ;;
    esac
}

if [ -z "$AGENT_LOCALE" ]; then
    AGENT_LOCALE=$(early_resolve_locale_from_rsm "$AGENT_TOKEN" 2>/dev/null || true)
fi
AGENT_LOCALE=$(early_normalize_locale "$AGENT_LOCALE")

choose_install_mode_if_root

# Installation directories
if [ "$RUN_AS_ROOT" = "1" ]; then
    INSTALL_DIR="${RS_AGENT_INSTALL_DIR:-/opt/rs-agent}"
    DATA_DIR="${RS_AGENT_DATA_DIR:-/var/lib/rs-agent}"
    LOG_FILE="${RS_AGENT_LOG_FILE:-/var/log/rs-agent.log}"
    PRIVATE_TMP_DIR="${RS_AGENT_TMP_DIR:-/run/rs-agent/tmp}"
    SYSTEMD_SERVICE_FILE="/etc/systemd/system/rs-agent.service"
    SYSTEMD_TIMER_FILE="/etc/systemd/system/rs-agent.timer"
    SYSTEMD_USER_DIR=""
    SYSTEMD_USER_SERVICE_FILE=""
    SYSTEMD_USER_TIMER_FILE=""
else
    INSTALL_DIR="${RS_AGENT_INSTALL_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/rs-agent}"
    DATA_DIR="${RS_AGENT_DATA_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/rs-agent}"
    LOG_FILE="${RS_AGENT_LOG_FILE:-$DATA_DIR/rs-agent.log}"
    PRIVATE_TMP_DIR="${RS_AGENT_TMP_DIR:-${XDG_RUNTIME_DIR:-$DATA_DIR}/rs-agent/tmp}"
    SYSTEMD_SERVICE_FILE=""
    SYSTEMD_TIMER_FILE=""
    SYSTEMD_USER_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
    SYSTEMD_USER_SERVICE_FILE="$SYSTEMD_USER_DIR/rs-agent.service"
    SYSTEMD_USER_TIMER_FILE="$SYSTEMD_USER_DIR/rs-agent.timer"
fi
CONFIG_FILE="$DATA_DIR/config.env"
RUNNER_FILE="$INSTALL_DIR/rs_agent_runner.sh"
SCHEDULER_TYPE=""

# RSM System lookup
RSM_ITEMS_GET_URL="https://rsm1.redsauce.net/AppController/commands_RSM/api/v2/items/get.php"
RSM_ITEMS_UPDATE_URL="https://rsm1.redsauce.net/AppController/commands_RSM/api/v2/items/update.php"
RSM_SYSTEM_HOSTNAME_PROPERTY_ID="1749"
RSM_SYSTEM_FQDN_PROPERTY_ID="1750"
RSM_SYSTEM_UUID_PROPERTY_ID="1780"
RSM_SYSTEM_HOSTNAME_STATUS_PROPERTY_ID="1751"
RSM_SYSTEM_ALIAS_PROPERTY_ID="1827"
RSM_SYSTEM_HOSTNAME_STATUS_ACTIVE_VALUE="Activo"
RSM_ACCOUNT_AGENT_TOKEN_PROPERTY_ID="1790"
RSM_APP_USER_AGENT_TOKEN_PROPERTY_ID="1821"
RSM_APP_USER_ACCOUNT_PROPERTY_ID="516"
RSM_APP_USER_LOCALE_PROPERTY_ID="1824"
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
    ensure_private_directory "$(dirname "$PRIVATE_TMP_DIR")"
    ensure_private_directory "$PRIVATE_TMP_DIR"
}

make_private_temp_file() {
    local prefix="$1"
    mktemp "$PRIVATE_TMP_DIR/${prefix}.XXXXXX"
}

banner() {
    echo ""
    echo "============================================================================"
    printf '  Firulai Inventory Agent - %s v0.2.4\n' "$(t installer_title)"
    printf '  %s\n' "$(t banner_subtitle)"
    echo "============================================================================"
    echo ""
}

check_root() {
    if [ "$RUN_AS_ROOT" = "1" ]; then
        warn "$(t root_mode)"
    else
        info "$(t user_mode)"
        warn "$(t less_complete)"
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
            info "$(t alias_needed)"
            printf "%s" "$(t alias_prompt)" > /dev/tty
            IFS= read -r SYSTEM_ALIAS < /dev/tty || SYSTEM_ALIAS=""
            SYSTEM_ALIAS=$(trim_string "$SYSTEM_ALIAS")
        fi
    fi

    if [ -z "$SYSTEM_ALIAS" ]; then
        error "$(t alias_required)"
        echo ""
        echo "$(t alias_usage)"
        echo "  curl -fsSL https://raw.githubusercontent.com/Redsauce/firulai-linux-agent/main/install.sh | bash -s -- <AGENT_TOKEN> <UUID> --alias <ALIAS>"
        echo ""
        echo "$(t alias_quotes)"
        exit 1
    fi
}

prepare_systemd_user_environment() {
    local user_uid runtime_dir

    [ "$RUN_AS_ROOT" != "1" ] || return 1

    user_uid=$(id -u 2>/dev/null) || return 1
    runtime_dir="/run/user/$user_uid"

    if [ -z "${XDG_RUNTIME_DIR:-}" ] && [ -d "$runtime_dir" ]; then
        export XDG_RUNTIME_DIR="$runtime_dir"
    fi

    if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ] && [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -S "$XDG_RUNTIME_DIR/bus" ]; then
        export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
    fi

    [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -S "$XDG_RUNTIME_DIR/bus" ]
}

systemd_user_available() {
    [ "$RUN_AS_ROOT" != "1" ] || return 1
    command -v systemctl &> /dev/null || return 1
    prepare_systemd_user_environment || return 1
    systemctl --user show-environment >/dev/null 2>&1
}

user_linger_enabled() {
    [ "$RUN_AS_ROOT" != "1" ] || return 1
    command -v loginctl >/dev/null 2>&1 || return 1
    [ "$(loginctl show-user "$(id -un)" -p Linger --value 2>/dev/null || true)" = "yes" ]
}

has_interactive_tty() {
    [ -r /dev/tty ] && [ -w /dev/tty ]
}

ask_yes_no() {
    local prompt="$1"
    local reply

    has_interactive_tty || return 1
    printf "%s %s " "$prompt" "$(t yes_no_suffix)" > /dev/tty
    IFS= read -r reply < /dev/tty || reply=""
    case "$reply" in
        s|S|si|SI|sí|Sí|y|Y|yes|YES|o|O|oui|OUI|j|J|ja|JA|b|B|bai|BAI|是|は|ハ) return 0 ;;
        *) return 1 ;;
    esac
}

run_privileged_command() {
    local command_string="$1"

    if [ "${EUID:-$(id -u)}" -eq 0 ]; then
        sh -c "$command_string"
        return $?
    fi

    has_interactive_tty || {
        error "$(t no_interactive_privileged)"
        return 1
    }

    info "$(t privileged_needed)"
    if command -v su >/dev/null 2>&1; then
        info "$(t trying_su)"
        if su root -c "$command_string" < /dev/tty > /dev/tty 2>&1; then
            return 0
        fi
        warn "$(t su_failed)"
    else
        warn "$(t su_missing)"
    fi

    error "$(t privileged_not_completed)"
    return 1
}

prepare_systemd_user_manager_with_privileged_access() {
    local username user_uid command_string

    [ "$RUN_AS_ROOT" != "1" ] || return 1
    command -v loginctl >/dev/null 2>&1 || return 1
    command -v systemctl >/dev/null 2>&1 || return 1

    username=$(id -un)
    user_uid=$(id -u)
    command_string="loginctl enable-linger $(shell_single_quote "$username") && systemctl start $(shell_single_quote "user@${user_uid}.service")"

    info "$(t preparing_systemd_user_privileged)"
    if ! run_privileged_command "$command_string"; then
        return 1
    fi

    if ! early_wait_for_user_systemd_bus_for "$username"; then
        return 1
    fi

    prepare_systemd_user_environment
    systemd_user_available
}

choose_scheduler_interactively() {
    if [ "$RUN_AS_ROOT" = "1" ] || [ -n "$SCHEDULER_CHOICE" ]; then
        return 0
    fi

    if [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then
        warn "$(t no_interactive_cron_default)"
        SCHEDULER_CHOICE="cron"
        return 0
    fi

    local reply
    echo "" > /dev/tty
    info "$(t automatic_execution_setup)"
    echo "  $(t scheduler_cron_title)" > /dev/tty
    echo "     $(t scheduler_cron_plus)" > /dev/tty
    echo "     $(t scheduler_cron_minus)" > /dev/tty
    echo "  $(t scheduler_systemd_title)" > /dev/tty
    echo "     $(t scheduler_systemd_plus)" > /dev/tty
    echo "     $(t scheduler_systemd_minus)" > /dev/tty
    printf "%s" "$(t scheduler_prompt)" > /dev/tty
    IFS= read -r reply < /dev/tty || reply=""
    reply=$(trim_string "$reply")

    case "$reply" in
        ""|cron|c|1)
            SCHEDULER_CHOICE="cron"
            ;;
        systemd|systemd-user|s|2)
            SCHEDULER_CHOICE="systemd-user"
            ;;
        *)
            error "$(t unknown_scheduler): $reply"
            echo "$(t scheduler_usage)" > /dev/tty
            exit 1
            ;;
    esac
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
    
    info "$(t distribution): $DISTRO $VERSION"
}

check_dependencies() {
    info "$(t checking_dependencies)"

    # Verify curl (it should be available if we reached this point)
    if ! command -v curl &> /dev/null; then
        error "$(t curl_missing)"
        exit 1
    fi
    log "$(t curl_found): $(curl --version | head -1)"

    # Verify bash 4+ (required by the agent for associative arrays)
    local bash_major
    bash_major=$(bash --version | grep -oE '[0-9]+\.[0-9]+' | head -1 | cut -d. -f1)
    if [ "${bash_major:-0}" -lt 4 ]; then
        error "$(t bash_required) ($bash_major)"
        exit 1
    fi
    log "$(t bash_found): ${bash_major}"

    if ! command -v flock &> /dev/null; then
        error "$(t flock_missing_install)"
        exit 1
    fi
    log "$(t flock_found): $(command -v flock)"

    if ! command -v mktemp &> /dev/null; then
        error "$(t mktemp_missing_install)"
        exit 1
    fi
    log "$(t mktemp_found): $(command -v mktemp)"
}

validate_uuid_format() {
    local uuid="$1"
    if [[ ! "$uuid" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
        error "'$uuid' $(t invalid_uuid_local)"
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
        es_ES:banner_subtitle) printf '%s' "Agente de analisis del sistema para deteccion de vulnerabilidades" ;;
        es_ES:root_mode) printf '%s' "Modo de instalacion root/sistema seleccionado; se usaran rutas del sistema." ;;
        es_ES:user_mode) printf '%s' "Modo de instalacion sin root seleccionado; el agente se instalara solo para el usuario actual." ;;
        es_ES:less_complete) printf '%s' "El inventario puede ser menos completo que en modo root si el sistema restringe algunos comandos." ;;
        es_ES:alias_needed) printf '%s' "Este instalador necesita un alias para identificar el sistema en Firulai." ;;
        es_ES:alias_prompt) printf '%s' "Alias del sistema: " ;;
        es_ES:alias_required) printf '%s' "El alias del sistema es obligatorio." ;;
        es_ES:alias_usage) printf '%s' "Ejecuta el instalador con la opcion --alias:" ;;
        es_ES:alias_quotes) printf '%s' "Si el alias contiene espacios, ponlo entre comillas." ;;
        es_ES:validating_uuid) printf '%s' "Validando UUID en RSM..." ;;
        es_ES:uuid_validate_failed) printf '%s' "No se pudo validar el UUID en RSM" ;;
        es_ES:uuid_validate_safety) printf '%s' "Por seguridad, la instalacion no continuara sin confirmar que el UUID esta disponible." ;;
        es_ES:uuid_validate_denied) printf '%s' "RSM no permitio validar el UUID" ;;
        es_ES:response) printf '%s' "Respuesta" ;;
        es_ES:invalid_uuid_rsm) printf '%s' "UUID invalido: no existe en RSM." ;;
        es_ES:uuid_not_generated) printf '%s' "El agente no se puede instalar con un UUID que no se haya generado desde Add New System." ;;
        es_ES:uuid_reserved) printf '%s' "UUID reservado en RSM y disponible para la instalacion" ;;
        es_ES:uuid_same_system) printf '%s' "UUID ya asociado con este sistema en RSM; el agente se reactivara y el inventario se actualizara" ;;
        es_ES:uuid_other_system) printf '%s' "Este UUID ya pertenece a otro sistema en RSM." ;;
        es_ES:uuid_other_system_local) printf '%s' "Este agente no se puede instalar en la maquina local con ese UUID." ;;
        es_ES:local_installed_same_uuid) printf '%s' "Este sistema ya tiene un agente instalado con este UUID." ;;
        es_ES:existing_agent) printf '%s' "Ya existe una instalacion del agente en este sistema." ;;
        es_ES:uninstall_current) printf '%s' "Para instalar un agente nuevo, desinstala primero el actual:" ;;
        es_ES:config_saving) printf '%s' "Guardando configuracion local del agente..." ;;
        es_ES:config_saved) printf '%s' "Configuracion guardada" ;;
        es_ES:running_initial) printf '%s' "Ejecutando recoleccion inicial..." ;;
        es_ES:inventory_ok) printf '%s' "Inventario generado correctamente" ;;
        es_ES:initial_failed) printf '%s' "No se pudo generar y enviar el inventario durante la ejecucion inicial" ;;
        es_ES:failure_details) printf '%s' "Los detalles del fallo se mostraron arriba." ;;
        es_ES:install_completed) printf '%s' "INSTALACION COMPLETADA" ;;
        es_ES:locations) printf '%s' "Ubicaciones:" ;;
        es_ES:execution) printf '%s' "Ejecucion:" ;;
        es_ES:automatic) printf '%s' "Automatica" ;;
        es_ES:manual) printf '%s' "Manual" ;;
        es_ES:current_alias) printf '%s' "Valor actual" ;;
        es_ES:uninstall) printf '%s' "Desinstalar:" ;;
        es_ES:no_interactive_privileged) printf '%s' "No hay ningun terminal interactivo disponible para solicitar acceso privilegiado." ;;
        es_ES:privileged_needed) printf '%s' "Esta accion necesita acceso privilegiado." ;;
        es_ES:trying_su) printf '%s' "Intentando obtener root con su. su pedira la contrasena de root y requiere que el inicio de sesion root este permitido." ;;
        es_ES:su_failed) printf '%s' "La accion privilegiada no se pudo completar con su/root." ;;
        es_ES:su_missing) printf '%s' "su no esta disponible, asi que no se puede solicitar acceso root desde este usuario." ;;
        es_ES:privileged_not_completed) printf '%s' "La accion privilegiada no se ha completado. Ejecuta el instalador como root y elige modo sin root, o ejecuta el comando requerido desde una sesion root." ;;
        es_ES:preparing_systemd_user_privileged) printf '%s' "Preparando systemd --user con acceso privilegiado..." ;;
        es_ES:no_interactive_cron_default) printf '%s' "No se ha detectado terminal interactivo; se usara cron de usuario por defecto." ;;
        es_ES:automatic_execution_setup) printf '%s' "Configuracion de ejecucion automatica:" ;;
        es_ES:scheduler_cron_title) printf '%s' "1) Cron de usuario" ;;
        es_ES:scheduler_cron_plus) printf '%s' "+ No requiere root para ejecutar el agente y no depende de una sesion de usuario activa." ;;
        es_ES:scheduler_cron_minus) printf '%s' "- Requiere cron/crontab instalado, activo y permitido. Si no, se intentara instalar/activar y necesitara acceso privilegiado." ;;
        es_ES:scheduler_systemd_title) printf '%s' "2) systemd --user" ;;
        es_ES:scheduler_systemd_plus) printf '%s' "+ Mejor integracion con systemd y systemctl --user." ;;
        es_ES:scheduler_systemd_minus) printf '%s' "- Requiere linger para ejecutarse sin una sesion activa. Si no esta activo, se habilitara y necesitara acceso privilegiado." ;;
        es_ES:scheduler_prompt) printf '%s' "Elige programador [1=cron, 2=systemd-user] (1): " ;;
        es_ES:unknown_scheduler) printf '%s' "Programador desconocido" ;;
        es_ES:scheduler_usage) printf '%s' "Usa 1/cron o 2/systemd-user." ;;
        es_ES:distribution) printf '%s' "Distribucion" ;;
        es_ES:checking_dependencies) printf '%s' "Comprobando dependencias..." ;;
        es_ES:curl_missing) printf '%s' "curl no esta instalado" ;;
        es_ES:curl_found) printf '%s' "curl encontrado" ;;
        es_ES:bash_required) printf '%s' "Se requiere bash 4 o superior" ;;
        es_ES:bash_found) printf '%s' "bash encontrado" ;;
        es_ES:flock_missing_install) printf '%s' "flock no esta instalado (normalmente lo proporciona el paquete util-linux)" ;;
        es_ES:flock_found) printf '%s' "flock encontrado" ;;
        es_ES:mktemp_missing_install) printf '%s' "mktemp no esta instalado" ;;
        es_ES:mktemp_found) printf '%s' "mktemp encontrado" ;;
        es_ES:invalid_uuid_local) printf '%s' "no es un UUID valido" ;;
        es_ES:rsm_item_missing) printf '%s' "No se pudo localizar el item de RSM asociado al UUID." ;;
        es_ES:rsm_status_safety) printf '%s' "Por seguridad, la instalacion no continuara sin poder actualizar el estado." ;;
        es_ES:root_existing) printf '%s' "Se ha encontrado una instalacion root existente en /opt/rs-agent o /var/lib/rs-agent." ;;
        es_ES:root_coexist) printf '%s' "La instalacion sin root coexistira con ella usando rutas del usuario actual." ;;
        es_ES:test_uuid_alias) printf '%s' "Para comparar, usa un UUID/alias de prueba separado." ;;
        es_ES:current_installed_uuid) printf '%s' "UUID instalado actualmente" ;;
        es_ES:requested_uuid) printf '%s' "UUID solicitado" ;;
        es_ES:update_rsm_missing_uuid) printf '%s' "No se pudo actualizar RSM porque no se encontro el item del UUID." ;;
        es_ES:marking_active) printf '%s' "Marcando sistema como activo en Firulai..." ;;
        es_ES:activate_failed) printf '%s' "No se pudo activar el sistema en RSM" ;;
        es_ES:activation_denied) printf '%s' "RSM no permitio activar el sistema" ;;
        es_ES:activated) printf '%s' "Sistema marcado como activo en Firulai" ;;
        es_ES:cron_install_unknown) printf '%s' "No se pudo determinar como instalar cron automaticamente en esta distribucion." ;;
        es_ES:cron_install_manual) printf '%s' "Instala cron manualmente o contacta con Firulai." ;;
        es_ES:cron_missing) printf '%s' "cron/crontab no esta instalado." ;;
        es_ES:cron_install_prompt) printf '%s' "Quieres que instalemos cron ahora? Esto necesita acceso privilegiado." ;;
        es_ES:cron_without_crontab) printf '%s' "No se puede continuar con cron sin crontab." ;;
        es_ES:installing_cron) printf '%s' "Intentando instalar cron con acceso privilegiado..." ;;
        es_ES:cron_enable_unknown) printf '%s' "No se pudo determinar como habilitar cron automaticamente en esta distribucion." ;;
        es_ES:cron_enable_manual) printf '%s' "Habilita cron manualmente o contacta con Firulai." ;;
        es_ES:cron_inactive) printf '%s' "cron/crond no parece estar activo." ;;
        es_ES:cron_enable_prompt) printf '%s' "Quieres que lo habilitemos ahora? Esto necesita acceso privilegiado." ;;
        es_ES:cron_daemon_required) printf '%s' "No se puede continuar con cron si el demonio no esta activo." ;;
        es_ES:enabling_cron) printf '%s' "Intentando habilitar cron con acceso privilegiado..." ;;
        es_ES:crontab_unavailable) printf '%s' "No se pudo dejar crontab disponible. Contacta con Firulai si necesitas ayuda." ;;
        es_ES:crontab_forbidden_1) printf '%s' "El usuario actual no puede gestionar su crontab." ;;
        es_ES:crontab_forbidden_2) printf '%s' "Un administrador debe permitir crontabs para este usuario y revisar las politicas de cron." ;;
        es_ES:crontab_forbidden_3) printf '%s' "Esto puede requerir acceso privilegiado. Contacta con Firulai si necesitas ayuda." ;;
        es_ES:cron_active_confirm_failed) printf '%s' "No se pudo confirmar que cron este activo. Contacta con Firulai si necesitas ayuda." ;;
        es_ES:systemd_user_unavailable) printf '%s' "systemd --user aun no esta disponible para este usuario/sesion." ;;
        es_ES:systemd_bus_su) printf '%s' "Esto puede ocurrir tras cambiar de usuario con su porque el bus systemd del usuario no se ha iniciado." ;;
        es_ES:systemd_prepare_prompt) printf '%s' "Quieres que preparemos systemd --user ahora? Esto necesita acceso privilegiado." ;;
        es_ES:systemd_no_bus) printf '%s' "No se puede continuar con systemd --user sin un bus systemd de usuario." ;;
        es_ES:systemd_choose_alternative) printf '%s' "Puedes ejecutar el instalador desde root y elegir modo sin root, elegir cron de usuario o contactar con Firulai." ;;
        es_ES:systemd_prepare_failed) printf '%s' "No se pudo preparar systemd --user para" ;;
        es_ES:linger_disabled) printf '%s' "linger no esta habilitado para" ;;
        es_ES:systemd_linger_unreliable) printf '%s' "systemd --user no sera fiable sin una sesion activa hasta habilitar linger." ;;
        es_ES:linger_enable_prompt) printf '%s' "Quieres que habilitemos linger ahora? Esto necesita acceso privilegiado." ;;
        es_ES:systemd_no_linger) printf '%s' "No se puede continuar con systemd --user sin linger." ;;
        es_ES:systemd_choose_cron) printf '%s' "Puedes elegir cron de usuario o contactar con Firulai." ;;
        es_ES:enabling_linger) printf '%s' "Intentando habilitar linger con acceso privilegiado..." ;;
        es_ES:linger_enable_failed) printf '%s' "No se pudo habilitar linger para" ;;
        es_ES:contact_firulai) printf '%s' "Contacta con Firulai si necesitas ayuda." ;;
        es_ES:checking_systemd_user) printf '%s' "Comprobando requisitos de systemd --user..." ;;
        es_ES:checking_cron_auto) printf '%s' "Comprobando requisitos de cron para la ejecucion automatica..." ;;
        es_ES:cleanup_partial) printf '%s' "Limpiando instalacion parcial..." ;;
        es_ES:partial_removed) printf '%s' "Instalacion parcial eliminada" ;;
        es_ES:creating_dirs) printf '%s' "Creando directorios..." ;;
        es_ES:dirs_created) printf '%s' "Directorios creados" ;;
        es_ES:downloading_agent) printf '%s' "Descargando agente desde GitHub..." ;;
        es_ES:agent_downloaded) printf '%s' "Agente descargado" ;;
        es_ES:download_agent_failed) printf '%s' "No se pudo descargar el agente desde GitHub" ;;
        es_ES:attempted_url) printf '%s' "URL intentada" ;;
        es_ES:check_that) printf '%s' "Comprueba que:" ;;
        es_ES:internet_connectivity) printf '%s' "Tienes conectividad a internet" ;;
        es_ES:github_accessible) printf '%s' "GitHub es accesible desde este servidor" ;;
        es_ES:downloading_runner) printf '%s' "Descargando runner de ejecucion automatica..." ;;
        es_ES:runner_downloaded) printf '%s' "Runner descargado" ;;
        es_ES:download_failed) printf '%s' "No se pudo descargar" ;;
        es_ES:downloading_uninstaller) printf '%s' "Descargando desinstalador desde GitHub..." ;;
        es_ES:uninstaller_downloaded) printf '%s' "Desinstalador descargado" ;;
        es_ES:uninstall_download_failed) printf '%s' "No se pudo descargar el desinstalador desde GitHub" ;;
        es_ES:configuring_auto) printf '%s' "Configurando ejecucion automatica..." ;;
        es_ES:systemd_reload_failed) printf '%s' "systemd no pudo recargar las unidades" ;;
        es_ES:systemd_enable_failed) printf '%s' "systemd no pudo habilitar rs-agent.timer" ;;
        es_ES:systemd_timer_configured) printf '%s' "Timer systemd configurado a las 03:00 con recuperacion al arrancar" ;;
        es_ES:systemd_linger_available_warn) printf '%s' "systemd --user esta disponible, pero linger no esta habilitado para el usuario actual." ;;
        es_ES:user_cron_fallback_session) printf '%s' "Se usara cron de usuario para no depender de una sesion activa." ;;
        es_ES:systemd_user_timer_configured) printf '%s' "Timer systemd --user configurado a las 03:00" ;;
        es_ES:systemd_user_enable_failed) printf '%s' "No se pudo habilitar systemd --user." ;;
        es_ES:systemd_user_try_cron) printf '%s' "No se pudo habilitar systemd --user; se intentara usar cron de usuario." ;;
        es_ES:auto_config_failed) printf '%s' "No se puede completar la instalacion con ejecucion automatica." ;;
        es_ES:root_crontab_failed) printf '%s' "No se pudo actualizar el crontab de root" ;;
        es_ES:user_crontab_failed) printf '%s' "No se pudo actualizar el crontab del usuario actual" ;;
        es_ES:root_cron_configured) printf '%s' "Cron root configurado con ejecucion diaria y recuperacion automatica" ;;
        es_ES:user_cron_configured) printf '%s' "Cron de usuario configurado con ejecucion diaria y recuperacion automatica" ;;
        es_ES:daily_at) printf '%s' "Diaria a las 03:00" ;;
        es_ES:recovery) printf '%s' "Recuperacion" ;;
        es_ES:recovery_detail) printf '%s' "una ejecucion pendiente cuando el sistema vuelve a estar operativo" ;;
        es_ES:alias_title) printf '%s' "Alias:" ;;
        es_ES:alias_saved) printf '%s' "Este alias se guarda en Firulai y puede modificarse desde la interfaz." ;;
        es_ES:view_inventory) printf '%s' "Ver inventario:" ;;
        es_ES:behavior_title) printf '%s' "Comportamiento:" ;;
        es_ES:no_python_jq) printf '%s' "Sin dependencia de Python ni jq (bash puro)" ;;
        es_ES:sends_complete) printf '%s' "Envia un inventario completo a RSM en cada ejecucion" ;;
        es_ES:rsm_manages_changes) printf '%s' "RSM detecta y gestiona los cambios" ;;
        es_ES:includes) printf '%s' "Incluye: SO, kernel, CPU, modelos de disco, paquetes y software critico" ;;
        es_ES:install_cancelled_initial) printf '%s' "Instalacion cancelada porque la primera ejecucion del agente ha fallado." ;;
        es_ES:uuid_conflict_hint) printf '%s' "Si el UUID ya pertenece a otro sistema, genera un nuevo UUID desde Add New System." ;;
        es_ES:auto_execution_config_failed) printf '%s' "No se pudo configurar la ejecucion automatica" ;;
        es_ES:install_success) printf '%s' "Instalacion correcta" ;;

        ca_ES:banner_subtitle) printf '%s' "Agent d'analisi del sistema per a deteccio de vulnerabilitats" ;;
        ca_ES:root_mode) printf '%s' "Mode d'instal.lacio root/sistema seleccionat; s'usaran rutes del sistema." ;;
        ca_ES:user_mode) printf '%s' "Mode d'instal.lacio sense root seleccionat; l'agent s'instal.lara nomes per a l'usuari actual." ;;
        ca_ES:less_complete) printf '%s' "L'inventari pot ser menys complet que en mode root si el sistema restringeix algunes ordres." ;;
        ca_ES:alias_needed) printf '%s' "Aquest instal.lador necessita un alias per identificar el sistema a Firulai." ;;
        ca_ES:alias_prompt) printf '%s' "Alias del sistema: " ;;
        ca_ES:alias_required) printf '%s' "L'alias del sistema es obligatori." ;;
        ca_ES:alias_usage) printf '%s' "Executa l'instal.lador amb l'opcio --alias:" ;;
        ca_ES:alias_quotes) printf '%s' "Si l'alias conte espais, posa'l entre cometes." ;;
        ca_ES:validating_uuid) printf '%s' "Validant UUID a RSM..." ;;
        ca_ES:uuid_validate_failed) printf '%s' "No s'ha pogut validar l'UUID a RSM" ;;
        ca_ES:uuid_validate_safety) printf '%s' "Per seguretat, la instal.lacio no continuara sense confirmar que l'UUID esta disponible." ;;
        ca_ES:uuid_validate_denied) printf '%s' "RSM no ha permes validar l'UUID" ;;
        ca_ES:response) printf '%s' "Resposta" ;;
        ca_ES:invalid_uuid_rsm) printf '%s' "UUID no valid: no existeix a RSM." ;;
        ca_ES:uuid_not_generated) printf '%s' "L'agent no es pot instal.lar amb un UUID que no s'hagi generat des d'Add New System." ;;
        ca_ES:uuid_reserved) printf '%s' "UUID reservat a RSM i disponible per a la instal.lacio" ;;
        ca_ES:uuid_same_system) printf '%s' "UUID ja associat amb aquest sistema a RSM; l'agent es reactivara i l'inventari s'actualitzara" ;;
        ca_ES:uuid_other_system) printf '%s' "Aquest UUID ja pertany a un altre sistema a RSM." ;;
        ca_ES:uuid_other_system_local) printf '%s' "Aquest agent no es pot instal.lar a la maquina local amb aquest UUID." ;;
        ca_ES:local_installed_same_uuid) printf '%s' "Aquest sistema ja te un agent instal.lat amb aquest UUID." ;;
        ca_ES:existing_agent) printf '%s' "Ja existeix una instal.lacio de l'agent en aquest sistema." ;;
        ca_ES:uninstall_current) printf '%s' "Per instal.lar un agent nou, desinstal.la primer l'actual:" ;;
        ca_ES:config_saving) printf '%s' "Desant la configuracio local de l'agent..." ;;
        ca_ES:config_saved) printf '%s' "Configuracio desada" ;;
        ca_ES:running_initial) printf '%s' "Executant recol.leccio inicial..." ;;
        ca_ES:inventory_ok) printf '%s' "Inventari generat correctament" ;;
        ca_ES:initial_failed) printf '%s' "No s'ha pogut generar i enviar l'inventari durant l'execucio inicial" ;;
        ca_ES:failure_details) printf '%s' "Els detalls de l'error s'han mostrat a dalt." ;;
        ca_ES:install_completed) printf '%s' "INSTAL.LACIO COMPLETADA" ;;
        ca_ES:locations) printf '%s' "Ubicacions:" ;;
        ca_ES:execution) printf '%s' "Execucio:" ;;
        ca_ES:automatic) printf '%s' "Automatica" ;;
        ca_ES:manual) printf '%s' "Manual" ;;
        ca_ES:current_alias) printf '%s' "Valor actual" ;;
        ca_ES:uninstall) printf '%s' "Desinstal.lar:" ;;
        ca_ES:no_interactive_cron_default) printf '%s' "No s'ha detectat cap terminal interactiu; s'usara cron d'usuari per defecte." ;;
        ca_ES:automatic_execution_setup) printf '%s' "Configuracio d'execucio automatica:" ;;
        ca_ES:scheduler_cron_title) printf '%s' "1) Cron d'usuari" ;;
        ca_ES:scheduler_cron_plus) printf '%s' "+ No requereix root per executar l'agent i no depen d'una sessio d'usuari activa." ;;
        ca_ES:scheduler_cron_minus) printf '%s' "- Requereix cron/crontab instal.lat, actiu i permes. Si no, s'intentara instal.lar/activar i caldra acces privilegiat." ;;
        ca_ES:scheduler_systemd_title) printf '%s' "2) systemd --user" ;;
        ca_ES:scheduler_systemd_plus) printf '%s' "+ Millor integracio amb systemd i systemctl --user." ;;
        ca_ES:scheduler_systemd_minus) printf '%s' "- Requereix linger per executar-se sense una sessio activa. Si no esta actiu, s'habilitara i caldra acces privilegiat." ;;
        ca_ES:scheduler_prompt) printf '%s' "Tria programador [1=cron, 2=systemd-user] (1): " ;;
        ca_ES:unknown_scheduler) printf '%s' "Programador desconegut" ;;
        ca_ES:scheduler_usage) printf '%s' "Usa 1/cron o 2/systemd-user." ;;
        ca_ES:distribution) printf '%s' "Distribucio" ;;
        ca_ES:checking_dependencies) printf '%s' "Comprovant dependencies..." ;;
        ca_ES:curl_missing) printf '%s' "curl no esta instal.lat" ;;
        ca_ES:curl_found) printf '%s' "curl trobat" ;;
        ca_ES:bash_required) printf '%s' "Cal bash 4 o superior" ;;
        ca_ES:bash_found) printf '%s' "bash trobat" ;;
        ca_ES:flock_missing_install) printf '%s' "flock no esta instal.lat (normalment el proporciona el paquet util-linux)" ;;
        ca_ES:flock_found) printf '%s' "flock trobat" ;;
        ca_ES:mktemp_missing_install) printf '%s' "mktemp no esta instal.lat" ;;
        ca_ES:mktemp_found) printf '%s' "mktemp trobat" ;;
        ca_ES:invalid_uuid_local) printf '%s' "no es un UUID valid" ;;
        es_ES:installer_title) printf '%s' "Instalador" ;;
        es_ES:private_dir_failed) printf '%s' "No se pudo crear un directorio privado seguro" ;;
        es_ES:unsafe_owner) printf '%s' "Directorio inseguro: no es propiedad del usuario actual" ;;
        es_ES:unsafe_symlink) printf '%s' "Ruta insegura: es un enlace simbólico" ;;
        ca_ES:activate_failed) printf '%s' "No s'ha pogut activar el sistema a RSM" ;;
        ca_ES:activated) printf '%s' "Sistema marcat com a actiu a Firulai" ;;
        ca_ES:activation_denied) printf '%s' "RSM no permetia l'activació del sistema" ;;
        ca_ES:agent_downloaded) printf '%s' "Agent descarregat" ;;
        ca_ES:alias_saved) printf '%s' "Aquest àlies es desa a Firulai i es pot canviar des de la interfície." ;;
        ca_ES:alias_title) printf '%s' "Àlies:" ;;
        ca_ES:attempted_url) printf '%s' "URL intentat" ;;
        ca_ES:auto_config_failed) printf '%s' "No es pot completar la instal·lació amb l'execució automàtica." ;;
        ca_ES:auto_execution_config_failed) printf '%s' "No s'ha pogut configurar l'execució automàtica" ;;
        ca_ES:behavior_title) printf '%s' "Comportament:" ;;
        ca_ES:check_that) printf '%s' "Comproveu que:" ;;
        ca_ES:checking_cron_auto) printf '%s' "S'estan comprovant els requisits de cron per a l'execució automàtica..." ;;
        ca_ES:checking_systemd_user) printf '%s' "S'estan comprovant els requisits de systemd --user..." ;;
        ca_ES:cleanup_partial) printf '%s' "Neteja de la instal·lació parcial..." ;;
        ca_ES:configuring_auto) printf '%s' "Configurant l'execució automàtica..." ;;
        ca_ES:contact_firulai) printf '%s' "Contacta amb Firulai si necessites ajuda." ;;
        ca_ES:creating_dirs) printf '%s' "S'estan creant directoris..." ;;
        ca_ES:cron_active_confirm_failed) printf '%s' "No s'ha pogut confirmar que cron estigui actiu. Contacta amb Firulai si necessites ajuda." ;;
        ca_ES:cron_daemon_required) printf '%s' "No es pot continuar amb cron si el dimoni no està actiu." ;;
        ca_ES:cron_enable_manual) printf '%s' "Habiliteu cron manualment o contacteu amb Firulai." ;;
        ca_ES:cron_enable_prompt) printf '%s' "Voleu que l'activem ara? Això necessita un accés privilegiat." ;;
        ca_ES:cron_enable_unknown) printf '%s' "No s'ha pogut determinar com habilitar cron automàticament en aquesta distribució." ;;
        ca_ES:cron_inactive) printf '%s' "cron/crond no sembla estar actiu." ;;
        ca_ES:cron_install_manual) printf '%s' "Instal·leu cron manualment o poseu-vos en contacte amb Firulai." ;;
        ca_ES:cron_install_prompt) printf '%s' "Voleu que instal·lem cron ara? Això necessita un accés privilegiat." ;;
        ca_ES:cron_install_unknown) printf '%s' "No s'ha pogut determinar com instal·lar cron automàticament en aquesta distribució." ;;
        ca_ES:cron_missing) printf '%s' "cron/crontab no està instal·lat." ;;
        ca_ES:cron_without_crontab) printf '%s' "No es pot continuar amb cron sense crontab." ;;
        ca_ES:crontab_forbidden_1) printf '%s' "L'usuari actual no pot gestionar el seu crontab." ;;
        ca_ES:crontab_forbidden_2) printf '%s' "Un administrador ha de permetre crontabs per a aquest usuari i revisar les polítiques de cron." ;;
        ca_ES:crontab_forbidden_3) printf '%s' "Això pot requerir un accés privilegiat. Contacta amb Firulai si necessites ajuda." ;;
        ca_ES:crontab_unavailable) printf '%s' "No s'ha pogut fer que crontab estigui disponible. Contacta amb Firulai si necessites ajuda." ;;
        ca_ES:current_installed_uuid) printf '%s' "UUID instal·lat actualment" ;;
        ca_ES:daily_at) printf '%s' "Cada dia a les 3:00 h" ;;
        ca_ES:dirs_created) printf '%s' "Directoris creats" ;;
        ca_ES:download_agent_failed) printf '%s' "No s'ha pogut descarregar l'agent de GitHub" ;;
        ca_ES:download_failed) printf '%s' "No s'ha pogut descarregar" ;;
        ca_ES:downloading_agent) printf '%s' "S'està baixant l'agent de GitHub..." ;;
        ca_ES:downloading_runner) printf '%s' "S'està baixant el runner d'execució automàtica..." ;;
        ca_ES:downloading_uninstaller) printf '%s' "S'està baixant el desinstal·lador de GitHub..." ;;
        ca_ES:enabling_cron) printf '%s' "S'està intentant habilitar cron amb accés privilegiat..." ;;
        ca_ES:enabling_linger) printf '%s' "S'està intentant habilitar la permanència amb accés privilegiat..." ;;
        ca_ES:github_accessible) printf '%s' "GitHub és accessible des d'aquest servidor" ;;
        ca_ES:includes) printf '%s' "Inclou: sistema operatiu, nucli, CPU, models de disc, paquets, programari crític" ;;
        ca_ES:install_cancelled_initial) printf '%s' "La instal·lació s'ha cancel·lat perquè l'execució inicial de l'agent ha fallat." ;;
        ca_ES:install_success) printf '%s' "Instal·lació correcta" ;;
        ca_ES:installer_title) printf '%s' "Instal·lador" ;;
        ca_ES:installing_cron) printf '%s' "S'està intentant instal·lar cron amb accés privilegiat..." ;;
        ca_ES:internet_connectivity) printf '%s' "Tens connexió a Internet" ;;
        ca_ES:linger_disabled) printf '%s' "Linger no està habilitat" ;;
        ca_ES:linger_enable_failed) printf '%s' "No s'ha pogut activar la permanència" ;;
        ca_ES:linger_enable_prompt) printf '%s' "Voleu que habilitem Linger ara? Això necessita un accés privilegiat." ;;
        ca_ES:marking_active) printf '%s' "Marcant el sistema com a actiu a Firulai..." ;;
        ca_ES:no_interactive_privileged) printf '%s' "No hi ha cap terminal interactiu disponible per sol·licitar accés privilegiat." ;;
        ca_ES:no_python_jq) printf '%s' "Sense dependència de Python o jq (bash pur)" ;;
        ca_ES:partial_removed) printf '%s' "S'ha eliminat parcialment la instal·lació" ;;
        ca_ES:private_dir_failed) printf '%s' "No s'ha pogut crear un directori privat segur" ;;
        ca_ES:privileged_needed) printf '%s' "Aquesta acció necessita accés privilegiat." ;;
        ca_ES:privileged_not_completed) printf '%s' "L'acció privilegiada no s'ha completat. Executa l'instal·lador com a root i tria el mode sense root, o executa l'ordre requerit des d'una sessió root." ;;
        ca_ES:recovery) printf '%s' "Recuperació" ;;
        ca_ES:recovery_detail) printf '%s' "una execució pendent quan el sistema torni a estar operatiu" ;;
        ca_ES:requested_uuid) printf '%s' "UUID sol·licitat" ;;
        ca_ES:root_coexist) printf '%s' "La instal·lació sense root coexistirà amb ella utilitzant les rutes de l'usuari actual." ;;
        ca_ES:root_cron_configured) printf '%s' "Cron de root configurat amb execució diària i recuperació automàtica" ;;
        ca_ES:root_crontab_failed) printf '%s' "No s'ha pogut actualitzar el crontab root" ;;
        ca_ES:root_existing) printf '%s' "S'ha trobat una instal·lació arrel existent a /opt/rs-agent o /var/lib/rs-agent." ;;
        ca_ES:rsm_item_missing) printf '%s' "No s'ha pogut localitzar l'element RSM associat a l'UUID." ;;
        ca_ES:rsm_manages_changes) printf '%s' "RSM detecta i gestiona els canvis" ;;
        ca_ES:rsm_status_safety) printf '%s' "Per seguretat, la instal·lació no continuarà sense poder actualitzar l'estat." ;;
        ca_ES:runner_downloaded) printf '%s' "Runner descarregat" ;;
        ca_ES:sends_complete) printf '%s' "Envia un inventari complet a RSM en cada execució" ;;
        ca_ES:su_failed) printf '%s' "L'acció privilegiada no s'ha pogut completar amb su/root." ;;
        ca_ES:su_missing) printf '%s' "su no s'ha trobat, de manera que no es pot sol·licitar accés root a aquest usuari." ;;
        ca_ES:systemd_bus_su) printf '%s' "Això pot passar després de canviar d'usuari amb su perquè el bus systemd de l'usuari no s'inicia." ;;
        ca_ES:systemd_choose_alternative) printf '%s' "Pots executar l'instal·lador des de root i triar el mode sense root, triar cron d'usuari o contactar amb Firulai." ;;
        ca_ES:systemd_choose_cron) printf '%s' "Pots triar cron d'usuari o contactar amb Firulai." ;;
        ca_ES:systemd_enable_failed) printf '%s' "systemd no ha pogut habilitar rs-agent.timer" ;;
        ca_ES:systemd_linger_available_warn) printf '%s' "systemd --user està disponible, però linger no està habilitat per a l'usuari actual." ;;
        ca_ES:systemd_linger_unreliable) printf '%s' "systemd --user no serà fiable sense una sessió activa fins que linger estigui habilitat." ;;
        ca_ES:systemd_no_bus) printf '%s' "No es pot continuar amb systemd --user sense un bus systemd d'usuari." ;;
        ca_ES:systemd_no_linger) printf '%s' "No es pot continuar amb systemd --user sense linger." ;;
        ca_ES:systemd_prepare_failed) printf '%s' "No s'ha pogut preparar systemd --user per" ;;
        ca_ES:systemd_prepare_prompt) printf '%s' "Voleu que preparem systemd --user ara? Això necessita un accés privilegiat." ;;
        ca_ES:systemd_reload_failed) printf '%s' "systemd no ha pogut recarregar les unitats" ;;
        ca_ES:systemd_timer_configured) printf '%s' "Temporitzador systemd configurat a les 03:00 amb recuperació en arrencar" ;;
        ca_ES:systemd_user_enable_failed) printf '%s' "No s'ha pogut habilitar systemd --user." ;;
        ca_ES:systemd_user_timer_configured) printf '%s' "systemd --user timer configurat a les 03:00" ;;
        ca_ES:systemd_user_try_cron) printf '%s' "No s'ha pogut habilitar systemd --user; En lloc d'això, es provarà el cron de l'usuari." ;;
        ca_ES:systemd_user_unavailable) printf '%s' "systemd --user encara no està disponible per a aquest usuari/sessió." ;;
        ca_ES:test_uuid_alias) printf '%s' "Per comparar, utilitzeu un UUID/àlies de prova independent." ;;
        ca_ES:trying_su) printf '%s' "Provant root mitjançant su. su demana la contrasenya d'arrel i requereix que es permeti l'inici de sessió." ;;
        ca_ES:uninstall_download_failed) printf '%s' "No s'ha pogut descarregar el desinstal·lador de GitHub" ;;
        ca_ES:uninstaller_downloaded) printf '%s' "Desinstal·lador baixat" ;;
        ca_ES:unsafe_owner) printf '%s' "Directori no segur: no és propietat de l'usuari actual" ;;
        ca_ES:unsafe_symlink) printf '%s' "Camí no segur: és un enllaç simbòlic" ;;
        ca_ES:update_rsm_missing_uuid) printf '%s' "No s'ha pogut actualitzar RSM perquè no s'ha trobat l'element UUID." ;;
        ca_ES:user_cron_configured) printf '%s' "Cron d'usuari configurat amb execució diària i recuperació automàtica" ;;
        ca_ES:user_cron_fallback_session) printf '%s' "S'utilitzarà el cron de l'usuari per evitar dependre d'una sessió activa." ;;
        ca_ES:user_crontab_failed) printf '%s' "No s'ha pogut actualitzar el crontab de l'usuari actual" ;;
        ca_ES:uuid_conflict_hint) printf '%s' "Si l'UUID ja pertany a un altre sistema, genereu un nou UUID des de Add New System." ;;
        ca_ES:view_inventory) printf '%s' "Veure l'inventari:" ;;
        eu_ES:activate_failed) printf '%s' "Ezin izan da sistema aktibatu RSMn" ;;
        eu_ES:activated) printf '%s' "Firulai-n aktibo gisa markatutako sistema" ;;
        eu_ES:activation_denied) printf '%s' "RSM-k ez zuen sistema aktibatzea onartzen" ;;
        eu_ES:agent_downloaded) printf '%s' "Agentea deskargatu da" ;;
        eu_ES:alias_needed) printf '%s' "Instalatzaile honek alias bat behar du Firulai-n sistema identifikatzeko." ;;
        eu_ES:alias_prompt) printf '%s' "Sistemaren ezizena: " ;;
        eu_ES:alias_quotes) printf '%s' "Aliasak zuriuneak baditu, jarri komatxo artean." ;;
        eu_ES:alias_required) printf '%s' "Sistemaren aliasa beharrezkoa da." ;;
        eu_ES:alias_saved) printf '%s' "Alias ​​hau Firulai-n gordetzen da eta interfazetik alda daiteke." ;;
        eu_ES:alias_title) printf '%s' "Ezizena:" ;;
        eu_ES:alias_usage) printf '%s' "Exekutatu instalatzailea --alias aukerarekin:" ;;
        eu_ES:attempted_url) printf '%s' "URL saiakera" ;;
        eu_ES:auto_config_failed) printf '%s' "Ezin da osatu instalazioa exekuzio automatikoarekin." ;;
        eu_ES:auto_execution_config_failed) printf '%s' "Ezin izan da exekuzio automatikoa konfiguratu" ;;
        eu_ES:automatic) printf '%s' "Automatikoa" ;;
        eu_ES:automatic_execution_setup) printf '%s' "Exekuzio automatikoaren konfigurazioa:" ;;
        eu_ES:banner_subtitle) printf '%s' "Ahultasunak hautemateko sistemaren analisiaren agentea" ;;
        eu_ES:bash_found) printf '%s' "bash aurkitu" ;;
        eu_ES:bash_required) printf '%s' "bash 4 edo handiagoa behar da" ;;
        eu_ES:behavior_title) printf '%s' "Portaera:" ;;
        eu_ES:check_that) printf '%s' "Egiaztatu hori:" ;;
        eu_ES:checking_cron_auto) printf '%s' "Exekuzio automatikorako cron baldintzak egiaztatzen..." ;;
        eu_ES:checking_dependencies) printf '%s' "Mendekotasunak egiaztatzen..." ;;
        eu_ES:checking_systemd_user) printf '%s' "systemd --erabiltzaileen eskakizunak egiaztatzen..." ;;
        eu_ES:cleanup_partial) printf '%s' "Instalazio partziala garbitzen..." ;;
        eu_ES:config_saved) printf '%s' "Konfigurazioa gorde da" ;;
        eu_ES:config_saving) printf '%s' "Agente lokalaren konfigurazioa gordetzen..." ;;
        eu_ES:configuring_auto) printf '%s' "Exekuzio automatikoa konfiguratzen..." ;;
        eu_ES:contact_firulai) printf '%s' "Jarri harremanetan Firulairekin laguntza behar baduzu." ;;
        eu_ES:creating_dirs) printf '%s' "Direktorioak sortzen..." ;;
        eu_ES:cron_active_confirm_failed) printf '%s' "Ezin izan da berretsi cron aktibo dagoela. Jarri harremanetan Firulairekin laguntza behar baduzu." ;;
        eu_ES:cron_daemon_required) printf '%s' "Ezin da cron-ekin jarraitu deabrua aktibo ez badago." ;;
        eu_ES:cron_enable_manual) printf '%s' "Gaitu cron eskuz edo jarri harremanetan Firulairekin." ;;
        eu_ES:cron_enable_prompt) printf '%s' "Orain gaitzea nahi duzu? Honek sarbide pribilegiatua behar du." ;;
        eu_ES:cron_enable_unknown) printf '%s' "Ezin izan da zehaztu nola gaitu automatikoki cron banaketa honetan." ;;
        eu_ES:cron_inactive) printf '%s' "cron/crond ez dirudi aktibo dagoenik." ;;
        eu_ES:cron_install_manual) printf '%s' "Instalatu cron eskuz edo jarri harremanetan Firulairekin." ;;
        eu_ES:cron_install_prompt) printf '%s' "Cron instalatzea nahi duzu orain? Honek sarbide pribilegiatua behar du." ;;
        eu_ES:cron_install_unknown) printf '%s' "Ezin izan da zehaztu nola instalatu automatikoki cron banaketa honetan." ;;
        eu_ES:cron_missing) printf '%s' "cron/crontab ez dago instalatuta." ;;
        eu_ES:cron_without_crontab) printf '%s' "Ezin da cron-ekin jarraitu crontab gabe." ;;
        eu_ES:crontab_forbidden_1) printf '%s' "Uneko erabiltzaileak ezin du bere crontab kudeatu." ;;
        eu_ES:crontab_forbidden_2) printf '%s' "Administratzaile batek crontab-ak baimendu behar ditu erabiltzaile honentzat eta cron politikak berrikusi." ;;
        eu_ES:crontab_forbidden_3) printf '%s' "Honek sarbide pribilegiatua eska dezake. Jarri harremanetan Firulairekin laguntza behar baduzu." ;;
        eu_ES:crontab_unavailable) printf '%s' "Ezin izan da crontab erabilgarri jarri. Jarri harremanetan Firulairekin laguntza behar baduzu." ;;
        eu_ES:curl_found) printf '%s' "kizkur aurkitu" ;;
        eu_ES:curl_missing) printf '%s' "curl ez dago instalatuta" ;;
        eu_ES:current_alias) printf '%s' "Egungo balioa" ;;
        eu_ES:current_installed_uuid) printf '%s' "Une honetan instalatuta dagoen UUID" ;;
        eu_ES:daily_at) printf '%s' "Egunero goizeko 3:00etan" ;;
        eu_ES:dirs_created) printf '%s' "Sortutako direktorioak" ;;
        eu_ES:distribution) printf '%s' "Banaketa" ;;
        eu_ES:download_agent_failed) printf '%s' "Ezin izan da agentea deskargatu GitHub-etik" ;;
        eu_ES:download_failed) printf '%s' "Ezin izan da deskargatu" ;;
        eu_ES:downloading_agent) printf '%s' "Agentea GitHub-etik deskargatzen..." ;;
        eu_ES:downloading_runner) printf '%s' "Exekuzio automatikoaren korrikalaria deskargatzen..." ;;
        eu_ES:downloading_uninstaller) printf '%s' "Desinstalatzailea GitHub-etik deskargatzen..." ;;
        eu_ES:enabling_cron) printf '%s' "Sarbide pribilegiodun cron gaitzen saiatzen..." ;;
        eu_ES:enabling_linger) printf '%s' "Sarbide pribilegiatuarekin Linger gaitzen saiatzen..." ;;
        eu_ES:execution) printf '%s' "Exekuzioa:" ;;
        eu_ES:existing_agent) printf '%s' "Lehendik dagoen agente-instalazio bat aurkitu da sistema honetan." ;;
        eu_ES:failure_details) printf '%s' "Porrotaren xehetasunak goian erakutsi ziren." ;;
        eu_ES:flock_found) printf '%s' "artaldea aurkitu" ;;
        eu_ES:flock_missing_install) printf '%s' "flock ez dago instalatuta (normalean util-linux paketeak ematen du)" ;;
        eu_ES:github_accessible) printf '%s' "GitHub zerbitzari honetatik erabil daiteke" ;;
        eu_ES:includes) printf '%s' "barne hartzen ditu: OS, kernel, CPU, disko ereduak, paketeak, software kritikoa" ;;
        eu_ES:initial_failed) printf '%s' "Ezin izan da inbentarioa sortu eta bidali hasierako exekuzioan" ;;
        eu_ES:install_cancelled_initial) printf '%s' "Instalazioa bertan behera utzi da hasierako agentearen exekuzioak huts egin duelako." ;;
        eu_ES:install_completed) printf '%s' "INSTALAZIOA BUKATUTA" ;;
        eu_ES:install_success) printf '%s' "Instalazioa arrakastatsua da" ;;
        eu_ES:installer_title) printf '%s' "Instalatzailea" ;;
        eu_ES:installing_cron) printf '%s' "Cron sarbide pribilegiatuarekin instalatzen saiatzen..." ;;
        eu_ES:internet_connectivity) printf '%s' "Interneteko konexioa duzu" ;;
        eu_ES:invalid_uuid_local) printf '%s' "ez da baliozko UUID bat" ;;
        eu_ES:invalid_uuid_rsm) printf '%s' "UUID baliogabea: ez dago RSMn." ;;
        eu_ES:inventory_ok) printf '%s' "Inbentarioa behar bezala sortu da" ;;
        eu_ES:less_complete) printf '%s' "Baliteke inbentarioa erro moduan baino oso osoa izatea sistemak komando batzuk mugatzen baditu." ;;
        eu_ES:linger_disabled) printf '%s' "linger ez dago gaituta" ;;
        eu_ES:linger_enable_failed) printf '%s' "Ezin izan da etenaldia gaitu" ;;
        eu_ES:linger_enable_prompt) printf '%s' "Linger gaitzea nahi duzu orain? Honek sarbide pribilegiatua behar du." ;;
        eu_ES:local_installed_same_uuid) printf '%s' "Sistema honek dagoeneko instalatuta dauka agente bat UUID honekin." ;;
        eu_ES:locations) printf '%s' "Lekuak:" ;;
        eu_ES:manual) printf '%s' "Eskuliburua" ;;
        eu_ES:marking_active) printf '%s' "Firulai-n aktibo gisa markatzeko sistema..." ;;
        eu_ES:mktemp_found) printf '%s' "mktemp aurkitu" ;;
        eu_ES:mktemp_missing_install) printf '%s' "mktemp ez dago instalatuta" ;;
        eu_ES:no_interactive_cron_default) printf '%s' "Ez da terminal interaktiborik detektatu; erabiltzaile-cron erabiliko da lehenespenez." ;;
        eu_ES:no_interactive_privileged) printf '%s' "Ez dago terminal interaktiborik erabilgarri sarbide pribilegiatua eskatzeko." ;;
        eu_ES:no_python_jq) printf '%s' "Ez dago Python edo jq menpekotasunik (bash hutsa)" ;;
        eu_ES:partial_removed) printf '%s' "Instalazio partziala kendu da" ;;
        eu_ES:private_dir_failed) printf '%s' "Ezin izan da direktorio pribatu seguru bat sortu" ;;
        eu_ES:privileged_needed) printf '%s' "Ekintza honek sarbide pribilegiatua behar du." ;;
        eu_ES:privileged_not_completed) printf '%s' "Ekintza pribilegiatua ez zen amaitu. Exekutatu instalatzailea root gisa eta aukeratu errorik gabeko modua edo exekutatu behar den komandoa root saio batetik." ;;
        eu_ES:recovery) printf '%s' "Berreskuratzea" ;;
        eu_ES:recovery_detail) printf '%s' "sistema berriro martxan jartzen denean exekutatzeko zain dagoen bat" ;;
        eu_ES:requested_uuid) printf '%s' "UUID eskatua" ;;
        eu_ES:response) printf '%s' "Erantzuna" ;;
        eu_ES:root_coexist) printf '%s' "Errorik gabeko instalazioa berarekin batera biziko da uneko erabiltzailearen bideak erabiliz." ;;
        eu_ES:root_cron_configured) printf '%s' "Erro cron eguneroko exekuzioarekin eta berreskuratze automatikoarekin konfiguratuta" ;;
        eu_ES:root_crontab_failed) printf '%s' "Ezin izan da root crontab eguneratu" ;;
        eu_ES:root_existing) printf '%s' "Lehendik dagoen root instalazio bat aurkitu da /opt/rs-agent edo /var/lib/rs-agent-en." ;;
        eu_ES:root_mode) printf '%s' "Erro/sistemaren instalazio modua hautatuta; sistemaren bideak erabiliko dira." ;;
        eu_ES:rsm_item_missing) printf '%s' "Ezin izan da UUIDarekin lotutako RSM elementua aurkitu." ;;
        eu_ES:rsm_manages_changes) printf '%s' "RSM-k aldaketak hautematen eta kudeatzen ditu" ;;
        eu_ES:rsm_status_safety) printf '%s' "Segurtasunagatik, instalazioak ez du jarraituko egoera eguneratu gabe." ;;
        eu_ES:runner_downloaded) printf '%s' "Korrikalari deskargatu da" ;;
        eu_ES:running_initial) printf '%s' "Hasierako bilduma martxan..." ;;
        eu_ES:scheduler_cron_minus) printf '%s' "- Cron/crontab instalatuta, aktiboa eta baimenduta behar du. Hala ez bada, instalazioa/aktibazioa saiatuko da eta pribilegiozko sarbidea beharko du." ;;
        eu_ES:scheduler_cron_plus) printf '%s' "+ Ez du root behar agentea exekutatzeko eta ez dago erabiltzailearen saio aktibo baten menpe." ;;
        eu_ES:scheduler_cron_title) printf '%s' "1) Erabiltzailearen cron" ;;
        eu_ES:scheduler_prompt) printf '%s' "Aukeratu programatzailea [1=cron, 2=systemd-user] (1): " ;;
        eu_ES:scheduler_systemd_minus) printf '%s' "- Saio aktiborik gabe korrika egiteko irautea eskatzen du. Aktibo ez badago, gaituta egongo da eta pribilegiozko sarbidea beharko du." ;;
        eu_ES:scheduler_systemd_plus) printf '%s' "+ Integrazio hobea systemd eta systemctl --user-ekin." ;;
        eu_ES:scheduler_systemd_title) printf '%s' "2) systemd --user" ;;
        eu_ES:scheduler_usage) printf '%s' "Erabili 1/cron edo 2/systemd-user." ;;
        eu_ES:sends_complete) printf '%s' "Inbentario osoa bidaltzen du RSM-ra korrika bakoitzean" ;;
        eu_ES:su_failed) printf '%s' "Ekintza pribilegiatua ezin izan da su/root-ekin osatu." ;;
        eu_ES:su_missing) printf '%s' "su ez da aurkitu, beraz, ezin zaio erabiltzaile honi root sarbidea eskatu." ;;
        eu_ES:systemd_bus_su) printf '%s' "Hau erabiltzailea su-rekin aldatu ondoren gerta daiteke, erabiltzailearen systemd busa abiarazten ez delako." ;;
        eu_ES:systemd_choose_alternative) printf '%s' "Instalatzailea errotik exekutatu eta errorik gabeko modua aukeratu, erabiltzailea cron aukeratu edo Firulairekin harremanetan jarri." ;;
        eu_ES:systemd_choose_cron) printf '%s' "Erabiltzailearen cron aukeratu dezakezu edo Firulairekin harremanetan jarri." ;;
        eu_ES:systemd_enable_failed) printf '%s' "systemd-ek ezin izan du gaitu rs-agent.timer" ;;
        eu_ES:systemd_linger_available_warn) printf '%s' "systemd --user eskuragarri dago, baina linger ez dago gaituta uneko erabiltzailearentzat." ;;
        eu_ES:systemd_linger_unreliable) printf '%s' "systemd --user ez da fidagarria izango saio aktiborik gabe linger gaitu arte." ;;
        eu_ES:systemd_no_bus) printf '%s' "Ezin da systemd --user erabiltzailearekin systemd bus gabe jarraitu." ;;
        eu_ES:systemd_no_linger) printf '%s' "Ezin da systemd --user-ekin jarraitu linger gabe." ;;
        eu_ES:systemd_prepare_failed) printf '%s' "Ezin izan da prestatu systemd --user for" ;;
        eu_ES:systemd_prepare_prompt) printf '%s' "Systemd --user orain prestatzea nahi duzu? Honek sarbide pribilegiatua behar du." ;;
        eu_ES:systemd_reload_failed) printf '%s' "systemd-ek ezin izan ditu unitateak birkargatu" ;;
        eu_ES:systemd_timer_configured) printf '%s' "systemd tenporizadorea 03:00etan konfiguratuta abiaraztearen berreskurapenarekin" ;;
        eu_ES:systemd_user_enable_failed) printf '%s' "Ezin izan da systemd --user gaitu." ;;
        eu_ES:systemd_user_timer_configured) printf '%s' "systemd --user tenporizadorea 03:00etan konfiguratuta" ;;
        eu_ES:systemd_user_try_cron) printf '%s' "Ezin izan da gaitu systemd --user; erabiltzailea cron saiatuko da horren ordez." ;;
        eu_ES:systemd_user_unavailable) printf '%s' "systemd --user ez dago erabilgarri erabiltzaile/saio honetarako oraindik." ;;
        eu_ES:test_uuid_alias) printf '%s' "Konparatzeko, erabili probaren UUID/alias bereizi bat." ;;
        eu_ES:trying_su) printf '%s' "Su bidez errotzen saiatzen. su root pasahitza eskatzen du eta root saioa baimentzea eskatzen du." ;;
        eu_ES:uninstall) printf '%s' "Desinstalatu:" ;;
        eu_ES:uninstall_current) printf '%s' "Agente berri bat instalatzeko, desinstalatu oraingoa lehenik:" ;;
        eu_ES:uninstall_download_failed) printf '%s' "Ezin izan da desinstalatzailea deskargatu GitHub-etik" ;;
        eu_ES:uninstaller_downloaded) printf '%s' "Desinstalatzailea deskargatu da" ;;
        eu_ES:unknown_scheduler) printf '%s' "Antolatzaile ezezaguna" ;;
        eu_ES:unsafe_owner) printf '%s' "Direktorio ez segurua: ez da uneko erabiltzailearen jabetzakoa" ;;
        eu_ES:unsafe_symlink) printf '%s' "Bide ez-segurua: lotura sinbolikoa da" ;;
        eu_ES:update_rsm_missing_uuid) printf '%s' "Ezin izan da RSM eguneratu UUID elementua ez delako aurkitu." ;;
        eu_ES:user_cron_configured) printf '%s' "Erabiltzailearen cron eguneroko exekuzioarekin eta berreskuratze automatikoarekin konfiguratuta" ;;
        eu_ES:user_cron_fallback_session) printf '%s' "Erabiltzailearen cron-a erabiliko da saio aktibo baten arabera ez egoteko." ;;
        eu_ES:user_crontab_failed) printf '%s' "Ezin izan da uneko erabiltzailearen crontab eguneratu" ;;
        eu_ES:user_mode) printf '%s' "Errorik gabeko instalazio modua hautatuta; agentea uneko erabiltzailearentzat bakarrik instalatuko da." ;;
        eu_ES:uuid_conflict_hint) printf '%s' "UUID dagoeneko beste sistema batekoa bada, sortu UUID berri bat Gehitu sistema berria-tik." ;;
        eu_ES:uuid_not_generated) printf '%s' "Agentea ezin da Gehitu Sistema Berritik sortu ez den UUID batekin instalatu." ;;
        eu_ES:uuid_other_system) printf '%s' "UUID hau RSMko beste sistema batekoa da jada." ;;
        eu_ES:uuid_other_system_local) printf '%s' "Agente hau ezin da instalatu UUID horrekin makina lokalean." ;;
        eu_ES:uuid_reserved) printf '%s' "UUID RSMn gordeta dago eta instalatzeko eskuragarri" ;;
        eu_ES:uuid_same_system) printf '%s' "Sistema honekin dagoeneko lotuta dagoen UUID RSMn; agentea berriro aktibatu eta inbentarioa eguneratuko da" ;;
        eu_ES:uuid_validate_denied) printf '%s' "RSM-k ez du baimendu UUID baliozkotzea" ;;
        eu_ES:uuid_validate_failed) printf '%s' "Ezin izan da UUID balioztatu RSMn" ;;
        eu_ES:uuid_validate_safety) printf '%s' "Segurtasunagatik, instalazioak ez du jarraituko UUID eskuragarri dagoela baieztatu gabe." ;;
        eu_ES:validating_uuid) printf '%s' "UUID RSM-n balioztatzen..." ;;
        eu_ES:view_inventory) printf '%s' "Ikusi inbentarioa:" ;;
        gl_ES:activate_failed) printf '%s' "Non se puido activar o sistema en RSM" ;;
        gl_ES:activated) printf '%s' "Sistema marcado como activo en Firulai" ;;
        gl_ES:activation_denied) printf '%s' "RSM non permitiu a activación do sistema" ;;
        gl_ES:agent_downloaded) printf '%s' "Axente descargado" ;;
        gl_ES:alias_needed) printf '%s' "Este instalador necesita un alias para identificar o sistema en Firulai." ;;
        gl_ES:alias_prompt) printf '%s' "Alias do sistema: " ;;
        gl_ES:alias_quotes) printf '%s' "Se o alias contén espazos, engádeo entre comiñas." ;;
        gl_ES:alias_required) printf '%s' "O alias do sistema é necesario." ;;
        gl_ES:alias_saved) printf '%s' "Este alias gárdase en Firulai e pódese cambiar desde a interface." ;;
        gl_ES:alias_title) printf '%s' "Alias:" ;;
        gl_ES:alias_usage) printf '%s' "Executa o instalador coa opción --alias:" ;;
        gl_ES:attempted_url) printf '%s' "URL tentativa" ;;
        gl_ES:auto_config_failed) printf '%s' "Non se pode completar a instalación coa execución automática." ;;
        gl_ES:auto_execution_config_failed) printf '%s' "Non se puido configurar a execución automática" ;;
        gl_ES:automatic) printf '%s' "Automático" ;;
        gl_ES:automatic_execution_setup) printf '%s' "Configuración de execución automática:" ;;
        gl_ES:banner_subtitle) printf '%s' "Axente de análise do sistema para a detección de vulnerabilidades" ;;
        gl_ES:bash_found) printf '%s' "bash atopado" ;;
        gl_ES:bash_required) printf '%s' "requírese bash 4 ou superior" ;;
        gl_ES:behavior_title) printf '%s' "Comportamento:" ;;
        gl_ES:check_that) printf '%s' "Comproba que:" ;;
        gl_ES:checking_cron_auto) printf '%s' "Comprobando os requisitos cron para a execución automática..." ;;
        gl_ES:checking_dependencies) printf '%s' "Comprobando dependencias..." ;;
        gl_ES:checking_systemd_user) printf '%s' "Comprobando systemd --requisitos do usuario..." ;;
        gl_ES:cleanup_partial) printf '%s' "Limpeza parcial instalación..." ;;
        gl_ES:config_saved) printf '%s' "Configuración gardada" ;;
        gl_ES:config_saving) printf '%s' "Gardando a configuración do axente local..." ;;
        gl_ES:configuring_auto) printf '%s' "Configurando a execución automática..." ;;
        gl_ES:contact_firulai) printf '%s' "Contacta con Firulai se necesitas axuda." ;;
        gl_ES:creating_dirs) printf '%s' "Creando directorios..." ;;
        gl_ES:cron_active_confirm_failed) printf '%s' "Non se puido confirmar que cron estea activo. Contacta con Firulai se necesitas axuda." ;;
        gl_ES:cron_daemon_required) printf '%s' "Non se pode continuar con cron se o daemon non está activo." ;;
        gl_ES:cron_enable_manual) printf '%s' "Habilita cron manualmente ou ponte en contacto con Firulai." ;;
        gl_ES:cron_enable_prompt) printf '%s' "Queres que o activemos agora? Isto precisa de acceso privilexiado." ;;
        gl_ES:cron_enable_unknown) printf '%s' "Non se puido determinar como activar cron automaticamente nesta distribución." ;;
        gl_ES:cron_inactive) printf '%s' "cron/crond non parece estar activo." ;;
        gl_ES:cron_install_manual) printf '%s' "Instala cron manualmente ou ponte en contacto con Firulai." ;;
        gl_ES:cron_install_prompt) printf '%s' "Queres que instalemos cron agora? Isto precisa de acceso privilexiado." ;;
        gl_ES:cron_install_unknown) printf '%s' "Non se puido determinar como instalar cron automaticamente nesta distribución." ;;
        gl_ES:cron_missing) printf '%s' "cron/crontab non está instalado." ;;
        gl_ES:cron_without_crontab) printf '%s' "Non se pode continuar con cron sen crontab." ;;
        gl_ES:crontab_forbidden_1) printf '%s' "O usuario actual non pode xestionar o seu crontab." ;;
        gl_ES:crontab_forbidden_2) printf '%s' "Un administrador debe permitir crontabs para este usuario e revisar as políticas cron." ;;
        gl_ES:crontab_forbidden_3) printf '%s' "Isto pode requirir acceso privilexiado. Contacta con Firulai se necesitas axuda." ;;
        gl_ES:crontab_unavailable) printf '%s' "Non se puido facer que crontab estea dispoñible. Contacta con Firulai se necesitas axuda." ;;
        gl_ES:curl_found) printf '%s' "rizo atopado" ;;
        gl_ES:curl_missing) printf '%s' "curl non está instalado" ;;
        gl_ES:current_alias) printf '%s' "Valor actual" ;;
        gl_ES:current_installed_uuid) printf '%s' "UUID instalado actualmente" ;;
        gl_ES:daily_at) printf '%s' "Diariamente ás 3:00 AM" ;;
        gl_ES:dirs_created) printf '%s' "Directorios creados" ;;
        gl_ES:distribution) printf '%s' "Distribución" ;;
        gl_ES:download_agent_failed) printf '%s' "Non se puido descargar o axente de GitHub" ;;
        gl_ES:download_failed) printf '%s' "Non se puido descargar" ;;
        gl_ES:downloading_agent) printf '%s' "Descargando o axente de GitHub..." ;;
        gl_ES:downloading_runner) printf '%s' "Descargando o corredor de execución automática..." ;;
        gl_ES:downloading_uninstaller) printf '%s' "Descargando o desinstalador de GitHub..." ;;
        gl_ES:enabling_cron) printf '%s' "Tentando habilitar cron con acceso privilexiado..." ;;
        gl_ES:enabling_linger) printf '%s' "Tentando habilitar Linger con acceso privilexiado..." ;;
        gl_ES:execution) printf '%s' "Execución:" ;;
        gl_ES:existing_agent) printf '%s' "Atopouse unha instalación de axente existente neste sistema." ;;
        gl_ES:failure_details) printf '%s' "Os detalles dos fallos mostráronse arriba." ;;
        gl_ES:flock_found) printf '%s' "rabaño atopado" ;;
        gl_ES:flock_missing_install) printf '%s' "flock non está instalado (normalmente proporcionado polo paquete util-linux)" ;;
        gl_ES:github_accessible) printf '%s' "GitHub é accesible desde este servidor" ;;
        gl_ES:includes) printf '%s' "Inclúe: SO, kernel, CPU, modelos de disco, paquetes, software crítico" ;;
        gl_ES:initial_failed) printf '%s' "Non se puido xerar nin enviar o inventario durante a execución inicial" ;;
        gl_ES:install_cancelled_initial) printf '%s' "A instalación cancelouse porque fallou a execución do axente inicial." ;;
        gl_ES:install_completed) printf '%s' "INSTALACIÓN COMPLETADA" ;;
        gl_ES:install_success) printf '%s' "Instalación exitosa" ;;
        gl_ES:installer_title) printf '%s' "Instalador" ;;
        gl_ES:installing_cron) printf '%s' "Intentando instalar cron con acceso privilexiado..." ;;
        gl_ES:internet_connectivity) printf '%s' "Tes conectividade a internet" ;;
        gl_ES:invalid_uuid_local) printf '%s' "non é un UUID válido" ;;
        gl_ES:invalid_uuid_rsm) printf '%s' "UUID non válido: non existe en RSM." ;;
        gl_ES:inventory_ok) printf '%s' "Inventario xerado correctamente" ;;
        gl_ES:less_complete) printf '%s' "O inventario pode estar menos completo que o modo root se o sistema restrinxe algúns comandos." ;;
        gl_ES:linger_disabled) printf '%s' "Linger non está habilitado para" ;;
        gl_ES:linger_enable_failed) printf '%s' "Non se puido activar a permanencia" ;;
        gl_ES:linger_enable_prompt) printf '%s' "Queres que activemos Linger agora? Isto precisa de acceso privilexiado." ;;
        gl_ES:local_installed_same_uuid) printf '%s' "Este sistema xa ten un axente instalado con este UUID." ;;
        gl_ES:locations) printf '%s' "Lugares:" ;;
        gl_ES:manual) printf '%s' "Manual" ;;
        gl_ES:marking_active) printf '%s' "Sistema de marcado como activo en Firulai..." ;;
        gl_ES:mktemp_found) printf '%s' "mktemp atopado" ;;
        gl_ES:mktemp_missing_install) printf '%s' "mktemp non está instalado" ;;
        gl_ES:no_interactive_cron_default) printf '%s' "Non se detectou ningún terminal interactivo; o usuario cron empregarase por defecto." ;;
        gl_ES:no_interactive_privileged) printf '%s' "Non hai ningún terminal interactivo dispoñible para solicitar acceso privilexiado." ;;
        gl_ES:no_python_jq) printf '%s' "Sen dependencia de Python ou jq (bash puro)" ;;
        gl_ES:partial_removed) printf '%s' "Instalación parcial eliminada" ;;
        gl_ES:private_dir_failed) printf '%s' "Non se puido crear un directorio privado seguro" ;;
        gl_ES:privileged_needed) printf '%s' "Esta acción necesita acceso privilexiado." ;;
        gl_ES:privileged_not_completed) printf '%s' "A acción privilexiada non se completou. Executa o instalador como root e escolla o modo sen root ou executa o comando necesario desde unha sesión root." ;;
        gl_ES:recovery) printf '%s' "Recuperación" ;;
        gl_ES:recovery_detail) printf '%s' "unha pendente de execución cando o sistema volva estar operativo" ;;
        gl_ES:requested_uuid) printf '%s' "UUID solicitado" ;;
        gl_ES:response) printf '%s' "Resposta" ;;
        gl_ES:root_coexist) printf '%s' "A instalación sen root coexistirá con ela utilizando as rutas do usuario actual." ;;
        gl_ES:root_cron_configured) printf '%s' "Root cron configurado con execución diaria e recuperación automática" ;;
        gl_ES:root_crontab_failed) printf '%s' "Non se puido actualizar o root crontab" ;;
        gl_ES:root_existing) printf '%s' "Atopouse unha instalación raíz existente en /opt/rs-agent ou /var/lib/rs-agent." ;;
        gl_ES:root_mode) printf '%s' "Modo de instalación raíz/sistema seleccionado; utilizaranse as rutas do sistema." ;;
        gl_ES:rsm_item_missing) printf '%s' "Non se puido localizar o elemento RSM asociado co UUID." ;;
        gl_ES:rsm_manages_changes) printf '%s' "RSM detecta e xestiona os cambios" ;;
        gl_ES:rsm_status_safety) printf '%s' "Por seguridade, a instalación non continuará sen poder actualizar o estado." ;;
        gl_ES:runner_downloaded) printf '%s' "Runner descargado" ;;
        gl_ES:running_initial) printf '%s' "En execución a colección inicial..." ;;
        gl_ES:scheduler_cron_minus) printf '%s' "- Require cron/crontab instalado, activo e permitido. Se non, tentarase a instalación/activación e necesitará acceso privilexiado." ;;
        gl_ES:scheduler_cron_plus) printf '%s' "+ Non require root para a execución do axente e non depende dunha sesión de usuario activa." ;;
        gl_ES:scheduler_cron_title) printf '%s' "1) Usuario cron" ;;
        gl_ES:scheduler_prompt) printf '%s' "Escolla planificador [1=cron, 2=usuario-systemd] (1): " ;;
        gl_ES:scheduler_systemd_minus) printf '%s' "- Require demora para correr sen unha sesión activa. Se non está activo, habilitarase e necesitará acceso privilexiado." ;;
        gl_ES:scheduler_systemd_plus) printf '%s' "+ Mellor integración con systemd e systemctl --user." ;;
        gl_ES:scheduler_systemd_title) printf '%s' "2) systemd --usuario" ;;
        gl_ES:scheduler_usage) printf '%s' "Use 1/cron ou 2/systemd-user." ;;
        gl_ES:sends_complete) printf '%s' "Envía un inventario completo a RSM en cada carreira" ;;
        gl_ES:su_failed) printf '%s' "A acción privilexiada non se puido completar con su/root." ;;
        gl_ES:su_missing) printf '%s' "su non se atopou, polo que non se lle pode solicitar acceso root a este usuario." ;;
        gl_ES:systemd_bus_su) printf '%s' "Isto pode ocorrer despois de cambiar de usuario con su porque o bus systemd do usuario non se inicia." ;;
        gl_ES:systemd_choose_alternative) printf '%s' "Pode executar o instalador desde root e escoller o modo sen root, escoller o usuario cron ou contactar con Firulai." ;;
        gl_ES:systemd_choose_cron) printf '%s' "Podes escoller o usuario cron ou contactar con Firulai." ;;
        gl_ES:systemd_enable_failed) printf '%s' "systemd non puido activar rs-agent.timer" ;;
        gl_ES:systemd_linger_available_warn) printf '%s' "systemd --user está dispoñible, pero Linger non está habilitado para o usuario actual." ;;
        gl_ES:systemd_linger_unreliable) printf '%s' "systemd --user non será fiable sen unha sesión activa ata que linger estea habilitado." ;;
        gl_ES:systemd_no_bus) printf '%s' "Non se pode continuar con systemd --user sen un bus systemd do usuario." ;;
        gl_ES:systemd_no_linger) printf '%s' "Non se pode continuar con systemd --user sen esperar." ;;
        gl_ES:systemd_prepare_failed) printf '%s' "Non se puido preparar systemd --user para" ;;
        gl_ES:systemd_prepare_prompt) printf '%s' "Queres que preparemos systemd --user agora? Isto precisa de acceso privilexiado." ;;
        gl_ES:systemd_reload_failed) printf '%s' "systemd non puido recargar as unidades" ;;
        gl_ES:systemd_timer_configured) printf '%s' "temporizador systemd configurado ás 03:00 con recuperación de arranque" ;;
        gl_ES:systemd_user_enable_failed) printf '%s' "Non se puido activar systemd --user." ;;
        gl_ES:systemd_user_timer_configured) printf '%s' "systemd --temporizador de usuario configurado ás 03:00" ;;
        gl_ES:systemd_user_try_cron) printf '%s' "Non se puido activar systemd --user; no seu lugar probarase o cron do usuario." ;;
        gl_ES:systemd_user_unavailable) printf '%s' "systemd --user aínda non está dispoñible para este usuario/sesión." ;;
        gl_ES:test_uuid_alias) printf '%s' "Para comparación, use un UUID/alias de proba separado." ;;
        gl_ES:trying_su) printf '%s' "Probando root a través de su. su pide o contrasinal de root e require que se permita o inicio de sesión de root." ;;
        gl_ES:uninstall) printf '%s' "Desinstalar:" ;;
        gl_ES:uninstall_current) printf '%s' "Para instalar un novo axente, desinstale primeiro o actual:" ;;
        gl_ES:uninstall_download_failed) printf '%s' "Non se puido descargar o desinstalador de GitHub" ;;
        gl_ES:uninstaller_downloaded) printf '%s' "Desinstalador descargado" ;;
        gl_ES:unknown_scheduler) printf '%s' "Programador descoñecido" ;;
        gl_ES:unsafe_owner) printf '%s' "Directorio non seguro: non é propiedade do usuario actual" ;;
        gl_ES:unsafe_symlink) printf '%s' "Camiño inseguro: é un enlace simbólico" ;;
        gl_ES:update_rsm_missing_uuid) printf '%s' "Non se puido actualizar RSM porque non se atopou o elemento UUID." ;;
        gl_ES:user_cron_configured) printf '%s' "Cron do usuario configurado con execución diaria e recuperación automática" ;;
        gl_ES:user_cron_fallback_session) printf '%s' "Usarase o cron do usuario para evitar depender dunha sesión activa." ;;
        gl_ES:user_crontab_failed) printf '%s' "Non se puido actualizar o crontab do usuario actual" ;;
        gl_ES:user_mode) printf '%s' "Modo de instalación sen root seleccionado; o axente instalarase só para o usuario actual." ;;
        gl_ES:uuid_conflict_hint) printf '%s' "Se o UUID xa pertence a outro sistema, xera un novo UUID desde Engadir novo sistema." ;;
        gl_ES:uuid_not_generated) printf '%s' "Non se pode instalar o axente cun UUID que non se xerou desde Engadir novo sistema." ;;
        gl_ES:uuid_other_system) printf '%s' "Este UUID xa pertence a outro sistema en RSM." ;;
        gl_ES:uuid_other_system_local) printf '%s' "Este axente non se pode instalar na máquina local con ese UUID." ;;
        gl_ES:uuid_reserved) printf '%s' "UUID reservado en RSM e dispoñible para a instalación" ;;
        gl_ES:uuid_same_system) printf '%s' "UUID xa asociado a este sistema en RSM; reactivarase o axente e actualizarase o inventario" ;;
        gl_ES:uuid_validate_denied) printf '%s' "RSM non permitiu a validación UUID" ;;
        gl_ES:uuid_validate_failed) printf '%s' "Non se puido validar o UUID en RSM" ;;
        gl_ES:uuid_validate_safety) printf '%s' "Por seguridade, a instalación non continuará sen confirmar que o UUID está dispoñible." ;;
        gl_ES:validating_uuid) printf '%s' "Validando UUID en RSM..." ;;
        gl_ES:view_inventory) printf '%s' "Ver inventario:" ;;
        fr_FR:activate_failed) printf '%s' "Impossible d'activer le système dans RSM" ;;
        fr_FR:activated) printf '%s' "Système marqué comme actif à Firulai" ;;
        fr_FR:activation_denied) printf '%s' "RSM n'a pas autorisé l'activation du système" ;;
        fr_FR:agent_downloaded) printf '%s' "Agent téléchargé" ;;
        fr_FR:alias_needed) printf '%s' "Ce programme d'installation a besoin d'un alias pour identifier le système dans Firulai." ;;
        fr_FR:alias_prompt) printf '%s' "Alias système : " ;;
        fr_FR:alias_quotes) printf '%s' "Si l'alias contient des espaces, placez-le entre guillemets." ;;
        fr_FR:alias_required) printf '%s' "L'alias du système est requis." ;;
        fr_FR:alias_saved) printf '%s' "Cet alias est enregistré dans Firulai et peut être modifié depuis l'interface." ;;
        fr_FR:alias_title) printf '%s' "Alias:" ;;
        fr_FR:alias_usage) printf '%s' "Exécutez le programme d'installation avec l'option --alias :" ;;
        fr_FR:attempted_url) printf '%s' "Tentative d'URL" ;;
        fr_FR:auto_config_failed) printf '%s' "Impossible de terminer l'installation avec une exécution automatique." ;;
        fr_FR:auto_execution_config_failed) printf '%s' "Impossible de configurer l'exécution automatique" ;;
        fr_FR:automatic) printf '%s' "Automatique" ;;
        fr_FR:automatic_execution_setup) printf '%s' "Configuration de l'exécution automatique :" ;;
        fr_FR:banner_subtitle) printf '%s' "Agent d'analyse système pour la détection des vulnérabilités" ;;
        fr_FR:bash_found) printf '%s' "bash trouvé" ;;
        fr_FR:bash_required) printf '%s' "bash 4 ou supérieur est requis" ;;
        fr_FR:behavior_title) printf '%s' "Comportement:" ;;
        fr_FR:check_that) printf '%s' "Vérifiez que :" ;;
        fr_FR:checking_cron_auto) printf '%s' "Vérification des exigences cron pour l'exécution automatique..." ;;
        fr_FR:checking_dependencies) printf '%s' "Vérification des dépendances..." ;;
        fr_FR:checking_systemd_user) printf '%s' "Vérification des exigences systemd --user..." ;;
        fr_FR:cleanup_partial) printf '%s' "Nettoyage de l'installation partielle..." ;;
        fr_FR:config_saved) printf '%s' "Configuration enregistrée" ;;
        fr_FR:config_saving) printf '%s' "Enregistrement de la configuration de l'agent local..." ;;
        fr_FR:configuring_auto) printf '%s' "Configuration de l'exécution automatique..." ;;
        fr_FR:contact_firulai) printf '%s' "Contactez Firulai si vous avez besoin d'aide." ;;
        fr_FR:creating_dirs) printf '%s' "Création de répertoires..." ;;
        fr_FR:cron_active_confirm_failed) printf '%s' "Impossible de confirmer que cron est actif. Contactez Firulai si vous avez besoin d'aide." ;;
        fr_FR:cron_daemon_required) printf '%s' "Impossible de continuer avec cron si le démon n'est pas actif." ;;
        fr_FR:cron_enable_manual) printf '%s' "Activez cron manuellement ou contactez Firulai." ;;
        fr_FR:cron_enable_prompt) printf '%s' "Voulez-vous que nous l’activions maintenant ? Cela nécessite un accès privilégié." ;;
        fr_FR:cron_enable_unknown) printf '%s' "Impossible de déterminer comment activer automatiquement cron sur cette distribution." ;;
        fr_FR:cron_inactive) printf '%s' "cron/crond ne semble pas être actif." ;;
        fr_FR:cron_install_manual) printf '%s' "Installez cron manuellement ou contactez Firulai." ;;
        fr_FR:cron_install_prompt) printf '%s' "Voulez-vous que nous installions cron maintenant ? Cela nécessite un accès privilégié." ;;
        fr_FR:cron_install_unknown) printf '%s' "Impossible de déterminer comment installer automatiquement cron sur cette distribution." ;;
        fr_FR:cron_missing) printf '%s' "cron/crontab n'est pas installé." ;;
        fr_FR:cron_without_crontab) printf '%s' "Impossible de continuer avec cron sans crontab." ;;
        fr_FR:crontab_forbidden_1) printf '%s' "L'utilisateur actuel ne peut pas gérer sa crontab." ;;
        fr_FR:crontab_forbidden_2) printf '%s' "Un administrateur doit autoriser les crontabs pour cet utilisateur et revoir les politiques cron." ;;
        fr_FR:crontab_forbidden_3) printf '%s' "Cela peut nécessiter un accès privilégié. Contactez Firulai si vous avez besoin d'aide." ;;
        fr_FR:crontab_unavailable) printf '%s' "Impossible de rendre crontab disponible. Contactez Firulai si vous avez besoin d'aide." ;;
        fr_FR:curl_found) printf '%s' "boucle trouvée" ;;
        fr_FR:curl_missing) printf '%s' "curl n'est pas installé" ;;
        fr_FR:current_alias) printf '%s' "Valeur actuelle" ;;
        fr_FR:current_installed_uuid) printf '%s' "UUID actuellement installé" ;;
        fr_FR:daily_at) printf '%s' "Tous les jours à 3h00" ;;
        fr_FR:dirs_created) printf '%s' "Répertoires créés" ;;
        fr_FR:distribution) printf '%s' "Distribution" ;;
        fr_FR:download_agent_failed) printf '%s' "Impossible de télécharger l'agent depuis GitHub" ;;
        fr_FR:download_failed) printf '%s' "Impossible de télécharger" ;;
        fr_FR:downloading_agent) printf '%s' "Agent de téléchargement depuis GitHub..." ;;
        fr_FR:downloading_runner) printf '%s' "Téléchargement du programme d'exécution automatique..." ;;
        fr_FR:downloading_uninstaller) printf '%s' "Téléchargement du programme de désinstallation depuis GitHub..." ;;
        fr_FR:enabling_cron) printf '%s' "Tentative d'activer cron avec un accès privilégié..." ;;
        fr_FR:enabling_linger) printf '%s' "Tentative de permettre de s'attarder avec un accès privilégié..." ;;
        fr_FR:execution) printf '%s' "Exécution :" ;;
        fr_FR:existing_agent) printf '%s' "Une installation d'agent existante a été trouvée sur ce système." ;;
        fr_FR:failure_details) printf '%s' "Les détails de l’échec ont été indiqués ci-dessus." ;;
        fr_FR:flock_found) printf '%s' "troupeau trouvé" ;;
        fr_FR:flock_missing_install) printf '%s' "flock n'est pas installé (normalement fourni par le paquet util-linux)" ;;
        fr_FR:github_accessible) printf '%s' "GitHub est accessible depuis ce serveur" ;;
        fr_FR:includes) printf '%s' "Comprend : système d'exploitation, noyau, processeur, modèles de disques, packages, logiciels critiques" ;;
        fr_FR:initial_failed) printf '%s' "Impossible de générer et d'envoyer l'inventaire lors de l'exécution initiale" ;;
        fr_FR:install_cancelled_initial) printf '%s' "Installation annulée car l'exécution initiale de l'agent a échoué." ;;
        fr_FR:install_completed) printf '%s' "INSTALLATION TERMINÉE" ;;
        fr_FR:install_success) printf '%s' "Installation réussie" ;;
        fr_FR:installer_title) printf '%s' "Installateur" ;;
        fr_FR:installing_cron) printf '%s' "Tentative d'installation de cron avec un accès privilégié..." ;;
        fr_FR:internet_connectivity) printf '%s' "Vous disposez d'une connectivité Internet" ;;
        fr_FR:invalid_uuid_local) printf '%s' "n'est pas un UUID valide" ;;
        fr_FR:invalid_uuid_rsm) printf '%s' "UUID invalide : il n'existe pas dans RSM." ;;
        fr_FR:inventory_ok) printf '%s' "Inventaire généré avec succès" ;;
        fr_FR:less_complete) printf '%s' "L'inventaire peut être moins complet que le mode root si le système restreint certaines commandes." ;;
        fr_FR:linger_disabled) printf '%s' "linger n'est pas activé pour" ;;
        fr_FR:linger_enable_failed) printf '%s' "Impossible de s'attarder pendant" ;;
        fr_FR:linger_enable_prompt) printf '%s' "Voulez-vous que nous activions Linger maintenant ? Cela nécessite un accès privilégié." ;;
        fr_FR:local_installed_same_uuid) printf '%s' "Ce système dispose déjà d'un agent installé avec cet UUID." ;;
        fr_FR:locations) printf '%s' "Emplacements :" ;;
        fr_FR:manual) printf '%s' "Manuel" ;;
        fr_FR:marking_active) printf '%s' "Système de marquage comme actif à Firulai..." ;;
        fr_FR:mktemp_found) printf '%s' "mktemp trouvé" ;;
        fr_FR:mktemp_missing_install) printf '%s' "mktemp n'est pas installé" ;;
        fr_FR:no_interactive_cron_default) printf '%s' "Aucune borne interactive détectée ; l'utilisateur cron sera utilisé par défaut." ;;
        fr_FR:no_interactive_privileged) printf '%s' "Aucune borne interactive n'est disponible pour demander un accès privilégié." ;;
        fr_FR:no_python_jq) printf '%s' "Aucune dépendance Python ou jq (pur bash)" ;;
        fr_FR:partial_removed) printf '%s' "Installation partielle supprimée" ;;
        fr_FR:private_dir_failed) printf '%s' "Impossible de créer un répertoire privé sécurisé" ;;
        fr_FR:privileged_needed) printf '%s' "Cette action nécessite un accès privilégié." ;;
        fr_FR:privileged_not_completed) printf '%s' "L'action privilégiée n'a pas été achevée. Exécutez le programme d'installation en tant qu'utilisateur root et choisissez le mode sans root, ou exécutez la commande requise à partir d'une session root." ;;
        fr_FR:recovery) printf '%s' "Récupération" ;;
        fr_FR:recovery_detail) printf '%s' "une exécution en attente lorsque le système redeviendra opérationnel" ;;
        fr_FR:requested_uuid) printf '%s' "UUID demandé" ;;
        fr_FR:response) printf '%s' "Réponse" ;;
        fr_FR:root_coexist) printf '%s' "L'installation sans racine coexistera avec elle en utilisant les chemins de l'utilisateur actuel." ;;
        fr_FR:root_cron_configured) printf '%s' "Cron racine configuré avec exécution quotidienne et récupération automatique" ;;
        fr_FR:root_crontab_failed) printf '%s' "Impossible de mettre à jour la crontab racine" ;;
        fr_FR:root_existing) printf '%s' "Une installation racine existante a été trouvée dans /opt/rs-agent ou /var/lib/rs-agent." ;;
        fr_FR:root_mode) printf '%s' "Mode d'installation racine/système sélectionné ; les chemins du système seront utilisés." ;;
        fr_FR:rsm_item_missing) printf '%s' "Impossible de localiser l'élément RSM associé à l'UUID." ;;
        fr_FR:rsm_manages_changes) printf '%s' "RSM détecte et gère les changements" ;;
        fr_FR:rsm_status_safety) printf '%s' "Pour des raisons de sécurité, l'installation ne continuera pas sans pouvoir mettre à jour l'état." ;;
        fr_FR:runner_downloaded) printf '%s' "Coureur téléchargé" ;;
        fr_FR:running_initial) printf '%s' "Exécution de la collecte initiale..." ;;
        fr_FR:scheduler_cron_minus) printf '%s' "- Nécessite que cron/crontab soit installé, actif et autorisé. Dans le cas contraire, l'installation/activation sera tentée et nécessitera un accès privilégié." ;;
        fr_FR:scheduler_cron_plus) printf '%s' "+ Ne nécessite pas de root pour l'exécution de l'agent et ne dépend pas d'une session utilisateur active." ;;
        fr_FR:scheduler_cron_title) printf '%s' "1) Cron de l'utilisateur" ;;
        fr_FR:scheduler_prompt) printf '%s' "Choisissez le planificateur [1=cron, 2=systemd-user] (1): " ;;
        fr_FR:scheduler_systemd_minus) printf '%s' "- Nécessite de s'attarder pour s'exécuter sans session active. S'il n'est pas actif, il sera activé et nécessitera un accès privilégié." ;;
        fr_FR:scheduler_systemd_plus) printf '%s' "+ Meilleure intégration avec systemd et systemctl --user." ;;
        fr_FR:scheduler_systemd_title) printf '%s' "2) systemd --utilisateur" ;;
        fr_FR:scheduler_usage) printf '%s' "Utilisez 1/cron ou 2/systemd-user." ;;
        fr_FR:sends_complete) printf '%s' "Envoie un inventaire complet à RSM à chaque exécution" ;;
        fr_FR:su_failed) printf '%s' "L'action privilégiée n'a pas pu être complétée avec su/root." ;;
        fr_FR:su_missing) printf '%s' "su n'a pas été trouvé, l'accès root ne peut donc pas être demandé à cet utilisateur." ;;
        fr_FR:systemd_bus_su) printf '%s' "Cela peut se produire après avoir changé d'utilisateur avec su car le bus systemd de l'utilisateur n'est pas démarré." ;;
        fr_FR:systemd_choose_alternative) printf '%s' "Vous pouvez exécuter le programme d'installation à partir de root et choisir le mode sans root, choisir l'utilisateur cron ou contacter Firulai." ;;
        fr_FR:systemd_choose_cron) printf '%s' "Vous pouvez choisir l'utilisateur cron ou contacter Firulai." ;;
        fr_FR:systemd_enable_failed) printf '%s' "systemd n'a pas pu activer rs-agent.timer" ;;
        fr_FR:systemd_linger_available_warn) printf '%s' "systemd --user est disponible, mais Linger n'est pas activé pour l'utilisateur actuel." ;;
        fr_FR:systemd_linger_unreliable) printf '%s' "systemd --user ne sera pas fiable sans session active jusqu'à ce que Linger soit activé." ;;
        fr_FR:systemd_no_bus) printf '%s' "Impossible de continuer avec systemd --user sans bus systemd utilisateur." ;;
        fr_FR:systemd_no_linger) printf '%s' "Impossible de continuer avec systemd --user sans s'attarder." ;;
        fr_FR:systemd_prepare_failed) printf '%s' "Impossible de préparer systemd --user pour" ;;
        fr_FR:systemd_prepare_prompt) printf '%s' "Voulez-vous que nous préparions systemd --user maintenant ? Cela nécessite un accès privilégié." ;;
        fr_FR:systemd_reload_failed) printf '%s' "systemd n'a pas pu recharger les unités" ;;
        fr_FR:systemd_timer_configured) printf '%s' "minuterie systemd configurée à 03h00 avec récupération de démarrage" ;;
        fr_FR:systemd_user_enable_failed) printf '%s' "Impossible d'activer systemd --user." ;;
        fr_FR:systemd_user_timer_configured) printf '%s' "systemd --user timer configuré à 03h00" ;;
        fr_FR:systemd_user_try_cron) printf '%s' "Impossible d'activer systemd --user ; l'utilisateur cron sera essayé à la place." ;;
        fr_FR:systemd_user_unavailable) printf '%s' "systemd --user n'est pas encore disponible pour cet utilisateur/session." ;;
        fr_FR:test_uuid_alias) printf '%s' "À des fins de comparaison, utilisez un UUID/alias de test distinct." ;;
        fr_FR:trying_su) printf '%s' "Essayer de rooter via su. su demande le mot de passe root et nécessite que la connexion root soit autorisée." ;;
        fr_FR:uninstall) printf '%s' "Désinstaller :" ;;
        fr_FR:uninstall_current) printf '%s' "Pour installer un nouvel agent, désinstallez d'abord l'agent actuel :" ;;
        fr_FR:uninstall_download_failed) printf '%s' "Impossible de télécharger le programme de désinstallation depuis GitHub" ;;
        fr_FR:uninstaller_downloaded) printf '%s' "Programme de désinstallation téléchargé" ;;
        fr_FR:unknown_scheduler) printf '%s' "Planificateur inconnu" ;;
        fr_FR:unsafe_owner) printf '%s' "Répertoire non sécurisé : n'appartient pas à l'utilisateur actuel" ;;
        fr_FR:unsafe_symlink) printf '%s' "Chemin non sécurisé : est un lien symbolique" ;;
        fr_FR:update_rsm_missing_uuid) printf '%s' "Impossible de mettre à jour RSM car l'élément UUID est introuvable." ;;
        fr_FR:user_cron_configured) printf '%s' "Cron utilisateur configuré avec exécution quotidienne et récupération automatique" ;;
        fr_FR:user_cron_fallback_session) printf '%s' "Le cron de l'utilisateur sera utilisé pour éviter de dépendre d'une session active." ;;
        fr_FR:user_crontab_failed) printf '%s' "Impossible de mettre à jour la crontab de l'utilisateur actuel" ;;
        fr_FR:user_mode) printf '%s' "Mode d'installation sans racine sélectionné ; l'agent sera installé uniquement pour l'utilisateur actuel." ;;
        fr_FR:uuid_conflict_hint) printf '%s' "Si l'UUID appartient déjà à un autre système, générez un nouvel UUID à partir de Ajouter un nouveau système." ;;
        fr_FR:uuid_not_generated) printf '%s' "L'agent ne peut pas être installé avec un UUID qui n'a pas été généré à partir de l'ajout d'un nouveau système." ;;
        fr_FR:uuid_other_system) printf '%s' "Cet UUID appartient déjà à un autre système dans RSM." ;;
        fr_FR:uuid_other_system_local) printf '%s' "Cet agent ne peut pas être installé sur la machine locale avec cet UUID." ;;
        fr_FR:uuid_reserved) printf '%s' "UUID réservé dans RSM et disponible pour l'installation" ;;
        fr_FR:uuid_same_system) printf '%s' "UUID déjà associé à ce système dans RSM ; l'agent sera réactivé et l'inventaire mis à jour" ;;
        fr_FR:uuid_validate_denied) printf '%s' "RSM n'a pas autorisé la validation de l'UUID" ;;
        fr_FR:uuid_validate_failed) printf '%s' "Impossible de valider l'UUID dans RSM" ;;
        fr_FR:uuid_validate_safety) printf '%s' "Pour des raisons de sécurité, l'installation ne continuera pas sans confirmer que l'UUID est disponible." ;;
        fr_FR:validating_uuid) printf '%s' "Validation de l'UUID dans RSM..." ;;
        fr_FR:view_inventory) printf '%s' "Afficher l'inventaire :" ;;
        de_DE:activate_failed) printf '%s' "Das System konnte im RSM nicht aktiviert werden" ;;
        de_DE:activated) printf '%s' "System in Firulai als aktiv markiert" ;;
        de_DE:activation_denied) printf '%s' "RSM erlaubte keine Systemaktivierung" ;;
        de_DE:agent_downloaded) printf '%s' "Agent heruntergeladen" ;;
        de_DE:alias_needed) printf '%s' "Dieses Installationsprogramm benötigt einen Alias, um das System in Firulai zu identifizieren." ;;
        de_DE:alias_prompt) printf '%s' "Systemalias: " ;;
        de_DE:alias_quotes) printf '%s' "Wenn der Alias Leerzeichen enthält, schließen Sie ihn in Anführungszeichen ein." ;;
        de_DE:alias_required) printf '%s' "Systemalias ist erforderlich." ;;
        de_DE:alias_saved) printf '%s' "Dieser Alias ​​wird in Firulai gespeichert und kann über die Benutzeroberfläche geändert werden." ;;
        de_DE:alias_title) printf '%s' "Alias:" ;;
        de_DE:alias_usage) printf '%s' "Führen Sie das Installationsprogramm mit der Option --alias aus:" ;;
        de_DE:attempted_url) printf '%s' "Versuchte URL" ;;
        de_DE:auto_config_failed) printf '%s' "Die Installation kann nicht mit automatischer Ausführung abgeschlossen werden." ;;
        de_DE:auto_execution_config_failed) printf '%s' "Die automatische Ausführung konnte nicht konfiguriert werden" ;;
        de_DE:automatic) printf '%s' "Automatisch" ;;
        de_DE:automatic_execution_setup) printf '%s' "Einrichtung der automatischen Ausführung:" ;;
        de_DE:banner_subtitle) printf '%s' "Systemanalyse-Agent zur Erkennung von Schwachstellen" ;;
        de_DE:bash_found) printf '%s' "bash gefunden" ;;
        de_DE:bash_required) printf '%s' "Bash 4 oder höher ist erforderlich" ;;
        de_DE:behavior_title) printf '%s' "Verhalten:" ;;
        de_DE:check_that) printf '%s' "Überprüfen Sie Folgendes:" ;;
        de_DE:checking_cron_auto) printf '%s' "Cron-Anforderungen für die automatische Ausführung werden überprüft..." ;;
        de_DE:checking_dependencies) printf '%s' "Abhängigkeiten prüfen..." ;;
        de_DE:checking_systemd_user) printf '%s' "Systemd --user-Anforderungen werden überprüft ..." ;;
        de_DE:cleanup_partial) printf '%s' "Teilinstallation reinigen..." ;;
        de_DE:config_saved) printf '%s' "Konfiguration gespeichert" ;;
        de_DE:config_saving) printf '%s' "Konfiguration des lokalen Agenten wird gespeichert..." ;;
        de_DE:configuring_auto) printf '%s' "Automatische Ausführung konfigurieren..." ;;
        de_DE:contact_firulai) printf '%s' "Kontaktieren Sie Firulai, wenn Sie Hilfe benötigen." ;;
        de_DE:creating_dirs) printf '%s' "Verzeichnisse erstellen..." ;;
        de_DE:cron_active_confirm_failed) printf '%s' "Es konnte nicht bestätigt werden, dass Cron aktiv ist. Kontaktieren Sie Firulai, wenn Sie Hilfe benötigen." ;;
        de_DE:cron_daemon_required) printf '%s' "Cron kann nicht fortgesetzt werden, wenn der Daemon nicht aktiv ist." ;;
        de_DE:cron_enable_manual) printf '%s' "Aktivieren Sie Cron manuell oder wenden Sie sich an Firulai." ;;
        de_DE:cron_enable_prompt) printf '%s' "Möchten Sie, dass wir es jetzt aktivieren? Dies erfordert einen privilegierten Zugriff." ;;
        de_DE:cron_enable_unknown) printf '%s' "Es konnte nicht ermittelt werden, wie Cron auf dieser Distribution automatisch aktiviert werden kann." ;;
        de_DE:cron_inactive) printf '%s' "cron/crond scheint nicht aktiv zu sein." ;;
        de_DE:cron_install_manual) printf '%s' "Installieren Sie cron manuell oder wenden Sie sich an Firulai." ;;
        de_DE:cron_install_prompt) printf '%s' "Möchten Sie, dass wir cron jetzt installieren? Dies erfordert einen privilegierten Zugriff." ;;
        de_DE:cron_install_unknown) printf '%s' "Es konnte nicht ermittelt werden, wie cron auf dieser Distribution automatisch installiert wird." ;;
        de_DE:cron_missing) printf '%s' "cron/crontab ist nicht installiert." ;;
        de_DE:cron_without_crontab) printf '%s' "Ohne Crontab kann mit Cron nicht fortgefahren werden." ;;
        de_DE:crontab_forbidden_1) printf '%s' "Der aktuelle Benutzer kann seine Crontab nicht verwalten." ;;
        de_DE:crontab_forbidden_2) printf '%s' "Ein Administrator muss Crontabs für diesen Benutzer zulassen und die Cron-Richtlinien überprüfen." ;;
        de_DE:crontab_forbidden_3) printf '%s' "Dies erfordert möglicherweise einen privilegierten Zugriff. Kontaktieren Sie Firulai, wenn Sie Hilfe benötigen." ;;
        de_DE:crontab_unavailable) printf '%s' "Crontab konnte nicht verfügbar gemacht werden. Kontaktieren Sie Firulai, wenn Sie Hilfe benötigen." ;;
        de_DE:curl_found) printf '%s' "Curl gefunden" ;;
        de_DE:curl_missing) printf '%s' "Curl ist nicht installiert" ;;
        de_DE:current_alias) printf '%s' "Aktueller Wert" ;;
        de_DE:current_installed_uuid) printf '%s' "Derzeit installierte UUID" ;;
        de_DE:daily_at) printf '%s' "Täglich um 3:00 Uhr" ;;
        de_DE:dirs_created) printf '%s' "Verzeichnisse erstellt" ;;
        de_DE:distribution) printf '%s' "Verteilung" ;;
        de_DE:download_agent_failed) printf '%s' "Der Agent konnte nicht von GitHub heruntergeladen werden" ;;
        de_DE:download_failed) printf '%s' "Konnte nicht heruntergeladen werden" ;;
        de_DE:downloading_agent) printf '%s' "Agent wird von GitHub heruntergeladen..." ;;
        de_DE:downloading_runner) printf '%s' "Automatischer Ausführungs-Runner wird heruntergeladen..." ;;
        de_DE:downloading_uninstaller) printf '%s' "Deinstallationsprogramm von GitHub herunterladen..." ;;
        de_DE:enabling_cron) printf '%s' "Es wird versucht, Cron mit privilegiertem Zugriff zu aktivieren ..." ;;
        de_DE:enabling_linger) printf '%s' "Es wird versucht, das Verweilen mit privilegiertem Zugriff zu aktivieren ..." ;;
        de_DE:execution) printf '%s' "Ausführung:" ;;
        de_DE:existing_agent) printf '%s' "Auf diesem System wurde eine vorhandene Agenteninstallation gefunden." ;;
        de_DE:failure_details) printf '%s' "Die Fehlerdetails wurden oben angezeigt." ;;
        de_DE:flock_found) printf '%s' "Herde gefunden" ;;
        de_DE:flock_missing_install) printf '%s' "flock ist nicht installiert (normalerweise vom util-linux-Paket bereitgestellt)" ;;
        de_DE:github_accessible) printf '%s' "GitHub ist von diesem Server aus zugänglich" ;;
        de_DE:includes) printf '%s' "Beinhaltet: Betriebssystem, Kernel, CPU, Festplattenmodelle, Pakete, kritische Software" ;;
        de_DE:initial_failed) printf '%s' "Der Bestand konnte beim ersten Durchlauf nicht generiert und gesendet werden" ;;
        de_DE:install_cancelled_initial) printf '%s' "Die Installation wurde abgebrochen, da die erste Ausführung des Agenten fehlgeschlagen ist." ;;
        de_DE:install_completed) printf '%s' "INSTALLATION ABGESCHLOSSEN" ;;
        de_DE:install_success) printf '%s' "Installation erfolgreich" ;;
        de_DE:installer_title) printf '%s' "Installateur" ;;
        de_DE:installing_cron) printf '%s' "Es wird versucht, Cron mit privilegiertem Zugriff zu installieren ..." ;;
        de_DE:internet_connectivity) printf '%s' "Sie verfügen über eine Internetverbindung" ;;
        de_DE:invalid_uuid_local) printf '%s' "ist keine gültige UUID" ;;
        de_DE:invalid_uuid_rsm) printf '%s' "Ungültige UUID: Sie existiert nicht in RSM." ;;
        de_DE:inventory_ok) printf '%s' "Inventar wurde erfolgreich erstellt" ;;
        de_DE:less_complete) printf '%s' "Die Bestandsaufnahme ist möglicherweise weniger vollständig als im Root-Modus, wenn das System einige Befehle einschränkt." ;;
        de_DE:linger_disabled) printf '%s' "Verweilen ist nicht aktiviert" ;;
        de_DE:linger_enable_failed) printf '%s' "Verweildauer konnte nicht aktiviert werden" ;;
        de_DE:linger_enable_prompt) printf '%s' "Möchten Sie, dass wir das Verweilen jetzt aktivieren? Dies erfordert einen privilegierten Zugriff." ;;
        de_DE:local_installed_same_uuid) printf '%s' "Auf diesem System ist bereits ein Agent mit dieser UUID installiert." ;;
        de_DE:locations) printf '%s' "Standorte:" ;;
        de_DE:manual) printf '%s' "Handbuch" ;;
        de_DE:marking_active) printf '%s' "Kennzeichnungssystem als aktiv in Firulai..." ;;
        de_DE:mktemp_found) printf '%s' "mktemp gefunden" ;;
        de_DE:mktemp_missing_install) printf '%s' "mktemp ist nicht installiert" ;;
        de_DE:no_interactive_cron_default) printf '%s' "Kein interaktives Terminal erkannt; Der Benutzer cron wird standardmäßig verwendet." ;;
        de_DE:no_interactive_privileged) printf '%s' "Für die Anforderung eines privilegierten Zugangs steht kein interaktives Terminal zur Verfügung." ;;
        de_DE:no_python_jq) printf '%s' "Keine Python- oder JQ-Abhängigkeit (reine Bash)" ;;
        de_DE:partial_removed) printf '%s' "Teilinstallation entfernt" ;;
        de_DE:private_dir_failed) printf '%s' "Es konnte kein sicheres privates Verzeichnis erstellt werden" ;;
        de_DE:privileged_needed) printf '%s' "Für diese Aktion ist privilegierter Zugriff erforderlich." ;;
        de_DE:privileged_not_completed) printf '%s' "Die privilegierte Aktion wurde nicht abgeschlossen. Führen Sie das Installationsprogramm als Root aus und wählen Sie den No-Root-Modus oder führen Sie den erforderlichen Befehl in einer Root-Sitzung aus." ;;
        de_DE:recovery) printf '%s' "Erholung" ;;
        de_DE:recovery_detail) printf '%s' "Eine davon wartet auf die Ausführung, wenn das System wieder betriebsbereit ist" ;;
        de_DE:requested_uuid) printf '%s' "Angeforderte UUID" ;;
        de_DE:response) printf '%s' "Antwort" ;;
        de_DE:root_coexist) printf '%s' "Die No-Root-Installation wird mit ihr koexistieren und dabei die Pfade des aktuellen Benutzers verwenden." ;;
        de_DE:root_cron_configured) printf '%s' "Root-Cron mit täglicher Ausführung und automatischer Wiederherstellung konfiguriert" ;;
        de_DE:root_crontab_failed) printf '%s' "Root-Crontab konnte nicht aktualisiert werden" ;;
        de_DE:root_existing) printf '%s' "Eine vorhandene Root-Installation wurde in /opt/rs-agent oder /var/lib/rs-agent gefunden." ;;
        de_DE:root_mode) printf '%s' "Root-/Systeminstallationsmodus ausgewählt; Es werden Systempfade verwendet." ;;
        de_DE:rsm_item_missing) printf '%s' "Das mit der UUID verknüpfte RSM-Element konnte nicht gefunden werden." ;;
        de_DE:rsm_manages_changes) printf '%s' "RSM erkennt und verwaltet Änderungen" ;;
        de_DE:rsm_status_safety) printf '%s' "Aus Sicherheitsgründen wird die Installation nicht fortgesetzt, ohne dass der Status aktualisiert werden kann." ;;
        de_DE:runner_downloaded) printf '%s' "Runner heruntergeladen" ;;
        de_DE:running_initial) printf '%s' "Erste Sammlung wird ausgeführt..." ;;
        de_DE:scheduler_cron_minus) printf '%s' "- Erfordert, dass cron/crontab installiert, aktiv und zulässig ist. Wenn nicht, wird die Installation/Aktivierung versucht und erfordert einen privilegierten Zugriff." ;;
        de_DE:scheduler_cron_plus) printf '%s' "+ Erfordert keinen Root für die Agentenausführung und ist nicht von einer aktiven Benutzersitzung abhängig." ;;
        de_DE:scheduler_cron_title) printf '%s' "1) Benutzer-Cron" ;;
        de_DE:scheduler_prompt) printf '%s' "Wählen Sie den Scheduler [1=cron, 2=systemd-user] (1): " ;;
        de_DE:scheduler_systemd_minus) printf '%s' "- Erfordert Linger, um ohne aktive Sitzung ausgeführt zu werden. Wenn es nicht aktiv ist, wird es aktiviert und benötigt einen privilegierten Zugriff." ;;
        de_DE:scheduler_systemd_plus) printf '%s' "+ Bessere Integration mit systemd und systemctl --user." ;;
        de_DE:scheduler_systemd_title) printf '%s' "2) systemd --user" ;;
        de_DE:scheduler_usage) printf '%s' "Verwenden Sie 1/cron oder 2/systemd-user." ;;
        de_DE:sends_complete) printf '%s' "Sendet bei jedem Lauf eine vollständige Bestandsaufnahme an RSM" ;;
        de_DE:su_failed) printf '%s' "Die privilegierte Aktion konnte mit su/root nicht abgeschlossen werden." ;;
        de_DE:su_missing) printf '%s' "su wurde nicht gefunden, daher kann von diesem Benutzer kein Root-Zugriff angefordert werden." ;;
        de_DE:systemd_bus_su) printf '%s' "Dies kann nach dem Benutzerwechsel mit su passieren, da der Systemd-Bus des Benutzers nicht gestartet ist." ;;
        de_DE:systemd_choose_alternative) printf '%s' "Sie können das Installationsprogramm von Root aus ausführen und den No-Root-Modus wählen, den Benutzer cron auswählen oder sich an Firulai wenden." ;;
        de_DE:systemd_choose_cron) printf '%s' "Sie können den Benutzer cron auswählen oder sich an Firulai wenden." ;;
        de_DE:systemd_enable_failed) printf '%s' "systemd konnte rs-agent.timer nicht aktivieren" ;;
        de_DE:systemd_linger_available_warn) printf '%s' "systemd --user ist verfügbar, aber Linger ist für den aktuellen Benutzer nicht aktiviert." ;;
        de_DE:systemd_linger_unreliable) printf '%s' "systemd --user ist ohne eine aktive Sitzung nicht zuverlässig, bis Linger aktiviert ist." ;;
        de_DE:systemd_no_bus) printf '%s' "Ohne einen Benutzer-Systemd-Bus kann mit systemd --user nicht fortgefahren werden." ;;
        de_DE:systemd_no_linger) printf '%s' "Ohne Verzögerung kann mit systemd --user nicht fortgefahren werden." ;;
        de_DE:systemd_prepare_failed) printf '%s' "systemd --user konnte nicht vorbereitet werden" ;;
        de_DE:systemd_prepare_prompt) printf '%s' "Möchten Sie, dass wir systemd --user jetzt vorbereiten? Dies erfordert einen privilegierten Zugriff." ;;
        de_DE:systemd_reload_failed) printf '%s' "systemd konnte die Einheiten nicht neu laden" ;;
        de_DE:systemd_timer_configured) printf '%s' "systemd-Timer auf 03:00 Uhr mit Boot-Wiederherstellung konfiguriert" ;;
        de_DE:systemd_user_enable_failed) printf '%s' "Systemd --user konnte nicht aktiviert werden." ;;
        de_DE:systemd_user_timer_configured) printf '%s' "systemd --user timer konfiguriert um 03:00" ;;
        de_DE:systemd_user_try_cron) printf '%s' "Systemd --user konnte nicht aktiviert werden; Stattdessen wird der Benutzer cron ausprobiert." ;;
        de_DE:systemd_user_unavailable) printf '%s' "systemd --user ist für diesen Benutzer/diese Sitzung noch nicht verfügbar." ;;
        de_DE:test_uuid_alias) printf '%s' "Verwenden Sie zum Vergleich eine separate Test-UUID/Alias." ;;
        de_DE:trying_su) printf '%s' "Versuche es mit root über su. su fragt nach dem Root-Passwort und erfordert, dass die Root-Anmeldung zugelassen wird." ;;
        de_DE:uninstall) printf '%s' "Deinstallieren:" ;;
        de_DE:uninstall_current) printf '%s' "Um einen neuen Agenten zu installieren, deinstallieren Sie zuerst den aktuellen:" ;;
        de_DE:uninstall_download_failed) printf '%s' "Das Deinstallationsprogramm konnte nicht von GitHub heruntergeladen werden" ;;
        de_DE:uninstaller_downloaded) printf '%s' "Deinstallationsprogramm heruntergeladen" ;;
        de_DE:unknown_scheduler) printf '%s' "Unbekannter Planer" ;;
        de_DE:unsafe_owner) printf '%s' "Unsicheres Verzeichnis: gehört nicht dem aktuellen Benutzer" ;;
        de_DE:unsafe_symlink) printf '%s' "Unsicherer Pfad: ist ein symbolischer Link" ;;
        de_DE:update_rsm_missing_uuid) printf '%s' "RSM konnte nicht aktualisiert werden, da das UUID-Element nicht gefunden wurde." ;;
        de_DE:user_cron_configured) printf '%s' "Benutzer-Cron mit täglicher Ausführung und automatischer Wiederherstellung konfiguriert" ;;
        de_DE:user_cron_fallback_session) printf '%s' "Um die Abhängigkeit von einer aktiven Sitzung zu vermeiden, wird ein Benutzer-Cron verwendet." ;;
        de_DE:user_crontab_failed) printf '%s' "Die Crontab des aktuellen Benutzers konnte nicht aktualisiert werden" ;;
        de_DE:user_mode) printf '%s' "No-Root-Installationsmodus ausgewählt; Der Agent wird nur für den aktuellen Benutzer installiert." ;;
        de_DE:uuid_conflict_hint) printf '%s' "Wenn die UUID bereits zu einem anderen System gehört, generieren Sie über „Neues System hinzufügen“ eine neue UUID." ;;
        de_DE:uuid_not_generated) printf '%s' "Der Agent kann nicht mit einer UUID installiert werden, die nicht durch „Neues System hinzufügen“ generiert wurde." ;;
        de_DE:uuid_other_system) printf '%s' "Diese UUID gehört bereits zu einem anderen System in RSM." ;;
        de_DE:uuid_other_system_local) printf '%s' "Dieser Agent kann mit dieser UUID nicht auf dem lokalen Computer installiert werden." ;;
        de_DE:uuid_reserved) printf '%s' "UUID ist im RSM reserviert und für die Installation verfügbar" ;;
        de_DE:uuid_same_system) printf '%s' "UUID ist diesem System in RSM bereits zugeordnet; Der Agent wird reaktiviert und der Bestand aktualisiert" ;;
        de_DE:uuid_validate_denied) printf '%s' "RSM hat keine UUID-Validierung zugelassen" ;;
        de_DE:uuid_validate_failed) printf '%s' "Die UUID in RSM konnte nicht validiert werden" ;;
        de_DE:uuid_validate_safety) printf '%s' "Aus Sicherheitsgründen wird die Installation nicht fortgesetzt, ohne zu bestätigen, dass die UUID verfügbar ist." ;;
        de_DE:validating_uuid) printf '%s' "Validierung der UUID in RSM..." ;;
        de_DE:view_inventory) printf '%s' "Inventar ansehen:" ;;
        it_IT:activate_failed) printf '%s' "Impossibile attivare il sistema in RSM" ;;
        it_IT:activated) printf '%s' "Sistema contrassegnato come attivo a Firulai" ;;
        it_IT:activation_denied) printf '%s' "RSM non ha consentito l'attivazione del sistema" ;;
        it_IT:agent_downloaded) printf '%s' "Agente scaricato" ;;
        it_IT:alias_needed) printf '%s' "Questo programma di installazione necessita di un alias per identificare il sistema in Firulai." ;;
        it_IT:alias_prompt) printf '%s' "Alias di sistema: " ;;
        it_IT:alias_quotes) printf '%s' "Se l'alias contiene spazi, racchiuderlo tra virgolette." ;;
        it_IT:alias_required) printf '%s' "È richiesto l'alias di sistema." ;;
        it_IT:alias_saved) printf '%s' "Questo alias viene salvato in Firulai e può essere modificato dall'interfaccia." ;;
        it_IT:alias_title) printf '%s' "Alias:" ;;
        it_IT:alias_usage) printf '%s' "Esegui il programma di installazione con l'opzione --alias:" ;;
        it_IT:attempted_url) printf '%s' "URL tentato" ;;
        it_IT:auto_config_failed) printf '%s' "Impossibile completare l'installazione con l'esecuzione automatica." ;;
        it_IT:auto_execution_config_failed) printf '%s' "Impossibile configurare l'esecuzione automatica" ;;
        it_IT:automatic) printf '%s' "Automatico" ;;
        it_IT:automatic_execution_setup) printf '%s' "Configurazione dell'esecuzione automatica:" ;;
        it_IT:banner_subtitle) printf '%s' "Agente di analisi del sistema per il rilevamento delle vulnerabilità" ;;
        it_IT:bash_found) printf '%s' "bash trovato" ;;
        it_IT:bash_required) printf '%s' "è richiesto bash 4 o versione successiva" ;;
        it_IT:behavior_title) printf '%s' "Comportamento:" ;;
        it_IT:check_that) printf '%s' "Controlla che:" ;;
        it_IT:checking_cron_auto) printf '%s' "Controllo dei requisiti cron per l'esecuzione automatica..." ;;
        it_IT:checking_dependencies) printf '%s' "Controllo delle dipendenze..." ;;
        it_IT:checking_systemd_user) printf '%s' "Controllo systemd --requisiti utente..." ;;
        it_IT:cleanup_partial) printf '%s' "Pulizia installazione parziale..." ;;
        it_IT:config_saved) printf '%s' "Configurazione salvata" ;;
        it_IT:config_saving) printf '%s' "Salvataggio della configurazione dell'agente locale..." ;;
        it_IT:configuring_auto) printf '%s' "Configurazione dell'esecuzione automatica..." ;;
        it_IT:contact_firulai) printf '%s' "Contatta Firulai se hai bisogno di aiuto." ;;
        it_IT:creating_dirs) printf '%s' "Creazione di directory..." ;;
        it_IT:cron_active_confirm_failed) printf '%s' "Impossibile confermare che cron sia attivo. Contatta Firulai se hai bisogno di aiuto." ;;
        it_IT:cron_daemon_required) printf '%s' "Impossibile continuare con cron se il demone non è attivo." ;;
        it_IT:cron_enable_manual) printf '%s' "Abilita cron manualmente o contatta Firulai." ;;
        it_IT:cron_enable_prompt) printf '%s' "Vuoi che lo abilitiamo adesso? Ciò richiede un accesso privilegiato." ;;
        it_IT:cron_enable_unknown) printf '%s' "Impossibile determinare come abilitare automaticamente cron su questa distribuzione." ;;
        it_IT:cron_inactive) printf '%s' "cron/crond non sembra essere attivo." ;;
        it_IT:cron_install_manual) printf '%s' "Installa cron manualmente o contatta Firulai." ;;
        it_IT:cron_install_prompt) printf '%s' "Vuoi che installiamo cron adesso? Ciò richiede un accesso privilegiato." ;;
        it_IT:cron_install_unknown) printf '%s' "Impossibile determinare come installare automaticamente cron su questa distribuzione." ;;
        it_IT:cron_missing) printf '%s' "cron/crontab non è installato." ;;
        it_IT:cron_without_crontab) printf '%s' "Impossibile continuare con cron senza crontab." ;;
        it_IT:crontab_forbidden_1) printf '%s' "L'utente corrente non può gestire il proprio crontab." ;;
        it_IT:crontab_forbidden_2) printf '%s' "Un amministratore deve consentire i crontab per questo utente ed esaminare le politiche cron." ;;
        it_IT:crontab_forbidden_3) printf '%s' "Ciò potrebbe richiedere un accesso privilegiato. Contatta Firulai se hai bisogno di aiuto." ;;
        it_IT:crontab_unavailable) printf '%s' "Impossibile rendere disponibile crontab. Contatta Firulai se hai bisogno di aiuto." ;;
        it_IT:curl_found) printf '%s' "ricciolo trovato" ;;
        it_IT:curl_missing) printf '%s' "l'arricciatura non è installata" ;;
        it_IT:current_alias) printf '%s' "Valore attuale" ;;
        it_IT:current_installed_uuid) printf '%s' "UUID attualmente installato" ;;
        it_IT:daily_at) printf '%s' "Tutti i giorni alle 3:00" ;;
        it_IT:dirs_created) printf '%s' "Directory create" ;;
        it_IT:distribution) printf '%s' "Distribuzione" ;;
        it_IT:download_agent_failed) printf '%s' "Impossibile scaricare l'agente da GitHub" ;;
        it_IT:download_failed) printf '%s' "Impossibile scaricare" ;;
        it_IT:downloading_agent) printf '%s' "Download dell'agente da GitHub in corso..." ;;
        it_IT:downloading_runner) printf '%s' "Download del runner di esecuzione automatica in corso..." ;;
        it_IT:downloading_uninstaller) printf '%s' "Download del programma di disinstallazione da GitHub in corso..." ;;
        it_IT:enabling_cron) printf '%s' "Tentativo di abilitare cron con accesso privilegiato..." ;;
        it_IT:enabling_linger) printf '%s' "Tentativo di abilitare il ritardo con accesso privilegiato..." ;;
        it_IT:execution) printf '%s' "Esecuzione:" ;;
        it_IT:existing_agent) printf '%s' "È stata trovata un'installazione dell'agente esistente su questo sistema." ;;
        it_IT:failure_details) printf '%s' "I dettagli dell'errore sono stati mostrati sopra." ;;
        it_IT:flock_found) printf '%s' "gregge trovato" ;;
        it_IT:flock_missing_install) printf '%s' "il gregge non è installato (normalmente fornito dal pacchetto util-linux)" ;;
        it_IT:github_accessible) printf '%s' "GitHub è accessibile da questo server" ;;
        it_IT:includes) printf '%s' "Include: sistema operativo, kernel, CPU, modelli di dischi, pacchetti, software critico" ;;
        it_IT:initial_failed) printf '%s' "Impossibile generare e inviare l'inventario durante l'esecuzione iniziale" ;;
        it_IT:install_cancelled_initial) printf '%s' "Installazione annullata perché l'esecuzione iniziale dell'agente non è riuscita." ;;
        it_IT:install_completed) printf '%s' "INSTALLAZIONE COMPLETATA" ;;
        it_IT:install_success) printf '%s' "Installazione riuscita" ;;
        it_IT:installer_title) printf '%s' "Installatore" ;;
        it_IT:installing_cron) printf '%s' "Tentativo di installazione di cron con accesso privilegiato..." ;;
        it_IT:internet_connectivity) printf '%s' "Hai la connettività Internet" ;;
        it_IT:invalid_uuid_local) printf '%s' "non è un UUID valido" ;;
        it_IT:invalid_uuid_rsm) printf '%s' "UUID non valido: non esiste in RSM." ;;
        it_IT:inventory_ok) printf '%s' "Inventario generato correttamente" ;;
        it_IT:less_complete) printf '%s' "L'inventario potrebbe essere meno completo della modalità root se il sistema limita alcuni comandi." ;;
        it_IT:linger_disabled) printf '%s' "il ritardo non è abilitato" ;;
        it_IT:linger_enable_failed) printf '%s' "Impossibile abilitare il ritardo per" ;;
        it_IT:linger_enable_prompt) printf '%s' "Vuoi che abilitiamo il ritardo adesso? Ciò richiede un accesso privilegiato." ;;
        it_IT:local_installed_same_uuid) printf '%s' "Su questo sistema è già installato un agente con questo UUID." ;;
        it_IT:locations) printf '%s' "Posizioni:" ;;
        it_IT:manual) printf '%s' "Manuale" ;;
        it_IT:marking_active) printf '%s' "Sistema di marcatura come attivo a Firulai..." ;;
        it_IT:mktemp_found) printf '%s' "mktemp trovato" ;;
        it_IT:mktemp_missing_install) printf '%s' "mktemp non è installato" ;;
        it_IT:no_interactive_cron_default) printf '%s' "Nessun terminale interattivo rilevato; per impostazione predefinita verrà utilizzato l'utente cron." ;;
        it_IT:no_interactive_privileged) printf '%s' "Non è disponibile alcun terminale interattivo per richiedere l'accesso privilegiato." ;;
        it_IT:no_python_jq) printf '%s' "Nessuna dipendenza da Python o jq (pura bash)" ;;
        it_IT:partial_removed) printf '%s' "Installazione parziale rimossa" ;;
        it_IT:private_dir_failed) printf '%s' "Impossibile creare una directory privata sicura" ;;
        it_IT:privileged_needed) printf '%s' "Questa azione richiede un accesso privilegiato." ;;
        it_IT:privileged_not_completed) printf '%s' "L'azione privilegiata non è stata completata. Esegui il programma di installazione come root e scegli la modalità no-root oppure esegui il comando richiesto da una sessione root." ;;
        it_IT:recovery) printf '%s' "Recupero" ;;
        it_IT:recovery_detail) printf '%s' "uno in attesa di esecuzione quando il sistema tornerà operativo" ;;
        it_IT:requested_uuid) printf '%s' "UUID richiesto" ;;
        it_IT:response) printf '%s' "Risposta" ;;
        it_IT:root_coexist) printf '%s' "L'installazione senza root coesisterà con essa utilizzando i percorsi dell'utente corrente." ;;
        it_IT:root_cron_configured) printf '%s' "Cron root configurato con esecuzione giornaliera e ripristino automatico" ;;
        it_IT:root_crontab_failed) printf '%s' "Impossibile aggiornare crontab root" ;;
        it_IT:root_existing) printf '%s' "È stata trovata un'installazione root esistente in /opt/rs-agent o /var/lib/rs-agent." ;;
        it_IT:root_mode) printf '%s' "Modalità di installazione root/sistema selezionata; verranno utilizzati i percorsi di sistema." ;;
        it_IT:rsm_item_missing) printf '%s' "Impossibile individuare l'elemento RSM associato all'UUID." ;;
        it_IT:rsm_manages_changes) printf '%s' "RSM rileva e gestisce le modifiche" ;;
        it_IT:rsm_status_safety) printf '%s' "Per motivi di sicurezza, l'installazione non proseguirà senza la possibilità di aggiornare lo stato." ;;
        it_IT:runner_downloaded) printf '%s' "Scaricato il corridore" ;;
        it_IT:running_initial) printf '%s' "Esecuzione della raccolta iniziale in corso..." ;;
        it_IT:scheduler_cron_minus) printf '%s' "- Richiede cron/crontab installato, attivo e consentito. In caso contrario, verrà tentata l'installazione/attivazione e sarà necessario l'accesso privilegiato." ;;
        it_IT:scheduler_cron_plus) printf '%s' "+ Non richiede root per l'esecuzione dell'agente e non dipende da una sessione utente attiva." ;;
        it_IT:scheduler_cron_title) printf '%s' "1) Cronologia utente" ;;
        it_IT:scheduler_prompt) printf '%s' "Scegli lo scheduler [1=cron, 2=systemd-user] (1): " ;;
        it_IT:scheduler_systemd_minus) printf '%s' "- Richiede più tempo per essere eseguito senza una sessione attiva. Se non è attivo, sarà abilitato e avrà bisogno di un accesso privilegiato." ;;
        it_IT:scheduler_systemd_plus) printf '%s' "+ Migliore integrazione con systemd e systemctl --user." ;;
        it_IT:scheduler_systemd_title) printf '%s' "2) systemd --utente" ;;
        it_IT:scheduler_usage) printf '%s' "Usa 1/cron o 2/systemd-user." ;;
        it_IT:sends_complete) printf '%s' "Invia un inventario completo a RSM a ogni esecuzione" ;;
        it_IT:su_failed) printf '%s' "Non è stato possibile completare l'azione privilegiata con su/root." ;;
        it_IT:su_missing) printf '%s' "su non è stato trovato, quindi non è possibile richiedere l'accesso root a questo utente." ;;
        it_IT:systemd_bus_su) printf '%s' "Ciò può accadere dopo aver cambiato utente con su perché il bus systemd dell'utente non è avviato." ;;
        it_IT:systemd_choose_alternative) printf '%s' "Puoi eseguire il programma di installazione da root e scegliere la modalità no-root, scegliere l'utente cron o contattare Firulai." ;;
        it_IT:systemd_choose_cron) printf '%s' "Puoi scegliere l'utente cron o contattare Firulai." ;;
        it_IT:systemd_enable_failed) printf '%s' "systemd non è riuscito ad abilitare rs-agent.timer" ;;
        it_IT:systemd_linger_available_warn) printf '%s' "systemd --user è disponibile, ma il ritardo non è abilitato per l'utente corrente." ;;
        it_IT:systemd_linger_unreliable) printf '%s' "systemd --user non sarà affidabile senza una sessione attiva finché il ritardo non sarà abilitato." ;;
        it_IT:systemd_no_bus) printf '%s' "Impossibile continuare con systemd --user senza un bus systemd utente." ;;
        it_IT:systemd_no_linger) printf '%s' "Impossibile continuare con systemd --user senza indugiare." ;;
        it_IT:systemd_prepare_failed) printf '%s' "Impossibile preparare systemd --user per" ;;
        it_IT:systemd_prepare_prompt) printf '%s' "Vuoi che prepariamo systemd --user adesso? Ciò richiede un accesso privilegiato." ;;
        it_IT:systemd_reload_failed) printf '%s' "systemd non è riuscito a ricaricare le unità" ;;
        it_IT:systemd_timer_configured) printf '%s' "timer systemd configurato alle 03:00 con ripristino dell'avvio" ;;
        it_IT:systemd_user_enable_failed) printf '%s' "Impossibile abilitare systemd --user." ;;
        it_IT:systemd_user_timer_configured) printf '%s' "systemd --timer utente configurato alle 03:00" ;;
        it_IT:systemd_user_try_cron) printf '%s' "Impossibile abilitare systemd --user; verrà invece provato l'utente cron." ;;
        it_IT:systemd_user_unavailable) printf '%s' "systemd --user non è ancora disponibile per questo utente/sessione." ;;
        it_IT:test_uuid_alias) printf '%s' "Per confronto, utilizzare un UUID/alias di test separato." ;;
        it_IT:trying_su) printf '%s' "Provando il root tramite su. su richiede la password di root e richiede che sia consentito l'accesso di root." ;;
        it_IT:uninstall) printf '%s' "Disinstalla:" ;;
        it_IT:uninstall_current) printf '%s' "Per installare un nuovo agente, disinstalla prima quello corrente:" ;;
        it_IT:uninstall_download_failed) printf '%s' "Impossibile scaricare il programma di disinstallazione da GitHub" ;;
        it_IT:uninstaller_downloaded) printf '%s' "Programma di disinstallazione scaricato" ;;
        it_IT:unknown_scheduler) printf '%s' "Programmatore sconosciuto" ;;
        it_IT:unsafe_owner) printf '%s' "Directory non sicura: non è di proprietà dell'utente corrente" ;;
        it_IT:unsafe_symlink) printf '%s' "Percorso non sicuro: è un collegamento simbolico" ;;
        it_IT:update_rsm_missing_uuid) printf '%s' "Impossibile aggiornare RSM perché l'elemento UUID non è stato trovato." ;;
        it_IT:user_cron_configured) printf '%s' "Cron utente configurato con esecuzione giornaliera e ripristino automatico" ;;
        it_IT:user_cron_fallback_session) printf '%s' "Il cron dell'utente verrà utilizzato per evitare di dipendere da una sessione attiva." ;;
        it_IT:user_crontab_failed) printf '%s' "Impossibile aggiornare il crontab dell'utente corrente" ;;
        it_IT:user_mode) printf '%s' "Modalità di installazione senza root selezionata; l'agente verrà installato solo per l'utente corrente." ;;
        it_IT:uuid_conflict_hint) printf '%s' "Se l'UUID appartiene già a un altro sistema, generare un nuovo UUID da Aggiungi nuovo sistema." ;;
        it_IT:uuid_not_generated) printf '%s' "Non è possibile installare l'agente con un UUID che non è stato generato da Aggiungi nuovo sistema." ;;
        it_IT:uuid_other_system) printf '%s' "Questo UUID appartiene già a un altro sistema in RSM." ;;
        it_IT:uuid_other_system_local) printf '%s' "Questo agente non può essere installato sul computer locale con quell'UUID." ;;
        it_IT:uuid_reserved) printf '%s' "UUID riservato in RSM e disponibile per l'installazione" ;;
        it_IT:uuid_same_system) printf '%s' "UUID già associato a questo sistema in RSM; l'agente verrà riattivato e l'inventario aggiornato" ;;
        it_IT:uuid_validate_denied) printf '%s' "RSM non ha consentito la convalida UUID" ;;
        it_IT:uuid_validate_failed) printf '%s' "Impossibile convalidare l'UUID in RSM" ;;
        it_IT:uuid_validate_safety) printf '%s' "Per motivi di sicurezza, l'installazione non continuerà senza la conferma che l'UUID è disponibile." ;;
        it_IT:validating_uuid) printf '%s' "Convalida dell'UUID in RSM..." ;;
        it_IT:view_inventory) printf '%s' "Visualizza inventario:" ;;
        ja_JP:activate_failed) printf '%s' "RSM でシステムをアクティブ化できませんでした" ;;
        ja_JP:activated) printf '%s' "Firulai でシステムがアクティブとしてマークされている" ;;
        ja_JP:activation_denied) printf '%s' "RSM はシステムのアクティベーションを許可しませんでした" ;;
        ja_JP:agent_downloaded) printf '%s' "エージェントがダウンロードされました" ;;
        ja_JP:alias_needed) printf '%s' "このインストーラーには、Firulai でシステムを識別するためのエイリアスが必要です。" ;;
        ja_JP:alias_prompt) printf '%s' "システム エイリアス: " ;;
        ja_JP:alias_quotes) printf '%s' "エイリアスにスペースが含まれる場合は、引用符で囲みます。" ;;
        ja_JP:alias_required) printf '%s' "システムエイリアスが必要です。" ;;
        ja_JP:alias_saved) printf '%s' "このエイリアスは Firulai に保存され、インターフェースから変更できます。" ;;
        ja_JP:alias_title) printf '%s' "エイリアス：" ;;
        ja_JP:alias_usage) printf '%s' "--alias オプションを指定してインストーラーを実行します。" ;;
        ja_JP:attempted_url) printf '%s' "試行された URL" ;;
        ja_JP:auto_config_failed) printf '%s' "自動実行ではインストールを完了できません。" ;;
        ja_JP:auto_execution_config_failed) printf '%s' "自動実行を設定できませんでした" ;;
        ja_JP:automatic) printf '%s' "自動" ;;
        ja_JP:automatic_execution_setup) printf '%s' "自動実行設定：" ;;
        ja_JP:banner_subtitle) printf '%s' "脆弱性検出のためのシステム分析エージェント" ;;
        ja_JP:bash_found) printf '%s' "バッシュが見つかりました" ;;
        ja_JP:bash_required) printf '%s' "bash 4 以降が必要です" ;;
        ja_JP:behavior_title) printf '%s' "行動：" ;;
        ja_JP:check_that) printf '%s' "次のことを確認してください。" ;;
        ja_JP:checking_cron_auto) printf '%s' "自動実行の cron 要件を確認しています..." ;;
        ja_JP:checking_dependencies) printf '%s' "依存関係を確認しています..." ;;
        ja_JP:checking_systemd_user) printf '%s' "systemd --user 要件を確認しています..." ;;
        ja_JP:cleanup_partial) printf '%s' "部分的な取り付けをクリーニング中..." ;;
        ja_JP:config_saved) printf '%s' "設定が保存されました" ;;
        ja_JP:config_saving) printf '%s' "ローカル エージェント構成を保存しています..." ;;
        ja_JP:configuring_auto) printf '%s' "自動実行を構成しています..." ;;
        ja_JP:contact_firulai) printf '%s' "サポートが必要な場合は、Firulai にご連絡ください。" ;;
        ja_JP:creating_dirs) printf '%s' "ディレクトリを作成しています..." ;;
        ja_JP:cron_active_confirm_failed) printf '%s' "cronが有効であることを確認できませんでした。サポートが必要な場合は、Firulai にご連絡ください。" ;;
        ja_JP:cron_daemon_required) printf '%s' "デーモンがアクティブでない場合、cron を続行できません。" ;;
        ja_JP:cron_enable_manual) printf '%s' "cron を手動で有効にするか、Firulai に問い合わせてください。" ;;
        ja_JP:cron_enable_prompt) printf '%s' "今すぐ有効にしますか?これには特権アクセスが必要です。" ;;
        ja_JP:cron_enable_unknown) printf '%s' "このディストリビューションで cron を自動的に有効にする方法を特定できませんでした。" ;;
        ja_JP:cron_inactive) printf '%s' "cron/crond がアクティブではないようです。" ;;
        ja_JP:cron_install_manual) printf '%s' "cron を手動でインストールするか、Firulai にお問い合わせください。" ;;
        ja_JP:cron_install_prompt) printf '%s' "今すぐ cron をインストールしますか?これには特権アクセスが必要です。" ;;
        ja_JP:cron_install_unknown) printf '%s' "このディストリビューションに cron を自動的にインストールする方法を決定できませんでした。" ;;
        ja_JP:cron_missing) printf '%s' "cron/crontabがインストールされていません。" ;;
        ja_JP:cron_without_crontab) printf '%s' "crontab がないと cron を続行できません。" ;;
        ja_JP:crontab_forbidden_1) printf '%s' "現在のユーザーは crontab を管理できません。" ;;
        ja_JP:crontab_forbidden_2) printf '%s' "管理者は、このユーザーに crontab を許可し、cron ポリシーを確認する必要があります。" ;;
        ja_JP:crontab_forbidden_3) printf '%s' "これには特権アクセスが必要になる場合があります。サポートが必要な場合は、Firulai にご連絡ください。" ;;
        ja_JP:crontab_unavailable) printf '%s' "crontab を使用可能にできませんでした。サポートが必要な場合は、Firulai にご連絡ください。" ;;
        ja_JP:curl_found) printf '%s' "カールが見つかりました" ;;
        ja_JP:curl_missing) printf '%s' "カールがインストールされていません" ;;
        ja_JP:current_alias) printf '%s' "現在値" ;;
        ja_JP:current_installed_uuid) printf '%s' "現在インストールされている UUID" ;;
        ja_JP:daily_at) printf '%s' "毎日午前 3 時" ;;
        ja_JP:dirs_created) printf '%s' "作成されたディレクトリ" ;;
        ja_JP:distribution) printf '%s' "配布" ;;
        ja_JP:download_agent_failed) printf '%s' "GitHub からエージェントをダウンロードできませんでした" ;;
        ja_JP:download_failed) printf '%s' "ダウンロードできませんでした" ;;
        ja_JP:downloading_agent) printf '%s' "GitHub からエージェントをダウンロードしています..." ;;
        ja_JP:downloading_runner) printf '%s' "自動実行ランナーをダウンロードしています..." ;;
        ja_JP:downloading_uninstaller) printf '%s' "GitHub からアンインストーラーをダウンロードしています..." ;;
        ja_JP:enabling_cron) printf '%s' "特権アクセスで cron を有効にしようとしています..." ;;
        ja_JP:enabling_linger) printf '%s' "特権アクセスによるリンガーを有効にしようとしています..." ;;
        ja_JP:execution) printf '%s' "実行:" ;;
        ja_JP:existing_agent) printf '%s' "既存のエージェントのインストールがこのシステムで見つかりました。" ;;
        ja_JP:failure_details) printf '%s' "障害の詳細は上に示されています。" ;;
        ja_JP:flock_found) printf '%s' "群れが見つかりました" ;;
        ja_JP:flock_missing_install) printf '%s' "flock がインストールされていません (通常は util-linux パッケージによって提供されます)" ;;
        ja_JP:github_accessible) printf '%s' "このサーバーから GitHub にアクセスできます" ;;
        ja_JP:includes) printf '%s' "含まれるもの: OS、カーネル、CPU、ディスクモデル、パッケージ、重要なソフトウェア" ;;
        ja_JP:initial_failed) printf '%s' "初回実行時にインベントリを生成して送信できませんでした" ;;
        ja_JP:install_cancelled_initial) printf '%s' "エージェントの最初の実行が失敗したため、インストールはキャンセルされました。" ;;
        ja_JP:install_completed) printf '%s' "インストールが完了しました" ;;
        ja_JP:install_success) printf '%s' "インストール成功" ;;
        ja_JP:installer_title) printf '%s' "インストーラ" ;;
        ja_JP:installing_cron) printf '%s' "特権アクセスを使用して cron をインストールしようとしています..." ;;
        ja_JP:internet_connectivity) printf '%s' "インターネット接続がある" ;;
        ja_JP:invalid_uuid_local) printf '%s' "有効な UUID ではありません" ;;
        ja_JP:invalid_uuid_rsm) printf '%s' "無効な UUID: RSM に存在しません。" ;;
        ja_JP:inventory_ok) printf '%s' "インベントリが正常に生成されました" ;;
        ja_JP:less_complete) printf '%s' "システムが一部のコマンドを制限している場合、インベントリはルート モードよりも不完全になる可能性があります。" ;;
        ja_JP:linger_disabled) printf '%s' "リンガーは有効になっていません" ;;
        ja_JP:linger_enable_failed) printf '%s' "リンガーを有効にできませんでした" ;;
        ja_JP:linger_enable_prompt) printf '%s' "今すぐリンガーを有効にしますか?これには特権アクセスが必要です。" ;;
        ja_JP:local_installed_same_uuid) printf '%s' "このシステムには、この UUID を使用してエージェントがすでにインストールされています。" ;;
        ja_JP:locations) printf '%s' "場所:" ;;
        ja_JP:manual) printf '%s' "マニュアル" ;;
        ja_JP:marking_active) printf '%s' "Firulai でシステムをアクティブとしてマーキングします..." ;;
        ja_JP:mktemp_found) printf '%s' "mktemp が見つかりました" ;;
        ja_JP:mktemp_missing_install) printf '%s' "mktemp がインストールされていません" ;;
        ja_JP:no_interactive_cron_default) printf '%s' "対話型端末が検出されませんでした。ユーザー cron がデフォルトで使用されます。" ;;
        ja_JP:no_interactive_privileged) printf '%s' "特権アクセスを要求できる対話型端末はありません。" ;;
        ja_JP:no_python_jq) printf '%s' "Python または jq への依存関係なし (純粋な bash)" ;;
        ja_JP:partial_removed) printf '%s' "部分的なインストールが削除されました" ;;
        ja_JP:private_dir_failed) printf '%s' "安全なプライベート ディレクトリを作成できませんでした" ;;
        ja_JP:privileged_needed) printf '%s' "このアクションには特権アクセスが必要です。" ;;
        ja_JP:privileged_not_completed) printf '%s' "特権アクションが完了しませんでした。インストーラーを root として実行し、no-root モードを選択するか、root セッションから必要なコマンドを実行します。" ;;
        ja_JP:recovery) printf '%s' "回復" ;;
        ja_JP:recovery_detail) printf '%s' "システムが再び動作可能になったときに保留中の実行が 1 つ" ;;
        ja_JP:requested_uuid) printf '%s' "要求された UUID" ;;
        ja_JP:response) printf '%s' "応答" ;;
        ja_JP:root_coexist) printf '%s' "root を使用しないインストールは、現在のユーザーのパスを使用して共存します。" ;;
        ja_JP:root_cron_configured) printf '%s' "毎日の実行と自動リカバリが設定された root cron" ;;
        ja_JP:root_crontab_failed) printf '%s' "ルートの crontab を更新できませんでした" ;;
        ja_JP:root_existing) printf '%s' "既存のルート インストールが /opt/rs-agent または /var/lib/rs-agent に見つかりました。" ;;
        ja_JP:root_mode) printf '%s' "ルート/システム インストール モードが選択されています。システムパスが使用されます。" ;;
        ja_JP:rsm_item_missing) printf '%s' "UUID に関連付けられた RSM アイテムが見つかりませんでした。" ;;
        ja_JP:rsm_manages_changes) printf '%s' "RSM は変更を検出して管理します" ;;
        ja_JP:rsm_status_safety) printf '%s' "安全のため、ステータスを更新できない限りインストールは続行されません。" ;;
        ja_JP:runner_downloaded) printf '%s' "ランナーをダウンロードしました" ;;
        ja_JP:running_initial) printf '%s' "初期収集を実行しています..." ;;
        ja_JP:scheduler_cron_minus) printf '%s' "- cron/crontab がインストールされ、アクティブで、許可されている必要があります。そうでない場合は、インストール/アクティブ化が試行され、特権アクセスが必要になります。" ;;
        ja_JP:scheduler_cron_plus) printf '%s' "+ エージェントの実行に root は必要なく、アクティブなユーザー セッションに依存しません。" ;;
        ja_JP:scheduler_cron_title) printf '%s' "1) ユーザー cron" ;;
        ja_JP:scheduler_prompt) printf '%s' "スケジューラを選択 [1=cron、2=systemd-user] (1): " ;;
        ja_JP:scheduler_systemd_minus) printf '%s' "- アクティブなセッションなしで実行するには、linger が必要です。アクティブでない場合は有効になり、特権アクセスが必要になります。" ;;
        ja_JP:scheduler_systemd_plus) printf '%s' "+ systemd および systemctl --user との統合が強化されました。" ;;
        ja_JP:scheduler_systemd_title) printf '%s' "2) systemd --user" ;;
        ja_JP:scheduler_usage) printf '%s' "1/cron または 2/systemd-user を使用します。" ;;
        ja_JP:sends_complete) printf '%s' "実行のたびに完全なインベントリを RSM に送信します" ;;
        ja_JP:su_failed) printf '%s' "特権アクションは su/root では完了できませんでした。" ;;
        ja_JP:su_missing) printf '%s' "su が見つからなかったため、このユーザーに root アクセスを要求できません。" ;;
        ja_JP:systemd_bus_su) printf '%s' "これは、ユーザーの systemd バスが開始されていないため、su でユーザーを切り替えた後に発生する可能性があります。" ;;
        ja_JP:systemd_choose_alternative) printf '%s' "root からインストーラーを実行して非 root モードを選択するか、ユーザー cron を選択するか、Firulai に問い合わせることができます。" ;;
        ja_JP:systemd_choose_cron) printf '%s' "ユーザー cron を選択するか、Firulai に連絡することができます。" ;;
        ja_JP:systemd_enable_failed) printf '%s' "systemd は rs-agent.timer を有効にできませんでした" ;;
        ja_JP:systemd_linger_available_warn) printf '%s' "systemd --user は使用できますが、現在のユーザーに対して linger が有効になっていません。" ;;
        ja_JP:systemd_linger_unreliable) printf '%s' "systemd --user は、linger が有効になるまで、アクティブなセッションがないと信頼できません。" ;;
        ja_JP:systemd_no_bus) printf '%s' "ユーザー systemd バスがないと systemd --user を続行できません。" ;;
        ja_JP:systemd_no_linger) printf '%s' "systemd --user をそのまま続行することはできません。" ;;
        ja_JP:systemd_prepare_failed) printf '%s' "systemd --user を準備できませんでした" ;;
        ja_JP:systemd_prepare_prompt) printf '%s' "今すぐ systemd --user を準備しますか?これには特権アクセスが必要です。" ;;
        ja_JP:systemd_reload_failed) printf '%s' "systemd がユニットをリロードできませんでした" ;;
        ja_JP:systemd_timer_configured) printf '%s' "systemd タイマーはブート リカバリを使用して 03:00 に設定されています" ;;
        ja_JP:systemd_user_enable_failed) printf '%s' "systemd --user を有効にできませんでした。" ;;
        ja_JP:systemd_user_timer_configured) printf '%s' "systemd --user タイマーは 03:00 に設定されています" ;;
        ja_JP:systemd_user_try_cron) printf '%s' "systemd --user を有効にできませんでした。代わりにユーザー cron が試行されます。" ;;
        ja_JP:systemd_user_unavailable) printf '%s' "systemd --user はこのユーザー/セッションではまだ使用できません。" ;;
        ja_JP:test_uuid_alias) printf '%s' "比較するには、別のテスト UUID/エイリアスを使用します。" ;;
        ja_JP:trying_su) printf '%s' "su経由でrootを試してみます。 su は root パスワードを要求し、root ログインを許可する必要があります。" ;;
        ja_JP:uninstall) printf '%s' "アンインストール:" ;;
        ja_JP:uninstall_current) printf '%s' "新しいエージェントをインストールするには、まず現在のエージェントをアンインストールします。" ;;
        ja_JP:uninstall_download_failed) printf '%s' "GitHub からアンインストーラーをダウンロードできませんでした" ;;
        ja_JP:uninstaller_downloaded) printf '%s' "アンインストーラーがダウンロードされました" ;;
        ja_JP:unknown_scheduler) printf '%s' "不明なスケジューラ" ;;
        ja_JP:unsafe_owner) printf '%s' "安全でないディレクトリ: 現在のユーザーが所有していません" ;;
        ja_JP:unsafe_symlink) printf '%s' "安全でないパス: シンボリック リンクです" ;;
        ja_JP:update_rsm_missing_uuid) printf '%s' "UUID 項目が見つからなかったため、RSM を更新できませんでした。" ;;
        ja_JP:user_cron_configured) printf '%s' "毎日の実行と自動リカバリが設定されたユーザー cron" ;;
        ja_JP:user_cron_fallback_session) printf '%s' "ユーザー cron は、アクティブなセッションへの依存を避けるために使用されます。" ;;
        ja_JP:user_crontab_failed) printf '%s' "現在のユーザーの crontab を更新できませんでした" ;;
        ja_JP:user_mode) printf '%s' "root なしインストール モードが選択されています。エージェントは現在のユーザーに対してのみインストールされます。" ;;
        ja_JP:uuid_conflict_hint) printf '%s' "UUID がすでに別のシステムに属している場合は、「新しいシステムの追加」から新しい UUID を生成します。" ;;
        ja_JP:uuid_not_generated) printf '%s' "新しいシステムの追加から生成されていない UUID を使用してエージェントをインストールすることはできません。" ;;
        ja_JP:uuid_other_system) printf '%s' "この UUID はすでに RSM 内の別のシステムに属しています。" ;;
        ja_JP:uuid_other_system_local) printf '%s' "このエージェントは、その UUID ではローカル マシンにインストールできません。" ;;
        ja_JP:uuid_reserved) printf '%s' "RSM で予約されており、インストールに使用できる UUID" ;;
        ja_JP:uuid_same_system) printf '%s' "UUID はすでに RSM でこのシステムに関連付けられています。エージェントが再アクティブ化され、インベントリが更新されます" ;;
        ja_JP:uuid_validate_denied) printf '%s' "RSM は UUID 検証を許可しませんでした" ;;
        ja_JP:uuid_validate_failed) printf '%s' "RSM で UUID を検証できませんでした" ;;
        ja_JP:uuid_validate_safety) printf '%s' "安全のため、UUID が使用可能であることを確認しない限り、インストールは続行されません。" ;;
        ja_JP:validating_uuid) printf '%s' "RSM で UUID を検証しています..." ;;
        ja_JP:view_inventory) printf '%s' "在庫を表示:" ;;
        zh_CN:activate_failed) printf '%s' "无法在 RSM 中激活系统" ;;
        zh_CN:activated) printf '%s' "系统在 Firulai 标记为活动状态" ;;
        zh_CN:activation_denied) printf '%s' "RSM 不允许系统激活" ;;
        zh_CN:agent_downloaded) printf '%s' "代理已下载" ;;
        zh_CN:alias_needed) printf '%s' "此安装程序需要一个别名来识别 Firulai 中的系统。" ;;
        zh_CN:alias_prompt) printf '%s' "系统别名： " ;;
        zh_CN:alias_quotes) printf '%s' "如果别名包含空格，请将其用引号引起来。" ;;
        zh_CN:alias_required) printf '%s' "需要系统别名。" ;;
        zh_CN:alias_saved) printf '%s' "该别名保存在 Firulai 中，可以从界面进行更改。" ;;
        zh_CN:alias_title) printf '%s' "别名：" ;;
        zh_CN:alias_usage) printf '%s' "使用 --alias 选项运行安装程序：" ;;
        zh_CN:attempted_url) printf '%s' "尝试的网址" ;;
        zh_CN:auto_config_failed) printf '%s' "无法通过自动执行完成安装。" ;;
        zh_CN:auto_execution_config_failed) printf '%s' "无法配置自动执行" ;;
        zh_CN:automatic) printf '%s' "自动" ;;
        zh_CN:automatic_execution_setup) printf '%s' "自动执行设置：" ;;
        zh_CN:banner_subtitle) printf '%s' "用于漏洞检测的系统分析代理" ;;
        zh_CN:bash_found) printf '%s' "bash 发现" ;;
        zh_CN:bash_required) printf '%s' "需要 bash 4 或更高版本" ;;
        zh_CN:behavior_title) printf '%s' "行为：" ;;
        zh_CN:check_that) printf '%s' "检查：" ;;
        zh_CN:checking_cron_auto) printf '%s' "检查自动执行的 cron 要求..." ;;
        zh_CN:checking_dependencies) printf '%s' "检查依赖关系..." ;;
        zh_CN:checking_systemd_user) printf '%s' "检查 systemd --用户要求..." ;;
        zh_CN:cleanup_partial) printf '%s' "清洁部分安装..." ;;
        zh_CN:config_saved) printf '%s' "配置已保存" ;;
        zh_CN:config_saving) printf '%s' "正在保存本地代理配置..." ;;
        zh_CN:configuring_auto) printf '%s' "配置自动执行..." ;;
        zh_CN:contact_firulai) printf '%s' "如果您需要帮助，请联系 Firulai。" ;;
        zh_CN:creating_dirs) printf '%s' "正在创建目录..." ;;
        zh_CN:cron_active_confirm_failed) printf '%s' "无法确认 cron 是否处于活动状态。如果您需要帮助，请联系 Firulai。" ;;
        zh_CN:cron_daemon_required) printf '%s' "如果守护进程未处于活动状态，则无法继续执行 cron。" ;;
        zh_CN:cron_enable_manual) printf '%s' "手动启用 cron 或联系 Firulai。" ;;
        zh_CN:cron_enable_prompt) printf '%s' "您希望我们现在启用它吗？这需要特权访问。" ;;
        zh_CN:cron_enable_unknown) printf '%s' "无法确定如何在此发行版上自动启用 cron。" ;;
        zh_CN:cron_inactive) printf '%s' "cron/crond 似乎没有处于活动状态。" ;;
        zh_CN:cron_install_manual) printf '%s' "手动安装 cron 或联系 Firulai。" ;;
        zh_CN:cron_install_prompt) printf '%s' "您希望我们现在安装 cron 吗？这需要特权访问。" ;;
        zh_CN:cron_install_unknown) printf '%s' "无法确定如何在此发行版上自动安装 cron。" ;;
        zh_CN:cron_missing) printf '%s' "未安装 cron/crontab。" ;;
        zh_CN:cron_without_crontab) printf '%s' "如果没有 crontab，则无法继续执行 cron。" ;;
        zh_CN:crontab_forbidden_1) printf '%s' "当前用户无法管理他们的 crontab。" ;;
        zh_CN:crontab_forbidden_2) printf '%s' "管理员必须允许该用户使用 crontab 并查看 cron 策略。" ;;
        zh_CN:crontab_forbidden_3) printf '%s' "这可能需要特权访问。如果您需要帮助，请联系 Firulai。" ;;
        zh_CN:crontab_unavailable) printf '%s' "无法使 crontab 可用。如果您需要帮助，请联系 Firulai。" ;;
        zh_CN:curl_found) printf '%s' "发现卷曲" ;;
        zh_CN:curl_missing) printf '%s' "未安装卷曲" ;;
        zh_CN:current_alias) printf '%s' "当前值" ;;
        zh_CN:current_installed_uuid) printf '%s' "当前安装的UUID" ;;
        zh_CN:daily_at) printf '%s' "每天凌晨 3:00" ;;
        zh_CN:dirs_created) printf '%s' "已创建目录" ;;
        zh_CN:distribution) printf '%s' "分布" ;;
        zh_CN:download_agent_failed) printf '%s' "无法从 GitHub 下载代理" ;;
        zh_CN:download_failed) printf '%s' "无法下载" ;;
        zh_CN:downloading_agent) printf '%s' "正在从 GitHub 下载代理..." ;;
        zh_CN:downloading_runner) printf '%s' "正在下载自动执行运行程序..." ;;
        zh_CN:downloading_uninstaller) printf '%s' "正在从 GitHub 下载卸载程序..." ;;
        zh_CN:enabling_cron) printf '%s' "正在尝试启用具有特权访问权限的 cron..." ;;
        zh_CN:enabling_linger) printf '%s' "正在尝试启用具有特权访问权限的 linger..." ;;
        zh_CN:execution) printf '%s' "执行：" ;;
        zh_CN:existing_agent) printf '%s' "在此系统上发现现有代理安装。" ;;
        zh_CN:failure_details) printf '%s' "故障详细信息如上所示。" ;;
        zh_CN:flock_found) printf '%s' "发现羊群" ;;
        zh_CN:flock_missing_install) printf '%s' "未安装集群（通常由 util-linux 软件包提供）" ;;
        zh_CN:github_accessible) printf '%s' "可以从此服务器访问 GitHub" ;;
        zh_CN:includes) printf '%s' "包括：操作系统、内核、CPU、磁盘型号、软件包、关键软件" ;;
        zh_CN:initial_failed) printf '%s' "在初始运行期间无法生成和发送库存" ;;
        zh_CN:install_cancelled_initial) printf '%s' "由于初始代理运行失败，安装被取消。" ;;
        zh_CN:install_completed) printf '%s' "安装完成" ;;
        zh_CN:install_success) printf '%s' "安装成功" ;;
        zh_CN:installer_title) printf '%s' "安装人员" ;;
        zh_CN:installing_cron) printf '%s' "正在尝试使用特权访问安装 cron..." ;;
        zh_CN:internet_connectivity) printf '%s' "您有互联网连接" ;;
        zh_CN:invalid_uuid_local) printf '%s' "不是有效的 UUID" ;;
        zh_CN:invalid_uuid_rsm) printf '%s' "无效的 UUID：RSM 中不存在。" ;;
        zh_CN:inventory_ok) printf '%s' "库存生成成功" ;;
        zh_CN:less_complete) printf '%s' "如果系统限制某些命令，清单可能不如根模式完整。" ;;
        zh_CN:linger_disabled) printf '%s' "未启用逗留" ;;
        zh_CN:linger_enable_failed) printf '%s' "无法启用延迟" ;;
        zh_CN:linger_enable_prompt) printf '%s' "您希望我们现在启用 linger 吗？这需要特权访问。" ;;
        zh_CN:local_installed_same_uuid) printf '%s' "该系统已安装了使用此 UUID 的代理。" ;;
        zh_CN:locations) printf '%s' "地点：" ;;
        zh_CN:manual) printf '%s' "手册" ;;
        zh_CN:marking_active) printf '%s' "在 Firulai 中将系统标记为活动状态..." ;;
        zh_CN:mktemp_found) printf '%s' "发现 mktemp" ;;
        zh_CN:mktemp_missing_install) printf '%s' "mktemp 未安装" ;;
        zh_CN:no_interactive_cron_default) printf '%s' "未检测到交互终端；默认情况下将使用用户 cron。" ;;
        zh_CN:no_interactive_privileged) printf '%s' "没有交互式终端可用于请求特权访问。" ;;
        zh_CN:no_python_jq) printf '%s' "没有 Python 或 jq 依赖项（纯 bash）" ;;
        zh_CN:partial_removed) printf '%s' "部分安装已删除" ;;
        zh_CN:private_dir_failed) printf '%s' "无法创建安全的私有目录" ;;
        zh_CN:privileged_needed) printf '%s' "此操作需要特权访问。" ;;
        zh_CN:privileged_not_completed) printf '%s' "特权操作未完成。以 root 身份运行安装程序并选择无 root 模式，或从 root 会话运行所需的命令。" ;;
        zh_CN:recovery) printf '%s' "恢复" ;;
        zh_CN:recovery_detail) printf '%s' "当系统再次运行时，有一个待执行的任务" ;;
        zh_CN:requested_uuid) printf '%s' "请求的 UUID" ;;
        zh_CN:response) printf '%s' "回应" ;;
        zh_CN:root_coexist) printf '%s' "无根安装将使用当前用户路径与其共存。" ;;
        zh_CN:root_cron_configured) printf '%s' "Root cron 配置每日执行和自动恢复" ;;
        zh_CN:root_crontab_failed) printf '%s' "无法更新 root crontab" ;;
        zh_CN:root_existing) printf '%s' "在 /opt/rs-agent 或 /var/lib/rs-agent 中找到了现有的 root 安装。" ;;
        zh_CN:root_mode) printf '%s' "选择root/系统安装模式；将使用系统路径。" ;;
        zh_CN:rsm_item_missing) printf '%s' "无法找到与 UUID 关联的 RSM 项目。" ;;
        zh_CN:rsm_manages_changes) printf '%s' "RSM 检测并管理变更" ;;
        zh_CN:rsm_status_safety) printf '%s' "为了安全起见，如果无法更新状态，安装将不会继续。" ;;
        zh_CN:runner_downloaded) printf '%s' "跑步者下载" ;;
        zh_CN:running_initial) printf '%s' "正在运行初始收集..." ;;
        zh_CN:scheduler_cron_minus) printf '%s' "- 需要安装、激活并允许 cron/crontab。如果没有，将尝试安装/激活并且需要特权访问。" ;;
        zh_CN:scheduler_cron_plus) printf '%s' "+ 不需要 root 来执行代理，也不依赖于活动用户会话。" ;;
        zh_CN:scheduler_cron_title) printf '%s' "1）用户cron" ;;
        zh_CN:scheduler_prompt) printf '%s' "选择调度程序 [1=cron, 2=systemd-user] (1): " ;;
        zh_CN:scheduler_systemd_minus) printf '%s' "- 需要 linger 才能在没有活动会话的情况下运行。如果它未激活，它将被启用并且需要特权访问。" ;;
        zh_CN:scheduler_systemd_plus) printf '%s' "+ 与 systemd 和 systemctl --user 更好地集成。" ;;
        zh_CN:scheduler_systemd_title) printf '%s' "2) 系统--用户" ;;
        zh_CN:scheduler_usage) printf '%s' "使用 1/cron 或 2/systemd-user。" ;;
        zh_CN:sends_complete) printf '%s' "每次运行时都会向 RSM 发送完整的清单" ;;
        zh_CN:su_failed) printf '%s' "无法使用 su/root 完成特权操作。" ;;
        zh_CN:su_missing) printf '%s' "未找到 su，因此无法向该用户请求 root 访问权限。" ;;
        zh_CN:systemd_bus_su) printf '%s' "使用 su 切换用户后可能会发生这种情况，因为用户 systemd 总线未启动。" ;;
        zh_CN:systemd_choose_alternative) printf '%s' "您可以从 root 运行安装程序并选择无 root 模式、选择用户 cron 或联系 Firulai。" ;;
        zh_CN:systemd_choose_cron) printf '%s' "您可以选择用户 cron 或联系 Firulai。" ;;
        zh_CN:systemd_enable_failed) printf '%s' "systemd 无法启用 rs-agent.timer" ;;
        zh_CN:systemd_linger_available_warn) printf '%s' "systemd --user 可用，但当前用户未启用 linger。" ;;
        zh_CN:systemd_linger_unreliable) printf '%s' "在启用 linger 之前，如果没有活动会话，systemd --user 将不可靠。" ;;
        zh_CN:systemd_no_bus) printf '%s' "如果没有用户 systemd 总线，则无法继续使用 systemd --user。" ;;
        zh_CN:systemd_no_linger) printf '%s' "无法在没有逗留的情况下继续使用 systemd --user。" ;;
        zh_CN:systemd_prepare_failed) printf '%s' "无法准备 systemd --user" ;;
        zh_CN:systemd_prepare_prompt) printf '%s' "您希望我们现在准备 systemd --user 吗？这需要特权访问。" ;;
        zh_CN:systemd_reload_failed) printf '%s' "systemd 无法重新加载单元" ;;
        zh_CN:systemd_timer_configured) printf '%s' "systemd 计时器配置为 03:00 并具有启动恢复功能" ;;
        zh_CN:systemd_user_enable_failed) printf '%s' "无法启用 systemd --user。" ;;
        zh_CN:systemd_user_timer_configured) printf '%s' "systemd --用户计时器配置为 03:00" ;;
        zh_CN:systemd_user_try_cron) printf '%s' "无法启用 systemd --user；将尝试用户 cron。" ;;
        zh_CN:systemd_user_unavailable) printf '%s' "systemd --user 对此用户/会话尚不可用。" ;;
        zh_CN:test_uuid_alias) printf '%s' "为了进行比较，请使用单独的测试 UUID/别名。" ;;
        zh_CN:trying_su) printf '%s' "尝试通过 su root。 su 要求输入 root 密码并要求允许 root 登录。" ;;
        zh_CN:uninstall) printf '%s' "卸载：" ;;
        zh_CN:uninstall_current) printf '%s' "要安装新代理，请先卸载当前代理：" ;;
        zh_CN:uninstall_download_failed) printf '%s' "无法从 GitHub 下载卸载程序" ;;
        zh_CN:uninstaller_downloaded) printf '%s' "卸载程序已下载" ;;
        zh_CN:unknown_scheduler) printf '%s' "未知的调度程序" ;;
        zh_CN:unsafe_owner) printf '%s' "不安全目录：不属于当前用户" ;;
        zh_CN:unsafe_symlink) printf '%s' "不安全路径：是符号链接" ;;
        zh_CN:update_rsm_missing_uuid) printf '%s' "无法更新 RSM，因为未找到 UUID 项目。" ;;
        zh_CN:user_cron_configured) printf '%s' "用户 cron 配置每日执行和自动恢复" ;;
        zh_CN:user_cron_fallback_session) printf '%s' "用户 cron 将用于避免依赖于活动会话。" ;;
        zh_CN:user_crontab_failed) printf '%s' "无法更新当前用户的 crontab" ;;
        zh_CN:user_mode) printf '%s' "选择免root安装模式；该代理将仅为当前用户安装。" ;;
        zh_CN:uuid_conflict_hint) printf '%s' "如果 UUID 已属于另一个系统，请从“添加新系统”生成新的 UUID。" ;;
        zh_CN:uuid_not_generated) printf '%s' "无法使用不是从“添加新系统”生成的 UUID 安装代理。" ;;
        zh_CN:uuid_other_system) printf '%s' "该 UUID 已属于 RSM 中的另一个系统。" ;;
        zh_CN:uuid_other_system_local) printf '%s' "该代理无法安装在具有该 UUID 的本地计算机上。" ;;
        zh_CN:uuid_reserved) printf '%s' "RSM 中保留并可供安装的 UUID" ;;
        zh_CN:uuid_same_system) printf '%s' "UUID 已在 RSM 中与该系统关联；代理将被重新激活并更新库存" ;;
        zh_CN:uuid_validate_denied) printf '%s' "RSM 不允许 UUID 验证" ;;
        zh_CN:uuid_validate_failed) printf '%s' "无法验证 RSM 中的 UUID" ;;
        zh_CN:uuid_validate_safety) printf '%s' "为了安全起见，在未确认 UUID 可用的情况下，安装不会继续。" ;;
        zh_CN:validating_uuid) printf '%s' "正在 RSM 中验证 UUID..." ;;
        zh_CN:view_inventory) printf '%s' "查看库存：" ;;

        *:banner_subtitle) printf '%s' "System analysis agent for vulnerability detection" ;;
        *:root_mode) printf '%s' "Root/system installation mode selected; system paths will be used." ;;
        *:user_mode) printf '%s' "No-root installation mode selected; the agent will be installed only for the current user." ;;
        *:less_complete) printf '%s' "The inventory may be less complete than root mode if the system restricts some commands." ;;
        *:alias_needed) printf '%s' "This installer needs an alias to identify the system in Firulai." ;;
        *:alias_prompt) printf '%s' "System alias: " ;;
        *:alias_required) printf '%s' "System alias is required." ;;
        *:alias_usage) printf '%s' "Run the installer with the --alias option:" ;;
        *:alias_quotes) printf '%s' "If the alias contains spaces, wrap it in quotes." ;;
        *:validating_uuid) printf '%s' "Validating UUID in RSM..." ;;
        *:uuid_validate_failed) printf '%s' "Could not validate the UUID in RSM" ;;
        *:uuid_validate_safety) printf '%s' "For safety, installation will not continue without confirming that the UUID is available." ;;
        *:uuid_validate_denied) printf '%s' "RSM did not allow UUID validation" ;;
        *:response) printf '%s' "Response" ;;
        *:invalid_uuid_rsm) printf '%s' "Invalid UUID: it does not exist in RSM." ;;
        *:uuid_not_generated) printf '%s' "The agent cannot be installed with a UUID that was not generated from Add New System." ;;
        *:uuid_reserved) printf '%s' "UUID reserved in RSM and available for installation" ;;
        *:uuid_same_system) printf '%s' "UUID already associated with this system in RSM; the agent will be reactivated and inventory updated" ;;
        *:uuid_other_system) printf '%s' "This UUID already belongs to another system in RSM." ;;
        *:uuid_other_system_local) printf '%s' "This agent cannot be installed on the local machine with that UUID." ;;
        *:local_installed_same_uuid) printf '%s' "This system already has an agent installed with this UUID." ;;
        *:existing_agent) printf '%s' "An existing agent installation was found on this system." ;;
        *:uninstall_current) printf '%s' "To install a new agent, uninstall the current one first:" ;;
        *:config_saving) printf '%s' "Saving local agent configuration..." ;;
        *:config_saved) printf '%s' "Configuration saved" ;;
        *:running_initial) printf '%s' "Running initial collection..." ;;
        *:inventory_ok) printf '%s' "Inventory generated successfully" ;;
        *:initial_failed) printf '%s' "Could not generate and send the inventory during the initial run" ;;
        *:failure_details) printf '%s' "Failure details were shown above." ;;
        *:install_completed) printf '%s' "INSTALLATION COMPLETED" ;;
        *:locations) printf '%s' "Locations:" ;;
        *:execution) printf '%s' "Execution:" ;;
        *:automatic) printf '%s' "Automatic" ;;
        *:manual) printf '%s' "Manual" ;;
        *:current_alias) printf '%s' "Current value" ;;
        *:uninstall) printf '%s' "Uninstall:" ;;
        *:no_interactive_cron_default) printf '%s' "No interactive terminal detected; user cron will be used by default." ;;
        *:automatic_execution_setup) printf '%s' "Automatic execution setup:" ;;
        *:scheduler_cron_title) printf '%s' "1) User cron" ;;
        *:scheduler_cron_plus) printf '%s' "+ Does not require root for agent execution and does not depend on an active user session." ;;
        *:scheduler_cron_minus) printf '%s' "- Requires cron/crontab installed, active, and allowed. If not, installation/activation will be attempted and will need privileged access." ;;
        *:scheduler_systemd_title) printf '%s' "2) systemd --user" ;;
        *:scheduler_systemd_plus) printf '%s' "+ Better integration with systemd and systemctl --user." ;;
        *:scheduler_systemd_minus) printf '%s' "- Requires linger to run without an active session. If it is not active, it will be enabled and will need privileged access." ;;
        *:scheduler_prompt) printf '%s' "Choose scheduler [1=cron, 2=systemd-user] (1): " ;;
        *:unknown_scheduler) printf '%s' "Unknown scheduler" ;;
        *:scheduler_usage) printf '%s' "Use 1/cron or 2/systemd-user." ;;
        *:distribution) printf '%s' "Distribution" ;;
        *:checking_dependencies) printf '%s' "Checking dependencies..." ;;
        *:curl_missing) printf '%s' "curl is not installed" ;;
        *:curl_found) printf '%s' "curl found" ;;
        *:bash_required) printf '%s' "bash 4 or higher is required" ;;
        *:bash_found) printf '%s' "bash found" ;;
        *:flock_missing_install) printf '%s' "flock is not installed (normally provided by the util-linux package)" ;;
        *:flock_found) printf '%s' "flock found" ;;
        *:mktemp_missing_install) printf '%s' "mktemp is not installed" ;;
        *:mktemp_found) printf '%s' "mktemp found" ;;
        *:invalid_uuid_local) printf '%s' "is not a valid UUID" ;;
        es_ES:yes_no_suffix) printf '%s' "[s/N]:" ;;
        ca_ES:yes_no_suffix) printf '%s' "[s/N]:" ;;
        ca_ES:preparing_systemd_user_privileged) printf '%s' "Preparant systemd --user amb accés privilegiat..." ;;
        eu_ES:yes_no_suffix) printf '%s' "[b/N]:" ;;
        eu_ES:preparing_systemd_user_privileged) printf '%s' "systemd --user sarbide pribilegiatuarekin prestatzen..." ;;
        gl_ES:yes_no_suffix) printf '%s' "[s/N]:" ;;
        gl_ES:preparing_systemd_user_privileged) printf '%s' "Preparando systemd --user con acceso privilexiado..." ;;
        fr_FR:yes_no_suffix) printf '%s' "[o/N]:" ;;
        fr_FR:preparing_systemd_user_privileged) printf '%s' "Préparation de systemd --user avec accès privilégié..." ;;
        de_DE:yes_no_suffix) printf '%s' "[j/N]:" ;;
        de_DE:preparing_systemd_user_privileged) printf '%s' "systemd --user wird mit privilegiertem Zugriff vorbereitet..." ;;
        it_IT:yes_no_suffix) printf '%s' "[s/N]:" ;;
        it_IT:preparing_systemd_user_privileged) printf '%s' "Preparazione di systemd --user con accesso privilegiato..." ;;
        ja_JP:yes_no_suffix) printf '%s' "[y/N]:" ;;
        ja_JP:preparing_systemd_user_privileged) printf '%s' "特権アクセスで systemd --user を準備しています..." ;;
        zh_CN:yes_no_suffix) printf '%s' "[是/否]:" ;;
        zh_CN:preparing_systemd_user_privileged) printf '%s' "正在使用特权访问准备 systemd --user..." ;;
        *:yes_no_suffix) printf '%s' "[y/N]:" ;;
        *:preparing_systemd_user_privileged) printf '%s' "Preparing systemd --user with privileged access..." ;;
        *:activate_failed) printf '%s' "Could not activate the system in RSM" ;;
        *:activated) printf '%s' "System marked as active in Firulai" ;;
        *:activation_denied) printf '%s' "RSM did not allow system activation" ;;
        *:agent_downloaded) printf '%s' "Agent downloaded" ;;
        *:alias_saved) printf '%s' "This alias is saved in Firulai and can be changed from the interface." ;;
        *:alias_title) printf '%s' "Alias:" ;;
        *:attempted_url) printf '%s' "Attempted URL" ;;
        *:auto_config_failed) printf '%s' "Cannot complete installation with automatic execution." ;;
        *:auto_execution_config_failed) printf '%s' "Could not configure automatic execution" ;;
        *:behavior_title) printf '%s' "Behavior:" ;;
        *:check_that) printf '%s' "Check that:" ;;
        *:checking_cron_auto) printf '%s' "Checking cron requirements for automatic execution..." ;;
        *:checking_systemd_user) printf '%s' "Checking systemd --user requirements..." ;;
        *:cleanup_partial) printf '%s' "Cleaning partial installation..." ;;
        *:configuring_auto) printf '%s' "Configuring automatic execution..." ;;
        *:contact_firulai) printf '%s' "Contact Firulai if you need help." ;;
        *:creating_dirs) printf '%s' "Creating directories..." ;;
        *:cron_active_confirm_failed) printf '%s' "Could not confirm that cron is active. Contact Firulai if you need help." ;;
        *:cron_daemon_required) printf '%s' "Cannot continue with cron if the daemon is not active." ;;
        *:cron_enable_manual) printf '%s' "Enable cron manually or contact Firulai." ;;
        *:cron_enable_prompt) printf '%s' "Do you want us to enable it now? This needs privileged access." ;;
        *:cron_enable_unknown) printf '%s' "Could not determine how to enable cron automatically on this distribution." ;;
        *:cron_inactive) printf '%s' "cron/crond does not appear to be active." ;;
        *:cron_install_manual) printf '%s' "Install cron manually or contact Firulai." ;;
        *:cron_install_prompt) printf '%s' "Do you want us to install cron now? This needs privileged access." ;;
        *:cron_install_unknown) printf '%s' "Could not determine how to install cron automatically on this distribution." ;;
        *:cron_missing) printf '%s' "cron/crontab is not installed." ;;
        *:cron_without_crontab) printf '%s' "Cannot continue with cron without crontab." ;;
        *:crontab_forbidden_1) printf '%s' "The current user cannot manage their crontab." ;;
        *:crontab_forbidden_2) printf '%s' "An administrator must allow crontabs for this user and review cron policies." ;;
        *:crontab_forbidden_3) printf '%s' "This may require privileged access. Contact Firulai if you need help." ;;
        *:crontab_unavailable) printf '%s' "Could not make crontab available. Contact Firulai if you need help." ;;
        *:current_installed_uuid) printf '%s' "Currently installed UUID" ;;
        *:daily_at) printf '%s' "Daily at 3:00 AM" ;;
        *:dirs_created) printf '%s' "Directories created" ;;
        *:download_agent_failed) printf '%s' "Could not download the agent from GitHub" ;;
        *:download_failed) printf '%s' "Could not download" ;;
        *:downloading_agent) printf '%s' "Downloading agent from GitHub..." ;;
        *:downloading_runner) printf '%s' "Downloading automatic execution runner..." ;;
        *:downloading_uninstaller) printf '%s' "Downloading uninstaller from GitHub..." ;;
        *:enabling_cron) printf '%s' "Attempting to enable cron with privileged access..." ;;
        *:enabling_linger) printf '%s' "Attempting to enable linger with privileged access..." ;;
        *:github_accessible) printf '%s' "GitHub is accessible from this server" ;;
        *:includes) printf '%s' "Includes: OS, kernel, CPU, disk models, packages, critical software" ;;
        *:install_cancelled_initial) printf '%s' "Installation cancelled because the initial agent run failed." ;;
        *:install_success) printf '%s' "Installation successful" ;;
        *:installer_title) printf '%s' "Installer" ;;
        *:installing_cron) printf '%s' "Attempting to install cron with privileged access..." ;;
        *:internet_connectivity) printf '%s' "You have internet connectivity" ;;
        *:linger_disabled) printf '%s' "linger is not enabled for" ;;
        *:linger_enable_failed) printf '%s' "Could not enable linger for" ;;
        *:linger_enable_prompt) printf '%s' "Do you want us to enable linger now? This needs privileged access." ;;
        *:marking_active) printf '%s' "Marking system as active in Firulai..." ;;
        *:no_interactive_privileged) printf '%s' "No interactive terminal is available to request privileged access." ;;
        *:no_python_jq) printf '%s' "No Python or jq dependency (pure bash)" ;;
        *:partial_removed) printf '%s' "Partial installation removed" ;;
        *:private_dir_failed) printf '%s' "Could not create a secure private directory" ;;
        *:privileged_needed) printf '%s' "This action needs privileged access." ;;
        *:privileged_not_completed) printf '%s' "The privileged action was not completed. Run the installer as root and choose no-root mode, or run the required command from a root session." ;;
        *:recovery) printf '%s' "Recovery" ;;
        *:recovery_detail) printf '%s' "one pending execution when the system becomes operational again" ;;
        *:requested_uuid) printf '%s' "Requested UUID" ;;
        *:root_coexist) printf '%s' "The no-root installation will coexist with it using current-user paths." ;;
        *:root_cron_configured) printf '%s' "Root cron configured with daily execution and automatic recovery" ;;
        *:root_crontab_failed) printf '%s' "Could not update root crontab" ;;
        *:root_existing) printf '%s' "An existing root installation was found in /opt/rs-agent or /var/lib/rs-agent." ;;
        *:rsm_item_missing) printf '%s' "Could not locate the RSM item associated with the UUID." ;;
        *:rsm_manages_changes) printf '%s' "RSM detects and manages changes" ;;
        *:rsm_status_safety) printf '%s' "For safety, installation will not continue without being able to update the status." ;;
        *:runner_downloaded) printf '%s' "Runner downloaded" ;;
        *:sends_complete) printf '%s' "Sends a complete inventory to RSM on every run" ;;
        *:su_failed) printf '%s' "The privileged action could not be completed with su/root." ;;
        *:su_missing) printf '%s' "su was not found, so root access cannot be requested from this user." ;;
        *:systemd_bus_su) printf '%s' "This can happen after switching user with su because the user systemd bus is not started." ;;
        *:systemd_choose_alternative) printf '%s' "You can run the installer from root and choose no-root mode, choose user cron, or contact Firulai." ;;
        *:systemd_choose_cron) printf '%s' "You can choose user cron or contact Firulai." ;;
        *:systemd_enable_failed) printf '%s' "systemd could not enable rs-agent.timer" ;;
        *:systemd_linger_available_warn) printf '%s' "systemd --user is available, but linger is not enabled for the current user." ;;
        *:systemd_linger_unreliable) printf '%s' "systemd --user will not be reliable without an active session until linger is enabled." ;;
        *:systemd_no_bus) printf '%s' "Cannot continue with systemd --user without a user systemd bus." ;;
        *:systemd_no_linger) printf '%s' "Cannot continue with systemd --user without linger." ;;
        *:systemd_prepare_failed) printf '%s' "Could not prepare systemd --user for" ;;
        *:systemd_prepare_prompt) printf '%s' "Do you want us to prepare systemd --user now? This needs privileged access." ;;
        *:systemd_reload_failed) printf '%s' "systemd could not reload units" ;;
        *:systemd_timer_configured) printf '%s' "systemd timer configured at 03:00 with boot recovery" ;;
        *:systemd_user_enable_failed) printf '%s' "Could not enable systemd --user." ;;
        *:systemd_user_timer_configured) printf '%s' "systemd --user timer configured at 03:00" ;;
        *:systemd_user_try_cron) printf '%s' "Could not enable systemd --user; user cron will be tried instead." ;;
        *:systemd_user_unavailable) printf '%s' "systemd --user is not available for this user/session yet." ;;
        *:test_uuid_alias) printf '%s' "For comparison, use a separate test UUID/alias." ;;
        *:trying_su) printf '%s' "Trying root via su. su asks for the root password and requires root login to be allowed." ;;
        *:uninstall_download_failed) printf '%s' "Could not download the uninstaller from GitHub" ;;
        *:uninstaller_downloaded) printf '%s' "Uninstaller downloaded" ;;
        *:unsafe_owner) printf '%s' "Unsafe directory: is not owned by the current user" ;;
        *:unsafe_symlink) printf '%s' "Unsafe path: is a symbolic link" ;;
        *:update_rsm_missing_uuid) printf '%s' "Could not update RSM because the UUID item was not found." ;;
        *:user_cron_configured) printf '%s' "User cron configured with daily execution and automatic recovery" ;;
        *:user_cron_fallback_session) printf '%s' "User cron will be used to avoid depending on an active session." ;;
        *:user_crontab_failed) printf '%s' "Could not update the current user's crontab" ;;
        *:uuid_conflict_hint) printf '%s' "If the UUID already belongs to another system, generate a new UUID from Add New System." ;;
        *:view_inventory) printf '%s' "View inventory:" ;;
        *) printf '%s' "$key" ;;
    esac
}

resolve_locale_from_rsm() {
    local token="$1"
    local payload response_body account_id locale

    [ -n "$token" ] || return 1
    command -v curl >/dev/null 2>&1 || return 1

    payload="{\"propertyIDs\":[\"$RSM_APP_USER_AGENT_TOKEN_PROPERTY_ID\",\"$RSM_APP_USER_LOCALE_PROPERTY_ID\"],\"translateIDs\":true,\"filterRules\":[{\"propertyID\":\"$RSM_APP_USER_AGENT_TOKEN_PROPERTY_ID\",\"value\":\"$(json_escape "$token")\",\"operation\":\"=\"}]}"
    response_body=$(curl --silent --show-error --location --request GET "$RSM_ITEMS_GET_URL" --header "Authorization: $token" --header "Content-Type: application/json" --data "$payload" --max-time 20 2>/dev/null) || response_body=""
    locale=$(json_extract_rsm_property "$response_body" "$RSM_APP_USER_LOCALE_PROPERTY_ID")
    if [ -n "$locale" ]; then
        normalize_locale "$locale"
        return 0
    fi

    payload="{\"propertyIDs\":[\"$RSM_ACCOUNT_AGENT_TOKEN_PROPERTY_ID\"],\"translateIDs\":true,\"filterRules\":[{\"propertyID\":\"$RSM_ACCOUNT_AGENT_TOKEN_PROPERTY_ID\",\"value\":\"$(json_escape "$token")\",\"operation\":\"=\"}]}"
    response_body=$(curl --silent --show-error --location --request GET "$RSM_ITEMS_GET_URL" --header "Authorization: $token" --header "Content-Type: application/json" --data "$payload" --max-time 20 2>/dev/null) || return 1
    account_id=$(json_extract_first_scalar_key "$response_body" "ID")
    [ -z "$account_id" ] && account_id=$(json_extract_first_scalar_key "$response_body" "id")
    [ -n "$account_id" ] || return 1

    payload="{\"propertyIDs\":[\"$RSM_APP_USER_ACCOUNT_PROPERTY_ID\",\"$RSM_APP_USER_LOCALE_PROPERTY_ID\"],\"translateIDs\":true,\"filterRules\":[{\"propertyID\":\"$RSM_APP_USER_ACCOUNT_PROPERTY_ID\",\"value\":\"$(json_escape "$account_id")\",\"operation\":\"=\"}]}"
    response_body=$(curl --silent --show-error --location --request GET "$RSM_ITEMS_GET_URL" --header "Authorization: $token" --header "Content-Type: application/json" --data "$payload" --max-time 20 2>/dev/null) || return 1
    locale=$(json_extract_rsm_property "$response_body" "$RSM_APP_USER_LOCALE_PROPERTY_ID")
    [ -n "$locale" ] || return 1
    normalize_locale "$locale"
}

resolve_agent_locale() {
    if [ -n "$AGENT_LOCALE" ]; then
        AGENT_LOCALE=$(normalize_locale "$AGENT_LOCALE")
        return 0
    fi

    AGENT_LOCALE=$(resolve_locale_from_rsm "$AGENT_TOKEN" 2>/dev/null || true)
    AGENT_LOCALE=$(normalize_locale "$AGENT_LOCALE")
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
    response_file=$(make_private_temp_file "rsm_install_uuid_check_response")
    payload="{\"propertyIDs\":[\"$RSM_SYSTEM_HOSTNAME_PROPERTY_ID\",\"$RSM_SYSTEM_FQDN_PROPERTY_ID\",\"$RSM_SYSTEM_UUID_PROPERTY_ID\",\"$RSM_SYSTEM_ALIAS_PROPERTY_ID\"],\"translateIDs\":true,\"filterRules\":[{\"propertyID\":\"$RSM_SYSTEM_UUID_PROPERTY_ID\",\"value\":\"$UUID\",\"operation\":\"=\"}]}"

    info "$(t validating_uuid)"

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
    rm -f "$response_file"

    if [ "$exit_code" -ne 0 ]; then
        error "$(t uuid_validate_failed) (curl exit: $exit_code)."
        error "$(t uuid_validate_safety)"
        exit 1
    fi

    if [ "$http_code" != "200" ] && [ "$http_code" != "201" ]; then
        error "$(t uuid_validate_denied) (HTTP $http_code)."
        error "$(t uuid_validate_safety)"
        echo "$(t response): $response_body"
        exit 1
    fi

    if ! printf '%s' "$response_body" | grep -Fq "$UUID"; then
        error "$(t invalid_uuid_rsm)"
        error "$(t uuid_not_generated)"
        echo ""
        echo "UUID: $UUID"
        exit 1
    fi

    RSM_SYSTEM_ITEM_ID=$(json_extract_first_scalar_key "$response_body" "ID")
    [ -z "$RSM_SYSTEM_ITEM_ID" ] && RSM_SYSTEM_ITEM_ID=$(json_extract_first_scalar_key "$response_body" "id")
    if [ -z "$RSM_SYSTEM_ITEM_ID" ]; then
        error "$(t rsm_item_missing)"
        error "$(t rsm_status_safety)"
        exit 1
    fi

    local existing_hostname existing_fqdn
    existing_hostname=$(json_extract_rsm_property "$response_body" "$RSM_SYSTEM_HOSTNAME_PROPERTY_ID")
    existing_fqdn=$(json_extract_rsm_property "$response_body" "$RSM_SYSTEM_FQDN_PROPERTY_ID")

    if [ -z "$existing_hostname" ] && [ -z "$existing_fqdn" ]; then
        log "$(t uuid_reserved)"
        return 0
    fi

    if identity_matches_local_system "$existing_hostname" "$existing_fqdn"; then
        log "$(t uuid_same_system)"
        return 0
    fi

    echo ""
    error "$(t uuid_other_system)"
    error "$(t uuid_other_system_local)"
    exit 1
}

check_existing_installation() {
    if [ -f "$INSTALL_DIR/rs_agent.sh" ] || [ -f "$CONFIG_FILE" ]; then
        local manual_prefix=""
        [ "$RUN_AS_ROOT" = "1" ] && manual_prefix="sudo "
        warn "$(t existing_agent)"
        warn "$(t uninstall_current)"
        warn "  ${manual_prefix}bash $INSTALL_DIR/uninstall.sh"
        exit 1
    fi
}

warn_about_parallel_root_installation() {
    if [ "$RUN_AS_ROOT" = "1" ]; then
        return 0
    fi

    if [ -f "/opt/rs-agent/rs_agent.sh" ] || [ -f "/var/lib/rs-agent/config.env" ]; then
        warn "$(t root_existing)"
        warn "$(t root_coexist)"
        warn "$(t test_uuid_alias)"
    fi
}

check_local_agent_installation() {
    if [ -f "$INSTALL_DIR/rs_agent.sh" ] || [ -f "$CONFIG_FILE" ]; then
        local installed_uuid=""
        if [ -f "$CONFIG_FILE" ]; then
            installed_uuid=$(sed -n "s/^UUID='\([^']*\)'.*/\1/p" "$CONFIG_FILE" | head -1)
        fi

        if [ -n "$installed_uuid" ] && [ "$installed_uuid" = "$UUID" ]; then
            error "$(t local_installed_same_uuid)"
        else
            error "$(t existing_agent)"
            if [ -n "$installed_uuid" ]; then
                echo "$(t current_installed_uuid): $installed_uuid"
            fi
            echo "$(t requested_uuid): $UUID"
        fi

        echo ""
        echo "$(t uninstall_current)"
        if [ "$RUN_AS_ROOT" = "1" ]; then
            echo "  sudo bash $INSTALL_DIR/uninstall.sh"
        else
            echo "  bash $INSTALL_DIR/uninstall.sh"
        fi
        exit 1
    fi
}

update_rsm_system_on_install() {
    local payload response_file http_code exit_code response_body

    if [ -z "$RSM_SYSTEM_ITEM_ID" ]; then
        error "$(t update_rsm_missing_uuid)"
        exit 1
    fi

    response_file=$(make_private_temp_file "rsm_install_system_update_response")
    payload="[{\"ID\":\"$RSM_SYSTEM_ITEM_ID\",\"$RSM_SYSTEM_ALIAS_PROPERTY_ID\":\"$(json_escape "$SYSTEM_ALIAS")\",\"$RSM_SYSTEM_HOSTNAME_STATUS_PROPERTY_ID\":\"$RSM_SYSTEM_HOSTNAME_STATUS_ACTIVE_VALUE\"}]"

    info "$(t marking_active)"

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
        error "$(t activate_failed) (curl exit: $exit_code)."
        exit 1
    fi

    if [ "$http_code" != "200" ] && [ "$http_code" != "201" ]; then
        error "$(t activation_denied) (HTTP $http_code)."
        echo "$(t response): $response_body"
        exit 1
    fi

    log "$(t activated)"
}

cron_daemon_active() {
    if command -v systemctl &> /dev/null && [ -d /run/systemd/system ]; then
        systemctl is-active --quiet cron.service 2>/dev/null && return 0
        systemctl is-active --quiet crond.service 2>/dev/null && return 0
        systemctl is-active --quiet cronie.service 2>/dev/null && return 0
    fi

    if command -v service &> /dev/null; then
        service cron status >/dev/null 2>&1 && return 0
        service crond status >/dev/null 2>&1 && return 0
    fi

    if command -v pgrep &> /dev/null; then
        pgrep -x cron >/dev/null 2>&1 && return 0
        pgrep -x crond >/dev/null 2>&1 && return 0
    fi

    return 1
}

cron_install_command() {
    if command -v apt-get >/dev/null 2>&1; then
        printf '%s' 'apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y cron'
        return 0
    fi

    if command -v dnf >/dev/null 2>&1; then
        printf '%s' 'dnf install -y cronie'
        return 0
    fi

    if command -v yum >/dev/null 2>&1; then
        printf '%s' 'yum install -y cronie'
        return 0
    fi

    if command -v zypper >/dev/null 2>&1; then
        printf '%s' 'zypper --non-interactive install cron'
        return 0
    fi

    return 1
}

cron_enable_command() {
    if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
        printf '%s' 'systemctl enable --now cron.service 2>/dev/null || systemctl enable --now crond.service 2>/dev/null || systemctl enable --now cronie.service'
        return 0
    fi

    if command -v service >/dev/null 2>&1; then
        printf '%s' 'service cron start 2>/dev/null || service crond start'
        return 0
    fi

    return 1
}

offer_install_cron() {
    local command_string

    command_string=$(cron_install_command) || {
        error "$(t cron_install_unknown)"
        error "$(t cron_install_manual)"
        return 1
    }

    warn "$(t cron_missing)"
    if ! ask_yes_no "$(t cron_install_prompt)"; then
        error "$(t cron_without_crontab)"
        return 1
    fi

    info "$(t installing_cron)"
    run_privileged_command "$command_string"
}

offer_enable_cron_daemon() {
    local command_string

    command_string=$(cron_enable_command) || {
        error "$(t cron_enable_unknown)"
        error "$(t cron_enable_manual)"
        return 1
    }

    warn "$(t cron_inactive)"
    if ! ask_yes_no "$(t cron_enable_prompt)"; then
        error "$(t cron_daemon_required)"
        return 1
    fi

    info "$(t enabling_cron)"
    run_privileged_command "$command_string"
}

check_cron_prerequisites() {
    local crontab_error_file

    if ! command -v crontab &> /dev/null; then
        if ! offer_install_cron || ! command -v crontab &> /dev/null; then
            error "$(t crontab_unavailable)"
            return 1
        fi
    fi

    crontab_error_file=$(make_private_temp_file "cron_access_check") || return 1
    if ! crontab -l >/dev/null 2>"$crontab_error_file"; then
        if ! grep -qi "no crontab" "$crontab_error_file"; then
            error "$(t crontab_forbidden_1)"
            error "$(t crontab_forbidden_2)"
            error "$(t crontab_forbidden_3)"
            cat "$crontab_error_file" 2>/dev/null || true
            rm -f "$crontab_error_file"
            return 1
        fi
    fi
    rm -f "$crontab_error_file"

    if ! cron_daemon_active; then
        if ! offer_enable_cron_daemon || ! cron_daemon_active; then
            error "$(t cron_active_confirm_failed)"
            return 1
        fi
    fi
}

cron_scheduler_required() {
    if [ "$RUN_AS_ROOT" = "1" ]; then
        if command -v systemctl &> /dev/null && [ -d /run/systemd/system ]; then
            return 1
        fi
        return 0
    fi

    if [ "$SCHEDULER_CHOICE" = "systemd-user" ]; then
        return 1
    fi

    return 0
}

check_systemd_user_prerequisites() {
    local username
    username=$(id -un)

    if ! systemd_user_available; then
        warn "$(t systemd_user_unavailable)"
        warn "$(t systemd_bus_su)"

        if ! ask_yes_no "$(t systemd_prepare_prompt)"; then
            error "$(t systemd_no_bus)"
            error "$(t systemd_choose_alternative)"
            return 1
        fi

        if ! prepare_systemd_user_manager_with_privileged_access; then
            error "$(t systemd_prepare_failed) $username."
            error "$(t systemd_choose_alternative)"
            return 1
        fi
    fi

    if ! user_linger_enabled && [ "${RS_AGENT_ALLOW_USER_SYSTEMD_WITHOUT_LINGER:-0}" != "1" ]; then
        warn "$(t linger_disabled) $username."
        warn "$(t systemd_linger_unreliable)"

        if ! ask_yes_no "$(t linger_enable_prompt)"; then
            error "$(t systemd_no_linger)"
            error "$(t systemd_choose_cron)"
            return 1
        fi

        info "$(t enabling_linger)"
        if ! prepare_systemd_user_manager_with_privileged_access || ! user_linger_enabled; then
            error "$(t linger_enable_failed) $username."
            error "$(t contact_firulai)"
            return 1
        fi
    fi
}

check_automatic_execution_prerequisites() {
    if [ "$RUN_AS_ROOT" != "1" ] && [ "$SCHEDULER_CHOICE" = "systemd-user" ]; then
        info "$(t checking_systemd_user)"
        check_systemd_user_prerequisites
        return
    fi

    if cron_scheduler_required; then
        info "$(t checking_cron_auto)"
        check_cron_prerequisites
    fi
}

cleanup_partial_installation() {
    warn "$(t cleanup_partial)"
    if [ "$RUN_AS_ROOT" = "1" ] && command -v systemctl &> /dev/null; then
        systemctl disable --now rs-agent.timer >/dev/null 2>&1 || true
        systemctl stop rs-agent.service >/dev/null 2>&1 || true
    fi
    [ -n "$SYSTEMD_SERVICE_FILE" ] && rm -f "$SYSTEMD_SERVICE_FILE"
    [ -n "$SYSTEMD_TIMER_FILE" ] && rm -f "$SYSTEMD_TIMER_FILE"
    if [ "$RUN_AS_ROOT" = "1" ] && command -v systemctl &> /dev/null; then
        systemctl daemon-reload >/dev/null 2>&1 || true
    fi
    if [ "$RUN_AS_ROOT" != "1" ] && command -v systemctl &> /dev/null; then
        systemctl --user disable --now rs-agent.timer >/dev/null 2>&1 || true
        rm -f "$SYSTEMD_USER_SERVICE_FILE" "$SYSTEMD_USER_TIMER_FILE"
        systemctl --user daemon-reload >/dev/null 2>&1 || true
    fi
    if command -v crontab &> /dev/null; then
        ({ crontab -l 2>/dev/null || true; } | grep -Fv "$INSTALL_DIR/rs_agent" || true) | crontab - || true
    fi
    rm -rf "$INSTALL_DIR"
    rm -rf "$DATA_DIR"
    rm -f "$LOG_FILE"
    log "$(t partial_removed)"
}

create_directories() {
    info "$(t creating_dirs)"
    
    mkdir -p "$INSTALL_DIR"
    chown root:root "$INSTALL_DIR" 2>/dev/null || true
    chmod 755 "$INSTALL_DIR"
    ensure_private_directory "$DATA_DIR"
    touch "$LOG_FILE"
    chown root:root "$LOG_FILE" 2>/dev/null || true
    if [ "$RUN_AS_ROOT" = "1" ]; then
        chmod 644 "$LOG_FILE"
    else
        chmod 600 "$LOG_FILE"
    fi
    
    log "$(t dirs_created)"
}

download_agent() {
    info "$(t downloading_agent)"

    AGENT_URL="${GITHUB_RAW_URL}/rs_agent.sh?ts=$(date +%s)"

    if curl -fsSL "$AGENT_URL" -o "$INSTALL_DIR/rs_agent.sh"; then
        chmod +x "$INSTALL_DIR/rs_agent.sh"
        log "$(t agent_downloaded): $INSTALL_DIR/rs_agent.sh"
    else
        error "$(t download_agent_failed)"
        error ""
        error "$(t attempted_url): $AGENT_URL"
        error ""
        error "$(t check_that)"
        error "  - $(t internet_connectivity)"
        error "  - $(t github_accessible)"
        exit 1
    fi
}

download_runner() {
    info "$(t downloading_runner)"

    RUNNER_URL="${GITHUB_RAW_URL}/rs_agent_runner.sh?ts=$(date +%s)"
    if curl -fsSL "$RUNNER_URL" -o "$RUNNER_FILE"; then
        chmod +x "$RUNNER_FILE"
        log "$(t runner_downloaded): $RUNNER_FILE"
    else
        error "$(t download_failed) $RUNNER_URL"
        exit 1
    fi
}

download_uninstaller() {
    info "$(t downloading_uninstaller)"

    UNINSTALLER_URL="${GITHUB_RAW_URL}/uninstall.sh?ts=$(date +%s)"

    if curl -fsSL "$UNINSTALLER_URL" -o "$INSTALL_DIR/uninstall.sh"; then
        chmod +x "$INSTALL_DIR/uninstall.sh"
        log "$(t uninstaller_downloaded): $INSTALL_DIR/uninstall.sh"
    else
        error "$(t uninstall_download_failed)"
        error ""
        error "$(t attempted_url): $UNINSTALLER_URL"
        error ""
        error "$(t check_that)"
        error "  - $(t internet_connectivity)"
        error "  - $(t github_accessible)"
        exit 1
    fi
}

write_agent_config() {
    local temporary_file

    info "$(t config_saving)"

    temporary_file=$(mktemp "$DATA_DIR/config.env.XXXXXX")
    chmod 600 "$temporary_file"
    cat > "$temporary_file" << CONFIG_EOF
AGENT_TOKEN=$(shell_single_quote "$AGENT_TOKEN")
UUID=$(shell_single_quote "$UUID")
SYSTEM_ALIAS=$(shell_single_quote "$SYSTEM_ALIAS")
AGENT_LOCALE=$(shell_single_quote "$AGENT_LOCALE")
CONFIG_EOF
    chown root:root "$temporary_file" 2>/dev/null || true
    mv -f "$temporary_file" "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"

    log "$(t config_saved): $CONFIG_FILE"
}

setup_automatic_execution() {
    info "$(t configuring_auto)"

    if [ "$RUN_AS_ROOT" = "1" ] && command -v systemctl &> /dev/null && [ -d /run/systemd/system ]; then
        cat > "$SYSTEMD_SERVICE_FILE" << SERVICE_EOF
[Unit]
Description=Firulai Inventory Agent execution
Wants=network-online.target
After=network-online.target
ConditionPathExists=$RUNNER_FILE

[Service]
Type=oneshot
ExecStart=/bin/bash $RUNNER_FILE --if-due --trigger systemd-timer
Restart=on-failure
RestartSec=30min
TimeoutStartSec=30min
SyslogIdentifier=rs-agent
SERVICE_EOF

        cat > "$SYSTEMD_TIMER_FILE" << TIMER_EOF
[Unit]
Description=Firulai Inventory Agent daily schedule

[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true
AccuracySec=1min
Unit=rs-agent.service

[Install]
WantedBy=timers.target
TIMER_EOF

        chmod 644 "$SYSTEMD_SERVICE_FILE" "$SYSTEMD_TIMER_FILE"
        if ! systemctl daemon-reload; then
            error "$(t systemd_reload_failed)"
            return 1
        fi
        if ! systemctl enable --now rs-agent.timer; then
            error "$(t systemd_enable_failed)"
            return 1
        fi
        SCHEDULER_TYPE="systemd timer"
        log "$(t systemd_timer_configured)"
        return 0
    fi

    if [ "$RUN_AS_ROOT" != "1" ] && [ "$SCHEDULER_CHOICE" != "cron" ] && systemd_user_available; then
        if ! user_linger_enabled && [ "${RS_AGENT_ALLOW_USER_SYSTEMD_WITHOUT_LINGER:-0}" != "1" ]; then
            warn "$(t systemd_linger_available_warn)"
            warn "$(t user_cron_fallback_session)"
        else
            mkdir -p "$SYSTEMD_USER_DIR"
            cat > "$SYSTEMD_USER_SERVICE_FILE" << SERVICE_EOF
[Unit]
Description=Firulai Inventory Agent execution
ConditionPathExists=$RUNNER_FILE

[Service]
Type=oneshot
ExecStart=/bin/bash $RUNNER_FILE --if-due --trigger systemd-user-timer
Restart=on-failure
RestartSec=30min
TimeoutStartSec=30min
SERVICE_EOF

            cat > "$SYSTEMD_USER_TIMER_FILE" << TIMER_EOF
[Unit]
Description=Firulai Inventory Agent daily schedule

[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true
AccuracySec=1min
Unit=rs-agent.service

[Install]
WantedBy=timers.target
TIMER_EOF

            chmod 644 "$SYSTEMD_USER_SERVICE_FILE" "$SYSTEMD_USER_TIMER_FILE"
            if systemctl --user daemon-reload && systemctl --user enable --now rs-agent.timer; then
                SCHEDULER_TYPE="systemd --user timer"
                log "$(t systemd_user_timer_configured)"
                return 0
            fi

            rm -f "$SYSTEMD_USER_SERVICE_FILE" "$SYSTEMD_USER_TIMER_FILE"
            systemctl --user daemon-reload >/dev/null 2>&1 || true
            if [ "$SCHEDULER_CHOICE" = "systemd-user" ]; then
                error "$(t systemd_user_enable_failed)"
                return 1
            fi
            warn "$(t systemd_user_try_cron)"
        fi
    fi

    if ! check_cron_prerequisites; then
        error "$(t auto_config_failed)"
        return 1
    fi

    local cron_watchdog cron_reboot
    cron_watchdog="*/30 * * * * /bin/bash $RUNNER_FILE --if-due --trigger cron-check >/dev/null 2>&1"
    cron_reboot="@reboot sleep 60; /bin/bash $RUNNER_FILE --if-due --trigger cron-boot >/dev/null 2>&1"

    # Checking every 30 minutes allows the 03:00 run and retries one missed
    # execution without duplicating it thanks to state.env and flock.
    if ! ({ crontab -l 2>/dev/null || true; } | grep -Fv "$INSTALL_DIR/rs_agent" || true; echo "$cron_watchdog"; echo "$cron_reboot") | crontab -; then
        if [ "$RUN_AS_ROOT" = "1" ]; then
            error "$(t root_crontab_failed)"
        else
            error "$(t user_crontab_failed)"
        fi
        return 1
    fi

    if [ "$RUN_AS_ROOT" = "1" ]; then
        SCHEDULER_TYPE="root cron"
        log "$(t root_cron_configured)"
    else
        SCHEDULER_TYPE="user cron"
        log "$(t user_cron_configured)"
    fi
}

test_agent() {
    info "$(t running_initial)"

    set +e
    RS_AGENT_TRIGGER="initial-installation" /bin/bash "$INSTALL_DIR/rs_agent.sh" --token "$AGENT_TOKEN" --uuid "$UUID" --alias "$SYSTEM_ALIAS" --locale "$AGENT_LOCALE" 2>&1 | tee -a "$LOG_FILE"
    local agent_status=${PIPESTATUS[0]}
    set -e

    if [ "$agent_status" -eq 0 ]; then
        if [ -f "$DATA_DIR/inventory.json" ]; then
            INVENTORY_SIZE=$(stat -c%s "$DATA_DIR/inventory.json" 2>/dev/null || stat -f%z "$DATA_DIR/inventory.json" 2>/dev/null)
            log "$(t inventory_ok) (${INVENTORY_SIZE} bytes)"
            return 0
        fi
    fi

    error "$(t initial_failed)"
    info "$(t failure_details)"
    return 1
}

print_summary() {
    local manual_prefix=""
    [ "$RUN_AS_ROOT" = "1" ] && manual_prefix="sudo "

    echo ""
    echo "============================================================================"
    printf '  %s\n' "$(t install_completed)"
    echo "============================================================================"
    echo ""
    echo "$(t locations)"
    echo "   - Agent:       $INSTALL_DIR/rs_agent.sh"
    echo "   - Inventory:   $DATA_DIR/inventory.json"
    echo "   - State:       $DATA_DIR/state.env"
    echo "   - Logs:        $LOG_FILE"
    echo ""
    echo "$(t execution)"
    echo "   - $(t automatic):   $(t daily_at) ($SCHEDULER_TYPE)"
    echo "   - $(t recovery):    $(t recovery_detail)"
    echo "   - $(t manual):      ${manual_prefix}bash $INSTALL_DIR/rs_agent.sh --token <AGENT_TOKEN> --uuid <UUID> --alias <ALIAS> --locale $AGENT_LOCALE"
    echo ""
    echo "$(t alias_title)"
    echo "   - $(t current_alias): $SYSTEM_ALIAS"
    echo "   - $(t alias_saved)"
    echo ""
    echo "$(t view_inventory)"
    echo "   cat $DATA_DIR/inventory.json"
    echo ""
    echo "$(t behavior_title)"
    echo "   - $(t no_python_jq)"
    echo "   - $(t sends_complete)"
    echo "   - $(t rsm_manages_changes)"
    echo "   - $(t banner_subtitle)"
    echo "   - $(t includes)"
    echo ""
    echo "$(t uninstall)"
    echo "   ${manual_prefix}bash $INSTALL_DIR/uninstall.sh"
    echo ""
    echo "============================================================================"
    echo ""
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    resolve_agent_locale
    banner
    
    # Verificaciones
    check_root
    detect_distro
    check_dependencies
    init_private_tmp_dir
    require_system_alias
    choose_scheduler_interactively
    validate_uuid_format "$UUID"
    check_local_agent_installation
    warn_about_parallel_root_installation
    check_automatic_execution_prerequisites
    check_uuid_available
    update_rsm_system_on_install
    
    # Instalacion
    create_directories
    download_agent
    download_runner
    download_uninstaller
    write_agent_config
    
    # Prueba
    echo ""
    if ! test_agent; then
        echo ""
        error "$(t install_cancelled_initial)"
        error "$(t uuid_conflict_hint)"
        cleanup_partial_installation
        exit 1
    fi

    if ! setup_automatic_execution; then
        error "$(t auto_execution_config_failed)"
        cleanup_partial_installation
        exit 1
    fi
    
    # Summary
    print_summary
    
    log "$(t install_success)"
}

# Ejecutar
main "$@"
