"""Minimal placeholder for a LangGraph-style orchestrator flow."""

from dataclasses import dataclass


@dataclass
class SecurityTask:
    capability: str
    tool: str
    objective: str


def plan_task(capability: str) -> SecurityTask:
    mapping = {
        "C-06": SecurityTask("C-06", "kubescape", "posture and vuln monitoring"),
        "C-07": SecurityTask("C-07", "hexstrike", "controlled security assessment"),
        "C-08": SecurityTask("C-08", "falco+wazuh", "detection and response correlation"),
    }
    return mapping.get(capability, SecurityTask("unknown", "manual", "human review"))
