from __future__ import annotations

import asyncio
import json
import logging
import os
import sys
from pathlib import Path
from typing import Any
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
TOOL_GROUPS = {
    "browser": {
        "browser_open",
        "browser_get_url",
        "browser_snapshot",
        "browser_screenshot",
        "browser_close",
    },
    "browser_interactive": {
        "browser_open",
        "browser_get_url",
        "browser_snapshot",
        "browser_screenshot",
        "browser_click",
        "browser_fill",
        "browser_press",
        "browser_upload",
        "browser_download",
        "browser_close",
    },
    "memory_query": {"iris_query_memory"},
    "memory_propose": {"iris_propose_memory"},
    "file_read": {"read_file", "search_files"},
    "file_write": {"read_file", "write_file", "patch", "search_files"},
    "shell": {"terminal", "process"},
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
            request_overrides={
                "temperature": 0,
                "extra_body": {
                    "think": False,
                    "options": {
                        "temperature": 0,
                        "num_predict": IRIS_MAX_TOKENS,
                    },
                },
            },
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

    async def prompt(self, prompt, session_id: str, **kwargs: Any):
        state = self.session_manager.get_session(session_id)
        if state is None:
            return await super().prompt(prompt, session_id, **kwargs)
        agent = state.agent
        original_tools = list(getattr(agent, "tools", []) or [])
        original_overrides = dict(getattr(agent, "request_overrides", {}) or {})
        allowed = tool_names_for_prompt(prompt)
        agent.tools = [
            tool
            for tool in original_tools
            if tool.get("function", {}).get("name") in allowed
        ]
        exact_tool_choice = exact_tool_choice_for_prompt(prompt, allowed)
        if allowed:
            agent.request_overrides = {
                **original_overrides,
                "tool_choice": exact_tool_choice or "auto",
            }
        else:
            agent.request_overrides = {
                key: value
                for key, value in original_overrides.items()
                if key != "tool_choice"
            }
        try:
            return await super().prompt(prompt, session_id, **kwargs)
        finally:
            agent.tools = original_tools
            agent.request_overrides = original_overrides


def tool_names_for_prompt(prompt) -> set[str]:
    text = prompt_text(prompt).lower()
    allowed: set[str] = set()
    explicit_tool_names = {
        "browser_click",
        "browser_close",
        "browser_download",
        "browser_fill",
        "browser_get_url",
        "browser_open",
        "browser_press",
        "browser_screenshot",
        "browser_snapshot",
        "browser_upload",
        "iris_propose_memory",
        "iris_query_memory",
        "patch",
        "process",
        "read_file",
        "search_files",
        "terminal",
        "write_file",
    }
    for name in explicit_tool_names:
        if name in text:
            allowed.add(name)
    if any(marker in allowed for marker in TOOL_GROUPS["browser_interactive"]):
        allowed.update(TOOL_GROUPS["browser"])
    if any(
        word in text
        for word in (
            "http://",
            "https://",
            "web",
            "online",
            "research",
            "browser",
            "search",
            "google",
            "brave",
            "look up",
            "lookup",
            "current",
            "latest",
            "today",
            "who won",
            "iris_research_authorized_by_user",
        )
    ):
        allowed.update(TOOL_GROUPS["browser"])
    if any(name in text for name in ("browser_click", "browser_fill", "browser_press", "browser_upload", "browser_download")):
        allowed.update(TOOL_GROUPS["browser_interactive"])
    if any(
        phrase in text
        for phrase in (
            "iris_query_memory",
            "query memory",
            "from memory",
            "memory summary",
            "what do you remember",
            "what do you know about me",
            "how old am i",
            "what's my age",
            "what is my age",
            "my age",
        )
    ):
        allowed.update(TOOL_GROUPS["memory_query"])
    if "iris_propose_memory" in text or "propose memory" in text or "stage memory" in text:
        allowed.update(TOOL_GROUPS["memory_propose"])
    if "read_file" in text or "search_files" in text:
        allowed.update(TOOL_GROUPS["file_read"])
    if "write_file" in text or "patch" in text:
        allowed.update(TOOL_GROUPS["file_write"])
    if "terminal" in text or "powershell" in text or "process" in text:
        allowed.update(TOOL_GROUPS["shell"])
    return allowed


def exact_tool_choice_for_prompt(prompt, allowed: set[str]):
    text = prompt_text(prompt).lower()
    exact_names = sorted(
        name
        for name in (
            "browser_click",
            "browser_close",
            "browser_download",
            "browser_fill",
            "browser_get_url",
            "browser_open",
            "browser_press",
            "browser_screenshot",
            "browser_snapshot",
            "browser_upload",
            "iris_propose_memory",
            "iris_query_memory",
            "patch",
            "process",
            "read_file",
            "search_files",
            "terminal",
            "write_file",
        )
        if name in allowed and (f"call {name}" in text or f"use {name}" in text)
    )
    if len(exact_names) != 1:
        return None
    return {"type": "function", "function": {"name": exact_names[0]}}


def prompt_text(prompt) -> str:
    parts: list[str] = []
    for block in prompt or []:
        text = getattr(block, "text", None)
        if isinstance(text, str):
            parts.append(text)
        elif isinstance(block, dict) and isinstance(block.get("text"), str):
            parts.append(block["text"])
    return "\n".join(parts)


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
                "requestOverrides": {
                    "temperature": 0,
                    "toolChoice": "prompt_scoped",
                    "extraBody": {
                        "think": False,
                        "options": {
                            "temperature": 0,
                            "numPredict": IRIS_MAX_TOKENS,
                        },
                    },
                },
                "promptScopedTools": True,
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
