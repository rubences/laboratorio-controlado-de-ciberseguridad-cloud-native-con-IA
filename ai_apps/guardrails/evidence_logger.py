import json
from datetime import UTC, datetime
from pathlib import Path


class EvidenceLogger:
    def __init__(self, base_directory: Path | None = None) -> None:
        repo_root = Path(__file__).resolve().parents[2]
        self.base_directory = base_directory or repo_root / "evidence" / "scaffold" / "scans"
        self.base_directory.mkdir(parents=True, exist_ok=True)

    def persist_scan(self, payload: dict) -> dict:
        timestamp = datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ")
        evidence_file = self.base_directory / f"{timestamp}_{payload['scan_id']}.json"
        relative_path = evidence_file.relative_to(self.base_directory.parents[2])

        enriched_payload = {
            **payload,
            "stored_at": timestamp,
            "evidence_path": str(relative_path).replace("\\", "/"),
            "execution_mode": "scaffold-mock-adapters",
        }
        evidence_file.write_text(
            json.dumps(enriched_payload, indent=2, ensure_ascii=False),
            encoding="utf-8",
        )
        return enriched_payload
