# Redsauce Inventory Agent

Agente de inventario para sistemas Linux. Recopila informacion del sistema, paquetes instalados y software critico, y la envia a Firulai/RSM para analisis y deteccion de vulnerabilidades CVE.

## Instalacion no-root

Esta rama experimental parte de `main` y permite instalar el agente sin usar root:

```bash
curl -fsSL https://raw.githubusercontent.com/Redsauce/firulai-linux-agent/experiment/non-root-install-from-main/install.sh | bash -s -- <AGENT_TOKEN> <UUID> --alias <ALIAS>
```

Si el script se ejecuta sin `sudo`, instala solo para el usuario actual. Si se ejecuta como root, conserva el modo clasico de sistema.

En modo no-root interactivo, el instalador pregunta que scheduler usar. Tambien puede indicarse de forma explicita:

```bash
curl -fsSL https://raw.githubusercontent.com/Redsauce/firulai-linux-agent/experiment/non-root-install-from-main/install.sh | bash -s -- <AGENT_TOKEN> <UUID> --alias <ALIAS> --scheduler cron
curl -fsSL https://raw.githubusercontent.com/Redsauce/firulai-linux-agent/experiment/non-root-install-from-main/install.sh | bash -s -- <AGENT_TOKEN> <UUID> --alias <ALIAS> --scheduler systemd-user
```

## Rutas no-root

Por defecto, en modo usuario:

| Ruta | Descripcion |
|------|-------------|
| `${XDG_DATA_HOME:-~/.local/share}/rs-agent/rs_agent.sh` | Agente principal |
| `${XDG_DATA_HOME:-~/.local/share}/rs-agent/rs_agent_runner.sh` | Runner automatico |
| `${XDG_DATA_HOME:-~/.local/share}/rs-agent/uninstall.sh` | Desinstalador |
| `${XDG_STATE_HOME:-~/.local/state}/rs-agent/config.env` | Token, UUID y alias |
| `${XDG_STATE_HOME:-~/.local/state}/rs-agent/inventory.json` | Ultimo inventario |
| `${XDG_STATE_HOME:-~/.local/state}/rs-agent/state.env` | Ultima ejecucion correcta |
| `${XDG_STATE_HOME:-~/.local/state}/rs-agent/rs-agent.log` | Log |

Estas rutas se pueden sobrescribir con `RS_AGENT_INSTALL_DIR`, `RS_AGENT_DATA_DIR`, `RS_AGENT_LOG_FILE` y `RS_AGENT_TMP_DIR`.

## Ejecucion automatica

El inventario se planifica a las `03:00` hora local.

En modo no-root, el instalador puede usar cron de usuario o `systemd --user`.

Cron de usuario:

- No requiere root.
- Requiere que `cron/crontab` este instalado, activo y permitido para el usuario.
- Si esos requisitos fallan, la instalacion automatica no se completa y se indica contactar con Firulai o con el administrador.

```bash
crontab -l | grep rs_agent_runner
```

`systemd --user`:

- Tiene mejor integracion con systemd.
- Para ejecutarse sin sesion activa necesita `linger`.
- Habilitar `linger` requiere root/admin: `loginctl enable-linger <usuario>`.

```bash
systemctl --user status rs-agent.timer
systemctl --user list-timers rs-agent.timer
```

Con `--scheduler auto`, si `systemd --user` no es fiable por falta de `linger`, se usa cron de usuario como fallback.

## Uso manual

```bash
bash ~/.local/share/rs-agent/rs_agent.sh --token <AGENT_TOKEN> --uuid <UUID> --alias <ALIAS>
```

## Desinstalacion

```bash
bash ~/.local/share/rs-agent/uninstall.sh
```

El desinstalador no-root elimina solo la instalacion del usuario actual. No toca `/opt/rs-agent`, `/var/lib/rs-agent`, unidades globales de systemd ni la instalacion root existente.

## Que recopila

El agente genera un JSON con:

- `system`: hostname, FQDN, UUID, alias, distribucion, kernel, arquitectura, timezone y version del agente.
- `hardware`: modelo de CPU y discos visibles mediante `lscpu` y `lsblk`.
- `components`: paquetes/componentes de `dpkg`, `rpm`, `pip` y `npm`, cuando los comandos esten disponibles para el usuario.
- `packages`: paquetes source derivados de `dpkg-query` en Debian/Ubuntu.

En Debian/Ubuntu normal, un usuario sin privilegios deberia poder listar `dpkg-query` sin problemas. Las diferencias frente a root deberian aparecer sobre todo en comandos restringidos por politicas del sistema, rutas no accesibles, paquetes Python/Node visibles por `PATH`, o informacion de hardware si el entorno esta capado.

## Comparacion con instalacion root

Para comparar resultados en un server que ya tiene el agente root:

1. Mantener la instalacion root existente sin tocar.
2. Crear un usuario normal de prueba, sin sudo ni grupos especiales.
3. Crear en Firulai/RSM un UUID de prueba distinto al UUID usado por el agente root.
4. Iniciar sesion como ese usuario y ejecutar el one-liner no-root de esta rama.
5. Comparar el inventario root con el inventario no-root usando el JSON local y lo recibido en RSM.
6. Revisar especialmente conteos de paquetes `dpkg`, `rpm`, `pip`, `npm`, hardware y campos vacios.

Comandos utiles en el server:

```bash
id
dpkg-query -W | wc -l
cat ~/.local/state/rs-agent/inventory.json
grep -o '"manager":"dpkg"' ~/.local/state/rs-agent/inventory.json | wc -l
grep -o '"manager":"pip"' ~/.local/state/rs-agent/inventory.json | wc -l
grep -o '"manager":"npm"' ~/.local/state/rs-agent/inventory.json | wc -l
```

## Requisitos

- Linux
- bash 4+
- curl
- `mktemp`
- `flock` (`util-linux`)
- `systemd --user` o `cron` para ejecucion automatica
