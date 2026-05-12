import re
from typing import Any

from pydantic import BaseModel, Field, field_validator

TOOL_NAMES = {"burp", "neurosploit"}
K8S_NAME_PATTERN = re.compile(r"^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$")


class ScanRequest(BaseModel):
    scan_id: str | None = Field(default=None, description="Optional external correlation id")
    scan_name: str = Field(default="baseline-lab-scan")
    target: str = Field(..., description="Target hostname, service name, or URL inside lab scope")
    target_namespace: str = Field(..., description="Kubernetes namespace for the target")
    allowed_tools: list[str] = Field(default_factory=lambda: ["burp", "neurosploit"])
    require_approval: bool = True
    requestor: str = Field(default="lab-operator")

    @field_validator("target")
    @classmethod
    def validate_target(cls, value: str) -> str:
        normalized = value.strip()
        if not normalized:
            raise ValueError("target cannot be empty")
        if any(char.isspace() for char in normalized):
            raise ValueError("target must not contain whitespace")
        return normalized

    @field_validator("target_namespace")
    @classmethod
    def validate_namespace(cls, value: str) -> str:
        normalized = value.strip().lower()
        if not K8S_NAME_PATTERN.match(normalized):
            raise ValueError("target_namespace must be a valid Kubernetes namespace-like name")
        return normalized

    @field_validator("allowed_tools")
    @classmethod
    def validate_tools(cls, value: list[str]) -> list[str]:
        if not value:
            raise ValueError("allowed_tools must include at least one tool")

        normalized = []
        for raw_tool in value:
            tool = raw_tool.strip().lower()
            if tool not in TOOL_NAMES:
                raise ValueError(f"unsupported tool requested: {raw_tool}")
            if tool not in normalized:
                normalized.append(tool)
        return normalized


class HealthResponse(BaseModel):
    status: str
    mode: str
    requested_model: str


class ScanResponse(BaseModel):
    scan_id: str
    status: str
    message: str
    requested_model: str
    scan_name: str
    requestor: str
    target: str
    target_namespace: str
    approval_required: bool
    policy: dict[str, Any]
    discovery: dict[str, Any]
    tool_runs: list[dict[str, Any]]
    evidence_path: str


def normalize_requested_tools(tools: list[str]) -> list[str]:
    return [tool.strip().lower() for tool in tools]
