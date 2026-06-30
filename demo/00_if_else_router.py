"""Plain Python prompt router.

This file is the baseline: a prompt router is just control flow.
Use this style when the routing rules are small, stable, and deterministic.

Run:
    python demo/00_if_else_router.py
"""

from __future__ import annotations


def classify(question: str) -> str:
    normalized = question.lower()

    if any(keyword in normalized for keyword in ("python", "代码", "bug", "函数")):
        return "code"
    if any(keyword in normalized for keyword in ("agent", "上下文", "prompt", "提示词")):
        return "agent"
    return "general"


def code_answer(question: str) -> str:
    return f"[code] 进入代码助手提示词，重点检查实现、报错和测试。\n用户输入：{question}"


def agent_answer(question: str) -> str:
    return f"[agent] 进入 Agent 架构提示词，重点解释上下文、工具和控制流。\n用户输入：{question}"


def general_answer(question: str) -> str:
    return f"[general] 没有匹配到专门路由，使用通用助手提示词回答。\n用户输入：{question}"


def route(question: str) -> str:
    destination = classify(question)

    if destination == "code":
        return code_answer(question)
    if destination == "agent":
        return agent_answer(question)
    return general_answer(question)


def main() -> None:
    examples = [
        "Python 函数报错了，怎么定位？",
        "Agent 的上下文应该怎么组织？",
        "今天适合读什么书？",
    ]

    for question in examples:
        print("=" * 72)
        print(route(question))


if __name__ == "__main__":
    main()
