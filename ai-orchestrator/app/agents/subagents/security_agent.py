import logging
from typing import TypedDict, Annotated
import operator
from langchain_core.messages import SystemMessage, HumanMessage
from langchain_ollama import ChatOllama
from langgraph.graph import StateGraph, START, END
from ...mcp_client import mcp_client

logger = logging.getLogger("argos.subagent.security")
llm = ChatOllama(model="hf.co/fdtn-ai/Foundation-Sec-8B-Reasoning", temperature=0.1)

class SecuritySubagentState(TypedDict):
    task: str
    target: str
    allowed_tools: list[str]
    messages: Annotated[list[str], operator.add]
    findings: Annotated[list[dict], operator.add]

async def tool_execution_node(state: SecuritySubagentState):
    """
    Subagent node that actively calls tools via MCP.
    """
    logger.info(f"SecuritySubagent executing on {state['target']}")
    
    # We use Foundation-Sec-8B to decide on tool execution based on available tools.
    prompt = f"""You are an advanced Security AI Subagent.
Your target is {state['target']}.
Available tools: {state['allowed_tools']}
Given the context, what tools should we execute to perform reconnaissance? Respond with ONLY the names of the tools, comma separated."""
    
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

    return {
        "messages": ["Tools executed successfully."],
        "findings": new_findings
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
    graph.add_node("evaluate", evaluator_node)
    
    graph.add_edge(START, "execute_tools")
    graph.add_edge("execute_tools", "evaluate")
    graph.add_edge("evaluate", END)
    
    return graph.compile()
