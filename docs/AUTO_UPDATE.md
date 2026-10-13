# Actualizacion automatica Linux

La instalacion desde `main` mantiene `AGENT_AUTO_UPDATE='1'` en `config.env`.
Una instalacion desde una rama de prueba usa `AGENT_AUTO_UPDATE='0'`, para no
sustituir el agente de prueba por la version estable. Publicar una release no
reactiva automaticamente una configuracion que tenga el valor `0`.

El agente consulta la ultima release al ejecutar el inventario. Solo actualiza
si su version numerica es superior a la instalada. Rechaza versiones de prueba,
malformadas o inferiores. Descarga `rs_agent.sh`, `api_endpoint.sh` y
`uninstall.sh` desde el tag concreto de esa release, en lugar de usar `main`.
Verifica la sintaxis y que la version del script coincida con la anunciada antes
de reemplazar archivos. Conserva configuracion, identidad y estado.

La descarga y seleccion de versiones se prueban sin red ni instalacion real:

```bash
bash scripts/test_auto_update.sh
bash scripts/test_install_source.sh
bash tests/system-eligibility.Tests.sh
bash -n rs_agent.sh install.sh rs_agent_runner.sh uninstall.sh
```

La prueba usa un paquete simulado y ejecuta el reinicio del script descargado,
comprobando que conserva configuracion y guarda el ejecutable anterior.
Tambien comprueba que una release con una version distinta de la anunciada no
modifica el agente instalado.

Los cambios locales deben publicarse en el repositorio oficial y en una release
cuyo tag y `AGENT_VERSION` coincidan para distribuirse. No se ha publicado nada.
Falta validar una actualizacion completa en un equipo Linux real. Este mecanismo
no incorpora la firma RSA del actualizador Windows ni una transaccion completa
de todos los scripts ante un corte de corriente.
