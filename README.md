# Redsauce Inventory Agent

Agente de inventario automatico para sistemas Linux enfocado en deteccion de vulnerabilidades CVE con auto-actualizacion desde GitHub Releases.

## Instalacion

```bash
curl -fsSL https://raw.githubusercontent.com/redsauce/inventory-agent/main/install.sh | sudo bash -s -- <AGENT_TOKEN> <UUID>
```

## Funcionalidades

- Recopila informacion de sistema operativo (OS, kernel, arquitectura)
- Recopila paquetes instalados (dpkg/rpm/pip/npm) con versiones
- Detecta software critico (Apache, MySQL, PHP, Docker, etc.) con versiones exactas
- **Optimizado para deteccion de CVE**: Solo recopila informacion relevante para vulnerabilidades
- Envío completo del inventario en cada ejecucion: RSM detecta los cambios
- Auto-actualizacion automatica desde GitHub Releases
- Ejecucion diaria programada (3:00 AM)

## Uso basico

```bash
# Ejecucion manual
sudo python3 /opt/rs-agent/rs_agent.py

# Ver inventario
cat /var/lib/rs-agent/inventory.json | python3 -m json.tool

# Analizar inventario
sudo python3 /opt/rs-agent/analyze_inventory.py

# Desinstalar
sudo bash /opt/rs-agent/uninstall.sh
```

**Ubicaciones:**

- Agente: `/opt/rs-agent/rs_agent.py`
- Inventario: `/var/lib/rs-agent/inventory.json`
- Logs: `/var/log/rs-agent.log`

---

## Sistema de Auto-actualizacion

El agente comprueba GitHub Releases cada vez que se ejecuta. Si detecta una version nueva, se actualiza automaticamente.

### Publicar nueva version

1. **Editar version en el codigo:**

```bash
# Cambiar linea 23 en rs_agent.py: AGENT_VERSION = "0.3.0"
git add rs_agent.py
git commit -m "Update to v0.3.0: [descripcion]"
git push
```

2. **Crear Release en GitHub:**
   - https://github.com/redsauce/inventory-agent/releases/new
   - Tag: `0.3.0` (sin `v`)
   - Title: `v0.3.0`
   - Publish release

3. **Los clientes se actualizan automaticamente** en las proximas 24h.

### Versionado Semantico

```
MAJOR.MINOR.PATCH
  0  .  2  .  0
  |     |     |-- Bug fixes
  |     |-------- Nuevas funcionalidades
  |-------------- Cambios incompatibles
```

### Ver version instalada

```bash
grep "AGENT_VERSION" /opt/rs-agent/rs_agent.py
```

---

## Estructura del Inventario JSON

```json
{
  "system": {
    "hostname": "servidor-web-01",
    "fqdn": "servidor-web-01.ejemplo.com",
    "os": {
      "name": "Ubuntu",
      "version": "22.04.3 LTS (Jammy Jellyfish)",
      "distro_id": "ubuntu",
      "distro_version": "22.04",
      "kernel": "5.15.0-91-generic",
      "architecture": "x86_64"
    },
    "collected_at": "2025-01-27T10:30:00.000000",
    "agent_version": "0.2.0"
  },
  "packages": [
    {
      "name": "openssl",
      "version": "3.0.2-0ubuntu1.12",
      "manager": "dpkg"
    },
    {
      "name": "requests",
      "version": "2.28.1",
      "manager": "pip"
    }
  ],
  "critical_software": [
    {
      "name": "nginx",
      "version": "1.18.0"
    },
    {
      "name": "openssl",
      "version": "3.0.2"
    }
  ]
}
```

## Requisitos

- Linux (Ubuntu, Debian, RHEL, CentOS, Fedora)
- Python 3.6+ con `requests`
- Permisos root

## Seguridad

- Solo lectura (no modifica el sistema)
- No recopila contraseñas ni claves
- No recopila informacion de hardware sensible
- Open source y auditable

---

**Redsauce** - 2026 | [redsauce.net](https://redsauce.net)
