# API: configuracion y pruebas Linux

La base se guarda en el archivo existente `config.env`:

```sh
RSM_BASE_URL='https://rsm1.redsauce.net/AppController/'
```

`api_endpoint.sh` agrega `commands_RSM/api/api.php`. Instalacion, inventario y
desinstalacion utilizan el mismo modulo. Un 301/308 seguido de respuesta 2xx
persiste la nueva base; un 302/307 conserva la anterior. Se mantiene el POST y
la autenticacion. Location debe indicar el endpoint completo (puede ser relativa).
Solo se acepta HTTPS sin credenciales, query ni fragmento, con cinco saltos maximo.
En cadenas mixtas se guarda solo el tramo permanente inicial. Los errores del
destino no cambian la configuracion. Token, UUID e idioma se conservan.

## Pruebas

```bash
bash scripts/test_install_source.sh
bash scripts/test_api_redirects.sh
bash scripts/test_api_redirects.sh --live --module /opt/rs-agent/api_endpoint.sh
bash scripts/test_agent_integration.sh --source /opt/rs-agent --live
```

HTTPBingo simula origen y destino. Se usan datos ficticios y archivos temporales;
no cambia la configuracion real. La prueba del modulo verifica el archivo y la
siguiente peticion. La prueba de integracion ejecuta una copia del agente en dos
procesos, sustituyendo recolectores por datos ficticios y adaptando solo el origen
al endpoint de simulacion HTTPBingo. Conserva archivos y logs en la ruta que imprime.
No demuestra el funcionamiento de los receptores reales de RSM.

## Instalar desde la rama de pruebas

Usar un contenedor limpio y credenciales de un equipo de pruebas:

```bash
export RS_AGENT_GITHUB_RAW_URL='https://raw.githubusercontent.com/Redsauce/firulai-linux-agent/test/api-base-redirects'
curl -fsSL "$RS_AGENT_GITHUB_RAW_URL/install.sh" | bash -s -- 'TOKEN' 'UUID' --locale es_ES
```

Todos los archivos vienen de la rama. Una fuente distinta de main guarda
`AGENT_AUTO_UPDATE='0'` para evitar volver a main automaticamente. La instalacion
normal mantiene las actualizaciones. Instalar se comunica con la API real; no
provoca una redireccion por si mismo. Los actualizadores antiguos descargan el
nuevo modulo y desinstalador cuando faltan. Publicar scripts y modulo juntos.
