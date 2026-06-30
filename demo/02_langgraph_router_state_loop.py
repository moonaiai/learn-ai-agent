"""LangGraph router with shared state, conditional edges, and a loop.

LangGraph does not make routing more mysterious than if/else. Its value is that
the if/else decision runs inside a state machine:

1. Each node receives and updates shared state.
2. Conditional edges decide the next node from the current state.
3. A graph can loop until a quality gate passes.
4. Streaming exposes node-by-node state updates for observability.
5. get_graph().draw_mermaid() gives a static view of the graph structure.

Run:
    python demo/02_langgraph_router_state_loop.py
"""

from __future__ import annotations

from pprint import pprint
from typing import Literal, TypedDict

from langgraph.graph import END, START, StateGraph


class AgentState(TypedDict):
    question: str
    route: str
    draft: str
    approved: bool
    retry_count: int
    events: list[str]


def append_event(state: AgentState, event: str) -> list[str]:
    return state["events"] + [event]


def classify(state: AgentState) -> dict:
    question = state["question"]
    normalized = question.lower()

    if any(keyword in normalized for keyword in ("python", "代码", "bug", "函数")):
        route = "code"
    elif any(keyword in normalized for keyword in ("agent", "上下文", "prompt", "提示词")):
        route = "agent"
    else:
        route = "general"

    return {
        "route": route,
        "events": append_event(state, f"classify -> {route}"),
    }


def choose_route(state: AgentState) -> Literal["code_node", "agent_node", "general_node"]:
    if state["route"] == "code":
        return "code_node"
    if state["route"] == "agent":
        return "agent_node"
    return "general_node"


def code_node(state: AgentState) -> dict:
    return {
        "draft": "代码问题回答草稿：先复现报错，再定位调用链，最后补测试。",
        "events": append_event(state, "code_node -> draft"),
    }


def agent_node(state: AgentState) -> dict:
    draft = "Agent 架构回答草稿：说明 context、tool、state、control flow 的关系。"
    return {
        "draft": draft,
        "events": append_event(state, "agent_node -> draft"),
    }


def general_node(state: AgentState) -> dict:
    return {
        "draft": "通用回答草稿：先澄清目标，再给出可执行建议。",
        "events": append_event(state, "general_node -> draft"),
    }


def quality_gate(state: AgentState) -> dict:
    """Pretend the first agent answer is too abstract and must be revised."""

    approved = not (state["route"] == "agent" and state["retry_count"] == 0)
    event = "quality_gate -> approved" if approved else "quality_gate -> revise"
    return {
        "approved": approved,
        "events": append_event(state, event),
    }


def after_quality_gate(state: AgentState) -> Literal["revise", "__end__"]:
    if state["approved"]:
        return END
    return "revise"


def revise(state: AgentState) -> dict:
    return {
        "draft": state["draft"] + "\n修订：补充一个具体例子，说明 router 只是条件跳转。",
        "retry_count": state["retry_count"] + 1,
        "events": append_event(state, "revise -> draft updated"),
    }


def build_graph():
    graph = StateGraph(AgentState)

    graph.add_node("classify", classify)
    graph.add_node("code_node", code_node)
    graph.add_node("agent_node", agent_node)
    graph.add_node("general_node", general_node)
    graph.add_node("quality_gate", quality_gate)
    graph.add_node("revise", revise)

    graph.add_edge(START, "classify")
    graph.add_conditional_edges("classify", choose_route)
    graph.add_edge("code_node", "quality_gate")
    graph.add_edge("agent_node", "quality_gate")
    graph.add_edge("general_node", "quality_gate")
    graph.add_conditional_edges("quality_gate", after_quality_gate)
    graph.add_edge("revise", "quality_gate")

    return graph.compile()


def main() -> None:
    app = build_graph()

    print("Static graph structure in Mermaid:")
    print(app.get_graph().draw_mermaid())

    initial_state: AgentState = {
        "question": "Agent 的上下文应该怎么组织？",
        "route": "",
        "draft": "",
        "approved": False,
        "retry_count": 0,
        "events": [],
    }

    print("\nNode-by-node updates:")
    for update in app.stream(initial_state):
        pprint(update)

    print("\nFinal state:")
    pprint(app.invoke(initial_state))


if __name__ == "__main__":
    main()
