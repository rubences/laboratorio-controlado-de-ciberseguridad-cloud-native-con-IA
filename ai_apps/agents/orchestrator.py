from uuid import uuid4

from ai_apps import FOUNDATION_MODEL
from ai_apps.agents.discovery import TargetDiscovery
from ai_apps.agents.validation import ScanRequest, normalize_requested_tools
from ai_apps.guardrails.evidence_logger import EvidenceLogger
from ai_apps.guardrails.policy_engine import TargetPolicyEngine
from ai_apps.mcp_clients.burp_client import BurpMCPClient
from ai_apps.mcp_clients.neurosploit_client import NeuroSploitClient


class ScanOrchestrator:
    """Coordinates guardrails, discovery, tool adapters, and evidence logging."""

    def __init__(self) -> None:
        self.discovery = TargetDiscovery()
        self.policy_engine = TargetPolicyEngine()
        self.evidence_logger = EvidenceLogger()
        self.burp_client = BurpMCPClient()
        self.neurosploit_client = NeuroSploitClient()

    def start_scan(self, request: ScanRequest) -> dict:
        scan_id = request.scan_id or f"scan-{uuid4().hex[:12]}"
        discovery_report = self.discovery.inspect(request.target, request.target_namespace)
        policy_decision = self.policy_engine.validate_target(
            target=request.target,
            namespace=request.target_namespace,
            discovered_host=discovery_report.resolved_host,
        )
        if not policy_decision.allowed:
            raise PermissionError(policy_decision.reason)

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

        result = {
            "scan_id": scan_id,
            "status": "accepted",
            "message": (
                "Scaffold execution completed with mock MCP adapters and persisted evidence."
            ),
            "requested_model": FOUNDATION_MODEL,
            "scan_name": request.scan_name,
            "requestor": request.requestor,
            "target": request.target,
            "target_namespace": request.target_namespace,
            "approval_required": request.require_approval,
            "policy": policy_decision.to_dict(),
            "discovery": discovery_report.to_dict(),
            "tool_runs": tool_runs,
        }
        return self.evidence_logger.persist_scan(result)
