from fastapi import APIRouter, HTTPException

from ai_apps import FOUNDATION_MODEL
from ai_apps.agents.orchestrator import ScanOrchestrator
from ai_apps.agents.validation import HealthResponse, ScanRequest, ScanResponse

router = APIRouter(tags=["scaffold"])
orchestrator = ScanOrchestrator()


@router.get("/health", response_model=HealthResponse)
def health() -> HealthResponse:
    return HealthResponse(
        status="healthy",
        mode="scaffold",
        requested_model=FOUNDATION_MODEL,
    )


@router.post("/api/v1/scans/start", response_model=ScanResponse)
def start_scan(request: ScanRequest) -> ScanResponse:
    try:
        result = orchestrator.start_scan(request)
    except PermissionError as exc:
        raise HTTPException(status_code=403, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    return ScanResponse.model_validate(result)
