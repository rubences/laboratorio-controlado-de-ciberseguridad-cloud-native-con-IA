# Wazuh local TLS material

Este directorio queda RESERVADO para certificados/llaves generados LOCALMENTE para Wazuh.

## Regla principal

- `*.pem`, `*.key`, `*.crt`, `*.csr`, `*.p12`, `*.pfx` y `*.jks` generados acá NO se versionan.
- El repo solo conserva documentación y un marcador de directorio.

## Bootstrap

1. Revisá `../certs.yml` y ajustá nombres/IPs si tu topología local cambió.
2. Desde `infrastructure/wazuh/`, ejecutá:

   ```powershell
   docker compose -f generate-certs.yml run --rm generator
   ```

3. Verificá que se hayan generado, como mínimo:
   - `root-ca.pem`
   - `admin.pem`
   - `admin-key.pem`
   - `wazuh.indexer.pem`
   - `wazuh.indexer-key.pem`
   - `wazuh.manager.pem`
   - `wazuh.manager-key.pem`
   - `wazuh.dashboard.pem`
   - `wazuh.dashboard-key.pem`
4. Recién ahí levantá `docker-compose.yml`.

## Rotación / regeneración

1. Bajá Wazuh: `docker compose -f infrastructure/wazuh/docker-compose.yml down`
2. Eliminá los PEM/KEY existentes de este directorio.
3. Regenerá con `generate-certs.yml`.
4. Volvé a levantar Wazuh.
5. Si necesitás una rotación realmente limpia de CA + estado persistente, recreá manualmente los volúmenes de Wazuh antes del siguiente arranque.

## Material especialmente sensible

- `root-ca.key` y `root-ca-manager.key` son llaves privadas de CA generadas por el helper.
- NO deben commitearse.
- Si no necesitás conservarlas para una operación puntual, movelas a un almacenamiento seguro fuera del repo o eliminálas y regenerá todo el set cuando haga falta.

## Nota operativa

Los mounts de `docker-compose.yml` esperan que estos archivos existan. Si este directorio solo contiene `README.md` y `.gitkeep`, primero tenés que ejecutar la regeneración local.
