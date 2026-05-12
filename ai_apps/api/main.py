from fastapi import FastAPI

from ai_apps import FOUNDATION_MODEL
from ai_apps.api.routes import router


def create_app() -> FastAPI:
    app = FastAPI(
        title="Controlled Cyber Lab Scaffold API",
        description=(
            "Arquitectura base funcional para coordinar escaneos controlados "
            "en laboratorio. No es una implementación productiva completa."
        ),
        version="0.1.0",
    )
    app.include_router(router)
    app.state.foundation_model = FOUNDATION_MODEL
    return app


app = create_app()
