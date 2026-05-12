from dataclasses import dataclass

try:
    from langchain_core.messages import HumanMessage, SystemMessage
except ModuleNotFoundError:
    @dataclass(slots=True)
    class SystemMessage:
        content: str

    @dataclass(slots=True)
    class HumanMessage:
        content: str


try:
    from langchain_ollama import ChatOllama as _ChatOllama
except ModuleNotFoundError:
    _ChatOllama = None


class FallbackLLMResponse:
    def __init__(self, content: str) -> None:
        self.content = content


class FallbackChatModel:
    """Deterministic fallback that keeps the legacy runtime executable for lab demos."""

    def __init__(self, model: str, temperature: float = 0.0) -> None:
        self.model = model
        self.temperature = temperature

    async def ainvoke(self, messages):
        prompt = "\n".join(getattr(message, "content", str(message)) for message in messages).lower()

        if "respond with only the names of the tools" in prompt:
            selected = []
            for tool_name in ("kubescape", "nmap_safe", "burp", "neurosploit"):
                if tool_name in prompt:
                    selected.append(tool_name)
            if not selected:
                selected = ["burp"]
            return FallbackLLMResponse(", ".join(selected))

        if "soc reporter" in prompt:
            return FallbackLLMResponse("Structured legacy summary generated with fallback LLM mode.")

        if "security evaluator" in prompt:
            return FallbackLLMResponse(
                "TASK ANSWER: Fallback evaluator summarized the verified findings.\n"
                "SUBTASK ANSWERS:\n"
                "- Login: Derived from recorded findings when present.\n"
                "- Products: Derived from recorded findings when present.\n"
                "- Evidence: Legacy bridge preserved the raw finding payloads."
            )

        return FallbackLLMResponse("Fallback planning response generated for legacy runtime compatibility.")


def build_chat_model(model: str, temperature: float):
    if _ChatOllama is None:
        return FallbackChatModel(model=model, temperature=temperature)
    return _ChatOllama(model=model, temperature=temperature)


try:
    from langgraph.graph import END, START, StateGraph
    LANGGRAPH_AVAILABLE = True
except ModuleNotFoundError:
    END = "__end__"
    START = "__start__"
    StateGraph = None
    LANGGRAPH_AVAILABLE = False
