"""A small LangChain RouterChain demo.

RouterChain is a classic LangChain abstraction for selecting the next chain.
This example keeps the router deterministic so it can run without an LLM API key:

1. KeywordRouterChain reads the user's input and returns a destination name.
2. MultiRouteChain dispatches the same input to the selected destination chain.
3. A default chain handles inputs that do not match any route.

Install:
    pip install -r demo/requirements.txt

Run:
    python demo/langchain_router_chain_demo.py
"""

from __future__ import annotations

from typing import Any

try:
    # Older LangChain versions expose the classic chain APIs from langchain.
    from langchain.chains.base import Chain
    from langchain.chains.router.base import MultiRouteChain, RouterChain
except ImportError:  # pragma: no cover - depends on installed LangChain version.
    # Newer LangChain versions moved legacy chain APIs into langchain-classic.
    from langchain_classic.chains.base import Chain
    from langchain_classic.chains.router.base import MultiRouteChain, RouterChain


class KeywordRouterChain(RouterChain):
    """Route an input to a destination chain by simple keyword rules."""

    @property
    def input_keys(self) -> list[str]:
        return ["input"]

    @property
    def output_keys(self) -> list[str]:
        return ["destination", "next_inputs"]

    def _call(self, inputs: dict[str, Any], run_manager: Any = None) -> dict[str, Any]:
        query = inputs["input"]
        normalized = query.lower()

        if any(keyword in normalized for keyword in ("python", "代码", "bug", "函数")):
            destination = "code"
        elif any(keyword in normalized for keyword in ("agent", "上下文", "prompt", "提示词")):
            destination = "agent"
        else:
            destination = None

        return {
            "destination": destination,
            "next_inputs": {"input": query},
        }


class DemoAnswerChain(Chain):
    """A tiny destination chain that formats a response for one route."""

    route_name: str
    answer_prefix: str

    @property
    def input_keys(self) -> list[str]:
        return ["input"]

    @property
    def output_keys(self) -> list[str]:
        return ["text"]

    def _call(self, inputs: dict[str, Any], run_manager: Any = None) -> dict[str, str]:
        return {
            "text": f"[{self.route_name}] {self.answer_prefix}\n用户输入：{inputs['input']}"
        }


def build_router_chain() -> MultiRouteChain:
    """Build a complete route -> dispatch chain."""

    return MultiRouteChain(
        router_chain=KeywordRouterChain(),
        destination_chains={
            "code": DemoAnswerChain(
                route_name="code",
                answer_prefix="这类问题会进入代码助手提示词，重点检查实现、报错和测试。",
            ),
            "agent": DemoAnswerChain(
                route_name="agent",
                answer_prefix="这类问题会进入 Agent 架构提示词，重点解释上下文、工具和控制流。",
            ),
        },
        default_chain=DemoAnswerChain(
            route_name="default",
            answer_prefix="没有匹配到专门路由，使用通用助手提示词回答。",
        ),
        silent_errors=True,
    )


def main() -> None:
    chain = build_router_chain()
    examples = [
        "Python 函数报错了，怎么定位？",
        "Agent 的上下文应该怎么组织？",
        "今天适合读什么书？",
    ]

    for question in examples:
        result = chain.invoke({"input": question})
        print("=" * 72)
        print(result["text"])


if __name__ == "__main__":
    main()
