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
EXPOSED_TOOLS = ["iris_query_memory", "iris_propose_memory", "iris_web_research"]
ACTING_TOOLS: list[str] = []
MEMORY_SUMMARY_TRIGGERS = (
    "what you know from memory",
    "what do you know from memory",
    "summarize memory",
    "summarize what you know",
    "memory summary",
)

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
    memory_error = ""
    web_results = []
    web_error = ""
    if mode in {"reason", "research"}:
        try:
            query = "*" if should_summarize_memory(text) else text[:120]
            memory = iris_broker.iris_query_memory(query, 8).get("results", [])
        except Exception as error:
            memory_error = str(error)
            memory = []
    if mode == "research":
        try:
            web_results = iris_broker.iris_web_research(web_query_from_task(text), 5).get("results", [])
        except Exception as error:
            web_error = str(error)

    proposals = propose_memory_if_requested(text)
    response_text = model_response(mode, text, memory, memory_error, web_results, web_error)
    return {
        "ok": True,
        "mode": mode,
        "text": response_text[:MAX_RESPONSE_CHARS],
        "memoryProposals": proposals,
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


def should_summarize_memory(text: str) -> bool:
    lowered = text.lower()
    return any(trigger in lowered for trigger in MEMORY_SUMMARY_TRIGGERS)


def web_query_from_task(text: str) -> str:
    clean = " ".join(text.split()).strip(" .")
    lowered = clean.lower()
    prefixes = (
        "iris, look online for ",
        "look online for ",
        "look up ",
        "search online for ",
        "search the web for ",
        "search the internet for ",
        "research ",
        "check online for ",
        "find online ",
    )
    for prefix in prefixes:
        if lowered.startswith(prefix):
            clean = clean[len(prefix) :].strip(" .")
            break
    for suffix in (
        " and summarize the useful sources",
        " and summarize useful sources",
        " and summarize it",
        " and summarize",
    ):
        if clean.lower().endswith(suffix):
            clean = clean[: -len(suffix)].strip(" .")
            break
    return clean[:120]


def propose_memory_if_requested(text: str) -> list[dict[str, Any]]:
    lowered = text.lower()
    prefixes = (
        "remember that ",
        "save to memory ",
        "save this to memory ",
        "propose memory ",
        "stage memory ",
    )
    proposal = ""
    for prefix in prefixes:
        if lowered.startswith(prefix):
            proposal = text[len(prefix) :].strip(" :-")
            break
    if not proposal:
        return []
    try:
        result = iris_broker.iris_propose_memory(proposal, "hermes_task")
    except Exception as error:
        return [{
            "id": 0,
            "text": f"Hermes memory proposal failed: {error}",
            "source": "hermes_task",
            "status": "rejected",
            "verdict": "rejected",
            "createdMs": 0,
            "updatedMs": 0,
        }]
    staging_id = result.get("staging_id") or result.get("stagingId") or 0
    return [{
        "id": int(staging_id),
        "text": proposal,
        "source": "hermes_task",
        "status": "pending" if staging_id else "rejected",
        "verdict": str(result.get("verdict", "staged")),
        "createdMs": 0,
        "updatedMs": 0,
    }]


def model_response(
    mode: str,
    text: str,
    memory: list[dict[str, Any]],
    memory_error: str,
    web_results: list[dict[str, Any]] | None = None,
    web_error: str = "",
) -> str:
    memory_block = format_memory(memory)
    if memory_error:
        memory_block = f"Memory retrieval failed: {memory_error}"
    web_block = format_web_results(web_results or [])
    if web_error:
        web_block = f"Web research failed: {web_error}"
    prompt = (
        "You are Hermes, Iris's sandboxed research, RAG, and memory-transfer helper.\n"
        "Use approved Iris memory, approved web research snippets, and the user's task.\n"
        "Approved web research has already been fetched before this prompt.\n"
        "If web results are present, summarize them and cite their URLs instead of saying you need to search.\n"
        "Do not claim computer-control capabilities. Do not invent sources.\n"
        "If evidence is empty, say what is missing and give the best next step.\n"
        "Be direct and useful.\n\n"
        f"Mode: {mode}\n"
        f"Approved memory:\n{memory_block}\n\n"
        f"Approved web research:\n{web_block}\n\n"
        f"User task: {text}\n"
        "Hermes:"
    )
    try:
        return iris_broker.iris_generate_text(prompt)
    except Exception as error:
        return f"Hermes could not complete the task because local model generation failed: {error}"


def format_memory(memory: list[dict[str, Any]]) -> str:
    lines = []
    for item in memory:
        text = str(item.get("text", "")).strip()
        if text:
            lines.append(f"- {text}")
    return "\n".join(lines) if lines else "(no approved memory retrieved)"


def format_web_results(results: list[dict[str, Any]]) -> str:
    lines = []
    for item in results:
        title = str(item.get("title", "")).strip()
        url = str(item.get("url", "")).strip()
        snippet = str(item.get("snippet", "")).strip()
        if title or snippet:
            lines.append(f"- {title} {url} {snippet}".strip())
    return "\n".join(lines) if lines else "(no approved web research retrieved)"


def _emit(payload: dict[str, Any]) -> None:
    sys.stdout.write(json.dumps(payload, separators=(",", ":")) + "\n")
    sys.stdout.flush()


if __name__ == "__main__":
    raise SystemExit(main())
