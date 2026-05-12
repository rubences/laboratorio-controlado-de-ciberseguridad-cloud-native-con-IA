# WALKTHROUGH: Implementación, Integración y Hardening de HexStrike AI (ARGOS)

Este documento describe el escenario unificado del laboratorio ARGOS: **scaffold moderno + runtime legacy/experimental + sensores de seguridad + capas Kubernetes diferenciadas**.

---

## 🚀 Guía Rápida de Inicio

1. **Despliegue de Infraestructura**:
   ```powershell
   ./deploy-lab.ps1
   ```
2. **Arranque del Scaffold API**:
   ```bash
   uvicorn ai_apps.api.main:app --reload
   ```
3. **Inspección del Stack Unificado**:
   ```bash
   curl http://localhost:8000/api/v1/stack-overview
   ```
4. **Ejecución de Demo**:
   ```powershell
   ./demo-scenario.ps1
   ```

---

## 🛡️ Resumen de las fases del escenario unificado

### Fase 1: Arquitectura de API Segura
- `ai_apps/` queda como entrada moderna para el laboratorio.
- El scaffold expone contratos simples, guardrails y evidencia persistida.

### Fase 2: Gestión de Secretos (Infraestructura)
- Las credenciales sensibles de soporte siguen fuera del código duro.
- `infrastructure/` conserva la parte operativa que no debe mezclarse con el scaffold.

### Fase 3: Convivencia Moderna + Legacy
- `ai_apps/` queda como entrypoint moderno y contrato explícito del laboratorio.
- `ai-orchestrator/` se preserva como runtime experimental/legacy avanzado, no como capa descartada.
- `ai_apps` ahora puede delegar opcionalmente al runtime legacy con `execution_mode=legacy_bridge` usando un bridge **in-process**.
- `k8s_platform/` e `infrastructure/` quedan conectados con responsabilidades distintas.

### Fase 4: Guardrails de IA
- El scaffold sigue validando alcance, target y herramientas solicitadas.
- La idea es frenar requests fuera del laboratorio ANTES de cualquier ejecución más agresiva.

### Fase 5: Alineación de Modelos
- El stack mantiene como referencia `hf.co/fdtn-ai/Foundation-Sec-8B-Reasoning`.

### Fase 6: Persistencia de Evidencias
- `ai_apps/` guarda evidencia estructurada en `evidence/scaffold/scans/`.
- `ai-orchestrator/` conserva su propia carpeta histórica de evidencias en `evidence/analyses/`.
- Cuando se usa `legacy_bridge`, la evidencia del scaffold registra además el modo, origen de findings, bridge path y limitaciones del runtime legacy.

### Fase 7: Sensores de Runtime Unificados
- **Falco** como detección runtime.
- **Kubescape** como postura/configuración y correlación.
- **Tetragon** como visibilidad de procesos y runtime basada en **eBPF**.
- **Wazuh** como capa externa de agregación/telemetría.

### Fase 8: Sandbox y Targets Modernos
- `k8s_platform/sandbox/` concentra `mcp-server`, `burp-suite` y `neurosploit` como componentes scaffold/mock.
- `k8s_platform/targets/` concentra `juiceshop` y `dvwa` como targets modernos.

### Fase 9: Legacy útil y no contradictorio
- `infrastructure/k8s/apps/vulnerable-apps.yaml` sigue desplegando los objetivos legacy.
- `infrastructure/k8s/security/network-policies.yaml` ahora cubre `vulnerable-apps`, `sandbox` y `targets`.

### Fase 10: Contrato documental/técnico del stack
- `ai_apps/contracts/unified-stack-profile.json` documenta qué existe, qué es mock, qué es experimental y cómo conviven las capas.
- `GET /api/v1/stack-overview` expone ese contrato desde la API moderna.

---

## 📊 Arquitectura del Sistema

```mermaid
graph TD
    User([Usuario / CI]) -->|POST /api/v1/scans/start| API[Modern Scaffold API]
    API -->|Contract + Guardrails| PROFILE[Unified Stack Overview]
    API --> ORCH[ScanOrchestrator]
    ORCH -->|execution_mode=scaffold| MOCK[Scaffold Mock Adapters]
    API -. bridge/runtime handoff .-> LG[Legacy LangGraph Governor]

    ORCH --> BURP[Burp Mock Adapter]
    ORCH --> NEURO[NeuroSploit Mock Adapter]
    ORCH --> EVIDENCE[Scaffold Evidence]

    subgraph Legacy Runtime
        LG --> P[Planner]
        P --> SA[Security Agent]
        SA --> EXE[Execute Tools]
        EXE --> AH[Anti-Hallucination Pipeline]
        AH --> EVAL[Evaluator]
    end

    ORCH --> K8S[Sandbox + Targets]
    K8S --> FALCO[Falco]
    K8S --> KUBESCAPE[Kubescape]
    K8S --> TETRAGON[Tetragon]
    LG -. external telemetry .-> WAZUH[Wazuh]
```

## 🧭 Qué despliega ahora `deploy-lab.ps1`

1. Kind + contexto de `kubectl`
2. Ingress NGINX
3. `k8s_platform/sandbox/*`
4. `k8s_platform/targets/*`
5. `infrastructure/k8s/apps/vulnerable-apps.yaml`
6. `infrastructure/k8s/security/network-policies.yaml`
7. `infrastructure/k8s/security/tetragon-runtime-observability.yaml`
8. Helm opcional para **Kubescape**, **Falco** y **Tetragon**

### Nota honesta sobre Falco en Kind sobre WSL2

En este repo Falco queda configurado para preferir `modern_ebpf` en vez del probe `ebpf` clásico. ¿Y sabés por qué? Porque en WSL2 el camino clásico suele intentar bajar un probe precompilado para un kernel muy específico o compilarlo con headers del host; cuando eso falla, el init container entra en crash loop. `modern_ebpf` evita esa dependencia y tiene bastante más chances reales de levantar en este entorno.

Si el clúster ya existe y solo querés reconciliar manifests/runtime, corré:

```powershell
./scripts/reconcile-k8s-lab.ps1
```

Ese script NO recrea Kind: re-aplica sandbox/targets/legacy + policies + Tetragon base y espera rollout de los deployments soportados.

### Endurecimiento práctico del bootstrap de ingress

- `deploy-lab.ps1` dejó de depender por default del `main` remoto mutable de `ingress-nginx`.
- Ahora usa por default un manifest pinneado a `controller-v1.11.5` para Kind.
- Si necesitás otra release o un manifest interno/local, podés setear:

```powershell
$env:ARGOS_INGRESS_NGINX_MANIFEST = "C:\ruta\a\ingress-nginx-kind.yaml"
$env:ARGOS_INGRESS_WAIT_TIMEOUT = "180s"
./deploy-lab.ps1
```

## 🔀 Modos de ejecución del endpoint `POST /api/v1/scans/start`

### Modo `scaffold` (default)

- usa `ai_apps/agents/orchestrator.py`
- corre discovery + policy + mock adapters propios
- deja findings marcados como `scaffold_mock_adapter`

Ejemplo:

```json
{
  "scan_name": "walkthrough-scaffold",
  "target": "juiceshop.targets.svc.cluster.local",
  "target_namespace": "targets",
  "allowed_tools": ["burp", "neurosploit"]
}
```

### Modo `legacy_bridge`

- mantiene los guardrails de `ai_apps`
- delega **in-process** a `ai-orchestrator/app/agents/supervisor.py:run_supervisor_workflow`
- NO llama por HTTP a `localhost` para fingir integración
- devuelve `finding_sources` y `limitations` para dejar claro qué vino del runtime legacy

Ejemplo:

```json
{
  "scan_name": "walkthrough-legacy-bridge",
  "target": "juiceshop.targets.svc.cluster.local",
  "target_namespace": "targets",
  "allowed_tools": ["burp", "neurosploit"],
  "execution_mode": "legacy_bridge",
  "require_approval": false,
  "requestor": "walkthrough"
}
```

También se acepta perfil:

```json
{
  "execution_profile": "legacy"
}
```

## ⚠️ Limitaciones honestas del bridge

- el runtime legacy sigue siendo experimental
- varias respuestas MCP del legacy siguen mockeadas
- el paso de aprobación humana legacy es simulado
- si faltan dependencias de `ai-orchestrator`, el endpoint responde error de disponibilidad en vez de fingir éxito

## 🔬 Qué significa Tetragon en ESTE repo

Tetragon queda integrado como:

- sensor de **runtime visibility**
- sensor **eBPF**
- visibilidad de **procesos/workloads** etiquetados para observación en namespaces del laboratorio

PERO no se presenta falsamente como una tubería productiva completa de respuesta automática, remediación cerrada y correlación perfecta. Acá queda el contrato correcto, el despliegue base y el punto de extensión.

## 🔐 Bootstrap seguro de Wazuh

1. Copiá `infrastructure/wazuh/.env.example` a `infrastructure/wazuh/.env`.
2. Definí secretos fuertes para:
   - `INDEXER_PASSWORD`
   - `API_PASSWORD`
   - `DASHBOARD_PASSWORD`
3. Si necesitás cambiar nombres/IPs para SANs, editá `infrastructure/wazuh/config/certs.yml` ANTES de generar.
4. Regenerá certificados localmente con el helper:

```powershell
./scripts/bootstrap-wazuh-tls.ps1
```

5. Copiá `infrastructure/wazuh/config/wazuh_dashboard/wazuh.local.yml.example` a `infrastructure/wazuh/config/wazuh_dashboard/wazuh.local.yml`.
6. Reemplazá `__SET_WAZUH_API_PASSWORD__` por el mismo valor que `API_PASSWORD`.
7. Recién ahí levantá el stack:

```powershell
docker compose -f infrastructure/wazuh/docker-compose.yml up -d
```

### Hardening aplicado en Wazuh

- `9200`, `55000` y `8444` publican en `127.0.0.1` por default.
- los puertos de ingesta (`1514`, `1515`, `514/udp`) siguen abiertos por default para no romper el laboratorio, pero ahora son configurables por `*_BIND_IP`
- Docker Compose exige secretos explícitos y ya NO cae en credenciales débiles por fallback
- `wazuh.yml` dejó de tener YAML duplicado/ambiguo y pasó a ser plantilla saneada
- los PEM/KEY reales salen del control de versiones y pasan a regenerarse localmente

### Rotación recomendada de Wazuh

1. Rotación de certs sin tocar volúmenes:

```powershell
./scripts/reset-wazuh-state.ps1 -RemoveCerts
./scripts/bootstrap-wazuh-tls.ps1
```

2. Rotación limpia de certs + estado persistente:

```powershell
./scripts/reset-wazuh-state.ps1 -RemoveCerts -RemoveVolumes
./scripts/bootstrap-wazuh-tls.ps1
```

3. Luego levantá Wazuh otra vez con su compose.

### Variables/env relevantes de Wazuh

- `INDEXER_PASSWORD`, `API_PASSWORD`, `DASHBOARD_PASSWORD`
- `WAZUH_INDEXER_BIND_IP`, `WAZUH_API_BIND_IP`, `WAZUH_DASHBOARD_BIND_IP`
- `WAZUH_INGEST_BIND_IP`, `WAZUH_SYSLOG_BIND_IP`
- `WAZUH_DASHBOARD_CONFIG_PATH`

## 🔐 Bootstrap seguro de CALDERA

1. Opcionalmente copiá `offensive/caldera/.env.example` a `offensive/caldera/.env` si necesitás cambiar bind addresses.
2. Levantá CALDERA normalmente:

```powershell
docker compose -f offensive/caldera/docker-compose.yml up -d
```

3. En el primer arranque normal, CALDERA genera `conf/local.yml` con secretos aleatorios y los persiste en el volumen `caldera_conf`.
4. Guardá las credenciales/API keys mostradas en logs del primer bootstrap.
5. Evitá `--insecure`; si lo usás, `conf/default.yml` ya NO contiene secretos reales y requiere reemplazo manual de placeholders.
6. Si configurás un certificado HTTPS propio, mantenelo como artefacto local/no versionado en `conf/local.yml` o en un volumen persistente.
7. Si ya existía `caldera_conf`, usá el helper para descartar secretos heredados:

```powershell
./scripts/reset-caldera-state.ps1 -RemoveVolumes
docker compose --project-directory offensive/caldera -f offensive/caldera/docker-compose.yml up -d
```

### Hardening aplicado en CALDERA

- `default.yml` quedó saneado y pasa a ser base documental, no fuente de secretos reales
- `8889` y `8443` quedan en loopback por default
- `8022` y `2222` también quedan en loopback por default porque son canales opcionales de mayor riesgo local
- `7011` ahora se publica explícitamente como UDP
- se agrega `caldera_conf` para persistir `conf/local.yml` generado automáticamente

### Variables/env relevantes de CALDERA

- `CALDERA_UI_BIND_IP`
- `CALDERA_HTTPS_BIND_IP`
- `CALDERA_AGENT_BIND_IP`
- `CALDERA_DNS_BIND_IP`
- `CALDERA_SSH_TUNNEL_BIND_IP`
- `CALDERA_FTP_BIND_IP`

## ✅ Smoke checks runtime/preflight de Docker

Para no adivinar si el operador dejó algo a medias, el repo ahora trae smoke checks PowerShell reutilizables para Wazuh y CALDERA.

### Scripts

```powershell
./scripts/check-runtime-smoke.ps1
./scripts/check-wazuh-runtime-smoke.ps1
./scripts/check-caldera-runtime-smoke.ps1
```

### Modos operativos

- `-Mode Precheck`: solo archivos/config/render de Compose. Ideal antes de `up -d`.
- `-Mode Auto`: precheck + runtime solo si detecta contenedores corriendo.
- `-Mode Runtime`: trata la ausencia del stack como problema y valida contenedores/puertos.

### Ejemplos

```powershell
./scripts/check-runtime-smoke.ps1 -Mode Precheck
./scripts/check-runtime-smoke.ps1 -Stack Wazuh -Mode Runtime
./scripts/check-runtime-smoke.ps1 -Stack Caldera -Mode Auto
```

### Cobertura

- **Wazuh**: `.env`, secretos vacíos, `wazuh.local.yml`, placeholder pendiente, certs requeridos, `docker compose config`, servicios esperados, `8444`, `55000` y reporte opcional de `9200`.
- **CALDERA**: compose, `.env` opcional, `docker compose config`, servicio/contenedor esperado, `8889`, GET HTTP básico en `8889` y reporte opcional de `8443`, `7010`, `7011/udp`, `7012`, `8853`.

Los scripts emiten mensajes `OK`, `WARN` y `FAIL` diferenciando PRECHECK vs RUNTIME para que un stack apagado no rompa el flujo cuando solo querés validar bootstrap.

## ☸️ Smoke checks Kubernetes del laboratorio unificado

El repo ahora también trae smoke checks PowerShell para la capa Kubernetes. MISMA idea, pero aplicada al cluster/lab: precheck primero, runtime después, sin build y sin depender de internet.

### Scripts

```powershell
./scripts/check-k8s-runtime-smoke.ps1
./scripts/k8s-smoke-helpers.ps1
```

### Modos operativos

- `-Mode Precheck`: valida manifests esperables del repo, `kubectl` y contexto si existe. Si el cluster está apagado, deja `WARN`, no rompe.
- `-Mode Auto`: corre precheck y suma runtime checks solo si detecta cluster accesible.
- `-Mode Runtime`: exige cluster accesible y revisa namespaces, deployments clave, ConfigMap base de Tetragon, network policies y releases Helm observables.

### Ejemplos

```powershell
./scripts/check-k8s-runtime-smoke.ps1 -Mode Precheck
./scripts/check-k8s-runtime-smoke.ps1 -Mode Auto
./scripts/check-k8s-runtime-smoke.ps1 -Mode Runtime
```

## 🧪 Validación real de detección runtime (Falco + Tetragon)

Cuando quieras validar detección REAL sin hacer nada destructivo, usá:

```powershell
./scripts/validate-runtime-detection.ps1
```

Qué hace este helper:

- resuelve un pod real del laboratorio (default: `targets/dvwa`)
- ejecuta un `sh -c "id && whoami && cat /etc/os-release | sed -n 1,2p"` para generar telemetría de procesos reproducible en **Tetragon**
- ejecuta una lectura controlada `cat /etc/shadow > /dev/null` para intentar disparar una regla segura de **Falco** sin volcar el contenido sensible a la evidencia
- junta evidencia en `evidence/runtime-detection/<timestamp>/`

Archivos esperados por corrida:

- `summary.md` y `summary.json`
- `target-process-command.txt`
- `falco-alerts.jsonl`
- `tetragon-process-events.jsonl`
- `falcosidekick.log`

Notas honestas:

- si el contenedor objetivo no permite leer `/etc/shadow`, Falco puede no alertar y el script lo deja explícito como limitación
- si `falcosidekick` sigue fallando contra `wazuh-syslog-bridge`, el problema ya puede ser Wazuh caído/no escuchando en host, no necesariamente DNS; la evidencia válida queda en los logs locales de Falco/Tetragon

### Bridge honesto Falcosidekick -> Wazuh

Para este lab en Kind sobre Docker Desktop/WSL2, el repo declara `falco/wazuh-syslog-bridge` como `ExternalName -> host.docker.internal`. Así Falcosidekick deja de depender de `wazuh.local`, que no existe mágicamente dentro del cluster.

PERO OJO: esto solo resuelve el puente de nombre/ruta hacia el host. Si `wazuh.manager` no está levantado en Docker o no escucha en `514/udp`, el pipeline completo a Wazuh va a seguir incompleto y eso se reporta como disponibilidad real del destino, no como falso "todo OK".

### Cobertura

- `kubectl` + `kubectl config current-context`
- verificación best-effort del Kind esperado `argos-lab`
- namespaces `ingress-nginx`, `sandbox`, `targets`, `vulnerable-apps`, `tetragon`
- readiness de `ingress-nginx-controller`, sandbox moderno (`mcp-server`, `burp-suite`, `neurosploit`), targets modernos (`juiceshop`, `dvwa`) y targets legacy soportados (`juice-shop`, `dvwa`)
- estado best-effort de `webgoat`: si la imagen upstream sigue saliendo con `Unable to access jarfile webgoat.jar`, se reporta `WARN` y no se finge soporte estable sin una imagen/entrypoint curado dentro del repo
- ConfigMap `tetragon/tetragon-lab-profile`
- releases Helm `kubescape`, `falco`, `tetragon` si Helm está disponible
- network policies esperadas en `sandbox`, `targets` y `vulnerable-apps`

La gracia es NO mentirse: si en `Auto` no hay cluster accesible, el script lo deja clarísimo con `WARN`; si corrés `Runtime`, ahí sí te exige el estado real del lab.

## 🔐 Hardening práctico del `ai-orchestrator`

### CORS con allowlist configurable

- `ai-orchestrator/app/main.py` ya no queda con `allow_origins=["*"]` por default.
- Default nuevo: allowlist local para `localhost` y `127.0.0.1` en puertos típicos de demo.
- Override por env:

```powershell
$env:ARGOS_CORS_ALLOW_ORIGINS = "http://localhost:3000,http://127.0.0.1:5173"
```

- Si de verdad necesitás apertura total temporal para una demo cerrada:

```powershell
$env:ARGOS_CORS_ALLOW_ORIGINS = "*"
```

### Policy gate más estructurado

`ai-orchestrator/app/agents/supervisor.py` ahora centraliza checks base para:

- namespace permitido (`ARGOS_ALLOWED_NAMESPACES`, default `sandbox,targets,vulnerable-apps`)
- herramientas soportadas (`burp`, `kubescape`, `neurosploit`, `nmap_safe`)
- requests vacíos de herramientas
- patrones de texto ligados a acceso de configuración/secrets, destrucción o salida de scope

## ⚠️ Limitaciones y mitigaciones

- Esto NO rota secretos históricos ni limpia el historial git previo.
- Si los certificados de Wazuh ya fueron compartidos fuera del repo, hay que regenerarlos localmente y evaluar recreación de volúmenes/estado antes de volver a confiar en el stack.
- CALDERA sigue permitiendo modos inseguros upstream (`--insecure`); la mitigación en este repo es dejar esa vía SIN secretos reales preconfigurados y documentarla como excepción.
- Un volumen `caldera_conf` viejo puede seguir reteniendo credenciales previas hasta que el operador lo recree.
- El policy gate del runtime legacy sigue siendo heurístico; esto lo hace más ordenado y menos laxo, pero NO lo convierte mágicamente en enforcement de producción.

## 🧹 Limpieza del Entorno

Cuando termines tus pruebas, puedes desmantelar todo el escenario limpiamente:
```powershell
./cleanup-lab.ps1
```
