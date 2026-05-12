#!/usr/bin/env python3
import sys
import json
import urllib.request
import urllib.error

def main():
    if len(sys.argv) < 2:
        print(json.dumps({"error": "Prompt argument missing"}))
        sys.exit(1)
        
    prompt = sys.argv[1]
    
    api_url = "http://localhost:8000/api/v1/analyze"
    # Ensure to import os at the top
    import os
    api_key = os.environ.get("ARGOS_API_KEY", "")
    
    payload = {
        "task_description": prompt,
        "target_namespace": "vulnerable-apps",
        "allowed_tools": ["kubescape", "nmap_safe"]
    }
    
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(api_url, data=data, headers={
        "Content-Type": "application/json",
        "X-ARGOS-API-KEY": api_key
    }, method="POST")
    
    try:
        with urllib.request.urlopen(req) as response:
            resp_data = json.loads(response.read().decode("utf-8"))
            # promptfoo expects output in the "output" key
            result = {"output": json.dumps(resp_data.get("results", resp_data))}
    except urllib.error.URLError as e:
        if hasattr(e, 'read'):
            err_body = e.read().decode("utf-8")
            result = {"error": f"{e.reason}: {err_body}"}
        else:
            result = {"error": str(e)}
            
    print(json.dumps(result))

if __name__ == "__main__":
    main()
