from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from .graph import run_security_workflow

app = FastAPI(
    title="ARGOS AI Orchestrator API",
    description="API gateway for the AI-driven cloud-native security laboratory",
    version="1.0.0"
)

class SecurityTaskRequest(BaseModel):
    task_description: str
    target_namespace: str = "vulnerable-apps"
    allowed_tools: list[str] = ["kubescape", "trivy", "nmap_safe"]

class SecurityTaskResponse(BaseModel):
    status: str
    results: dict

@app.get("/")
def read_root():
    return {"message": "Welcome to ARGOS AI Orchestrator"}

@app.post("/api/v1/analyze", response_model=SecurityTaskResponse)
async def analyze_target(request: SecurityTaskRequest):
    try:
        # Aquí se invocaría el grafo de LangGraph
        result = await run_security_workflow(
            task=request.task_description,
            namespace=request.target_namespace,
            tools=request.allowed_tools
        )
        return SecurityTaskResponse(status="success", results=result)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
