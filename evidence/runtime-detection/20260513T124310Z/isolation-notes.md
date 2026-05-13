# Isolation notes

- Runtime validation run (`summary.json`) started at `2026-05-13T12:43:10Z` and executed a real `kubectl exec` on pod `dvwa-5688bcb659-4hswm` plus a controlled `/etc/shadow` read.
- `falco-alerts.jsonl` contains a fresh Falco event for that pod and command, so the Falco detection step DID trigger.
- `tetragon-process-events.jsonl` contains 10 matching process events for the same pod, so the runtime action was real and observable.
- `falcosidekick.log` shows WebUI POST activity at `2026/05/13 12:36:40` and previous nearby runs, but it does NOT expose a positive Syslog send confirmation.
- `wazuh-alerts.jsonl` is empty for the latest automatic runtime run, so the final automatic Falco -> Falcosidekick -> Wazuh alert was NOT demonstrated.
- `wazuh-alerts-tail.jsonl` proves Wazuh still parses Falcosidekick-formatted syslog correctly because it contains:
  - a previous real runtime alert for `dvwa-5688bcb659-4hswm` with rule `110003`
  - a controlled manual bridge probe from inside `deploy/falco-falcosidekick` with marker `bridge-probe-20260513T1242Z`, ingested by Wazuh as rule `110001` at `2026-05-13T12:42:00.773+0000`
- Therefore, the remaining blocker is narrowly bounded: the current real Falco runtime event is being generated, but that specific automatic event was not observed arriving in Wazuh during the validation window even though the bridge path from the Falcosidekick pod to Wazuh still works.
