# Continuar la desinstalaci?n Linux

Rama `feature/agent-uninstallation-20261019`, basada en `origin/main` (0.4.7, `40283bf`).

Incluye `api_endpoint.sh`, `uninstall.sh` y `tests/uninstallation.Tests.sh`: espera de confirmaci?n persistida, retirada solo tras confirmaci?n, bloqueo de inventarios concurrentes y rechazo de respuestas de otros sistemas. Se conservan las comprobaciones horarias y los reintentos de actualizaci?n de 0.4.7.

No hay nueva versi?n ni instalador publicado. Antes de publicar, coordinar el backend de Firulai y la entrega de `vulnwatcher/deliveries/agent-uninstallation`, disponibles en la rama del mismo nombre. La gu?a general y el checklist est?n en `apps/rsm-firulai/specs/054-agent-uninstallation/HANDOFF.md` y `validation-workflows.md` del repositorio web.

Pruebas locales aprobadas: desinstalaci?n simulada root/usuario, fallo de confirmaci?n conservando el agente, respuestas ambiguas, actualizaci?n autom?tica, runner y 24 casos de elegibilidad. Sigue pendiente la desinstalaci?n real root y usuario y el caso de fallo de eliminaci?n local despu?s de confirmar en RSM.
