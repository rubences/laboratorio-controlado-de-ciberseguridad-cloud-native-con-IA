import importlib
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from ai_apps.agents.discovery import DiscoveryReport
from ai_apps.agents.validation import ScanRequest, normalize_requested_tools
from ai_apps.guardrails.policy_engine import PolicyDecision


@dataclass(slots=True)
class LegacyBridgeResult:
    status: str
    message: str
    tool_runs: list[dict[str, Any]]
    finding_sources: list[dict[str, Any]]
    execution_details: dict[str, Any]
    limitations: list[str]


class LegacyBridge:
    """In-process adapter from ai_apps into the legacy ai-orchestrator workflow."""

    def __init__(self) -> None:
        self.repo_root = Path(__file__).resolve().parents[2]
        self.legacy_root = self.repo_root / "ai-orchestrator"

    async def execute(
        self,
        *,
        scan_id: str,
        request: ScanRequest,
        discovery_report: DiscoveryReport,
        policy_decision: PolicyDecision,
    ) -> LegacyBridgeResult:
        run_supervisor_workflow, mcp_client = self._load_runtime()
        await mcp_client.initialize()

        legacy_result = await run_supervisor_workflow(
            task=self._build_task_description(request, discovery_report),
            namespace=request.target_namespace,
            tools=normalize_requested_tools(request.allowed_tools),
            require_approval=request.require_approval,
        )

        normalized_findings = self._normalize_findings(legacy_result.get("details", []))
        legacy_status = str(legacy_result.get("status", "unknown"))
        is_success = legacy_status in {"completed", "auto_approved", "human_approved"}
        status = "accepted" if is_success else "blocked"

        message = (
            "Legacy bridge executed in-process through ai-orchestrator. "
            "Results below come from the experimental LangGraph runtime and keep its limitations explicit."
        )
        if legacy_result.get("message"):
            message = f"{message} Legacy runtime message: {legacy_result['message']}"

        limitations = [
            "Legacy runtime remains experimental and depends on ai-orchestrator LangGraph components.",
            "Legacy MCP tool calls are still mocked/simulated in several paths; findings are not a production-grade scan.",
            "Human approval in the legacy runtime is simulated with a timed pause, not a real operator workflow.",
        ]

        return LegacyBridgeResult(
            status=status,
            message=message,
            tool_runs=normalized_findings,
            finding_sources=[
                {
                    "mode": "legacy_bridge",
                    "runtime": "ai-orchestrator",
                    "bridge_path": "in_process",
                    "source": "app.agents.supervisor.run_supervisor_workflow",
                    "total_findings": len(normalized_findings),
                }
            ],
            execution_details={
                "requested_mode": "legacy_bridge",
                "resolved_mode": "legacy_bridge",
                "bridge_used": True,
                "bridge_path": "in_process",
                "runtime": "ai-orchestrator",
                "runtime_entrypoint": "ai-orchestrator/app/agents/supervisor.py:run_supervisor_workflow",
                "mcp_initialization": "ai-orchestrator/app/mcp_client.py:ArgosMCPClient.initialize",
                "legacy_status": legacy_status,
                "legacy_total_findings": legacy_result.get("total_findings", len(normalized_findings)),
                "legacy_result": legacy_result,
                "scan_id": scan_id,
                "policy_rule": policy_decision.matched_rule,
            },
            limitations=limitations,
        )

    def _load_runtime(self):
        if not self.legacy_root.exists():
            raise RuntimeError("legacy bridge unavailable: ai-orchestrator directory not found")

        legacy_path = str(self.legacy_root)
        if legacy_path not in sys.path:
            sys.path.insert(0, legacy_path)

        try:
            supervisor_module = importlib.import_module("app.agents.supervisor")
            mcp_module = importlib.import_module("app.mcp_client")
        except ModuleNotFoundError as exc:
            raise RuntimeError(
                "legacy bridge unavailable: ai-orchestrator dependencies are missing in the active Python environment"
            ) from exc
        except Exception as exc:
            raise RuntimeError(f"legacy bridge unavailable: failed to load ai-orchestrator runtime ({exc})") from exc

        return supervisor_module.run_supervisor_workflow, mcp_module.mcp_client

    @staticmethod
    def _build_task_description(request: ScanRequest, discovery_report: DiscoveryReport) -> str:
        return (
            f"Perform a controlled security analysis for scan '{request.scan_name}' against "
            f"target '{discovery_report.resolved_host}:{discovery_report.resolved_port}' in namespace "
            f"'{request.target_namespace}'. Stay within lab scope, use only approved tools "
            f"{normalize_requested_tools(request.allowed_tools)}, and report verified findings only."
        )

    def _normalize_findings(self, details: list[dict[str, Any]]) -> list[dict[str, Any]]:
        normalized = []
        for finding in details:
            tool_name = str(finding.get("tool", "legacy-runtime"))
            raw_result = finding.get("result")
            parsed_result = self._try_parse_json(raw_result)
            normalized.append(
                {
                    "tool": tool_name,
                    "status": "verified" if finding.get("verified") else self._extract_status(parsed_result),
                    "adapter_mode": "legacy-bridge",
                    "finding_origin": "ai-orchestrator",
                    "summary": self._summarize_result(tool_name, parsed_result),
                    "verification": {
                        "verified": finding.get("verified", False),
                        "confidence": finding.get("confidence"),
                    },
                    "raw_result": parsed_result,
                }
            )
        return normalized

    @staticmethod
    def _try_parse_json(raw_result: Any) -> Any:
        if isinstance(raw_result, str):
            try:
                return json.loads(raw_result)
            except json.JSONDecodeError:
                return {"raw_text": raw_result}
        return raw_result

    @staticmethod
    def _extract_status(parsed_result: Any) -> str:
        if isinstance(parsed_result, dict):
            return str(parsed_result.get("status", "observed"))
        return "observed"

    @staticmethod
    def _summarize_result(tool_name: str, parsed_result: Any) -> str:
        if not isinstance(parsed_result, dict):
            return f"Legacy runtime returned a non-structured result for {tool_name}."

        if tool_name == "burp_suite":
            routes = parsed_result.get("routes", [])
            return f"Legacy Burp path mapped {len(routes)} routes through the ai-orchestrator mock MCP flow."
        if tool_name == "neurosploit_v3":
            return "Legacy NeuroSploit path reported exploit workflow output through the experimental bridge."
        if tool_name == "kubescape":
            findings = parsed_result.get("findings", [])
            return f"Legacy Kubescape path returned {len(findings)} posture findings."

        return f"Legacy runtime reported {tool_name} output through the in-process bridge."
