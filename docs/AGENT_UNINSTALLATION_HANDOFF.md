# Continuar la desinstalaci?n Linux

## Preparación para pruebas, 19 de octubre

Linux **0.4.8** está publicado: https://github.com/Redsauce/firulai-linux-agent/releases/tag/0.4.8 . La etiqueta apunta a `d49018a`; incluye los cambios de desinstalación y fija la misma versión en `install.sh` y `rs_agent.sh`.

Firulai está desplegado como `firulai-v2026.10.19-01` con el endpoint de confirmación disponible. La usuaria confirma que ha actualizado los objetos RSM. Su ejecución y asociaciones se validarán con el piloto.

El catálogo RSM sigue seleccionando **0.4.7**. Para probar la desinstalación nueva, instalar primero **0.4.8** en el equipo piloto con su token y UUID actuales. El instalador fijado está en https://raw.githubusercontent.com/Redsauce/firulai-linux-agent/0.4.8/install.sh . Confirmar la versión instalada antes de ejecutar el desinstalador. Tras el piloto, seleccionar 0.4.8 en RSM para su distribución normal.

Comprobados: sintaxis de los cinco archivos públicos, coincidencia con las fuentes, desinstalación simulada root/usuario, conservación ante falta de confirmación, reintentos y 24 casos de elegibilidad. También se ha ejercitado la descarga pública fijada de 0.4.8 desde el actualizador 0.4.7 en una carpeta aislada, conservando la configuración e interceptando el reinicio; no se ha cambiado el catálogo ni enviado inventario de prueba.

Pendientes: desinstalación real root/usuario, verificación de historial y plazas, y recuperación si falla el borrado local tras confirmar remotamente. No hay una prueba real de desinstalación marcada como aprobada.

## Registro anterior a la publicación

Los apartados siguientes conservan el traspaso anterior; para el estado publicado prevalece la sección anterior.

Rama `feature/agent-uninstallation-20261019`, basada en `origin/main` (0.4.7, `40283bf`).

Incluye `api_endpoint.sh`, `uninstall.sh` y `tests/uninstallation.Tests.sh`: espera de confirmaci?n persistida, retirada solo tras confirmaci?n, bloqueo de inventarios concurrentes y rechazo de respuestas de otros sistemas. Se conservan las comprobaciones horarias y los reintentos de actualizaci?n de 0.4.7.

No hay nueva versi?n ni instalador publicado. Antes de publicar, coordinar el backend de Firulai y la entrega de `vulnwatcher/deliveries/agent-uninstallation`, disponibles en la rama del mismo nombre. La gu?a general y el checklist est?n en `apps/rsm-firulai/specs/054-agent-uninstallation/HANDOFF.md` y `validation-workflows.md` del repositorio web.

Pruebas locales aprobadas: desinstalaci?n simulada root/usuario, fallo de confirmaci?n conservando el agente, respuestas ambiguas, actualizaci?n autom?tica, runner y 24 casos de elegibilidad. Sigue pendiente la desinstalaci?n real root y usuario y el caso de fallo de eliminaci?n local despu?s de confirmar en RSM.
