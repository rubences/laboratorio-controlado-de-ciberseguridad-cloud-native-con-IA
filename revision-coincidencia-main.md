# Revisión de coincidencia: estado actual del repositorio vs propuesta ARGOS

## Resultado ejecutivo

Con el contenido disponible en este repositorio **no es posible validar implementación técnica contra la propuesta**, porque actualmente solo existen archivos documentales y no hay artefactos de infraestructura/código para contrastar (no hay manifiestos Kubernetes, Dockerfiles, FastAPI, LangGraph, conectores MCP, ni configuración de herramientas de seguridad).

## Evidencia revisada

- `README.md`
- `propuesta-escenario-argos.md`

## Verificación por bloques de la propuesta

| Bloque de la propuesta | ¿Hay evidencia en repo? | Observación |
|---|---:|---|
| Backend FastAPI | ❌ | No existe código de API. |
| Orquestación LangGraph | ❌ | No hay agentes, grafo ni estado de ejecución. |
| Integración MCP | ❌ | No hay servidores MCP ni clientes configurados. |
| Laboratorio K8s/Docker | ❌ | No hay manifests Helm/Kustomize/Terraform/Docker Compose. |
| Kubescape / K8sGPT | ❌ | No hay jobs, scripts ni salidas de findings. |
| Trivy / Syft / Grype | ❌ | No hay pipeline SBOM/CVE ni reportes. |
| Falco | ❌ | No hay reglas ni despliegue de sensor runtime. |
| Wazuh + OpenSearch | ❌ | No hay stack SIEM/XDR ni dashboards. |
| CALDERA | ❌ | No hay playbooks ni evidencias ATT&CK. |
| ZAP/Burp | ❌ | No hay escaneos DAST ni artefactos. |
| PyRIT / garak / promptfoo | ❌ | No hay pruebas de seguridad de IA registradas. |
| Métricas (TSP, SCR, FVR, etc.) | ❌ | No hay dataset ni cuadro de mando de métricas. |

## Conclusión

A fecha de esta revisión, el repositorio contiene la **propuesta** pero no la **implementación**. Por tanto, la coincidencia funcional solo puede evaluarse en el plano conceptual (documentación), no en ejecución real.

## Recomendación mínima para poder validar coincidencia

1. Añadir estructura técnica base (`/infra`, `/backend`, `/agents`, `/security`, `/evidence`).
2. Subir un escenario ejecutable mínimo (Kind/K3s + app vulnerable + FastAPI + 1 flujo LangGraph).
3. Incluir al menos 1 evidencia por capacidad:
   - C-06: reporte Kubescape/Trivy.
   - C-07: ejecución controlada HexStrike o equivalente.
   - C-08: alerta Falco correlacionada en Wazuh/OpenSearch.
4. Publicar métricas en formato reproducible (`json/csv`) y un dashboard o informe.

Con esos artefactos sí se podría hacer una auditoría de coincidencia completa y cuantificable con la propuesta.
