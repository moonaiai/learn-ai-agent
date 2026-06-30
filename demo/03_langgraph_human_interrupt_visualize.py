"""LangGraph human-in-the-loop and visualization demo.

This example shows the part that plain if/else does not give you for free:

1. The graph reaches a human_review node and calls interrupt(...).
2. Execution pauses and returns the review payload to the caller.
3. A checkpointer keeps the thread state.
4. The caller resumes the same thread with Command(resume=...).
5. The graph continues from the interrupted node.

Run:
    python demo/03_langgraph_human_interrupt_visualize.py
"""

from __future__ import annotations

from pprint import pprint
from typing import Literal, TypedDict

from langgraph.checkpoint.memory import MemorySaver
from langgraph.graph import END, START, StateGraph
from langgraph.types import Command, interrupt


class ReviewState(TypedDict):
    question: str
    draft: str
    approved: bool
    reviewer_comment: str
    executed: bool
    events: list[str]


def append_event(state: ReviewState, event: str) -> list[str]:
    return state["events"] + [event]


def draft_answer(state: ReviewState) -> dict:
    return {
        "draft": (
            "准备执行一个高风险动作：把生成结果写入外部系统。\n"
            f"用户问题：{state['question']}"
        ),
        "events": append_event(state, "draft_answer -> draft"),
    }


def human_review(state: ReviewState) -> dict:
    decision = interrupt(
        {
            "message": "请审核这次动作。可以批准、拒绝，或给出修改意见。",
            "draft": state["draft"],
            "expected_resume_payload": {
                "approved": True,
                "comment": "批准执行",
            },
        }
    )

    return {
        "approved": bool(decision["approved"]),
        "reviewer_comment": str(decision.get("comment", "")),
        "events": append_event(state, "human_review -> resumed"),
    }


def after_review(state: ReviewState) -> Literal["execute_action", "revise_draft"]:
    if state["approved"]:
        return "execute_action"
    return "revise_draft"


def revise_draft(state: ReviewState) -> dict:
    return {
        "draft": state["draft"] + f"\n人工意见：{state['reviewer_comment']}",
        "events": append_event(state, "revise_draft -> draft updated"),
    }


def execute_action(state: ReviewState) -> dict:
    return {
        "executed": True,
        "events": append_event(state, "execute_action -> done"),
    }


def build_graph():
    graph = StateGraph(ReviewState)

    graph.add_node("draft_answer", draft_answer)
    graph.add_node("human_review", human_review)
    graph.add_node("revise_draft", revise_draft)
    graph.add_node("execute_action", execute_action)

    graph.add_edge(START, "draft_answer")
    graph.add_edge("draft_answer", "human_review")
    graph.add_conditional_edges("human_review", after_review)
    graph.add_edge("revise_draft", "human_review")
    graph.add_edge("execute_action", END)

    return graph.compile(checkpointer=MemorySaver())


def print_pending_interrupts(app, config: dict) -> None:
    """Print pending human review payloads from the checkpoint snapshot."""

    snapshot = app.get_state(config)
    print("Paused before nodes:", snapshot.next)

    for task in snapshot.tasks:
        for pending_interrupt in task.interrupts:
            pprint(
                {
                    "node": task.name,
                    "resumable": pending_interrupt.resumable,
                    "payload": pending_interrupt.value,
                }
            )


def main() -> None:
    app = build_graph()

    print("Static graph structure in Mermaid:")
    print(app.get_graph().draw_mermaid())

    config = {"configurable": {"thread_id": "human-review-demo"}}
    initial_state: ReviewState = {
        "question": "把这份 Agent 报告同步到外部系统",
        "draft": "",
        "approved": False,
        "reviewer_comment": "",
        "executed": False,
        "events": [],
    }

    print("\nFirst invoke pauses at interrupt:")
    paused = app.invoke(initial_state, config=config)
    pprint(paused)
    print_pending_interrupts(app, config)

    print("\nResume the same thread with a human decision:")
    resumed = app.invoke(
        Command(resume={"approved": True, "comment": "人工确认，可以执行"}),
        config=config,
    )
    pprint(resumed)


if __name__ == "__main__":
    main()
