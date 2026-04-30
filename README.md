# laboratorio-controlado-de-ciberseguridad-cloud-native-con-IA

## Documento de propuesta

- Ver `propuesta-escenario-argos.md` para la propuesta completa del laboratorio.
- Ver `revision-coincidencia-main.md` para la revisión de coincidencia propuesta vs repo.

## Estructura base del proyecto

- `infra/`: base de infraestructura y manifiestos de laboratorio.
- `backend/`: API FastAPI para orquestación y gobierno de alcance.
- `agents/`: flujo base tipo LangGraph para planificación de tareas C-06/C-07/C-08.
- `security/`: políticas y controles del laboratorio aislado.
- `evidence/`: almacenamiento de evidencias auditables.
- `scripts/`: utilidades de ejecución local.

## Ejecución rápida de la API

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r backend/requirements.txt
./scripts/run_api.sh
```
