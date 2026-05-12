from ai_apps.agents.discovery import DiscoveryReport


class BurpMCPClient:
    """Explicit mock adapter for a future Burp MCP integration."""

    def run_scan(self, scan_id: str | None, requested_model: str, discovery_report: DiscoveryReport) -> dict:
        return {
            "tool": "burp",
            "status": "mocked",
            "adapter_mode": "scaffold-mock",
            "scan_id": scan_id,
            "requested_model": requested_model,
            "summary": "Mock passive web enumeration prepared for the discovered target.",
            "findings": [
                {
                    "id": "burp-mock-001",
                    "severity": "info",
                    "title": "Passive route census placeholder",
                    "detail": (
                        f"Prepared a passive crawl plan for {discovery_report.resolved_host}:"
                        f"{discovery_report.resolved_port} without launching a real Burp scan."
                    ),
                }
            ],
        }
