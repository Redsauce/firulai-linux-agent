#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Redsauce Inventory Agent - Recopilador de inventario de sistemas Linux
Version: 0.2.0 (con modelo de firmware para CVE, sin tamaño)
Requiere: Permisos de root/sudo
"""

import json
import subprocess
import platform
import socket
import os
import sys
import re
import argparse
import uuid
from datetime import datetime
from pathlib import Path

try:
    import requests
except ImportError:
    requests = None

# ============ CONFIGURACION ============

# Version actual del agente
AGENT_VERSION = "0.2.0"

# URLs de GitHub para auto-actualizacion
GITHUB_API_URL = "https://api.github.com/repos/redsauce/inventory-agent/releases/latest"
GITHUB_AGENT_URL = "https://raw.githubusercontent.com/redsauce/inventory-agent/main/rs_agent.py"

# Directorio donde se guardara el inventario
OUTPUT_DIR = "/var/lib/rs-agent"

# Archivos de salida
OUTPUT_FILE = "inventory.json"

# Configuracion RSM
RSM_API_URL = "https://rsm1.redsauce.net/AppController/commands_RSM/api/api.php"

# Inicializadas via argparse en main()
AGENT_TOKEN = ""
UUID        = ""

# ============ UTILIDADES ============

def run_command(cmd, shell=True, ignore_errors=False):
    """
    Ejecuta un comando y retorna su salida
    """
    try:
        result = subprocess.run(
            cmd,
            shell=shell,
            capture_output=True,
            text=True,
            timeout=30
        )
        if result.returncode != 0 and not ignore_errors:
            return None
        return result.stdout.strip()
    except subprocess.TimeoutExpired:
        print(f"Timeout ejecutando: {cmd}")
        return None
    except Exception as e:
        if not ignore_errors:
            print(f"Error ejecutando {cmd}: {e}")
        return None

def detect_distro():
    """
    Detecta la distribucion Linux
    """
    # Intentar con /etc/os-release (metodo moderno)
    if os.path.exists("/etc/os-release"):
        os_release = {}
        with open("/etc/os-release", "r") as f:
            for line in f:
                if "=" in line:
                    key, value = line.strip().split("=", 1)
                    os_release[key] = value.strip('"')
        
        return {
            "name": os_release.get("NAME", "Unknown"),
            "version": os_release.get("VERSION", "Unknown"),
            "id": os_release.get("ID", "unknown"),
            "version_id": os_release.get("VERSION_ID", "Unknown")
        }
    
    # Fallback para sistemas antiguos
    if os.path.exists("/etc/redhat-release"):
        with open("/etc/redhat-release", "r") as f:
            content = f.read().strip()
            return {"name": content, "version": "Unknown", "id": "rhel-based", "version_id": "Unknown"}
    
    if os.path.exists("/etc/debian_version"):
        with open("/etc/debian_version", "r") as f:
            version = f.read().strip()
            return {"name": "Debian", "version": version, "id": "debian", "version_id": version}
    
    return {"name": "Unknown", "version": "Unknown", "id": "unknown", "version_id": "Unknown"}

def get_package_manager():
    """
    Detecta el gestor de paquetes disponible
    """
    managers = {
        "dpkg": "dpkg -l",
        "rpm": "rpm -qa",
        "apt": "apt list --installed",
        "yum": "yum list installed",
        "dnf": "dnf list installed"
    }
    
    for manager, cmd in managers.items():
        if run_command(f"which {manager}", ignore_errors=True):
            return manager
    
    return None

# ============ RECOPILADORES ============

def collect_system_info():
    """
    Informacion basica del sistema (relevante para CVE)
    """
    distro = detect_distro()
    
    return {
        "hostname": socket.gethostname(),
        "fqdn": socket.getfqdn(),
        "os": {
            "name": distro["name"],
            "version": distro["version"],
            "distro_id": distro["id"],
            "distro_version": distro["version_id"],
            "kernel": platform.release(),
            "architecture": platform.machine()
        },
        "python_version": platform.python_version(),
        "collected_at": datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
        "agent_version": AGENT_VERSION
    }

def collect_hardware():
    """
    Informacion de hardware (CPU y modelo de firmware para CVE)
    """
    hardware = {}
    
    # CPU Model
    cpu_info = run_command("lscpu")
    if cpu_info:
        for line in cpu_info.split('\n'):
            if "Model name:" in line:
                hardware["cpu_model"] = line.split(":", 1)[1].strip()
                break
    
    # Firmware (solo modelo para CVE de firmware)
    firmware = []
    disk_info = run_command("lsblk -d -o NAME,TYPE,MODEL -n")
    if disk_info:
        for line in disk_info.split('\n'):
            parts = line.split()
            if len(parts) >= 2 and parts[1] == "disk":
                firmware.append({
                    "device": f"/dev/{parts[0]}",
                    "model": " ".join(parts[2:]) if len(parts) > 2 else "Unknown"
                })
    hardware["firmware"] = firmware
    
    return hardware

def collect_packages_dpkg():
    """
    Recopila paquetes instalados via dpkg (Debian/Ubuntu)
    """
    packages = []
    output = run_command("dpkg-query -W -f='${Package}\t${Version}\t${Status}\n'")
    
    if output:
        for line in output.split('\n'):
            parts = line.split('\t')
            if len(parts) >= 3 and "installed" in parts[2]:
                packages.append({
                    "name": parts[0],
                    "version": parts[1],
                    "manager": "dpkg"
                })
    
    return packages

def collect_packages_rpm():
    """
    Recopila paquetes instalados via rpm (RHEL/CentOS/Fedora)
    """
    packages = []
    output = run_command("rpm -qa --queryformat '%{NAME}\t%{VERSION}-%{RELEASE}\n'")
    
    if output:
        for line in output.split('\n'):
            parts = line.split('\t')
            if len(parts) >= 2:
                packages.append({
                    "name": parts[0],
                    "version": parts[1],
                    "manager": "rpm"
                })
    
    return packages

def collect_packages():
    """
    Recopila todos los paquetes del sistema
    """
    pkg_manager = get_package_manager()
    
    if pkg_manager in ["dpkg", "apt"]:
        return collect_packages_dpkg()
    elif pkg_manager in ["rpm", "yum", "dnf"]:
        return collect_packages_rpm()
    else:
        print("No se detecto un gestor de paquetes compatible")
        return []

def collect_pip_packages():
    """
    Recopila paquetes Python instalados
    """
    packages = []
    
    # Intentar con pip3
    for pip_cmd in ["pip3", "pip"]:
        output = run_command(f"{pip_cmd} list --format=json", ignore_errors=True)
        if output:
            try:
                pip_list = json.loads(output)
                for pkg in pip_list:
                    packages.append({
                        "name": pkg["name"],
                        "version": pkg["version"],
                        "manager": "pip"
                    })
                break  # Si funciono, no intentar el otro
            except json.JSONDecodeError:
                continue
    
    return packages

def collect_npm_packages():
    """
    Recopila paquetes Node.js globales
    """
    packages = []
    output = run_command("npm list -g --depth=0 --json", ignore_errors=True)
    
    if output:
        try:
            npm_data = json.loads(output)
            deps = npm_data.get("dependencies", {})
            for name, info in deps.items():
                packages.append({
                    "name": name,
                    "version": info.get("version", "unknown"),
                    "manager": "npm"
                })
        except json.JSONDecodeError:
            pass
    
    return packages

def collect_core_software():
    """
    Detecta versiones de software core comun
    Retorna array de objetos con estructura: {name, version, raw_output}
    """
    software = []
    
    # Lista de software a detectar con regex para extraer version
    checks = {
        "apache2": {
            "cmd": "apache2 -v",
            "regex": r"Apache/(\d+\.\d+\.\d+)"
        },
        "httpd": {
            "cmd": "httpd -v",
            "regex": r"Apache/(\d+\.\d+\.\d+)"
        },
        "nginx": {
            "cmd": "nginx -v",
            "regex": r"nginx/(\d+\.\d+\.\d+)"
        },
        "mysql": {
            "cmd": "mysql --version",
            "regex": r"Ver (\d+\.\d+\.\d+)"
        },
        "mysqld": {
            "cmd": "mysqld --version",
            "regex": r"Ver (\d+\.\d+\.\d+)"
        },
        "postgresql": {
            "cmd": "psql --version",
            "regex": r"PostgreSQL[)\s]+(\d+\.\d+(?:\.\d+)?)"
        },
        "postgres": {
            "cmd": "postgres --version",
            "regex": r"PostgreSQL[)\s]+(\d+\.\d+(?:\.\d+)?)"
        },
        "docker": {
            "cmd": "docker --version",
            "regex": r"Docker version (\d+\.\d+\.\d+)"
        },
        "php": {
            "cmd": "php --version",
            "regex": r"PHP (\d+\.\d+\.\d+)"
        },
        "node": {
            "cmd": "node --version",
            "regex": r"v(\d+\.\d+\.\d+)"
        },
        "java": {
            "cmd": "java -version",
            "regex": r'version "(\d+\.\d+\.\d+)'
        },
        "python3": {
            "cmd": "python3 --version",
            "regex": r"Python (\d+\.\d+\.\d+)"
        },
        "openssh": {
            "cmd": "ssh -V",
            "regex": r"OpenSSH_(\d+\.\d+p?\d*)"
        },
        "openssl": {
            "cmd": "openssl version",
            "regex": r"OpenSSL (\d+\.\d+\.\d+[a-z]?)"
        },
        "git": {
            "cmd": "git --version",
            "regex": r"git version (\d+\.\d+\.\d+)"
        }
    }
    
    for name, config in checks.items():
        raw_output = run_command(config["cmd"], ignore_errors=True)
        if raw_output:
            # Extraer solo la primera linea
            first_line = raw_output.split('\n')[0]
            
            # Intentar extraer version limpia con regex
            version = "unknown"
            if "regex" in config:
                match = re.search(config["regex"], first_line)
                if match:
                    version = match.group(1)
            
            software.append({
                "name": name,
                "version": version,
                "raw_output": first_line
            })
    
    return software

# ============ ENVIO A RSM ============

def send_to_rsm(inventory):
    """
    Envia el inventario completo a RSM mediante curl
    Retorna True si el envio fue exitoso, False en caso contrario
    """
    print("\nEnviando inventario a RSM...")
    
    # Convertir inventario completo a JSON
    rsm_json = json.dumps(inventory, ensure_ascii=False)
    
    # Informacion basica del inventario
    print(f"\nEstructura del inventario:")
    print(f"   - Total packages: {len(inventory.get('packages', []))}")
    
    # Contar por tipo de manager
    packages = inventory.get('packages', [])
    dpkg_count = sum(1 for p in packages if p.get('manager') == 'dpkg')
    rpm_count = sum(1 for p in packages if p.get('manager') == 'rpm')
    pip_count = sum(1 for p in packages if p.get('manager') == 'pip')
    npm_count = sum(1 for p in packages if p.get('manager') == 'npm')
    
    print(f"     - Sistema (dpkg/rpm): {dpkg_count + rpm_count}")
    print(f"     - Python (pip): {pip_count}")
    print(f"     - Node.js (npm): {npm_count}")
    print(f"   - Core software: {len(inventory.get('core_software', []))}")
    print(f"   - Firmware detectados: {len(inventory.get('hardware', {}).get('firmware', []))}")
    
    # Mostrar software core detectado con versiones
    core_sw = inventory.get('core_software', [])
    if core_sw:
        print(f"     - Detectados:")
        for sw in core_sw[:5]:  # Mostrar solo los primeros 5
            print(f"       - {sw['name']}: {sw['version']}")
        if len(core_sw) > 5:
            print(f"       - ... y {len(core_sw) - 5} mas")
    
    print(f"\nLongitud total del JSON: {len(rsm_json)} caracteres ({len(rsm_json)/1024:.2f} KB)")
    
    # Guardar JSON completo en archivo temporal
    debug_json_path = "/tmp/rsm_debug_payload.json"
    with open(debug_json_path, 'w') as f:
        f.write(rsm_json)
    print(f"JSON completo guardado en: {debug_json_path}")

    # Construir comando curl
    curl_cmd = [
        'curl',
        '--location', RSM_API_URL,
        '--form', 'RStrigger=newServerData',
        '--form', f'RSdata={rsm_json}',
        '--form', f'RStoken={AGENT_TOKEN}',
        '--max-time', '30',
        '--show-error',
        '--verbose'
    ]

    print(f"   - Token (repr): {repr(AGENT_TOKEN)}")
    
    # Configuracion RSM
    print(f"\nConfiguracion RSM:")
    print(f"   - URL: {RSM_API_URL}")
    print(f"   - Token: {AGENT_TOKEN}")
    print(f"   - Hostname: {inventory.get('system', {}).get('hostname', 'N/A')}")
    
    try:
        print(f"\nEjecutando peticion a RSM...")
        
        # Ejecutar curl
        result = subprocess.run(
            curl_cmd,
            capture_output=True,
            text=True,
            timeout=35
        )
        
        # Mostrar respuesta completa
        print(f"\nCodigo de salida: {result.returncode}")
        
        if result.stdout:
            print(f"STDOUT del servidor:")
            print(f"   {result.stdout}")
        
        if result.stderr:
            print(f"STDERR (info de curl):")
            stderr_lines = result.stderr.split('\n')
            for line in stderr_lines[:30]:
                if line.strip():
                    print(f"   {line}")
        
        if result.returncode == 0:
            print(f"\nInventario enviado correctamente ({len(rsm_json)/1024:.2f} KB)")
            return True
        else:
            print(f"\nERROR: Fallo al enviar inventario a RSM")
            return False
            
    except subprocess.TimeoutExpired:
        print("ERROR: Timeout al enviar datos a RSM (>30s)")
        return False
    except Exception as e:
        print(f"ERROR: Excepcion al enviar datos a RSM: {e}")
        import traceback
        traceback.print_exc()
        return False

# ============ AUTO-ACTUALIZACION ============

def check_for_updates():
    """Comprueba si hay nueva version en GitHub Releases"""
    if not requests:
        return False  # Si no hay requests, no puede actualizar
    
    try:
        response = requests.get(GITHUB_API_URL, timeout=5)
        if response.status_code == 200:
            data = response.json()
            latest_version = data['tag_name'].lstrip('v')  # Por si usa v0.1.0
            
            if latest_version > AGENT_VERSION:
                print(f"Nueva version disponible: {latest_version} (actual: {AGENT_VERSION})")
                return download_update()
    except Exception as e:
        # Falla silenciosamente para no interrumpir el inventario
        pass
    
    return False

def download_update():
    """Descarga e instala la nueva version"""
    try:
        print("Descargando actualizacion...")
        response = requests.get(GITHUB_AGENT_URL, timeout=10)
        
        if response.status_code == 200:
            script_path = "/opt/rs-agent/rs_agent.py"
            
            # Guardar backup
            backup_path = script_path + ".backup"
            if os.path.exists(script_path):
                os.rename(script_path, backup_path)
            
            # Escribir nueva version
            with open(script_path, 'w') as f:
                f.write(response.text)
            os.chmod(script_path, 0o755)
            
            print("Actualizacion completada. Reiniciando agente...")
            
            # Re-ejecutar el script actualizado
            os.execv(sys.executable, [sys.executable] + sys.argv)
            
        return True
        
    except Exception as e:
        print(f"Error actualizando: {e}")
        # Restaurar backup si existe
        if os.path.exists(backup_path):
            os.rename(backup_path, script_path)
        return False

# ============ MAIN ============

def parse_args():
    def valid_uuid(value):
        try:
            uuid.UUID(value)
            return value
        except ValueError:
            raise argparse.ArgumentTypeError(f"'{value}' no es un UUID válido")

    parser = argparse.ArgumentParser(description="Redsauce Inventory Agent")
    parser.add_argument("--token",     required=True, help="Agent token (AGENT_TOKEN)")
    parser.add_argument("--uuid", required=True, type=valid_uuid, help="RSM UUID (formato UUID)")
    return parser.parse_args()


def check_root():
    """
    Verifica que el script se ejecute como root
    """
    if os.geteuid() != 0:
        print("ERROR: Este script requiere permisos de root")
        print("   Ejecuta con: sudo python3 rs_agent.py")
        sys.exit(1)

def ensure_output_dir():
    """
    Crea el directorio de salida si no existe
    """
    Path(OUTPUT_DIR).mkdir(parents=True, exist_ok=True)

def main():
    global AGENT_TOKEN, UUID
    args = parse_args()
    AGENT_TOKEN = args.token
    UUID        = args.uuid

    print("\n" + "="*60)
    print("Redsauce Inventory Agent - Recopilando informacion")
    print("="*60 + "\n")
    
    # Verificar permisos
    check_root()
    
    # Comprobar actualizaciones (antes de recopilar inventario)
    if check_for_updates():
        return  # Si se actualizo, el script se re-ejecuta automaticamente
    
    # Crear directorio de salida
    ensure_output_dir()
    
    # Recopilar informacion
    inventory = {}
    
    print("Recopilando informacion del sistema...")
    inventory["system"] = collect_system_info()
    inventory["system"]["uuid"] = UUID
    inventory["system"]["agent_token"] = AGENT_TOKEN

    print("Recopilando informacion de hardware...")
    inventory["hardware"] = collect_hardware()
    
    # Mostrar firmware detectados
    firmware = inventory["hardware"].get("firmware", [])
    print(f"   -> {len(firmware)} firmware(s) detectado(s)")
    for disk in firmware:
        print(f"      - {disk['device']}: {disk['model']}")
    
    print("Recopilando paquetes del sistema...")
    system_packages = collect_packages()
    print(f"   -> {len(system_packages)} paquetes del sistema")
    
    print("Recopilando paquetes Python...")
    pip_packages = collect_pip_packages()
    print(f"   -> {len(pip_packages)} paquetes Python")
    
    print("Recopilando paquetes Node.js...")
    npm_packages = collect_npm_packages()
    print(f"   -> {len(npm_packages)} paquetes Node.js")
    
    # Unificar todos los paquetes en un solo array
    all_packages = system_packages + pip_packages + npm_packages
    inventory["packages"] = all_packages
    print(f"   Total unificado: {len(all_packages)} paquetes")
    
    print("Detectando software core...")
    inventory["core_software"] = collect_core_software()
    core_count = len(inventory['core_software'])
    print(f"   -> {core_count} aplicaciones detectadas")
    
    # Mostrar algunas versiones detectadas
    if core_count > 0:
        parsed_count = sum(1 for sw in inventory["core_software"] if sw['version'] != 'unknown')
        print(f"   -> {parsed_count}/{core_count} versiones parseadas correctamente")
    
    output_path = os.path.join(OUTPUT_DIR, OUTPUT_FILE)
    
    # Guardar inventario localmente
    print(f"\nGuardando inventario en {output_path}...")
    
    with open(output_path, 'w') as f:
        json.dump(inventory, f, indent=2)
    
    # Enviar datos a RSM (siempre, sin comprobar cambios)
    if not send_to_rsm(inventory):
        print("\n" + "="*60)
        print("ERROR CRITICO: No se pudo enviar el inventario a RSM")
        print("="*60)
        print("\nVerifica:")
        print(f"   - Token: {AGENT_TOKEN}")
        print(f"   - UUID: {UUID}")
        print(f"   - URL: {RSM_API_URL}")
        print(f"   - Conectividad de red")
        print()
        sys.exit(1)
    
    # Estadisticas finales
    total_packages = len(inventory['packages'])
    
    print("\n" + "="*60)
    print("Inventario recopilado y enviado correctamente")
    print("="*60)
    print(f"\nResumen:")
    print(f"   - Sistema: {inventory['system']['os']['name']} {inventory['system']['os']['version']}")
    print(f"   - Hostname: {inventory['system']['hostname']}")
    print(f"   - CPU: {inventory['hardware'].get('cpu_model', 'N/A')}")
    print(f"   - Firmware: {len(firmware)}")
    print(f"   - Total paquetes: {total_packages}")
    print(f"   - Software core: {len(inventory['core_software'])}")
    print(f"   - Archivo: {output_path}")
    print(f"   - Tamano: {os.path.getsize(output_path) / 1024:.2f} KB")
    print()

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\nProceso interrumpido por el usuario")
        sys.exit(1)
    except Exception as e:
        print(f"\nError inesperado: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)