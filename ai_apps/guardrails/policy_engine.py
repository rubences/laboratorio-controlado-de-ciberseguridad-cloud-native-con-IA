import re
from dataclasses import asdict, dataclass
from ipaddress import ip_address, ip_network
from urllib.parse import urlparse


@dataclass(slots=True, frozen=True)
class PolicyDecision:
    allowed: bool
    matched_rule: str
    reason: str

    def to_dict(self) -> dict:
        return asdict(self)


class TargetPolicyEngine:
    def __init__(self) -> None:
        self.allowed_namespaces = {"sandbox", "targets", "vulnerable-apps"}
        self.blocked_namespaces = {"default", "kube-system", "prod", "production"}
        self.allowed_services = {"juiceshop", "dvwa", "mcp-server", "burp-suite", "neurosploit"}
        self.allowed_cidrs = [ip_network("10.10.0.0/24"), ip_network("10.20.0.0/24"), ip_network("127.0.0.1/32")]
        self.allowed_dns_patterns = [
            re.compile(r"^[a-z0-9-]+\.lab\.local$"),
            re.compile(r"^[a-z0-9-]+\.(sandbox|targets)\.svc\.cluster\.local$"),
        ]
        self.blocked_dns_patterns = [
            re.compile(r".*\.prod\..*"),
            re.compile(r".*\.corp\..*"),
        ]

    def validate_target(self, target: str, namespace: str, discovered_host: str) -> PolicyDecision:
        normalized_namespace = namespace.strip().lower()
        if normalized_namespace in self.blocked_namespaces:
            return PolicyDecision(False, "blocked_namespace", f"namespace '{normalized_namespace}' is out of scope")
        if normalized_namespace not in self.allowed_namespaces:
            return PolicyDecision(False, "unknown_namespace", f"namespace '{normalized_namespace}' is not declared in the scaffold policy")

        host = self._extract_host(target, discovered_host)
        if host in self.allowed_services:
            return PolicyDecision(True, "allowed_service_name", f"service '{host}' is explicitly allowed in lab namespace '{normalized_namespace}'")

        try:
            candidate_ip = ip_address(host)
        except ValueError:
            for pattern in self.blocked_dns_patterns:
                if pattern.match(host):
                    return PolicyDecision(False, "blocked_dns_pattern", f"host '{host}' matches a blocked DNS pattern")
            for pattern in self.allowed_dns_patterns:
                if pattern.match(host):
                    return PolicyDecision(True, "allowed_dns_pattern", f"host '{host}' matches an approved laboratory DNS pattern")
            return PolicyDecision(False, "unmatched_dns_target", f"host '{host}' does not match approved lab DNS targets")

        if any(candidate_ip in cidr for cidr in self.allowed_cidrs):
            return PolicyDecision(True, "allowed_cidr", f"ip '{host}' is inside an approved laboratory CIDR")
        return PolicyDecision(False, "blocked_ip_range", f"ip '{host}' is outside approved laboratory CIDRs")

    @staticmethod
    def _extract_host(target: str, fallback_host: str) -> str:
        parsed = urlparse(target if "://" in target else f"http://{target}")
        return (parsed.hostname or fallback_host).strip().lower()
