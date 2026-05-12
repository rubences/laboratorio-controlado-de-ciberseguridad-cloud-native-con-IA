import re
from typing import Any, Literal

from pydantic import BaseModel, Field, field_validator, model_validator

TOOL_NAMES = {"burp", "neurosploit"}
K8S_NAME_PATTERN = re.compile(r"^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$")
EXECUTION_PROFILE_ALIASES = {
    "default": "scaffold",
    "scaffold": "scaffold",
    "legacy": "legacy_bridge",
    "legacy_bridge": "legacy_bridge",
}


class ScanRequest(BaseModel):
    scan_id: str | None = Field(default=None, description="Optional external correlation id")
    scan_name: str = Field(default="baseline-lab-scan")
    target: str = Field(..., description="Target hostname, service name, or URL inside lab scope")
    target_namespace: str = Field(..., description="Kubernetes namespace for the target")
    allowed_tools: list[str] = Field(default_factory=lambda: ["burp", "neurosploit"])
    require_approval: bool = True
    requestor: str = Field(default="lab-operator")
    execution_mode: Literal["scaffold", "legacy_bridge"] | None = Field(
        default=None,
        description="Execution path for the scan request. 'scaffold' keeps local mock adapters, 'legacy_bridge' delegates in-process to ai-orchestrator.",
    )
    execution_profile: str | None = Field(
        default=None,
        description="Optional profile alias. Supported values: default, scaffold, legacy, legacy_bridge.",
    )

    @model_validator(mode="after")
    def validate_execution_selection(self) -> "ScanRequest":
        if self.execution_profile is None:
            return self

        profile = self.execution_profile.strip().lower()
        resolved_mode = EXECUTION_PROFILE_ALIASES.get(profile)
        if resolved_mode is None:
            supported_profiles = ", ".join(sorted(EXECUTION_PROFILE_ALIASES))
            raise ValueError(f"unsupported execution_profile: {self.execution_profile}. Supported profiles: {supported_profiles}")
        if self.execution_mode is not None and self.execution_mode != resolved_mode:
            raise ValueError(
                "execution_mode and execution_profile must resolve to the same path"
            )
        self.execution_profile = profile
        return self

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
    execution_mode: str
    execution_details: dict[str, Any]
    finding_sources: list[dict[str, Any]]
    limitations: list[str]
    evidence_path: str


def resolve_execution_mode(request: ScanRequest) -> str:
    if request.execution_profile:
        return EXECUTION_PROFILE_ALIASES[request.execution_profile]
    return request.execution_mode or "scaffold"


def normalize_requested_tools(tools: list[str]) -> list[str]:
    return [tool.strip().lower() for tool in tools]
