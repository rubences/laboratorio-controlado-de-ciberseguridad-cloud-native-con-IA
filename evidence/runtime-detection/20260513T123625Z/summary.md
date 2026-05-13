# Runtime detection validation

- Started at (UTC): 2026-05-13T12:36:25Z
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
- tetragon-process-events.jsonl -> 10 match(es)
- wazuh-alerts.jsonl -> 0 match(es)
- target-process-command.txt
- target-shadow-command.txt
- falcosidekick.log

## End-to-end status
- Demonstrated automatically: False
- Wazuh rule: 
- Wazuh description: 
- Falco event time (from Wazuh payload): 
- Wazuh ingest time: 
- Decoder/program:  / 

## Limitations
- Wazuh no generÃ³ alertas correlacionables con el pod objetivo dentro de la ventana observada.