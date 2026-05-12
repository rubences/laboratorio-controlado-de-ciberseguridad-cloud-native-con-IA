from dataclasses import asdict, dataclass
from ipaddress import ip_address
from urllib.parse import urlparse


@dataclass(slots=True)
class DiscoveryReport:
    input_target: str
    normalized_target: str
    target_type: str
    resolved_host: str
    resolved_port: int
    target_namespace: str
    notes: list[str]

    def to_dict(self) -> dict:
        return asdict(self)


class TargetDiscovery:
    """Minimal target normalization for the scaffold."""

    def inspect(self, target: str, namespace: str) -> DiscoveryReport:
        normalized = target.strip()
        parsed = urlparse(normalized if "://" in normalized else f"http://{normalized}")
        host = parsed.hostname or normalized
        port = parsed.port or (443 if parsed.scheme == "https" else 80)
        target_type = self._infer_target_type(host)
        notes = [
            "Scaffold discovery only normalizes the target.",
            "DNS resolution and active probing are intentionally deferred.",
        ]

        if host.endswith(".svc.cluster.local"):
            notes.append("Detected Kubernetes service DNS naming convention.")
        if target_type == "ip":
            notes.append("IP target will be validated against allowed lab CIDRs.")

        return DiscoveryReport(
            input_target=target,
            normalized_target=normalized,
            target_type=target_type,
            resolved_host=host,
            resolved_port=port,
            target_namespace=namespace,
            notes=notes,
        )

    @staticmethod
    def _infer_target_type(host: str) -> str:
        try:
            ip_address(host)
            return "ip"
        except ValueError:
            if "." in host:
                return "dns"
            return "service"
