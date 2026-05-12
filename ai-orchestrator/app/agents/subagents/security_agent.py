import logging
from typing import TypedDict, Annotated
import operator
from langchain_core.messages import SystemMessage, HumanMessage
from langchain_ollama import ChatOllama
from langgraph.graph import StateGraph, START, END
from ...mcp_client import mcp_client

logger = logging.getLogger("hexstrike.subagent.security")
llm = ChatOllama(model="hf.co/fdtn-ai/Foundation-Sec-8B-Reasoning", temperature=0.1)

class SecuritySubagentState(TypedDict):
    task: str
    target: str
    allowed_tools: list[str]
    messages: Annotated[list[str], operator.add]
    findings: Annotated[list[dict], operator.add]
    raw_results: Annotated[list[dict], operator.add]

async def tool_execution_node(state: SecuritySubagentState):
    """
    Subagent node that actively calls tools via MCP.
    """
    logger.info(f"HexStrike SecuritySubagent executing on {state['target']}")
    
    prompt = f"""You are the HexStrike Autonomous Pentesting Agent.
Target: {state['target']}
Available toolkit: {state['allowed_tools']}
Decide which tools to use (nmap, kubescape, burp, neurosploit). Respond with ONLY the names of the tools, comma separated."""
    
    response = await llm.ainvoke([HumanMessage(content=prompt)])
    decision_text = response.content.lower()
    
    new_findings = []
    
    import re
    safe_target = re.sub(r'[^a-zA-Z0-9-]', '', state['target'])
    
    if "kubescape" in state["allowed_tools"] and "kubescape" in decision_text:
        result = await mcp_client.call_tool("kubescape", "scan_namespace", {"namespace": safe_target})
        new_findings.append({"tool": "kubescape", "result": result})
        
    if "nmap_safe" in state["allowed_tools"] and "nmap" in decision_text:
        result = await mcp_client.call_tool("hexstrike", "nmap_scan", {"target": safe_target})
        new_findings.append({"tool": "nmap", "result": result})

    if "burp" in state["allowed_tools"] and ("burp" in decision_text or "web" in decision_text):
        result = await mcp_client.call_tool("burp", "active_scan", {"target": state["target"]})
        new_findings.append({"tool": "burp_suite", "result": result})

    if "neurosploit" in state["allowed_tools"] and ("neuro" in decision_text or "exploit" in decision_text):
        result = await mcp_client.call_tool("neurosploit", "msf_execute", {"target": safe_target})
        new_findings.append({"tool": "neurosploit_v3", "result": result})

    return {
        "messages": ["Tools executed successfully."],
        "raw_results": new_findings
    }

async def anti_hallucination_node(state: SecuritySubagentState):
    """
    NeuroSploit V3 Pipeline: Verifies findings to prevent LLM hallucinations.
    """
    logger.info("NeuroSploit V3: Running Anti-Hallucination Cross-Check...")
    if not state["raw_results"]:
        return {"messages": ["No raw results to verify."]}
        
    verified = []
    import json
    for res in state["raw_results"]:
        # Logic: NeuroSploit performs a second validation of the finding.
        check = await mcp_client.call_tool("neurosploit", "verify_finding", {"finding": res})
        check_data = json.loads(check)
        if check_data.get("verified"):
            verified.append({**res, "confidence": check_data.get("confidence"), "verified": True})
            logger.info(f"Finding from {res['tool']} VERIFIED by NeuroSploit V3.")
        else:
            logger.warning(f"Finding from {res['tool']} REJECTED by NeuroSploit V3 (Possible Hallucination).")

    return {
        "findings": verified,
        "messages": [f"NeuroSploit V3 verified {len(verified)} findings."]
    }

async def evaluator_node(state: SecuritySubagentState):
    """
    Subagent node that evaluates if the task is complete.
    """
    logger.info("SecuritySubagent evaluating results...")
    
    if len(state["findings"]) > 0:
        eval_prompt = f"""You are a senior SOC analyst. Evaluate these findings and indicate if there are critical anomalies.
Findings: {state["findings"]}"""
        eval_response = await llm.ainvoke([SystemMessage(content="Be concise."), HumanMessage(content=eval_prompt)])
        return {"messages": [eval_response.content]}
        
    return {"messages": ["Evaluation complete. No anomalies."]}

def build_security_subagent():
    graph = StateGraph(SecuritySubagentState)
    graph.add_node("execute_tools", tool_execution_node)
    graph.add_node("verify", anti_hallucination_node)
    graph.add_node("evaluate", evaluator_node)
    
    graph.add_edge(START, "execute_tools")
    graph.add_edge("execute_tools", "verify")
    graph.add_edge("verify", "evaluate")
    graph.add_edge("evaluate", END)
    
    return graph.compile()
