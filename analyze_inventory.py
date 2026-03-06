#!/usr/bin/env python3
"""
Herramienta de analisis de inventario - Redsauce Agent
Muestra estadisticas y resumen del ultimo inventario recopilado
Version: 0.2.3 - Enfocado en vulnerabilidades CVE (modelo de firmware sin tamaño)
"""

import json
import sys
from pathlib import Path
from datetime import datetime

INVENTORY_FILE = "/var/lib/rs-agent/inventory.json"

def load_inventory():
    """Carga el archivo de inventario"""
    if not Path(INVENTORY_FILE).exists():
        print(f"No se encuentra el inventario en: {INVENTORY_FILE}")
        print("   Ejecuta primero: sudo python3 /opt/rs-agent/rs_agent.py")
        sys.exit(1)
    
    with open(INVENTORY_FILE, 'r') as f:
        return json.load(f)

def print_section(title):
    """Imprime encabezado de seccion"""
    print(f"\n{'='*70}")
    print(f"  {title}")
    print(f"{'='*70}")

def analyze_system(inventory):
    """Analiza informacion del sistema"""
    print_section("INFORMACION DEL SISTEMA")
    
    system = inventory.get('system', {})
    os_info = system.get('os', {})
    
    print(f"Hostname:           {system.get('hostname', 'N/A')}")
    print(f"FQDN:               {system.get('fqdn', 'N/A')}")
    print(f"OS:                 {os_info.get('name', 'N/A')} {os_info.get('version', 'N/A')}")
    print(f"Distribucion:       {os_info.get('distro_id', 'N/A')}")
    print(f"Kernel:             {os_info.get('kernel', 'N/A')}")
    print(f"Arquitectura:       {os_info.get('architecture', 'N/A')}")
    print(f"Python:             {system.get('python_version', 'N/A')}")
    print(f"Version del agente: {system.get('agent_version', 'N/A')}")
    
    collected_at = system.get('collected_at', 'N/A')
    if collected_at != 'N/A':
        try:
            dt = datetime.fromisoformat(collected_at)
            print(f"Recopilado:         {dt.strftime('%d/%m/%Y %H:%M:%S')}")
        except:
            print(f"Recopilado:         {collected_at}")

def analyze_hardware(inventory):
    """Analiza informacion de hardware (CPU y modelos de firmware)"""
    print_section("HARDWARE")
    
    hardware = inventory.get('hardware', {})
    
    if not hardware:
        print("No se encontro informacion de hardware")
        return
    
    # CPU Model
    cpu_model = hardware.get('cpu_model', 'N/A')
    print(f"CPU Model:          {cpu_model}")
    
    # Firmware (solo modelo)
    firmware = hardware.get('firmware', [])
    print(f"\nFirmware:           {len(firmware)} dispositivo(s)")
    
    if firmware:
        for disk in firmware:
            model = disk.get('model', 'Unknown')
            device = disk.get('device', 'N/A')
            print(f"  - {device:15s} {model}")
    
    print(f"\nNOTA: Informacion relevante para CVE de CPU (Spectre/Meltdown)")
    print(f"      y vulnerabilidades de firmware (Samsung, WD, etc.)")

def analyze_packages(inventory):
    """Analiza paquetes instalados"""
    print_section("PAQUETES INSTALADOS")
    
    # Paquetes unificados
    packages = inventory.get('packages', [])
    
    # Contar por tipo
    dpkg_count = sum(1 for p in packages if p.get('manager') == 'dpkg')
    rpm_count = sum(1 for p in packages if p.get('manager') == 'rpm')
    pip_count = sum(1 for p in packages if p.get('manager') == 'pip')
    npm_count = sum(1 for p in packages if p.get('manager') == 'npm')
    
    print(f"Sistema (dpkg/rpm): {dpkg_count + rpm_count} paquetes")
    print(f"Python (pip):       {pip_count} paquetes")
    print(f"Node.js (npm):      {npm_count} paquetes")
    print(f"\nTOTAL:              {len(packages)} paquetes")
    
    # Top 10 paquetes del sistema
    system_packages = [p for p in packages if p.get('manager') in ['dpkg', 'rpm']]
    if system_packages:
        print(f"\nTop 10 paquetes del sistema:")
        for pkg in system_packages[:10]:
            print(f"  - {pkg['name']:40s} {pkg['version']}")
    
    # Paquetes Python
    pip_packages = [p for p in packages if p.get('manager') == 'pip']
    if pip_packages:
        print(f"\nTop 10 paquetes Python:")
        for pkg in pip_packages[:10]:
            print(f"  - {pkg['name']:40s} {pkg['version']}")

def analyze_core_software(inventory):
    """Analiza software core detectado"""
    print_section("SOFTWARE CORE DETECTADO")
    
    software = inventory.get('core_software', [])
    
    if not software:
        print("No se detecto software core")
        return
    
    print(f"Total: {len(software)} aplicaciones\n")
    
    # Categorizar
    categories = {
        'Servidores Web': ['apache2', 'httpd', 'nginx'],
        'Bases de Datos': ['mysql', 'mysqld', 'postgresql', 'postgres'],
        'Lenguajes': ['python3', 'php', 'node', 'java'],
        'Herramientas': ['docker', 'git', 'openssh', 'openssl']
    }
    
    for category, keywords in categories.items():
        found = [sw for sw in software if sw['name'] in keywords]
        if found:
            print(f"{category}:")
            for sw in found:
                version_display = sw['version']
                # Si tiene raw_output y es diferente a version, mostrar ambos
                if 'raw_output' in sw and sw['version'] not in sw['raw_output']:
                    version_display = f"{sw['version']} ({sw['raw_output'][:50]}...)" if len(sw['raw_output']) > 50 else f"{sw['version']} ({sw['raw_output']})"
                print(f"  - {sw['name']:15s} -> {version_display}")
            print()
    
    # Mostrar todas las versiones no categorizadas
    categorized_names = [name for names in categories.values() for name in names]
    uncategorized = [sw for sw in software if sw['name'] not in categorized_names]
    
    if uncategorized:
        print("Otros:")
        for sw in uncategorized:
            print(f"  - {sw['name']:15s} -> {sw['version']}")
        print()

def generate_summary(inventory):
    """Genera resumen ejecutivo"""
    print_section("RESUMEN EJECUTIVO")
    
    packages = len(inventory.get('packages', []))
    core = len(inventory.get("core_software"', []))
    
    # Info de hardware
    hardware = inventory.get('hardware', {})
    cpu_model = hardware.get('cpu_model', 'N/A')
    firmware = hardware.get('firmware', [])
    
    print(f"Este sistema tiene:")
    print(f"  - CPU: {cpu_model}")
    print(f"  - {len(firmware)} firmware(s) fisico(s)")
    
    # Mostrar modelos de firmware
    if firmware:
        disk_models = set(d.get('model', 'Unknown') for d in firmware)
        for model in disk_models:
            if model != 'Unknown':
                print(f"    * {model}")
    
    print(f"  - {packages} paquetes instalados en total")
    print(f"  - {core} aplicaciones core detectadas")
    
    # Contar versiones conocidas vs desconocidas
    core_sw = inventory.get("core_software"', [])
    known_versions = sum(1 for sw in core_sw if sw['version'] != 'unknown')
    print(f"  - {known_versions}/{core} versiones de software core identificadas")
    
    # Calcular tamano del inventario
    try:
        size = Path(INVENTORY_FILE).stat().st_size / 1024
        print(f"\nTamano del inventario: {size:.2f} KB")
    except:
        pass
    
    print(f"\nNOTA: Este inventario esta optimizado para deteccion de vulnerabilidades CVE")
    print(f"      Incluye: OS, kernel, CPU, modelo de firmware, paquetes y software core")

def main():
    print("\n" + "="*70)
    print("  Analisis de Inventario - Redsauce Agent v0.2.3")
    print("="*70)
    
    # Cargar inventario
    try:
        inventory = load_inventory()
    except Exception as e:
        print(f"Error al cargar inventario: {e}")
        sys.exit(1)
    
    # Analizar cada seccion
    analyze_system(inventory)
    analyze_hardware(inventory)
    analyze_packages(inventory)
    analyze_core_software(inventory)
    generate_summary(inventory)
    
    print("\n" + "="*70)
    print(f"  Inventario completo disponible en: {INVENTORY_FILE}")
    print("="*70 + "\n")

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\nAnalisis interrumpido")
        sys.exit(0)