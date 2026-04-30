from typing import TypedDict, Annotated, Sequence
from langgraph.graph import StateGraph, START, END
# from langchain_core.messages import BaseMessage
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Definimos el estado del grafo
class SecurityState(TypedDict):
    task: str
    namespace: str
    allowed_tools: list[str]
    current_step: str
    findings: list[dict]
    # messages: Annotated[Sequence[BaseMessage], operator.add]

# Nodo 1: Planner
def planner_node(state: SecurityState):
    logger.info(f"Planner Agent evaluando tarea: {state['task']}")
    # Aquí el LLM decide los pasos a seguir dentro de las herramientas permitidas
    return {"current_step": "reconnaissance"}

# Nodo 2: Security Agent (Ejecución MCP)
def security_agent_node(state: SecurityState):
    logger.info(f"Security Agent ejecutando fase: {state['current_step']}")
    # Aquí el agente invoca servidores MCP (HexStrike, Kubescape)
    # Simulación de un finding
    mock_finding = {"tool": "kubescape", "severity": "HIGH", "description": "Privileged container detected"}
    return {"findings": [mock_finding], "current_step": "evaluation"}

# Nodo 3: Evidence & SOC Agent
def evidence_node(state: SecurityState):
    logger.info("Evidence Agent consolidando hallazgos...")
    # Correlacionar con Wazuh/Falco
    return {"current_step": "completed"}

# Construir el grafo
def build_graph():
    workflow = StateGraph(SecurityState)
    
    workflow.add_node("planner", planner_node)
    workflow.add_node("security_agent", security_agent_node)
    workflow.add_node("evidence_agent", evidence_node)
    
    workflow.add_edge(START, "planner")
    workflow.add_edge("planner", "security_agent")
    workflow.add_edge("security_agent", "evidence_agent")
    workflow.add_edge("evidence_agent", END)
    
    return workflow.compile()

async def run_security_workflow(task: str, namespace: str, tools: list[str]) -> dict:
    graph = build_graph()
    initial_state = SecurityState(
        task=task,
        namespace=namespace,
        allowed_tools=tools,
        current_step="init",
        findings=[]
    )
    
    final_state = graph.invoke(initial_state)
    return {
        "final_step": final_state.get("current_step"),
        "total_findings": len(final_state.get("findings", [])),
        "details": final_state.get("findings", [])
    }
