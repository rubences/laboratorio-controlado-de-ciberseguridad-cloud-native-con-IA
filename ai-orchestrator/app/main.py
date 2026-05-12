from fastapi import FastAPI, HTTPException, Security, Depends
from fastapi.security.api_key import APIKeyHeader
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
import uuid
import logging
import time
import os
import json
import secrets
from contextlib import asynccontextmanager
from .agents.supervisor import run_supervisor_workflow
from .mcp_client import mcp_client

# Configure Logging
logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] [%(name)s] %(message)s")
logger = logging.getLogger("hexstrike.api")

API_KEY_NAME = "X-ARGOS-API-KEY"
api_key_header = APIKeyHeader(name=API_KEY_NAME, auto_error=False)

def get_api_key(api_key_header: str = Security(api_key_header)) -> str:
    # Read key from environment securely instead of hardcoding
    expected_key = os.environ.get("ARGOS_API_KEY")
    if not expected_key:
        logger.error("ARGOS_API_KEY environment variable is missing. API is locked.")
        raise HTTPException(status_code=500, detail="Server misconfiguration")
        
    if api_key_header and secrets.compare_digest(api_key_header, expected_key):
        return api_key_header
    raise HTTPException(status_code=403, detail="Could not validate credentials")

@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Initializing MCP Client...")
    await mcp_client.initialize()
    yield

app = FastAPI(
    title="HexStrike AI Orchestrator",
    description="Motor de orquestación autónoma de ciberseguridad para el laboratorio ARGOS.",
    version="1.0.0",
    lifespan=lifespan
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)

class SecurityTaskRequest(BaseModel):
    task_description: str
    target_namespace: str
    allowed_tools: list[str]
    require_approval: bool = False

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
        # SmartOps Integration: Handover to LangGraph Governor
        result = await run_supervisor_workflow(
            task=request.task_description,
            namespace=request.target_namespace,
            tools=request.allowed_tools,
            require_approval=request.require_approval
        )
        exec_time = (time.time() - start_time) * 1000
        response = SecurityTaskResponse(
            correlation_id=correlation_id,
            status="success",
            execution_time_ms=exec_time,
            results=result
        )
        
        # Save evidence automatically
        try:
            evidence_dir = os.path.join(os.path.dirname(__file__), "..", "..", "evidence", "analyses")
            os.makedirs(evidence_dir, exist_ok=True)
            evidence_path = os.path.join(evidence_dir, f"analysis_{correlation_id}.json")
            with open(evidence_path, "w") as f:
                json.dump(response.model_dump(), f, indent=2)
            logger.info(f"[{correlation_id}] Evidence saved to {evidence_path}")
        except Exception as e:
            logger.error(f"[{correlation_id}] Failed to save evidence: {str(e)}")

        return response
    except Exception as e:
        logger.error(f"[{correlation_id}] Workflow failed: {str(e)}")
        raise HTTPException(status_code=500, detail="Internal workflow execution failed")

@app.get("/api/v1/scope", dependencies=[Depends(get_api_key)])
def scope() -> dict[str, list[str]]:
    return {
        "allowed_targets": ["*.lab.local", "10.0.0.0/24", "vulnerable-apps"],
        "blocked_targets": ["0.0.0.0/0", "*.prod.*"],
    }
