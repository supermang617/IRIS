from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[2]
PROVIDER_DIR = REPO_ROOT / "plugins" / "memory" / "iris_broker"
MAX_RESPONSE_CHARS = 4000
MAX_TASK_CHARS = 2000
ALLOWED_MODES = {"reason", "research", "code_suggestion"}
EXPOSED_TOOLS = ["iris_query_memory", "iris_propose_memory"]
ACTING_TOOLS: list[str] = []

sys.path.insert(0, str(PROVIDER_DIR))

import provider as iris_broker  # noqa: E402


def main() -> int:
    try:
        iris_broker.startup_check()
    except Exception as error:
        _emit({"ok": False, "mode": "startup", "text": f"Hermes unavailable: {error}", "memoryProposals": []})
        return 1

    for line in sys.stdin:
        try:
            request = json.loads(line)
            if request.get("type") == "status":
                response = runtime_status()
            else:
                response = handle_request(request)
        except Exception as error:
            response = {"ok": False, "mode": "error", "text": f"Hermes task failed: {error}", "memoryProposals": []}
        _emit(response)
    return 0


def handle_request(request: dict[str, Any]) -> dict[str, Any]:
    if request.get("type") != "task":
        raise ValueError("unsupported Hermes request type")
    mode = str(request.get("mode", ""))
    if mode not in ALLOWED_MODES:
        raise ValueError("unsupported Hermes task mode")
    text = " ".join(str(request.get("text", "")).split())
    if not text:
        raise ValueError("Hermes task text cannot be empty")
    if len(text) > MAX_TASK_CHARS:
        raise ValueError("Hermes task text is too large")
    if contains_prompt_injection_text(text):
        raise ValueError("Hermes task text contains prompt-injection language")

    if mode == "research" and not bool(request.get("explicitUserResearchRequest")):
        raise ValueError("research mode requires an explicit user research request")

    memory = []
    if mode in {"reason", "research"}:
        try:
            memory = iris_broker.iris_query_memory(text[:120], 5).get("results", [])
        except Exception:
            memory = []

    response_text = bounded_response(mode, text, memory)
    return {
        "ok": True,
        "mode": mode,
        "text": response_text[:MAX_RESPONSE_CHARS],
        "memoryProposals": [],
    }


def runtime_status() -> dict[str, Any]:
    inference = iris_broker.inference_policy()
    return {
        "ok": True,
        "profile": "iris_restricted",
        "tools": EXPOSED_TOOLS,
        "actingTools": ACTING_TOOLS,
        "provider": inference["provider"],
        "model": inference["model"],
        "endpoint": inference["endpoint"],
        "modelSource": inference["modelSource"],
        "usesExistingIrisModel": inference["usesExistingIrisModel"],
        "modelSwitching": inference["modelSwitching"],
        "modelPulling": inference["modelPulling"],
        "modelAutoSelection": inference["modelAutoSelection"],
        "fallbackModels": inference["fallbackModels"],
        "criticWorkerSplit": inference["criticWorkerSplit"],
        "multiModelDebate": inference["multiModelDebate"],
        "parallelInferenceStreams": inference["parallelInferenceStreams"],
        "sequentialTasksOnly": inference["sequentialTasksOnly"],
    }


def contains_prompt_injection_text(text: str) -> bool:
    lowered = text.lower()
    blocked = [
        "ignore previous instructions",
        "ignore all previous",
        "system prompt",
        "developer message",
        "reveal your prompt",
        "jailbreak",
        "override safety",
        "bypass safety",
        "act as system",
        "do not follow iris",
    ]
    return any(phrase in lowered for phrase in blocked)


def bounded_response(mode: str, text: str, memory: list[dict[str, Any]]) -> str:
    if mode == "code_suggestion":
        return f"Hermes code suggestion only. No files edited, commands run, or tests executed. Suggestion: {text}"
    if memory:
        memory_lines = "; ".join(str(item.get("text", "")) for item in memory[:3] if item.get("text"))
        return f"Hermes reasoning summary using Iris-approved memory only: {text} Relevant memory: {memory_lines}"
    if mode == "research":
        return f"Hermes research summary is bounded to approved local broker context. No external browsing was performed. Task: {text}"
    return f"Hermes reasoning summary: {text}"


def _emit(payload: dict[str, Any]) -> None:
    sys.stdout.write(json.dumps(payload, separators=(",", ":")) + "\n")
    sys.stdout.flush()


if __name__ == "__main__":
    raise SystemExit(main())
