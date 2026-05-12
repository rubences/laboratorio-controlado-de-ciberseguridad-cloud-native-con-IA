# laboratorio-controlado-de-ciberseguridad-cloud-native-con-IA

## Documento de propuesta

- Ver `propuesta-escenario-argos.md` para la propuesta completa del laboratorio.
- Ver `docs/architecture/decision_tecnica.md` para la revisión de decisiones de arquitectura.

## Estructura base del proyecto

- `infrastructure/`: manifiestos Kubernetes (K8s), configuración de Wazuh y políticas.
- `ai-orchestrator/`: API FastAPI principal, Orquestador multi-agente LangGraph (Policy Gate, Planner, Security, SOC).
- `ai-security-testing/`: Entorno de evaluación (promptfoo) de inyecciones y out-of-scope.
- `offensive/`: Configuración y despliegue de plataformas de emulación (CALDERA).
- `evidence/`: almacenamiento de evidencias auditables.
- `scripts/`: utilidades de despliegue y ejecución local.

## Arquitectura del Orquestador

```mermaid
graph TD
    User([Usuario / CI]) -->|POST /api/v1/analyze| API[FastAPI Gateway]
    API -->|Valida API Key| LG[LangGraph Orchestrator]
    
    subgraph LangGraph Orchestrator
        START --> PG[Policy Gate Node]
        PG -- "Ataque / Out-of-Scope" --> END
        PG -- "Lícito" --> P[Planner Node]
        P --> SA[Security Agent Node]
        SA --> SOC[SOC Reporter Node]
        SOC --> END
    end

    SA -->|LLM Tool Calling| MCP[MCP Client]
    MCP -.->|nmap, kubescape| Tools[Herramientas de Ciberseguridad]
    Tools -.-> K8s[Clúster Kubernetes / Apps Vulnerables]
```

## Ejecución rápida de la API

```bash
cd ai-orchestrator
python -m venv .venv
# source .venv/bin/activate (Linux/Mac)
# .\.venv\Scripts\Activate (Windows)
pip install -r requirements.txt
cd ..
./scripts/run_api.sh
```
