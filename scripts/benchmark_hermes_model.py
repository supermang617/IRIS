from __future__ import annotations

import argparse
import json
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
OLLAMA_CHAT_URL = "http://127.0.0.1:11434/api/chat"


@dataclass(frozen=True)
class Scenario:
    name: str
    prompt: str
    tool: str
    arguments: dict[str, Any]


SCENARIOS = [
    Scenario("read_file", "Read C:/work/notes.txt.", "read_file", {"path": "C:/work/notes.txt"}),
    Scenario("list_files", "List files in C:/work/src.", "list_files", {"path": "C:/work/src"}),
    Scenario("search_text", "Search C:/work for the exact text TODO.", "search_text", {"path": "C:/work", "query": "TODO"}),
    Scenario("write_file", "Write hello to C:/work/out.txt.", "write_file", {"path": "C:/work/out.txt", "content": "hello"}),
    Scenario("delete_file", "Delete C:/work/old.tmp.", "delete_file", {"path": "C:/work/old.tmp"}),
    Scenario("run_command", "Run cargo test in C:/work.", "run_command", {"cwd": "C:/work", "command": "cargo test"}),
    Scenario("git_status", "Check git status in C:/work.", "git_status", {"cwd": "C:/work"}),
    Scenario("git_diff", "Show the git diff in C:/work.", "git_diff", {"cwd": "C:/work"}),
    Scenario("open_url", "Open https://example.com/docs.", "open_url", {"url": "https://example.com/docs"}),
    Scenario("web_search", "Search the web for Ollama release notes.", "web_search", {"query": "Ollama release notes"}),
    Scenario("click", "Click the button named Continue.", "click", {"target": "Continue"}),
    Scenario(
        "type_text",
        "Type the exact text `alejandro` into the field whose target identifier is exactly `username`.",
        "type_text",
        {"target": "username", "text": "alejandro"},
    ),
    Scenario("take_screenshot", "Take a screenshot named login-page.", "take_screenshot", {"name": "login-page"}),
    Scenario("query_memory", "Find memories about Iris voice latency.", "query_memory", {"query": "Iris voice latency"}),
    Scenario(
        "stage_memory",
        "Stage this exact memory text without adding punctuation: `Alejandro is 45`.",
        "stage_memory",
        {"text": "Alejandro is 45"},
    ),
    Scenario("inspect_process", "Inspect process 4242.", "inspect_process", {"pid": 4242}),
    Scenario("stop_process", "Stop process 4242.", "stop_process", {"pid": 4242}),
    Scenario("download_file", "Download https://example.com/file.txt to C:/work/file.txt.", "download_file", {"url": "https://example.com/file.txt", "path": "C:/work/file.txt"}),
    Scenario("apply_patch", "Apply patch fix-123 to C:/work.", "apply_patch", {"cwd": "C:/work", "patch": "fix-123"}),
    Scenario(
        "ask_approval",
        "Ask approval with risk class exactly `install_or_admin` and summary exactly `install package demo`.",
        "ask_approval",
        {"risk": "install_or_admin", "summary": "install package demo"},
    ),
]


def tool_definition(scenario: Scenario) -> dict[str, Any]:
    properties = {}
    required = []
    for key, value in scenario.arguments.items():
        value_type = "integer" if isinstance(value, int) else "string"
        properties[key] = {"type": value_type}
        if scenario.tool == "ask_approval" and key == "risk":
            properties[key]["enum"] = ["install_or_admin"]
        required.append(key)
    return {
        "type": "function",
        "function": {
            "name": scenario.tool,
            "description": f"Inert benchmark tool for {scenario.name}.",
            "parameters": {
                "type": "object",
                "properties": properties,
                "required": required,
                "additionalProperties": False,
            },
        },
    }


def request_tool_call(model: str, scenario: Scenario, seed: int) -> dict[str, Any]:
    payload = {
        "model": model,
        "stream": False,
        "think": False,
        "messages": [
            {
                "role": "system",
                "content": (
                    "Select the one provided tool that performs the user's request. "
                    "Do not claim the tool ran. Return a tool call with exact arguments."
                ),
            },
            {"role": "user", "content": scenario.prompt},
        ],
        "tools": [tool_definition(item) for item in SCENARIOS],
        "options": {"temperature": 0, "seed": seed},
    }
    request = urllib.request.Request(
        OLLAMA_CHAT_URL,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=180) as response:
        return json.load(response)


def normalize_arguments(arguments: Any) -> dict[str, Any] | None:
    if isinstance(arguments, dict):
        return arguments
    if isinstance(arguments, str):
        try:
            value = json.loads(arguments)
        except json.JSONDecodeError:
            return None
        return value if isinstance(value, dict) else None
    return None


def score_response(response: dict[str, Any], scenario: Scenario) -> tuple[bool, str]:
    tool_calls = response.get("message", {}).get("tool_calls", [])
    if len(tool_calls) != 1:
        return False, f"expected one tool call, received {len(tool_calls)}"
    function = tool_calls[0].get("function", {})
    if function.get("name") != scenario.tool:
        return False, f"expected {scenario.tool}, received {function.get('name')}"
    arguments = normalize_arguments(function.get("arguments"))
    if arguments != scenario.arguments:
        return False, f"expected {scenario.arguments!r}, received {arguments!r}"
    return True, "matched"


def configured_model() -> str:
    manifest = json.loads((ROOT / "manifest.json").read_text(encoding="utf-8"))
    return manifest["model_policy"]["model_id"]


def run_benchmark(model: str, runs: int, minimum: int) -> dict[str, Any]:
    report: dict[str, Any] = {
        "model": model,
        "endpoint": OLLAMA_CHAT_URL,
        "runs": [],
        "minimum_successes": minimum,
        "tools_executed": False,
        "unauthorized_actions": 0,
    }
    for run_index in range(runs):
        results = []
        successes = 0
        for scenario_index, scenario in enumerate(SCENARIOS):
            started = time.perf_counter()
            try:
                response = request_tool_call(model, scenario, seed=3100 + scenario_index)
                passed, detail = score_response(response, scenario)
            except (OSError, TimeoutError, urllib.error.URLError, ValueError) as error:
                passed, detail = False, str(error)
            successes += int(passed)
            results.append(
                {
                    "scenario": scenario.name,
                    "passed": passed,
                    "detail": detail,
                    "elapsed_ms": round((time.perf_counter() - started) * 1000),
                }
            )
        report["runs"].append(
            {
                "run": run_index + 1,
                "successes": successes,
                "total": len(SCENARIOS),
                "passed": successes >= minimum,
                "results": results,
            }
        )
    return report


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", default=configured_model())
    parser.add_argument("--runs", type=int, default=2)
    parser.add_argument("--minimum", type=int, default=18)
    parser.add_argument(
        "--output",
        type=Path,
        default=ROOT / "diagnostics" / "hermes-model-benchmark.json",
    )
    args = parser.parse_args()
    if args.runs < 1 or not 0 <= args.minimum <= len(SCENARIOS):
        parser.error("runs must be positive and minimum must be between 0 and 20")

    report = run_benchmark(args.model, args.runs, args.minimum)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    for run in report["runs"]:
        print(f"run {run['run']}: {run['successes']}/{run['total']}")
    print(f"report: {args.output}")
    return 0 if all(run["passed"] for run in report["runs"]) else 1


if __name__ == "__main__":
    raise SystemExit(main())
