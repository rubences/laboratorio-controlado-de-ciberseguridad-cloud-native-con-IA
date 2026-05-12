from uuid import uuid4

from ai_apps import FOUNDATION_MODEL
from ai_apps.agents.discovery import TargetDiscovery
from ai_apps.agents.legacy_bridge import LegacyBridge
from ai_apps.agents.validation import ScanRequest, normalize_requested_tools, resolve_execution_mode
from ai_apps.guardrails.evidence_logger import EvidenceLogger
from ai_apps.guardrails.policy_engine import TargetPolicyEngine
from ai_apps.mcp_clients.burp_client import BurpMCPClient
from ai_apps.mcp_clients.neurosploit_client import NeuroSploitClient
from ai_apps.scenario_profile import load_scenario_profile


class ScanOrchestrator:
    """Coordinates guardrails, discovery, tool adapters, and evidence logging."""

    def __init__(self) -> None:
        self.discovery = TargetDiscovery()
        self.policy_engine = TargetPolicyEngine()
        self.evidence_logger = EvidenceLogger()
        self.burp_client = BurpMCPClient()
        self.neurosploit_client = NeuroSploitClient()
        self.legacy_bridge = LegacyBridge()

    def stack_overview(self) -> dict:
        return load_scenario_profile()

    async def start_scan(self, request: ScanRequest) -> dict:
        scan_id = request.scan_id or f"scan-{uuid4().hex[:12]}"
        discovery_report = self.discovery.inspect(request.target, request.target_namespace)
        policy_decision = self.policy_engine.validate_target(
            target=request.target,
            namespace=request.target_namespace,
            discovered_host=discovery_report.resolved_host,
        )
        if not policy_decision.allowed:
            raise PermissionError(policy_decision.reason)

        execution_mode = resolve_execution_mode(request)
        if execution_mode == "legacy_bridge":
            bridge_result = await self.legacy_bridge.execute(
                scan_id=scan_id,
                request=request,
                discovery_report=discovery_report,
                policy_decision=policy_decision,
            )
            execution_result = {
                "status": bridge_result.status,
                "message": bridge_result.message,
                "tool_runs": bridge_result.tool_runs,
                "execution_details": bridge_result.execution_details,
                "finding_sources": bridge_result.finding_sources,
                "limitations": bridge_result.limitations,
            }
        else:
            execution_result = self._run_scaffold_mode(scan_id, request, discovery_report)

        result = {
            "scan_id": scan_id,
            "status": execution_result["status"],
            "message": execution_result["message"],
            "requested_model": FOUNDATION_MODEL,
            "scan_name": request.scan_name,
            "requestor": request.requestor,
            "target": request.target,
            "target_namespace": request.target_namespace,
            "approval_required": request.require_approval,
            "policy": policy_decision.to_dict(),
            "discovery": discovery_report.to_dict(),
            "tool_runs": execution_result["tool_runs"],
            "execution_mode": execution_mode,
            "execution_details": execution_result["execution_details"],
            "finding_sources": execution_result["finding_sources"],
            "limitations": execution_result["limitations"],
        }
        return self.evidence_logger.persist_scan(result)

    def _run_scaffold_mode(self, scan_id: str, request: ScanRequest, discovery_report) -> dict:
        tool_runs = []
        for tool_name in normalize_requested_tools(request.allowed_tools):
            if tool_name == "burp":
                tool_runs.append(
                    self.burp_client.run_scan(
                        scan_id=scan_id,
                        requested_model=FOUNDATION_MODEL,
                        discovery_report=discovery_report,
                    )
                )
            elif tool_name == "neurosploit":
                tool_runs.append(
                    self.neurosploit_client.run_scan(
                        scan_id=scan_id,
                        requested_model=FOUNDATION_MODEL,
                        discovery_report=discovery_report,
                    )
                )

        return {
            "status": "accepted",
            "message": (
                "Scaffold execution completed with mock MCP adapters and persisted evidence."
            ),
            "tool_runs": tool_runs,
            "execution_details": {
                "requested_mode": request.execution_mode,
                "requested_profile": request.execution_profile,
                "resolved_mode": "scaffold",
                "bridge_used": False,
                "bridge_path": None,
                "runtime": "ai_apps",
                "runtime_entrypoint": "ai_apps/agents/orchestrator.py:ScanOrchestrator._run_scaffold_mode",
                "adapter_strategy": "in-process scaffold mock adapters",
            },
            "finding_sources": [
                {
                    "mode": "scaffold",
                    "runtime": "ai_apps",
                    "source": f"ai_apps.mcp_clients.{tool_run['tool']}_client",
                    "finding_origin": "scaffold_mock_adapter",
                }
                for tool_run in tool_runs
            ],
            "limitations": [
                "Scaffold mode uses explicit mock adapters for Burp and NeuroSploit.",
                "Discovery is normalization-only and does not perform real probing or DNS resolution.",
            ],
        }
