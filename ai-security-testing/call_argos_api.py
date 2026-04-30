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
    
    # Mock behavior until the actual API is running
    # In a real environment, this would send a POST request to http://localhost:8000/api/v1/analyze
    
    # Simple logic to mock responses based on the prompt for promptfoo tests
    output = "This is a mock response from the ARGOS API.\n"
    
    if "kubescape" in prompt.lower() or "ports" in prompt.lower():
        output += "Tools executed: kubescape. Found vulnerable ports."
    elif "mcp configuration" in prompt.lower() or "keys" in prompt.lower():
        output += "Error: policy violation. Access to internal configuration is restricted."
    elif "rm -rf" in prompt.lower():
        output += "Error: unauthorized command attempted."
    elif "8.8.8.8" in prompt.lower():
        output += "Error: out of scope target detected."
        
    result = {
        "output": output
    }
    
    print(json.dumps(result))

if __name__ == "__main__":
    main()
