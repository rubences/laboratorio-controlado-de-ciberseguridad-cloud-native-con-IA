# Runtime detection validation

- Started at (UTC): 2026-05-12T17:50:09Z
- Context: kind-argos-lab
- Target pod: dvwa-5688bcb659-4hswm
- Target node: argos-lab-worker
- Falco pod: falco-j7rd4
- Tetragon pod: tetragon-5xnrl

## Actions executed
- process_exec_probe: kubectl exec -n targets dvwa-5688bcb659-4hswm -- sh -c "id && whoami && cat /etc/os-release | sed -n 1,2p" (exit_code=0)
- falco_sensitive_file_probe: kubectl exec -n targets dvwa-5688bcb659-4hswm -- sh -c "cat /etc/shadow > /dev/null" (exit_code=0)

## Evidence files
- falco-alerts.jsonl -> 1 match(es)
- tetragon-process-events.jsonl -> 20 match(es)
- target-process-command.txt
- target-shadow-command.txt
- falcosidekick.log

## Limitations
- Falcosidekick muestra fallos de salida Syslog/Wazuh; la evidencia confiable queda en logs locales de Falco.