# Redsauce Inventory Agent

Agente de inventario para sistemas Linux. Recopila información del sistema, paquetes instalados y software crítico, y la envía a Firulai para su análisis y detección de vulnerabilidades CVE.

---

## Instalación

```bash
curl -fsSL https://raw.githubusercontent.com/redsauce/inventory-agent/main/install.sh | sudo bash -s -- <AGENT_TOKEN> <UUID> --alias <ALIAS>
```

### Modo no-root experimental

La rama `experiment/non-root-agent` permite instalar y ejecutar el agente sin
`sudo` para comparar resultados. No es equivalente al modo root: usa rutas del
usuario, cron de usuario y el inventario puede ser menos completo.

Puede convivir con una instalación root existente en la misma máquina. En ese
caso no toca `/opt/rs-agent` ni `/var/lib/rs-agent`; instala una segunda copia
en rutas del usuario para comparar ambos inventarios.

Rutas usadas en modo no-root:

| Ruta | Descripción |
|------|-------------|
| `~/.local/share/rs-agent/` | Scripts del agente |
| `~/.local/state/rs-agent/` | Configuración, estado, inventario y logs |
| `${XDG_RUNTIME_DIR:-~/.local/state}/rs-agent/tmp/` | Temporales privados del usuario |

El instalador (`install.sh`) realiza los siguientes pasos:

1. **Verifica dependencias** — comprueba que `curl` y bash 4+ estén disponibles.
2. **Crea los directorios** — `/opt/rs-agent` (binario) y `/var/lib/rs-agent` (datos).
3. **Descarga el agente** — obtiene `rs_agent.sh` y `rs_agent_runner.sh` desde GitHub y los deja en `/opt/rs-agent/`.
4. **Configura la ejecución automática** — usa un timer persistente de systemd cuando está disponible; en otros sistemas instala un cron con recuperación al arrancar y comprobación cada 30 minutos.
5. **Primera ejecución** — lanza el agente inmediatamente para generar el inventario inicial.
6. **Instala el desinstalador** — descarga `uninstall.sh`, guarda la configuración local y deja `/opt/rs-agent/uninstall.sh` listo para ejecutar.

### Desinstalación

```bash
sudo bash /opt/rs-agent/uninstall.sh
```

El desinstalador avisa de que solo se borrará la instalación local del agente. No borra datos de RSM. Si se confirma, busca el System por UUID (`1780`) y, si existe, actualiza `Hostnamestatus` (`1751`) a `Disconnected`; después elimina el timer o cron, configuración, estado, inventario, logs y archivos locales del agente. Si el UUID ya no existe en Firulai, la desinstalación local continúa igualmente.

Si se instala de nuevo con un UUID que ya existe y corresponde al mismo equipo, el instalador reutiliza ese System, actualiza el alias y cambia `Hostnamestatus` (`1751`) a `Activo` antes de ejecutar el inventario inicial. Si el UUID pertenece a otro equipo, la instalación se bloquea.

---

El alias es obligatorio. Si no se pasa con la opcion `--alias`, el instalador intentara pedirlo por terminal; si no hay terminal interactiva disponible, la instalacion se detendra indicando que debe incluirse en el comando. El alias se envia a Firulai/RSM como parte de los datos del sistema asociado al UUID, y podra modificarse posteriormente desde Firulai.

## Ejecución automática y recuperación

El inventario está previsto diariamente a las `03:00`, según la hora local del equipo. El agente no enciende ni despierta la máquina. Si estaba apagada o suspendida, ejecuta un único inventario pendiente cuando vuelve a estar operativa, aunque se hayan perdido varios días.

El envío correcto se guarda atómicamente en `/var/lib/rs-agent/state.env`. El estado no se actualiza si falla la recopilación o Firulai no confirma el envío. `flock` evita que el arranque, el programador, un reintento y una ejecución manual trabajen simultáneamente.

Las ejecuciones automáticas escriben en `/var/log/rs-agent.log` y, con systemd, también en el journal del sistema. El token no se incluye en ninguno de estos logs.

### Sistemas con systemd

El instalador crea `rs-agent.service` y `rs-agent.timer` con:

- `OnCalendar=*-*-* 03:00:00`.
- `Persistent=true`, que recupera la ejecución perdida al activar el timer después de arrancar.
- Reintento del servicio cada 30 minutos cuando la ejecución falla.

Comprobar el timer y la siguiente ejecución:

```bash
systemctl status rs-agent.timer
systemctl list-timers rs-agent.timer
```

Consultar las ejecuciones en los logs nativos de Linux:

```bash
journalctl -u rs-agent.service --since "7 days ago"
journalctl -u rs-agent.service -f
```

### Sistemas sin systemd

El fallback de cron comprueba cada 30 minutos si la ejecución de las 03:00 sigue pendiente y también realiza una comprobación 60 segundos después de arrancar mediante `@reboot`. `state.env` hace que estas comprobaciones no generen inventarios duplicados.

```bash
sudo crontab -l | grep rs_agent_runner
```

## Uso manual

```bash
sudo bash /opt/rs-agent/rs_agent.sh --token <AGENT_TOKEN> --uuid <UUID> --alias <ALIAS>
```

Una ejecución manual correcta también actualiza `state.env`, por lo que satisface la ejecución pendiente del día.

## Qué recopila el agente

El agente (`rs_agent.sh`) genera un JSON con cuatro secciones:

### `system`
Información básica del host: hostname, FQDN, UUID, distribución Linux (nombre, versión, ID), versión del kernel y arquitectura.

### `hardware`
Modelo de CPU (vía `lscpu`) y lista de discos con su modelo de firmware (vía `lsblk`), útil para correlacionar CVEs de firmware.

### `packages`
Todos los paquetes instalados, unificados en un único array con el campo `manager` indicando el origen:

| Manager | Fuente |
|---------|--------|
| `dpkg` | Sistemas Debian/Ubuntu (`dpkg-query`) |
| `rpm` | Sistemas RHEL/CentOS/Fedora (`rpm -qa`) |
| `pip` | Paquetes Python (`pip list`) |
| `npm` | Paquetes Node.js globales (`npm list -g`) |

### `core_software`
Versiones de software crítico detectado en el sistema: Apache, nginx, MySQL, PostgreSQL, Docker, PHP, Node.js, Java, OpenSSH, OpenSSL y Git. Cada entrada incluye el nombre, la versión parseada y la salida raw del comando de versión.

---

## Archivos y rutas

| Ruta | Descripción |
|------|-------------|
| `/opt/rs-agent/rs_agent.sh` | Agente principal |
| `/opt/rs-agent/rs_agent_runner.sh` | Comprueba si existe una ejecución pendiente y carga la configuración segura |
| `/var/lib/rs-agent/inventory.json` | Último inventario generado |
| `/var/lib/rs-agent/config.env` | Configuración local usada por el desinstalador |
| `/var/lib/rs-agent/state.env` | Instante UTC y epoch de la última ejecución confirmada |
| `/var/log/rs-agent.log` | Log de ejecuciones automáticas |
| `/opt/rs-agent/uninstall.sh` | Script de desinstalación |
| `/run/rs-agent/tmp/` | Ficheros temporales privados de root, creados con nombres aleatorios mediante `mktemp` |

---

## Requisitos

- Linux (Debian, Ubuntu, RHEL, CentOS, Fedora, Rocky, Alma u otras)
- bash 4+
- curl
- `mktemp`
- `flock` (paquete `util-linux`)
- systemd o cron para la ejecución automática
- Permisos de root
