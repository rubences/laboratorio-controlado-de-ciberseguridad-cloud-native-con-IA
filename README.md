# laboratorio-controlado-de-ciberseguridad-cloud-native-con-IA

## Estado actual del repositorio

Este repo ahora muestra un **escenario unificado** donde conviven de forma EXPLÍCITA:

- `ai_apps/` como **API/base moderna** de entrada.
- `ai-orchestrator/` como **runtime experimental/legacy avanzado**.
- `k8s_platform/` como **layout Kubernetes moderno** para sandbox y targets.
- `infrastructure/` como **capa de bootstrap, hardening y soporte legacy**.
- **Falco + Kubescape + Tetragon + Wazuh** como sensores/capas de seguridad con responsabilidades distintas.

Importante: sigue siendo un laboratorio controlado. Acá se deja claro qué es **real**, qué es **scaffold**, qué es **mock** y qué es **experimental/legacy**. NO se vende humo con integraciones productivas que todavía no existen.

## Documentación principal

- Ver `propuesta-escenario-argos.md` para la propuesta completa del laboratorio.
- Ver `docs/architecture/decision_tecnica.md` para la revisión de decisiones de arquitectura.
- Ver `WALKTHROUGH.md` para la guía detallada de hardening, despliegue y convivencia entre capas.

## Escenario unificado: moderno + legacy

- `ai_apps/api/`: FastAPI scaffold con `GET /health`, `GET /api/v1/stack-overview` y `POST /api/v1/scans/start`.
- `ai_apps/agents/`: orquestación base, discovery mínimo y validación de requests.
- `ai_apps/agents/legacy_bridge.py`: bridge in-process hacia `ai-orchestrator` cuando se solicita `legacy_bridge`.
- `ai_apps/mcp_clients/`: adapters mock explícitos para Burp y NeuroSploit.
- `ai_apps/guardrails/`: policy engine estructurado y evidence logger JSON.
- `ai_apps/contracts/unified-stack-profile.json`: contrato documental/técnico del stack unificado.
- `k8s_platform/sandbox/`: manifiestos modernos para `mcp-server`, `burp-suite` y `neurosploit`.
- `k8s_platform/targets/`: manifiestos modernos para `juiceshop` y `dvwa`.
- `ai-orchestrator/`: runtime previo/experimental con LangGraph, preservado como capa avanzada/legacy.
- `infrastructure/k8s/`: bootstrap con Kind, apps legacy, network policies y values/configs de sensores.
- `infrastructure/k8s/security/tetragon-runtime-observability.yaml`: contrato base para Tetragon como sensor eBPF/runtime.
- `evidence/scaffold/scans/`: evidencia persistida por el scaffold API.

## Modelo LLM referenciado

El stack unificado referencia explícitamente el modelo:

`hf.co/fdtn-ai/Foundation-Sec-8B-Reasoning`

Importante: en esta etapa el modelo queda **declarado e integrado en contratos y configuración**, pero el repo NO intenta fingir todavía serving integral de producción, correlación completa de sensores ni automatización cerrada de respuesta.

## Arquitectura unificada del laboratorio

```mermaid
graph TD
    User([Operator / Demo Script]) -->|POST /api/v1/scans/start| API[Scaffold FastAPI]
    API --> ORCH[ScanOrchestrator]
    API --> PROFILE[Stack Overview Contract]
    ORCH --> DISC[TargetDiscovery]
    ORCH --> POLICY[TargetPolicyEngine]
    ORCH --> BURP[Burp MCP Mock Adapter]
    ORCH --> NEURO[NeuroSploit MCP Mock Adapter]
    ORCH --> EVIDENCE[EvidenceLogger -> evidence/scaffold/scans]
    POLICY --> K8S[Sandbox + Targets Scope]
    ORCH -. requested_model .-> LLM[hf.co/fdtn-ai/Foundation-Sec-8B-Reasoning]
    API -. coexistence .-> LEGACY[ai-orchestrator LangGraph Runtime]
    K8S --> FALCO[Falco]
    K8S --> KUBESCAPE[Kubescape]
    K8S --> TETRAGON[Tetragon eBPF Runtime Visibility]
    LEGACY -. external telemetry .-> WAZUH[Wazuh Docker Compose]
```

## Cómo conviven las capas sin contradecirse

### 1. `ai_apps/` = entrada moderna y segura

Es la capa recomendada para demos, contratos API, guardrails y persistencia de evidencia estructurada.

### 2. `ai-orchestrator/` = runtime legacy/experimental avanzado

No reemplaza al scaffold: lo complementa. Se conserva como referencia y runtime más profundo para casos donde se quiera evolucionar hacia multiagente/LangGraph, HIL y automatización más sofisticada.

### 3. `k8s_platform/` = layout moderno del escenario

Representa el layout Kubernetes nuevo del laboratorio:

- `sandbox`: herramientas/control plane mock del scaffold.
- `targets`: objetivos modernos del laboratorio.

### 4. `infrastructure/` = bootstrap + soporte + legado útil

Mantiene lo que el layout moderno NO debe duplicar:

- creación del clúster Kind
- apps legacy vulnerables
- values/config de Falco, Kubescape y Tetragon
- network policies compartidas
- Wazuh fuera del clúster vía Docker Compose

## Sensores del escenario

- **Falco**: detección runtime en Kubernetes. En este laboratorio Kind sobre WSL2 se prioriza `modern_ebpf`, porque el probe eBPF clásico depende de artefactos/kernel headers del host y suele romperse en WSL2.
- **Kubescape**: postura/configuración + correlación de seguridad.
- **Tetragon**: **sensor eBPF de runtime y visibilidad de procesos**. Queda integrado como base de observabilidad/runtime, NO como respuesta productiva mágica ya terminada.
- **Wazuh**: capa externa tipo SIEM/XDR para agregación y análisis complementario.

## Qué es real, mock y experimental

### Real en este scaffold/base

- API FastAPI funcional.
- Validación de payload con Pydantic.
- Guardrails de alcance con validación de namespaces, DNS e IPs de laboratorio.
- Persistencia real de evidencia JSON dentro del repo.
- Contrato JSON del stack unificado.
- Manifiestos Kubernetes modernos y legacy coexistiendo con responsabilidades claras.
- Base config de Tetragon + camino de despliegue por Helm.

### Intencionalmente mock o no cerrado todavía

- Integración MCP real con Burp Suite.
- Integración MCP real con NeuroSploit.
- Pipeline productivo completo de Tetragon/Falco/Kubescape/Wazuh hacia respuesta automática.
- Planeación multiagente de producción completamente estabilizada.
- Serving completo del modelo LLM en runtime.

## Cómo ejecutar el scaffold API

### 1. Instalar dependencias

```bash
python -m venv .venv
# source .venv/bin/activate
# .\.venv\Scripts\Activate
pip install -r ai_apps/requirements.txt
```

### 2. Levantar la API

```bash
uvicorn ai_apps.api.main:app --reload
```

### 3. Probar health

```bash
curl http://localhost:8000/health
```

### 4. Inspeccionar el stack unificado

```bash
curl http://localhost:8000/api/v1/stack-overview
```

### 5. Lanzar un scan base

```bash
curl -X POST http://localhost:8000/api/v1/scans/start \
  -H "Content-Type: application/json" \
  -d '{
    "scan_name": "baseline-lab-scan",
    "target": "juiceshop.targets.svc.cluster.local",
    "target_namespace": "targets",
    "allowed_tools": ["burp", "neurosploit"],
    "require_approval": true,
    "requestor": "readme-example"
  }'
```

### 6. Elegir modo de ejecución: `scaffold` o `legacy_bridge`

El request ahora puede elegir el camino de ejecución de forma EXPLÍCITA:

- `scaffold` → default sensato; usa los mock adapters propios de `ai_apps/`.
- `legacy_bridge` → delega **in-process** a `ai-orchestrator/app/agents/supervisor.py:run_supervisor_workflow`.

Ejemplo default (`scaffold` por omisión):

```bash
curl -X POST http://localhost:8000/api/v1/scans/start \
  -H "Content-Type: application/json" \
  -d '{
    "scan_name": "baseline-lab-scan",
    "target": "juiceshop.targets.svc.cluster.local",
    "target_namespace": "targets",
    "allowed_tools": ["burp", "neurosploit"],
    "requestor": "readme-scaffold"
  }'
```

Ejemplo puenteando al runtime legacy:

```bash
curl -X POST http://localhost:8000/api/v1/scans/start \
  -H "Content-Type: application/json" \
  -d '{
    "scan_name": "legacy-bridge-scan",
    "target": "juiceshop.targets.svc.cluster.local",
    "target_namespace": "targets",
    "allowed_tools": ["burp", "neurosploit"],
    "execution_mode": "legacy_bridge",
    "require_approval": false,
    "requestor": "readme-legacy-bridge"
  }'
```

También podés usar perfil en vez de modo:

```json
{
  "execution_profile": "legacy"
}
```

La respuesta/evidencia ahora deja explícito:

- `execution_mode`
- `execution_details.bridge_path`
- `finding_sources`
- `limitations`

Eso evita vender humo: si corrés `legacy_bridge`, los findings quedan marcados como originados en `ai-orchestrator` y se explicita que ese runtime sigue siendo experimental/mockeado en partes.

## Despliegue del laboratorio unificado

`deploy-lab.ps1` ahora contempla el escenario híbrido:

1. crea/usa el clúster Kind
2. despliega ingress
3. aplica `k8s_platform/sandbox/`
4. aplica `k8s_platform/targets/`
5. mantiene `infrastructure/k8s/apps/vulnerable-apps.yaml`
6. aplica `infrastructure/k8s/security/network-policies.yaml`
7. aplica base config de **Tetragon**
8. si existe Helm, instala **Kubescape + Falco + Tetragon**

Si querés re-aplicar y esperar readiness del stack Kubernetes SIN recrear el clúster, usá:

```powershell
./scripts/reconcile-k8s-lab.ps1
```

Ese helper:

- re-aplica `sandbox`, `targets`, `vulnerable-apps`, network policies y ConfigMap base de Tetragon
- espera rollout exitoso de los deployments modernos y de los legacy que hoy sí están soportados (`juice-shop`, `dvwa`)
- deja `webgoat` como **best-effort** mientras no exista en el repo una imagen/entrypoint verificado offline para su JAR

### Variables operativas útiles para `deploy-lab.ps1`

- `ARGOS_INGRESS_NGINX_MANIFEST`: permite sobreescribir el manifest de ingress. Default: release pinneada `controller-v1.11.5` de `ingress-nginx` para Kind, en vez de `main` remoto mutable.
- `ARGOS_INGRESS_WAIT_TIMEOUT`: timeout para `kubectl wait` del controller. Default: `90s`.

Ejemplo:

```powershell
$env:ARGOS_INGRESS_NGINX_MANIFEST = "https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.5/deploy/static/provider/kind/deploy.yaml"
$env:ARGOS_INGRESS_WAIT_TIMEOUT = "180s"
./deploy-lab.ps1
```

## Demo script endurecido

`demo-scenario.ps1` ya NO hardcodea la API key. Ahora la toma desde:

1. parámetro `-ApiKey`, o
2. variable de entorno `ARGOS_API_KEY`

Ejemplo:

```powershell
$env:ARGOS_API_KEY = "tu-api-key"
./demo-scenario.ps1
```

También podés cambiar el endpoint con `-ApiUrl` o `ARGOS_API_URL`.

## Estructura histórica del repo

Además del stack unificado, el repo conserva componentes previos útiles como referencia y expansión:

- `infrastructure/`: bootstrap, seguridad runtime, Wazuh y políticas compartidas.
- `ai-orchestrator/`: implementación anterior/experimental con LangGraph.
- `ai-security-testing/`: evaluación de seguridad para prompts/agentes.
- `offensive/`: activos de CALDERA y emulación.

## Nota de seguridad

Se endureció `.gitignore` para reducir riesgo de trackear material criptográfico generado (`*.key`, `*.pem`, `*.crt`, etc.). OJO: eso no destrackea secretos ya versionados; esos archivos deben sanearse aparte si se decide limpiarlos del historial.

## Bootstrap seguro de Wazuh y CALDERA

## Runtime smoke checks operativos

Se agregan smoke checks PowerShell SIN build y SIN depender de internet para validar precondiciones y estado runtime básico de Wazuh/CALDERA.

### Scripts disponibles

- `./scripts/check-runtime-smoke.ps1`: wrapper para ambos stacks.
- `./scripts/check-wazuh-runtime-smoke.ps1`: smoke dedicado de Wazuh.
- `./scripts/check-caldera-runtime-smoke.ps1`: smoke dedicado de CALDERA.

### Modos

- `Precheck`: valida archivos requeridos + `docker compose config`. NO falla por stack apagado.
- `Auto`: corre precheck y, si detecta contenedores running, agrega checks runtime. Si el stack no está arriba, deja `WARN` y sigue.
- `Runtime`: además del precheck, EXIGE stack levantado y valida contenedores/puertos.

### Ejemplos de uso

```powershell
./scripts/check-runtime-smoke.ps1 -Mode Precheck
./scripts/check-runtime-smoke.ps1 -Stack Wazuh -Mode Auto
./scripts/check-runtime-smoke.ps1 -Stack Caldera -Mode Runtime

./scripts/check-wazuh-runtime-smoke.ps1 -Mode Runtime
./scripts/check-caldera-runtime-smoke.ps1 -Mode Precheck
```

### Qué valida cada smoke

#### Wazuh

- existencia de `infrastructure/wazuh/.env`
- secretos críticos no vacíos en `.env`
- existencia del `wazuh.local.yml` efectivo
- placeholder `__SET_WAZUH_API_PASSWORD__` resuelto
- certificados locales requeridos
- `docker compose config`
- si el stack está arriba: servicios/contenedores esperados + puertos locales `8444` y `55000` (y reporte opcional de `9200`)

#### CALDERA

- existencia de `offensive/caldera/docker-compose.yml`
- `.env` local opcional (si falta, informa `WARN`, no `FAIL`)
- `docker compose config`
- si el stack está arriba: servicio/contenedor esperado + puerto local `8889`
- si `8889` responde, intenta además un GET HTTP básico local
- reporte opcional de `8443`, `7010`, `7011/udp`, `7012` y `8853`

## Kubernetes smoke checks del laboratorio unificado

Se agregan smoke checks PowerShell para Kubernetes SIN build y SIN depender de internet. La idea es la misma que con Docker: tener prechecks útiles antes del despliegue y runtime checks claros cuando el cluster está accesible.

### Scripts disponibles

- `./scripts/check-k8s-runtime-smoke.ps1`: wrapper principal del laboratorio Kubernetes.
- `./scripts/k8s-smoke-helpers.ps1`: helpers reutilizables para precheck/runtime.

### Modos

- `Precheck`: valida `kubectl`, contexto si existe y manifests esperables del repo. NO falla porque el cluster esté apagado o inaccesible.
- `Auto`: hace el precheck y, si detecta contexto/cluster accesible, suma runtime checks. Si no, deja `WARN` y sigue.
- `Runtime`: exige cluster accesible y revisa namespaces, deployments, ConfigMap de Tetragon, network policies y releases Helm si Helm está disponible.

### Ejemplos de uso

```powershell
./scripts/check-k8s-runtime-smoke.ps1 -Mode Precheck
./scripts/check-k8s-runtime-smoke.ps1 -Mode Auto
./scripts/check-k8s-runtime-smoke.ps1 -Mode Runtime
./scripts/check-k8s-runtime-smoke.ps1 -Mode Runtime -ExpectedKindClusterName argos-lab
```

### Qué valida el smoke de Kubernetes

- acceso a `kubectl` y `kubectl config current-context`
- verificación best-effort del cluster Kind esperado `argos-lab`
- manifests base del laboratorio (`kind-config`, sandbox, targets, vulnerable-apps, network policies, Tetragon)
- namespaces `ingress-nginx`, `sandbox`, `targets`, `vulnerable-apps`, `tetragon`
- readiness de deployments clave del escenario moderno y legacy:
  - `ingress-nginx-controller`
  - `mcp-server`, `burp-suite`, `neurosploit`
  - `juiceshop`, `dvwa` en `targets`
  - `juice-shop`, `dvwa` en `vulnerable-apps`
- estado **best-effort** de `webgoat` en `vulnerable-apps`: si la imagen upstream sigue rompiendo con `Unable to access jarfile webgoat.jar`, el smoke lo reporta como `WARN` y no como `FAIL` hasta que exista un entrypoint verificado dentro del repo
- existencia del ConfigMap `tetragon/tetragon-lab-profile`
- si Helm está disponible: reporte de releases `kubescape`, `falco`, `tetragon`
- network policies esperadas en `sandbox`, `targets` y `vulnerable-apps`

La salida mantiene el mismo contrato visual: `OK`, `WARN` y `FAIL`, pensado para uso manual y para pipelines livianos de validación.

### Wazuh

1. Copiá `infrastructure/wazuh/.env.example` a `infrastructure/wazuh/.env`.
2. Completá `INDEXER_PASSWORD`, `API_PASSWORD` y `DASHBOARD_PASSWORD` con secretos fuertes.
3. Si tu topología local cambia, ajustá `infrastructure/wazuh/config/certs.yml` ANTES de regenerar certificados.
4. Regenerá el material TLS localmente con el helper del repo:

```powershell
./scripts/bootstrap-wazuh-tls.ps1
```

5. Copiá `infrastructure/wazuh/config/wazuh_dashboard/wazuh.local.yml.example` a `infrastructure/wazuh/config/wazuh_dashboard/wazuh.local.yml`.
6. Reemplazá `__SET_WAZUH_API_PASSWORD__` por el mismo valor que uses en `API_PASSWORD`.
7. Si necesitás exponer más que localhost, cambiá los `*_BIND_IP` en `infrastructure/wazuh/.env` de forma EXPLÍCITA.
8. Recién ahí levantá el stack Wazuh con `docker compose -f infrastructure/wazuh/docker-compose.yml up -d`.

Bridge honesto Falco -> Wazuh en este entorno:

- `infrastructure/k8s/security/wazuh-syslog-bridge.yaml` declara `falco/wazuh-syslog-bridge` como `ExternalName -> host.docker.internal`
- `falco-values.yaml` hace que Falcosidekick envíe Syslog a `wazuh-syslog-bridge.falco.svc.cluster.local:514/UDP`
- esto resuelve el gap de DNS/bridge dentro de Kind sobre Docker Desktop/WSL2
- esto **NO** significa que Wazuh esté siempre arriba: si `wazuh.manager` no está corriendo en Docker, Falcosidekick puede seguir fallando por disponibilidad del destino aunque el DNS ya esté resuelto

Hardening aplicado:

- ya NO quedan defaults sensibles funcionales en archivos trackeados críticos
- `9200`, `55000` y `8444` quedan atados a loopback por default
- el dashboard monta `wazuh.local.yml` en vez de un archivo trackeado con secreto duro
- si faltan secretos, Docker Compose falla temprano en vez de arrancar con credenciales débiles
- los PEM/KEY del indexer/manager/dashboard dejan de versionarse y pasan a ser artefactos locales regenerables

Rotación recomendada de Wazuh:

1. Reset liviano de certs:

   ```powershell
   ./scripts/reset-wazuh-state.ps1 -RemoveCerts
   ./scripts/bootstrap-wazuh-tls.ps1
   ```

2. Reset limpio de estado + volúmenes:

   ```powershell
   ./scripts/reset-wazuh-state.ps1 -RemoveCerts -RemoveVolumes
   ./scripts/bootstrap-wazuh-tls.ps1
   ```

3. volver a levantar el stack.

Variables/env relevantes de Wazuh:

- `INDEXER_PASSWORD`, `API_PASSWORD`, `DASHBOARD_PASSWORD`: obligatorias en `infrastructure/wazuh/.env`
- `INDEXER_USERNAME`, `API_USERNAME`, `DASHBOARD_USERNAME`: opcionales si necesitás override local
- `WAZUH_INDEXER_BIND_IP`, `WAZUH_API_BIND_IP`, `WAZUH_DASHBOARD_BIND_IP`: exposición loopback por default
- `WAZUH_INGEST_BIND_IP`, `WAZUH_SYSLOG_BIND_IP`: mantienen puertos de ingesta/sislog abiertos para el laboratorio, pero podés cerrarlos más si tu demo no los necesita
- `WAZUH_DASHBOARD_CONFIG_PATH`: override opcional del archivo local montado en dashboard

### CALDERA

1. Revisá `offensive/caldera/.env.example` y, si necesitás cambiar exposición local, copiá los valores a un `.env` local en esa carpeta.
2. Levantá CALDERA con su compose. El primer arranque normal genera `offensive/caldera/caldera-src/conf/local.yml` con secretos aleatorios dentro del volumen persistente `caldera_conf`.
3. Guardá las credenciales/API keys que CALDERA muestra en logs al crear `local.yml`.
4. NO uses `--insecure` salvo para debugging aislado y efímero.
5. Si activás certificados HTTPS propios para CALDERA, mantenelos como material LOCAL/NO versionado dentro de `conf/local.yml` o en un volumen, nunca en el repo.
6. Si ya venías usando CALDERA con un volumen previo, regenerá `caldera_conf` con el helper del repo si querés descartar secretos viejos:

```powershell
./scripts/reset-caldera-state.ps1 -RemoveVolumes
docker compose --project-directory offensive/caldera -f offensive/caldera/docker-compose.yml up -d
```

Hardening aplicado:

- `conf/default.yml` quedó como plantilla saneada, sin secretos reales
- la estrategia recomendada pasa por `conf/local.yml` autogenerado y persistido en volumen
- UI/HTTPS/SSH/FTP quedan en loopback por default; los canales de agentes siguen configurables para el laboratorio
- se corrigió la publicación UDP de `7011`, que antes estaba ambigua/incorrecta

Variables/env relevantes de CALDERA:

- `CALDERA_UI_BIND_IP`, `CALDERA_HTTPS_BIND_IP`: loopback por default
- `CALDERA_AGENT_BIND_IP`, `CALDERA_DNS_BIND_IP`: abiertos por default para la emulación del laboratorio
- `CALDERA_SSH_TUNNEL_BIND_IP`, `CALDERA_FTP_BIND_IP`: loopback por default

## Endurecimiento operativo del `ai-orchestrator`

- `ARGOS_CORS_ALLOW_ORIGINS`: lista separada por comas para CORS en `ai-orchestrator/app/main.py`. Si no se define, queda una allowlist local sensata (`localhost`/`127.0.0.1` en puertos típicos) en vez de `*`.
- Si necesitás compatibilidad amplia para una demo puntual, podés forzar `ARGOS_CORS_ALLOW_ORIGINS=*`.
- `ARGOS_ALLOWED_NAMESPACES`: lista separada por comas para el policy gate del supervisor. Default: `sandbox,targets,vulnerable-apps`.

## Limitaciones honestas

- Este cambio NO limpia el historial git previo ni rota secretos ya expuestos fuera del repo.
- La rotación real sigue siendo una tarea OPERATIVA manual: hay que regenerar localmente los certs de Wazuh y, si corresponde, recrear volúmenes/estado persistente antes de confiar en el entorno renovado.
- Algunos canales opcionales de CALDERA (FTP/SSH tunnel) quedan con placeholders en `default.yml`; si se usan, el operador debe completarlos en `conf/local.yml`.
- Si existe un volumen `caldera_conf` previo al saneamiento, puede seguir conteniendo secretos históricos hasta que el operador lo regenere.
- El helper de CALDERA resetea el estado del compose, pero las credenciales nuevas siguen mostrándose en logs del primer bootstrap; el operador tiene que guardarlas manualmente.
