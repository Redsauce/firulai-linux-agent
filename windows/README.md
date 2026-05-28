# Redsauce Inventory Agent para Windows

Agente de inventario para sistemas Windows. Recopila informacion del sistema, paquetes instalados y software critico, y la envia a Firulai para su analisis y deteccion de vulnerabilidades CVE.

Este documento es para usuarios finales. La guia interna de publicacion y mantenimiento esta en `README_RELEASE.md`.

---

## Instalacion

### Metodo grafico

1. Descarga `RSAgentSetup.exe` desde el Release publicado.
2. Haz doble clic sobre el instalador.
3. Acepta la solicitud de permisos de Administrador de Windows.
4. Introduce el UUID asignado por RSM cuando el asistente lo pida.
5. Finaliza la instalacion.

### Metodo silencioso

Para despliegues automatizados, ejecuta el instalador con el UUID:

```powershell
RSAgentSetup.exe /VERYSILENT /SUPPRESSMSGBOXES /UUID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

El instalador realiza los siguientes pasos:

1. **Verifica privilegios** - solicita permisos de Administrador mediante UAC.
2. **Copia el agente** - instala `RsAgent.exe` en `C:\Program Files\RSAgent\`.
3. **Crea los directorios** - `C:\ProgramData\RSAgent\` y `C:\ProgramData\RSAgent\logs\`.
4. **Escribe la configuracion** - genera `config.json` con el UUID y la URL de la API.
5. **Aplica permisos** - restringe `config.json` a `SYSTEM` y `Administrators`.
6. **Registra el servicio** - crea el servicio Windows `RSAgent` con inicio automatico.
7. **Primera ejecucion** - arranca el servicio y genera/envia el inventario inicial.
8. **Crea el desinstalador** - registra `unins000.exe` en "Agregar o quitar programas".

### Desinstalacion

Desde Windows:

```text
Configuracion -> Apps -> Redsauce Inventory Agent -> Desinstalar
```

Desde PowerShell:

```powershell
& "C:\Program Files\RSAgent\unins000.exe"
```

Desinstalacion silenciosa:

```powershell
& "C:\Program Files\RSAgent\unins000.exe" /VERYSILENT /SUPPRESSMSGBOXES
```

El desinstalador detiene y elimina el servicio `RSAgent`, borra `C:\Program Files\RSAgent\` y, en modo grafico, pregunta si quieres eliminar tambien `C:\ProgramData\RSAgent\`. En modo silencioso elimina tambien configuracion, inventario y logs.

---

## Comprobacion

### Por interfaz grafica

1. Abre `services.msc`.
2. Busca el servicio `RSAgent`.
3. Comprueba que aparece como iniciado y con tipo de inicio automatico.

Para ver el log, abre este archivo con un editor de texto ejecutado como Administrador:

```text
C:\ProgramData\RSAgent\logs\rs_agent.log
```

### Por PowerShell

Ver estado del servicio:

```powershell
Get-Service RSAgent
```

Ver logs:

```powershell
Get-Content "C:\ProgramData\RSAgent\logs\rs_agent.log" -Tail 50
```

---

## Que recopila el agente

El agente (`RsAgent.exe`) genera un JSON con cuatro secciones:

### `system`
Informacion basica del host: hostname, FQDN, UUID, nombre y version de Windows, build, edicion, kernel, arquitectura, zona horaria, fecha de recopilacion y version del agente.

### `hardware`
Modelo de CPU via WMI (`Win32_Processor`) y lista de discos via WMI (`Win32_DiskDrive`) con dispositivo y modelo, util para correlacionar CVEs de firmware.

### `packages`
Todos los paquetes instalados, unificados en un unico array con el campo `manager` indicando el origen:

| Manager | Fuente |
|---------|--------|
| `registry` | Registro de Windows (`HKLM\...\Uninstall`) |
| `winget` | Paquetes visibles con `winget list` |
| `choco` | Paquetes Chocolatey locales |
| `pip` | Paquetes Python (`pip list --format=json`) |
| `npm` | Paquetes Node.js globales (`npm list -g --json`) |

### `core_software`
Versiones de software critico detectado en el sistema: IIS, Apache/httpd, nginx, MySQL, SQL Server, PostgreSQL, PHP, Node.js, Python, Java, Docker, Git, OpenSSH, OpenSSL, PowerShell, .NET runtimes y .NET SDKs. Cada entrada incluye el nombre, la version parseada y la salida raw del comando o fuente de version.

---

## Ejecucion automatica

El agente se ejecuta como servicio Windows `RSAgent`.

- Arranca automaticamente con Windows.
- Ejecuta una primera recopilacion al iniciar el servicio.
- Programa una ejecucion diaria a las 03:00.
- Si falla el envio por red/DNS, reintenta automaticamente cada 30 minutos.

---

## Archivos y rutas

| Ruta | Descripcion |
|------|-------------|
| `C:\Program Files\RSAgent\RsAgent.exe` | Agente principal |
| `C:\ProgramData\RSAgent\config.json` | Configuracion del agente |
| `C:\ProgramData\RSAgent\inventory.json` | Ultimo inventario generado |
| `C:\ProgramData\RSAgent\logs\rs_agent.log` | Log de ejecuciones automaticas |
| `C:\Program Files\RSAgent\unins000.exe` | Desinstalador generado por InnoSetup |

---

## Requisitos

- Windows 10 / Windows Server 2019 o superior
- .NET Framework 4.x
- Permisos de Administrador para instalar
- Conectividad HTTPS hacia `rsm1.redsauce.net`
