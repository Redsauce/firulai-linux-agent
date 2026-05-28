# Redsauce Inventory Agent

Agente de inventario para sistemas Linux. Recopila información del sistema, paquetes instalados y software crítico, y la envía a Firulai para su análisis y detección de vulnerabilidades CVE.

---

## Instalación

```bash
curl -fsSL https://raw.githubusercontent.com/redsauce/inventory-agent/main/install.sh | sudo bash -s <AGENT_TOKEN> <UUID>
```

El instalador (`install.sh`) realiza los siguientes pasos:

1. **Verifica dependencias** — comprueba que `curl` y bash 4+ estén disponibles.
2. **Crea los directorios** — `/opt/rs-agent` (binario) y `/var/lib/rs-agent` (datos).
3. **Descarga el agente** — obtiene `rs_agent.sh` desde GitHub y lo deja en `/opt/rs-agent/`.
4. **Configura el cron** — añade una entrada en el crontab de root para ejecutar el agente diariamente a las 3:00 AM.
5. **Primera ejecución** — lanza el agente inmediatamente para generar el inventario inicial.
6. **Crea el desinstalador** — genera `/opt/rs-agent/uninstall.sh`.

### Desinstalación

```bash
sudo bash /opt/rs-agent/uninstall.sh
```

El desinstalador muestra un aviso de eliminacion completa. Si confirmas, busca en RSM el `System` por el UUID de instalacion, borra sus `Packages`, `Firmware`, `Core Software` y `Custom Software`, y despues borra el propio `System`. Si el `System` sigue existiendo en RSM, cancela la desinstalacion local para poder reintentar. Cuando RSM queda limpio, borra la entrada de cron, `/opt/rs-agent`, `/var/lib/rs-agent` y `/var/log/rs-agent.log`.

---

## Uso manual

```bash
sudo bash /opt/rs-agent/rs_agent.sh --token <AGENT_TOKEN> --uuid <UUID>
```

---

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
| `/var/lib/rs-agent/inventory.json` | Último inventario generado |
| `/var/log/rs-agent.log` | Log de ejecuciones automáticas |
| `/opt/rs-agent/uninstall.sh` | Script de desinstalación |
| `/tmp/rsm_debug_payload.json` | Payload completo de la última llamada a RSM |

---

## Requisitos

- Linux (Debian, Ubuntu, RHEL, CentOS, Fedora, Rocky, Alma u otras)
- bash 4+
- curl
- Permisos de root
