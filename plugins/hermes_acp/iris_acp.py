from __future__ import annotations

import asyncio
import json
import logging
import os
import sys
from pathlib import Path
from urllib.parse import urlparse

os.environ["HERMES_DISABLE_LAZY_INSTALLS"] = "1"

import acp
from acp_adapter.entry import _setup_logging
from acp_adapter.server import HermesACPAgent
from acp_adapter.session import SessionManager, _register_task_cwd
from iris_browser_tools import (
    IRIS_BROWSER_TOOLS,
    IRIS_BROWSER_TOOLSET,
    register_iris_browser_tools,
)
from iris_action_tools import (
    IRIS_ACTION_TOOLS,
    IRIS_ACTION_TOOLSETS,
    register_iris_action_guards,
)
from iris_memory_tools import IRIS_MEMORY_TOOLS, register_iris_memory_tools


IRIS_TOOLSET = "iris-acp-bridge"
IRIS_MAX_ITERATIONS = 8
IRIS_MAX_TOKENS = 512
DISABLED_TOOLSETS = [
    "web",
    "vision",
    "image_gen",
    "skills",
    "memory",
    "session_search",
    "execute_code",
    "delegate_task",
]
IRIS_SLASH_COMMANDS = {
    "help": "Show available commands",
    "tools": "List available tools",
    "context": "Show conversation context info",
    "reset": "Clear conversation history",
    "version": "Show Hermes version",
}


def required_env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise RuntimeError(f"missing required environment variable {name}")
    return value


def local_ollama_base_url() -> str:
    value = required_env("IRIS_HERMES_OLLAMA_BASE_URL").rstrip("/")
    parsed = urlparse(value)
    if parsed.scheme != "http" or parsed.hostname not in {"127.0.0.1", "localhost", "::1"}:
        raise RuntimeError("Hermes ACP Ollama endpoint must be plain HTTP loopback")
    return value


class IrisSessionManager(SessionManager):
    def _get_db(self):
        return None

    def _make_agent(
        self,
        *,
        session_id: str,
        cwd: str,
        model: str | None = None,
        requested_provider: str | None = None,
        base_url: str | None = None,
        api_mode: str | None = None,
    ):
        from run_agent import AIAgent
        from toolsets import TOOLSETS

        os.environ["TERMINAL_CWD"] = cwd
        os.environ["IRIS_AGENTIC_WORKSPACE"] = cwd
        _register_task_cwd(session_id, cwd)
        memory_tools = list(register_iris_memory_tools())
        action_tools = list(register_iris_action_guards())
        browser_tools = list(register_iris_browser_tools())
        TOOLSETS[IRIS_TOOLSET] = {
            "description": "Iris-owned read-only RAG and staged-memory tools",
            "tools": memory_tools,
            "includes": [],
        }
        TOOLSETS[IRIS_BROWSER_TOOLSET] = {
            "description": "Iris-owned isolated browser tools",
            "tools": browser_tools,
            "includes": [],
        }
        configured_model = required_env("IRIS_HERMES_MODEL")
        configured_base_url = local_ollama_base_url()
        agent = AIAgent(
            platform="acp",
            provider="custom",
            api_mode="chat_completions",
            base_url=configured_base_url,
            api_key="ollama-local",
            model=configured_model,
            enabled_toolsets=[
                IRIS_TOOLSET,
                IRIS_BROWSER_TOOLSET,
                *IRIS_ACTION_TOOLSETS,
            ],
            disabled_toolsets=DISABLED_TOOLSETS,
            quiet_mode=True,
            session_id=session_id,
            session_db=None,
            skip_memory=True,
            skip_context_files=True,
            load_soul_identity=False,
            checkpoints_enabled=False,
            max_iterations=IRIS_MAX_ITERATIONS,
            max_tokens=IRIS_MAX_TOKENS,
            reasoning_config={"enabled": False},
            request_overrides={"extra_body": {"think": False}},
        )
        agent._print_fn = lambda *args, **kwargs: print(
            *args, **{**kwargs, "file": sys.stderr}
        )
        return agent


class IrisACPAgent(HermesACPAgent):
    _SLASH_COMMANDS = IRIS_SLASH_COMMANDS
    _ADVERTISED_COMMANDS = tuple(
        command
        for command in HermesACPAgent._ADVERTISED_COMMANDS
        if command["name"] in IRIS_SLASH_COMMANDS
    )

    async def _register_session_mcp_servers(self, state, mcp_servers) -> None:
        if mcp_servers:
            raise RuntimeError("Iris ACP bridge does not allow MCP servers")


def audit_tools() -> int:
    from tools.registry import registry
    from toolsets import TOOLSETS

    tools = list(register_iris_memory_tools())
    action_tools = list(register_iris_action_guards())
    browser_tools = list(register_iris_browser_tools())
    TOOLSETS[IRIS_TOOLSET] = {
        "description": "Iris-owned read-only RAG and staged-memory tools",
        "tools": tools,
        "includes": [],
    }
    TOOLSETS[IRIS_BROWSER_TOOLSET] = {
        "description": "Iris-owned isolated browser tools",
        "tools": browser_tools,
        "includes": [],
    }
    print(
        json.dumps(
            {
                "toolset": IRIS_TOOLSET,
                "tools": tools,
                "registeredTools": registry.get_tool_names_for_toolset(IRIS_TOOLSET),
                "actionTools": action_tools,
                "actingTools": action_tools,
                "browserTools": browser_tools,
                "allActingTools": [*action_tools, *browser_tools],
                "maxIterations": IRIS_MAX_ITERATIONS,
                "maxTokens": IRIS_MAX_TOKENS,
                "nativeDurableMemory": False,
                "mcpAllowed": False,
            },
            separators=(",", ":"),
        )
    )
    return 0


def main() -> int:
    if "--audit-tools" in sys.argv[1:]:
        return audit_tools()
    _setup_logging()
    logging.getLogger(__name__).info("Starting Iris-owned Hermes ACP bridge")
    home = Path(required_env("HERMES_HOME"))
    home.mkdir(parents=True, exist_ok=True)
    agent = IrisACPAgent(session_manager=IrisSessionManager())
    try:
        asyncio.run(acp.run_agent(agent, use_unstable_protocol=True))
    except KeyboardInterrupt:
        return 0
    except Exception:
        logging.getLogger(__name__).exception("Iris Hermes ACP bridge crashed")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
