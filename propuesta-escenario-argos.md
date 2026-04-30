# Escenario Integrado de Evaluación Continua de Seguridad con IA para Entornos Cloud-Native tipo ARGOS

## 1. Decisión de diseño

La estrategia recomendada para el trabajo es construir un **laboratorio controlado de ciberseguridad cloud-native con IA**, alineado con ARGOS, para validar de forma integrada:

- **C-06**: monitorización continua de activos y vulnerabilidades.
- **C-07**: evaluación de seguridad asistida por IA.
- **C-08**: detección y respuesta integrada.

La herramienta principal propuesta es **HexStrike AI** vía **MCP**, gobernada por **LangGraph + FastAPI** y ejecutada únicamente en un laboratorio aislado. Se complementa con herramientas defensivas y de validación para cubrir el ciclo completo de postura, evaluación ofensiva controlada, detección y evidencia.

## 2. Criterios de selección

| Criterio | Peso | Justificación |
|---|---|---|
| Alineación con ARGOS | Muy alto | Debe cubrir C-06, C-07 y C-08, no solo pentesting puntual. |
| Integración con MCP | Muy alto | MCP se plantea como interfaz estándar para agentes y herramientas. |
| Seguridad y control | Muy alto | Escenario autorizado, trazable, reproducible y con límites de alcance. |
| Capacidad cloud-native/Kubernetes | Alto | Contexto centrado en PaaS, microservicios y Kubernetes. |
| Evidencia auditable | Alto | Se requieren hallazgos, logs, métricas, reportes y trazabilidad. |
| Valor académico/TFG | Alto | Debe justificar arquitectura, decisiones y resultados. |
| Riesgo operativo | Alto | Evitar autonomía no gobernada y minimizar riesgo fuera de alcance. |

## 3. Herramientas seleccionadas y rol

### 3.1 HexStrike AI (principal para C-07)

- Orquestación ofensiva controlada en laboratorio.
- Descubrimiento de exposición y rutas de ataque simuladas.
- Evidencias de ejecución y resultados por tarea.
- Integración natural con MCP para gobernanza.

> Control obligatorio: allowlist de objetivos, denegación de destinos externos y trazabilidad completa.

### 3.2 CALDERA

- Emulación adversaria basada en ATT&CK.
- Validación de controles defensivos para C-07/C-08.
- Actividad simulada medible para correlación y detección.

### 3.3 Kubescape

- Postura de seguridad Kubernetes.
- Misconfigurations, compliance y findings estructurados.
- Base de C-06 + apoyo a C-07.

### 3.4 K8sGPT

- Diagnóstico operacional asistido por IA en clúster.
- Explicabilidad de fallos y eventos anómalos.

### 3.5 Trivy + Syft + Grype

- Inventario SBOM, CVEs y supply-chain security.
- Evidencia antes/después de mitigaciones.

### 3.6 Falco

- Detección runtime en contenedores/Kubernetes.
- Señales de shell inesperada, privilegios, binarios y red.

### 3.7 Wazuh + OpenSearch/Elastic

- Correlación SIEM/XDR, dashboards y cronología de incidentes.
- Capa central de evidencia de C-08.

### 3.8 ZAP o Burp Suite

- Validación DAST de superficie web/API.
- Opción OSS (ZAP) o profesional (Burp) según contexto.

### 3.9 PyRIT + garak + promptfoo

- Seguridad de la propia IA (prompt injection, jailbreak, tool misuse, fuga de datos).
- Extensión del escenario hacia “security for AI”.

## 4. Arquitectura recomendada

```text
┌──────────────────────────────────────────────────────────────┐
│                     SmartOps / Dashboard                      │
│     Visualización, prompts, resultados, evidencias, informes  │
└───────────────────────┬──────────────────────────────────────┘
                        │
┌───────────────────────▼──────────────────────────────────────┐
│              API Gateway / FastAPI / Backend IA               │
│        Control de alcance, autenticación, auditoría           │
└───────────────────────┬──────────────────────────────────────┘
                        │
┌───────────────────────▼──────────────────────────────────────┐
│              LangGraph Multi-Agent Orchestrator               │
│  Planner Agent | Security Agent | Evidence Agent | SOC Agent  │
└───────────────┬─────────────┬─────────────┬──────────────────┘
                │             │             │
        ┌───────▼──────┐ ┌────▼─────┐ ┌────▼────────┐
        │ MCP Servers  │ │ RAG/Docs │ │ Policy Gate │
        └───────┬──────┘ └──────────┘ └─────────────┘
                │
┌───────────────▼───────────────────────────────────────────────┐
│                 Herramientas de ciberseguridad                │
│ HexStrike | Kubescape | K8sGPT | Trivy | Falco | Wazuh | ZAP  │
│ CALDERA | PyRIT | garak | promptfoo | Nmap controlado         │
└───────────────┬───────────────────────────────────────────────┘
                │
┌───────────────▼───────────────────────────────────────────────┐
│                  Laboratorio aislado Kubernetes/Docker        │
│   Apps vulnerables | APIs | workloads | namespace DMZ | logs   │
└───────────────────────────────────────────────────────────────┘
```

## 5. Flujo operativo del escenario

1. **Descubrimiento de activos**: Kubescape, K8sGPT, Nmap controlado (vía HexStrike).
2. **Análisis de vulnerabilidades**: Trivy, Syft, Grype, Kubescape.
3. **Evaluación ofensiva controlada**: HexStrike, CALDERA, ZAP/Burp.
4. **Detección y correlación**: Falco + Wazuh + OpenSearch/Elastic.
5. **Análisis asistido por IA**: LangGraph + RAG + MCP para priorización y blast radius.
6. **Seguridad del agente IA**: PyRIT, garak y promptfoo.
7. **Informe final**: evidencias, métricas, findings y recomendaciones.

## 6. Herramientas descartadas como núcleo

- **PentestGPT**: válido como baseline, pero menos alineado como eje MCP integral.
- **HackingBuddyGPT**: útil para exploración, con menor gobernanza para este objetivo.
- **XBOW/ARTEMIS**: valiosas como referencia comparativa, menos adecuadas como núcleo académico de laboratorio controlado.

## 7. Métricas recomendadas

| Métrica | Qué mide |
|---|---|
| TSP (Tool Selection Precision) | Elección correcta de herramienta por tarea. |
| SCR (Scope Compliance Rate) | Respeto del alcance permitido. |
| FVR (Finding Validity Rate) | Hallazgos reales vs falsos positivos. |
| ECI (Evidence Completeness Index) | Completitud de evidencias y trazabilidad. |
| SSA (Safety Stop Accuracy) | Parada ante acciones fuera de alcance. |
| MTTD | Tiempo medio de detección. |
| MTTA | Tiempo medio de análisis. |
| MTTR simulado | Tiempo hasta recomendación de mitigación. |
| Coverage | Activos/namespaces analizados. |
| RAG Grounding Score | Justificación de respuestas IA en evidencias reales. |

## 8. Conclusión

La opción más sólida es un **escenario integrado** en lugar de un pentest aislado. El núcleo debe ser **HexStrike AI**, pero siempre bajo **MCP + LangGraph + políticas de alcance + laboratorio aislado** y acompañado por capacidades defensivas, de observabilidad y de seguridad de IA.

Esta decisión permite cubrir con coherencia:

- **C-06**: inventario, vulnerabilidades, compliance y cATO.
- **C-07**: exposición, misconfigurations, emulación adversaria y blast radius.
- **C-08**: telemetría, correlación, triage, respuesta y operación tipo SOC.

