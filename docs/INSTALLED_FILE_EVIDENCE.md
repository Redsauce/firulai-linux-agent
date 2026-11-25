# Observación de archivos instalados

La coincidencia del nombre de un paquete no distingue dos proyectos con el mismo nombre. Los datos de un archivo instalado permiten contrastar su identidad con una referencia de distribución; no equivalen por sí mismos a una verificación ni a un veredicto sobre un CVE.

## Linux con dpkg

`collect_dpkg_command_evidence` conserva `inventory_evidence` con su contrato `schema: 1` y a?ade `installed_file_evidence` con contrato `schema: 2`. As? un receptor anterior sigue recibiendo su observaci?n de comandos. El receptor actualizado prefiere el campo adicional cuando est? presente, sin aceptar datos inv?lidos mediante una vuelta silenciosa al contrato anterior. Incluye nombre y versión binaria completos, arquitectura, paquete fuente y versión fuente completos, instante de observación, cobertura y lista de comandos del manifiesto dpkg.

Cada comando mantiene `path`, `present` y `executable`. Cuando se puede medir un archivo regular ejecutable, añade conjuntamente:

| Campo | Significado |
| --- | --- |
| `sha256` | SHA-256 de los bytes leídos del archivo instalado |
| `size_bytes` | Tamaño completo observado |
| `mtime_ns` | Fecha de modificación observada, en nanosegundos |
| `resolved_path` | Ruta resuelta del archivo |

La lectura usa el mismo descriptor y compara identidad, tamaño y fechas antes y después, incluyendo la ruta actual. Omite enlaces simbólicos y archivos cambiados. No ejecuta los comandos, instala herramientas ni descarga referencias. La funcionalidad es opcional cuando no hay Python 3. No modifica la recogida RPM.

Los límites globales por inventario son 256 archivos, 96 MiB y un presupuesto de 2 segundos comprobado entre lecturas; cada archivo admite como máximo 8 MiB. El tiempo no es un timeout duro de las llamadas del sistema. Se conservan los límites de 128 entradas y 7.600 bytes por observación. Se prepara primero la lista de comandos y después se añaden las huellas que caben: una huella nunca desplaza un comando ya observado. La cobertura incompleta queda marcada como tal. `complete` se refiere a la lista del manifiesto, no a cobertura completa de huellas. Agotar el presupuesto deja los metadatos sin huella; no demuestra ausencia ni seguridad. La selección limitada puede dejar comandos sin medir.

## Windows

El recolector de DLL en directorios de aplicaciones mantiene los campos de `FileVersionInfo` y añade opcionalmente cuatro cadenas: `file_sha256`, `file_size_bytes`, `file_mtime_utc` e `file_observed_at`. Emplea los mismos límites de lectura, compartidos entre todas las aplicaciones. Durante la medición mantiene abierto un archivo con `FileShare.Read`; un archivo bloqueado o un enlace de archivo se omite. Los archivos sin presupuesto mantienen sus metadatos anteriores.

Esta ampliación cubre las DLL que el agente ya inventariaba. No constituye una medición de todos los ejecutables de Windows. `CompanyName` y `ProductName` son metadatos del archivo: no se comprueba Authenticode ni se certifica al fabricante.

## Receptor y matcher

`vulnwatcher` valida los tipos, límites y campos antes de guardar la observación en el campo existente de inventario **2000**. El envoltorio de almacenamiento continúa en `schema: 1`, ligado a nombre, versión completa y gestor. La observación Linux interior admite los esquemas 1 y 2; el segundo contrasta también paquete y versión fuente con el inventario recibido. Windows conserva su observación `windows_file_version_info` y añade un objeto `file_measurement` cuando recibe el grupo completo y válido.

El matcher recupera esa observación del componente. Los datos incorrectos se descartan; una nueva observación inválida limpia la evidencia anterior. No se acepta un campo enviado por el agente como autorización para declarar un CVE afectado, corregido o descartado.

Para retirar una asociación por implementación distinta falta contrastar los bytes con una referencia binaria fiable y vinculada a la versión y arquitectura correctas. El matcher mantiene los candidatos de identidad en Pending aunque ya tengan una huella sin referencia. No hay listas de CVE, máquinas o productos en esta ampliación.

## Validación local

- Linux: `python -m pytest tests/test_dpkg_file_fingerprint.py tests/test_dpkg_command_evidence.py tests/test_dpkg_inventory_provenance.py` y `bash -n firulaiAgent.sh`.
- Windows: `scripts/test-file-measurement.ps1`; regresión de inventario y transporte con `scripts/test-large-inventory.ps1`.
- Receptor: `tests/firulai/test_measured_inventory_storage.py` y `tests/firulai/test_native_command_observation_storage.py` en `vulnwatcher`.
- Seguridad de identidad: `tests/test_installed_identity_safety.py` en `vulnwatcher`.

Los cambios están preparados localmente. Esta documentación no acredita publicación, actualización de agentes ni evidencia recogida en equipos reales.
