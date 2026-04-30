# Decisión técnica recomendada

Para este trabajo, yo construiría el escenario de pruebas sobre un laboratorio controlado de ciberseguridad cloud-native con IA, alineado con ARGOS, donde se validen tres capacidades principales: C-06 monitorización continua de activos y vulnerabilidades, C-07 evaluación de seguridad asistida por IA y C-08 detección y respuesta integrada. Estas tres líneas son las que mejor conectan con el objetivo del proyecto: cero vulnerabilidades, cATO, DevSecOps, XDR, IA operacional y evaluación continua del posture de seguridad. El documento de casos de uso indica explícitamente que ARGOS debe validar “zero obsolescence”, “zero vulnerability”, “Continuous Secure Delivery”, “Continuous Asset & Vulnerability Monitoring”, “AI-Driven Security Assessment” e “Integrated Threat Detection & Response”.

Mi decisión sería la siguiente:

Herramienta principal del escenario: HexStrike AI integrado mediante MCP, gobernado por LangGraph/FastAPI, ejecutado solo en laboratorio aislado, y complementado con Kubescape, K8sGPT, Trivy/Syft/Grype, Falco, Wazuh/OpenSearch, CALDERA, Burp Suite/ZAP, PyRIT, garak y promptfoo.

No elegiría una única herramienta “mágica”. El escenario debe demostrar una arquitectura de validación, no solo la ejecución de un pentest asistido por IA.

## 1. Criterios de selección

He usado estos criterios para decidir:

| Criterio | Peso | Justificación |
| :--- | :--- | :--- |
| Alineación con ARGOS | Muy alto | Debe cubrir C-06, C-07 y C-08, no solo pentesting. |
| Integración con MCP | Muy alto | El DDJF plantea MCP como mecanismo estándar para conectar agentes con herramientas externas. |
| Seguridad y control | Muy alto | El escenario debe ser autorizado, trazable y reproducible. |
| Capacidad cloud-native/Kubernetes | Alto | ARGOS se orienta a PaaS, microservicios, Kubernetes y entornos cloud-native. |
| Evidencia auditable | Alto | El escenario debe generar findings, logs, informes, métricas y trazabilidad. |
| Valor académico/TFG | Alto | El alumno debe poder explicar decisiones, arquitectura y resultados. |
| Riesgo operativo | Alto | Se deben evitar herramientas opacas o con comportamiento autónomo no gobernado. |

## 2. Herramientas analizadas y decisión

### 2.1. HexStrike AI — herramienta principal de orquestación ofensiva controlada

**Decisión**: seleccionada como herramienta principal para C-07.

HexStrike AI encaja muy bien porque el informe de herramientas lo describe como una plataforma multiagente que integra más de 150 herramientas profesionales, incluyendo Nmap, FFuf, SQLMap, Trivy y utilidades de ingeniería inversa, y que se apoya en MCP/FastMCP como puente entre modelos de lenguaje y funciones tácticas del entorno.

Su valor para el escenario no está en “explotar”, sino en demostrar:
- Descubrimiento de exposición: servicios, puertos, APIs y superficies accesibles.
- Validación controlada de rutas de ataque: siempre dentro de un laboratorio.
- Generación de evidencias: comandos ejecutados, hallazgos, trazas y resultados.
- Integración natural con MCP: coherente con la arquitectura ARGOS.

El DDJF también menciona explícitamente HexStrike AI como una plataforma MCP de automatización de ciberseguridad útil para reconocimiento, descubrimiento de vulnerabilidades y como capa única de acceso a múltiples herramientas subyacentes.

**Riesgo**: es una herramienta potente. Por tanto, debe ejecutarse con una política de alcance estricta: solo laboratorio, sin Internet salvo feeds controlados, sin objetivos externos y con allowlist de targets.

### 2.2. CALDERA — adversarial emulation controlada

**Decisión**: seleccionada como herramienta de validación defensiva.

CALDERA encaja mejor que una herramienta de explotación directa cuando se quiere demostrar C-07.UC3 Attack path validation & adversarial emulation y C-08 Integrated Threat Detection & Response. El DDJF lo identifica como plataforma MITRE para emulación adversaria automatizada, basada en ATT&CK, con servidor C2, API REST e interfaz web, útil para ejercicios controlados y validación de controles defensivos.

CALDERA debe usarse para generar actividad simulada, observable y medible, no para comprometer sistemas reales. Su papel sería comprobar si Falco/Wazuh/OpenSearch detectan la actividad y si el agente de IA puede correlacionarla y explicarla.

### 2.3. Kubescape — postura de seguridad Kubernetes

**Decisión**: seleccionada como herramienta base para C-06 y C-07.

Kubescape es muy adecuado porque el documento de arquitectura lo menciona como plataforma de seguridad Kubernetes capaz de operar como CLI y como operador dentro del clúster, monitorizando postura de seguridad, configuraciones erróneas y vulnerabilidades. Además, expone findings como objetos de Kubernetes y dispone de servidor MCP dentro de la CLI.

Se utilizaría para:
- Validar configuración de Kubernetes.
- Detectar misconfigurations.
- Evaluar compliance.
- Alimentar al agente IA con findings estructurados.
- Generar evidencias para cATO.

### 2.4. K8sGPT — diagnóstico operacional asistido por IA

**Decisión**: seleccionada como herramienta de soporte operacional.

K8sGPT encaja con la parte de AI Operator Support y diagnóstico cloud-native. El DDJF lo describe como una plataforma de troubleshooting asistido por IA para entender eventos, logs y problemas de Kubernetes, ejecutable como CLI, operador o servicio, y con servidor MCP oficial.

Su papel no sería ofensivo, sino explicar:
- Por qué un pod falla.
- Qué eventos anómalos aparecen.
- Qué recursos están mal configurados.
- Qué impacto puede tener un fallo de configuración.

### 2.5. Trivy, Syft y Grype — inventario, SBOM y vulnerabilidades

**Decisión**: seleccionadas como herramientas de supply chain y vulnerabilidad.

Aunque el documento menciona Trivy dentro del ecosistema de HexStrike, para el escenario conviene usarlo también de forma independiente. Trivy permite analizar imágenes, dependencias y configuraciones; Syft genera SBOM; Grype analiza vulnerabilidades sobre SBOM. Esta combinación es muy útil para demostrar C-05 y C-06:
- Inventario de componentes.
- Identificación de CVEs.
- Relación entre imagen vulnerable, workload desplegado y criticidad.
- Evidencia antes/después de parcheo.

### 2.6. Falco — detección runtime en Kubernetes

**Decisión**: seleccionada para runtime security.

Falco encaja con la arquitectura XDR propuesta, porque el DDJF define una capa de runtime detection orientada a detectar comportamiento sospechoso, escalada de privilegios, actividad inesperada, eventos de red, identidades y telemetría host/container.

Falco sería el sensor principal para detectar:
- Shell inesperada dentro de contenedor.
- Lectura de ficheros sensibles.
- Ejecución de binarios no previstos.
- Cambios de privilegios.
- Conexiones anómalas entre servicios.

### 2.7. Wazuh + OpenSearch/Elastic — SIEM/XDR académico

**Decisión**: seleccionada para correlación y evidencias.

El escenario necesita una capa donde se consoliden eventos. Wazuh con OpenSearch o Elastic permite representar un SOC académico y generar dashboards, alertas e informes. Encaja con C-08, ya que el documento de casos de uso plantea la necesidad de correlación en tiempo real, integración por capas —aplicaciones, contenedores, red y host— y respuesta coordinada con apoyo de IA.

### 2.8. Burp Suite o OWASP ZAP — validación web/API

**Decisión**: seleccionada como herramienta secundaria para superficie web/API.

Burp Suite es especialmente útil si el escenario incluye una aplicación vulnerable como Juice Shop, DVWA, WebGoat o una API vulnerable. El informe de herramientas destaca que Burp AI mantiene un enfoque human-in-the-loop, con capacidades como Explore Issue, Explainer y reducción de falsos positivos, sin sustituir completamente al analista.

Para un TFG, propondría:
- OWASP ZAP si se busca 100% open source y reproducibilidad.
- Burp Suite Community/Professional si el alumno tiene licencia o se quiere un flujo más profesional.
- Burp MCP como integración avanzada si el objetivo es demostrar conexión con agentes IA.

### 2.9. PyRIT, garak y promptfoo — seguridad de la propia IA

**Decisión**: seleccionadas para una fase adicional de “Security for AI”.

El informe distingue dos macrodisciplinas: IA para ciberseguridad y seguridad para la IA, es decir, proteger modelos, pipelines y agentes frente a ataques adversarios. Por tanto, el escenario no debe limitarse a usar IA para pentesting; también debe evaluar si el propio agente es vulnerable a prompt injection, fuga de datos, jailbreaks o uso indebido de herramientas.

- **PyRIT**: útil para campañas adversarias contra LLMs, con conversores de prompts, scoring y posibilidad de orquestación mediante MCP.
- **garak**: adecuado para escaneo de vulnerabilidades de LLMs mediante probes, incluyendo jailbreaks e inyecciones codificadas.
- **promptfoo**: muy útil para integrar pruebas de seguridad de prompts en CI/CD y mapear hallazgos contra OWASP Top 10 for LLM Applications, NIST, MITRE ATLAS y EU AI Act.

## 3. Arquitectura final recomendada del escenario

La arquitectura que propongo sería esta:

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

Esta arquitectura está alineada con el DDJF porque ARGOS propone una capa de integración de IA con APIs, SmartOps, FastAPI, agentes, MCP, LangGraph y conexión con herramientas externas de ciberseguridad. También se alinea con el principio de que MCP actúa como interfaz estándar para que los agentes accedan a herramientas, recursos y prompts mediante una arquitectura host-cliente-servidor.

## 4. Escenario de pruebas elegido

**Nombre del escenario**
Escenario Integrado de Evaluación Continua de Seguridad con IA para Entornos Cloud-Native tipo ARGOS

**Objetivo**
Demostrar que un entorno cloud-native puede ser evaluado, monitorizado y defendido mediante agentes de IA integrados con herramientas de ciberseguridad, manteniendo trazabilidad, control humano y evidencias auditables.

**Flujo general**
1. **Descubrimiento de activos**
   - Herramientas: Kubescape, K8sGPT, Nmap controlado vía HexStrike.
   - Resultado: inventario de servicios, namespaces, workloads, APIs y exposición.
2. **Análisis de vulnerabilidades**
   - Herramientas: Trivy, Syft, Grype, Kubescape.
   - Resultado: CVEs, SBOM, imágenes vulnerables, configuraciones inseguras.
3. **Evaluación ofensiva controlada**
   - Herramientas: HexStrike AI, CALDERA, ZAP/Burp.
   - Resultado: rutas de ataque simuladas, validación de superficie expuesta y evidencias.
4. **Detección y correlación**
   - Herramientas: Falco, Wazuh, OpenSearch/Elastic.
   - Resultado: alertas runtime, eventos correlacionados y timeline del incidente.
5. **Análisis IA**
   - Herramientas: LangGraph, RAG, MCP, LLM local o controlado.
   - Resultado: explicación del incidente, priorización, recomendaciones y blast radius.
6. **Evaluación de seguridad del agente IA**
   - Herramientas: PyRIT, garak, promptfoo.
   - Resultado: pruebas de prompt injection, jailbreak, tool misuse y fuga de contexto.
7. **Informe final**
   - Evidencias: logs, capturas, JSON de findings, dashboards, métricas, recomendaciones.

## 5. Herramientas definitivas por capa

| Capa | Herramienta elegida | Motivo |
| :--- | :--- | :--- |
| Orquestación IA | LangGraph | Permite flujos multiagente, estado, decisiones condicionales y trazabilidad. |
| Integración de herramientas | MCP | Es el mecanismo más alineado con ARGOS. |
| API | FastAPI | Coherente con el DDJF, fácil de documentar con OpenAPI. |
| Interfaz | SmartOps simplificado / dashboard propio | Permite mostrar resultados y evidencias. |
| Laboratorio | Docker + Kubernetes/K3s/Kind | Reproducible y seguro. |
| Seguridad Kubernetes | Kubescape | Postura, compliance, misconfigurations y MCP. |
| Diagnóstico K8s | K8sGPT | Explicabilidad operacional. |
| SBOM/vulnerabilidades | Syft + Grype + Trivy | Inventario y CVEs. |
| Runtime detection | Falco | Detección de comportamiento anómalo en contenedores. |
| SIEM/XDR | Wazuh + OpenSearch/Elastic | Correlación, dashboards y evidencias. |
| Ofensiva controlada | HexStrike AI | Principal por MCP y amplitud de herramientas. |
| Emulación adversaria | CALDERA | Validación defensiva basada en MITRE ATT&CK. |
| Web/API | OWASP ZAP o Burp Suite | Validación DAST. |
| Seguridad de IA | PyRIT + garak + promptfoo | Evaluación del propio agente y prompts. |

## 6. Herramientas descartadas como núcleo

- No pondría PentestGPT como herramienta principal. Es interesante como baseline académico porque el informe destaca su enfoque Docker-first, persistencia de sesión y resultados coste-eficientes, pero para este escenario HexStrike encaja mejor por MCP y por su capacidad de actuar como capa de acceso a múltiples herramientas.
- No pondría HackingBuddyGPT como núcleo. Es muy útil para investigación y prototipado, especialmente por su simplicidad y uso de SSH/tmux, pero el escenario ARGOS necesita más gobierno, trazabilidad, integración MCP y separación entre hipótesis/evidencia.
- No elegiría XBOW/ARTEMIS para el TFG salvo como referencia comparativa, porque son plataformas más comerciales y menos controlables en un laboratorio académico.

## 7. Métricas de evaluación recomendadas

Para que el escenario tenga valor académico y técnico, mediría:

| Métrica | Qué mide |
| :--- | :--- |
| TSP — Tool Selection Precision | Si el agente elige la herramienta adecuada para cada tarea. |
| SCR — Scope Compliance Rate | Si el agente respeta el alcance permitido. |
| FVR — Finding Validity Rate | Porcentaje de hallazgos reales frente a falsos positivos. |
| ECI — Evidence Completeness Index | Calidad de evidencias: logs, capturas, comandos, outputs. |
| SSA — Safety Stop Accuracy | Capacidad de detener acciones fuera de alcance. |
| MTTD | Tiempo medio de detección. |
| MTTA | Tiempo medio de análisis. |
| MTTR simulado | Tiempo hasta recomendación de mitigación. |
| Coverage | Porcentaje de activos y namespaces analizados. |
| RAG Grounding Score | Si las respuestas IA están justificadas en evidencias reales. |

## 8. Decisión final

La mejor elección para el trabajo es un escenario integrado de ciberseguridad e IA, no una práctica aislada de pentesting. La herramienta central debe ser HexStrike AI, pero siempre gobernada por MCP + LangGraph + políticas de alcance + laboratorio aislado. A su alrededor deben integrarse herramientas defensivas y de validación: Kubescape, K8sGPT, Trivy/Syft/Grype, Falco, Wazuh/OpenSearch, CALDERA, ZAP/Burp, PyRIT, garak y promptfoo.

Esta combinación permite cubrir de forma coherente:
- **C-06**: inventario, vulnerabilidades, compliance y cATO.
- **C-07**: exposición, misconfigurations, emulación adversaria y blast radius.
- **C-08**: telemetría, correlación, triage, respuesta y SOC.
- **Seguridad de la IA**: evaluación de prompt injection, jailbreaks y abuso de herramientas.

En términos de TFG, esta decisión es sólida porque el alumno no solo demuestra que una IA puede ejecutar herramientas, sino que diseña una arquitectura segura, trazable, explicable y evaluable, alineada con una plataforma tipo ARGOS y con los principios modernos de DevSecOps, XDR, MCP y agentes IA.
