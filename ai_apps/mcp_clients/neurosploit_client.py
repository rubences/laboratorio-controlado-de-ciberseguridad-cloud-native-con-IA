from ai_apps.agents.discovery import DiscoveryReport


class NeuroSploitClient:
    """Explicit mock adapter for a future NeuroSploit MCP integration."""

    def run_scan(self, scan_id: str | None, requested_model: str, discovery_report: DiscoveryReport) -> dict:
        return {
            "tool": "neurosploit",
            "status": "mocked",
            "adapter_mode": "scaffold-mock",
            "scan_id": scan_id,
            "requested_model": requested_model,
            "summary": "Mock offensive safety check recorded with no exploit execution.",
            "findings": [
                {
                    "id": "neurosploit-mock-001",
                    "severity": "low",
                    "title": "Safety checkpoint placeholder",
                    "detail": (
                        f"Recorded a no-op exploitability assessment for {discovery_report.resolved_host} "
                        "to preserve the orchestrator contract without pretending production behavior."
                    ),
                }
            ],
        }
