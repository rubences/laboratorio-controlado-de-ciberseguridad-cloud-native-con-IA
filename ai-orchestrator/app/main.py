from fastapi import FastAPI, HTTPException, Security, Depends
from fastapi.security.api_key import APIKeyHeader
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
import uuid
import logging
import time
from .agents.supervisor import run_supervisor_workflow

# Configure Logging
logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] [%(name)s] %(message)s")
logger = logging.getLogger("argos.api")

API_KEY_NAME = "X-ARGOS-API-KEY"
api_key_header = APIKeyHeader(name=API_KEY_NAME, auto_error=False)

# Dummy verification for demonstration (Should use env vars/secrets in prod)
def get_api_key(api_key_header: str = Security(api_key_header)) -> str:
    if api_key_header == "argos_super_secret_key_2026":
        return api_key_header
    raise HTTPException(status_code=403, detail="Could not validate credentials")

app = FastAPI(
    title="ARGOS AI Orchestrator API",
    description="Secured API gateway for the AI-driven cloud-native security laboratory",
    version="2.0.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)

class SecurityTaskRequest(BaseModel):
    task_description: str = Field(..., max_length=500, description="The security task to perform")
    target_namespace: str = Field(default="vulnerable-apps", pattern="^[a-z0-9-]+$")
    allowed_tools: list[str] = Field(default=["kubescape", "trivy"])

class SecurityTaskResponse(BaseModel):
    correlation_id: str
    status: str
    execution_time_ms: float
    results: dict

@app.middleware("http")
async def add_correlation_id_and_time(request, call_next):
    correlation_id = str(uuid.uuid4())
    request.state.correlation_id = correlation_id
    start_time = time.time()
    
    logger.info(f"[{correlation_id}] Incoming request: {request.method} {request.url.path}")
    response = await call_next(request)
    
    process_time = (time.time() - start_time) * 1000
    logger.info(f"[{correlation_id}] Completed in {process_time:.2f}ms")
    response.headers["X-Correlation-ID"] = correlation_id
    response.headers["X-Process-Time"] = str(process_time)
    return response

@app.get("/health", dependencies=[Depends(get_api_key)])
def health_check():
    return {"status": "healthy", "version": "2.0.0"}

@app.post("/api/v1/analyze", response_model=SecurityTaskResponse, dependencies=[Depends(get_api_key)])
async def analyze_target(request: SecurityTaskRequest):
    correlation_id = str(uuid.uuid4())
    logger.info(f"[{correlation_id}] Starting task: {request.task_description} on {request.target_namespace}")
    start_time = time.time()
    try:
        # Invoking the LangGraph Supervisor
        result = await run_supervisor_workflow(
            task=request.task_description,
            namespace=request.target_namespace,
            tools=request.allowed_tools
        )
        exec_time = (time.time() - start_time) * 1000
        return SecurityTaskResponse(
            correlation_id=correlation_id,
            status="success",
            execution_time_ms=exec_time,
            results=result
        )
    except Exception as e:
        logger.error(f"[{correlation_id}] Workflow failed: {str(e)}")
        raise HTTPException(status_code=500, detail="Internal workflow execution failed")
