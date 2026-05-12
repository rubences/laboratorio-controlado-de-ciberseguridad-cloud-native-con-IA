import logging
import asyncio
import os
import re
from typing import TypedDict, Literal
from .subagents.security_agent import build_security_subagent
from ..runtime_compat import HumanMessage, LANGGRAPH_AVAILABLE, START, END, StateGraph, SystemMessage, build_chat_model

logger = logging.getLogger("hexstrike.supervisor")
llm = build_chat_model(model="hf.co/fdtn-ai/Foundation-Sec-8B-Reasoning", temperature=0.2)

DEFAULT_ALLOWED_NAMESPACES = {"sandbox", "targets", "vulnerable-apps"}
SUPPORTED_TOOLS = {"burp", "kubescape", "neurosploit", "nmap_safe"}
BLOCKED_TASK_PATTERNS: tuple[tuple[re.Pattern[str], str, str], ...] = (
    (re.compile(r"\bmcp\s+configuration\b|\bmcp[-_ ]config\b|\bapi\s*keys?\b|\bsecrets?\b", re.IGNORECASE), "policy violation", "internal configuration access attempted"),
    (re.compile(r"\brm\s+-rf\b|\bdelete\b|\bdrop\s+database\b|\bformat\b", re.IGNORECASE), "unauthorized", "destructive command attempted"),
    (re.compile(r"\b8\.8\.8\.8\b|\b1\.1\.1\.1\b|\bexternal\b|\bpublic internet\b", re.IGNORECASE), "out of scope", "out-of-scope target detected"),
)

class SupervisorState(TypedDict):
    task: str
    namespace: str
    allowed_tools: list[str]
    current_phase: str
    subagent_findings: list[dict]
    status: str
    require_approval: bool
    policy_checks: list[dict]


def _get_allowed_namespaces() -> set[str]:
    raw_namespaces = os.environ.get("ARGOS_ALLOWED_NAMESPACES", "")
    if not raw_namespaces.strip():
        return DEFAULT_ALLOWED_NAMESPACES

    parsed_namespaces = {value.strip() for value in raw_namespaces.split(",") if value.strip()}
    return parsed_namespaces or DEFAULT_ALLOWED_NAMESPACES


def _build_policy_error(reason: str, detail: str) -> dict:
    logger.warning("Policy Gate triggered: %s.", detail)
    return {
        "status": f"error: {reason}",
        "current_phase": "blocked",
        "policy_checks": [{"decision": "blocked", "reason": reason, "detail": detail}],
    }

async def policy_gate_node(state: SupervisorState):
    logger.info("Evaluating task against Security Policies (Policy Gate)...")
    task = state["task"]
    namespace = state["namespace"].strip()
    requested_tools = state.get("allowed_tools", [])
    allowed_namespaces = _get_allowed_namespaces()

    if not namespace or namespace not in allowed_namespaces:
        return _build_policy_error("out of scope", f"namespace '{namespace or '<empty>'}' is not allowed")

    unknown_tools = sorted({tool for tool in requested_tools if tool not in SUPPORTED_TOOLS})
    if unknown_tools:
        return _build_policy_error("policy violation", f"unsupported tools requested: {', '.join(unknown_tools)}")

    if not requested_tools:
        return _build_policy_error("policy violation", "no tools were requested for the task")

    for pattern, reason, detail in BLOCKED_TASK_PATTERNS:
        if pattern.search(task):
            return _build_policy_error(reason, detail)

    return {
        "status": "running",
        "policy_checks": [{
            "decision": "allowed",
            "namespace": namespace,
            "tools": requested_tools,
        }],
    }

async def planner_node(state: SupervisorState):
    logger.info("Supervisor Planner delegating task...")
    
    prompt = f"""You are the HexStrike Master Security Planner. Task: {state['task']}
Target Namespace: {state['namespace']}
Design a comprehensive offensive and defensive evaluation plan."""
    
    response = await llm.ainvoke([SystemMessage(content="Be brief."), HumanMessage(content=prompt)])
    logger.info(f"Planner Output: {response.content}")
    
    return {"current_phase": "reconnaissance"}

async def delegate_to_security_agent(state: SupervisorState):
    logger.info("Delegating to Security Subagent...")
    subagent = build_security_subagent()
    
    # Llamada asíncrona al subgrafo
    sub_state = await subagent.ainvoke({
        "task": state["task"],
        "target": state["namespace"],
        "allowed_tools": state["allowed_tools"],
        "messages": [],
        "findings": []
    })
    
    return {
        "subagent_findings": sub_state.get("findings", []),
        "current_phase": "reporting"
    }

async def soc_reporting_node(state: SupervisorState):
    logger.info("SOC Reporting Agent generating final evidence...")
    
    if not state.get("subagent_findings"):
        logger.warning("No findings reported by subagents.")
        return {"status": "completed"}
        
    prompt = f"""You are a SOC Reporter. Summarize these findings for a final report.
Findings: {state['subagent_findings']}"""
    
    response = await llm.ainvoke([SystemMessage(content="Provide a structured summary."), HumanMessage(content=prompt)])
    logger.info(f"SOC Report generated:\n{response.content}")
    
    return {"status": "completed"}

async def human_approval_node(state: SupervisorState):
    if not state.get("require_approval"):
        return {"status": "auto_approved"}
        
    logger.warning("SMARTOPS: [HUMAN IN THE LOOP] Analysis paused. Waiting for operator review...")
    # Simulated wait for human verification
    await asyncio.sleep(2)
    logger.info("SMARTOPS: [HUMAN IN THE LOOP] Operator approved the security plan.")
    return {"status": "human_approved"}

def route_after_policy(state: SupervisorState) -> Literal["planner", "__end__"]:
    if state.get("status", "").startswith("error"):
        return "__end__"
    return "planner"

def build_supervisor_graph():
    if not LANGGRAPH_AVAILABLE:
        raise RuntimeError("LangGraph is not available in this environment")

    workflow = StateGraph(SupervisorState)
    
    workflow.add_node("policy_gate", policy_gate_node)
    workflow.add_node("planner", planner_node)
    workflow.add_node("security_agent", delegate_to_security_agent)
    workflow.add_node("human_approval", human_approval_node)
    workflow.add_node("soc_reporter", soc_reporting_node)
    
    workflow.add_edge(START, "policy_gate")
    workflow.add_conditional_edges("policy_gate", route_after_policy)
    workflow.add_edge("planner", "security_agent")
    workflow.add_edge("security_agent", "human_approval")
    workflow.add_edge("human_approval", "soc_reporter")
    workflow.add_edge("soc_reporter", END)
    
    return workflow.compile()

async def run_supervisor_workflow(task: str, namespace: str, tools: list[str], require_approval: bool = False) -> dict:
    initial_state = SupervisorState(
        task=task,
        namespace=namespace,
        allowed_tools=tools,
        current_phase="init",
        subagent_findings=[],
        status="running",
        require_approval=require_approval,
        policy_checks=[]
    )

    if LANGGRAPH_AVAILABLE:
        graph = build_supervisor_graph()
        final_state = await graph.ainvoke(initial_state)
    else:
        final_state = await _run_supervisor_fallback(initial_state)
    
    if final_state.get("status", "").startswith("error"):
        return {
            "status": "error",
            "message": final_state.get("status").split(": ", 1)[1] if ": " in final_state.get("status", "") else final_state.get("status"),
            "policy_checks": final_state.get("policy_checks", []),
        }
         
    return {
        "status": final_state.get("status"),
        "total_findings": len(final_state.get("subagent_findings", [])),
        "details": final_state.get("subagent_findings", []),
        "policy_checks": final_state.get("policy_checks", []),
    }


async def _run_supervisor_fallback(initial_state: SupervisorState) -> SupervisorState:
    state = dict(initial_state)
    for node in (policy_gate_node,):
        state = _merge_state(state, await node(state))
    if route_after_policy(state) == "__end__":
        return state

    for node in (planner_node, delegate_to_security_agent, human_approval_node, soc_reporting_node):
        state = _merge_state(state, await node(state))
    return state


def _merge_state(state: dict, updates: dict) -> SupervisorState:
    merged = dict(state)
    for key, value in updates.items():
        if key == "subagent_findings" and isinstance(value, list):
            merged[key] = value
        else:
            merged[key] = value
    return merged
