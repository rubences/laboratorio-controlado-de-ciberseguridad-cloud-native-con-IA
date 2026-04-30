import logging
from typing import TypedDict, Annotated
import operator
# from langchain_core.messages import BaseMessage, HumanMessage, AIMessage
from langgraph.graph import StateGraph, START, END
from ..mcp_client import mcp_client

logger = logging.getLogger("argos.subagent.security")

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
    
    # In a real setup, an LLM decides WHICH tool to call based on `allowed_tools`.
    # Here we mock the LLM decision and execute tools.
    new_findings = []
    
    if "kubescape" in state["allowed_tools"]:
        result = await mcp_client.call_tool("kubescape", "scan_namespace", {"namespace": state["target"]})
        new_findings.append({"tool": "kubescape", "result": result})
        
    if "nmap_safe" in state["allowed_tools"]:
        result = await mcp_client.call_tool("hexstrike", "nmap_scan", {"target": state["target"]})
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
        return {"messages": ["Evaluation complete. Anomalies detected."]}
    return {"messages": ["Evaluation complete. No anomalies."]}

def build_security_subagent():
    graph = StateGraph(SecuritySubagentState)
    graph.add_node("execute_tools", tool_execution_node)
    graph.add_node("evaluate", evaluator_node)
    
    graph.add_edge(START, "execute_tools")
    graph.add_edge("execute_tools", "evaluate")
    graph.add_edge("evaluate", END)
    
    return graph.compile()
