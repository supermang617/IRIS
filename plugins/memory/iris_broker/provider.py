from __future__ import annotations

import json
import os
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any


DEFAULT_BROKER_URL = "http://127.0.0.1:48731"
IRIS_OLLAMA_GENERATE_URL = "http://127.0.0.1:11434/api/generate"
STATUS_ENDPOINT = "/memory/status"
SEARCH_ENDPOINT = "/memory/search"
PROPOSE_ENDPOINT = "/memory/propose"
REQUEST_TIMEOUT_SECONDS = 5
MAX_QUERY_CHARS = 120
MAX_PROPOSAL_CHARS = 240
EXPOSED_TOOLS = ("iris_query_memory", "iris_propose_memory")
PROFILE_NAME = "iris_restricted"
PROMPT_INJECTION_PHRASES = (
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
)


class IrisBrokerUnavailable(RuntimeError):
    pass


def repo_root() -> Path:
    return Path(__file__).resolve().parents[3]


def broker_url() -> str:
    configured = os.environ.get("IRIS_HERMES_BROKER_URL", DEFAULT_BROKER_URL).rstrip("/")
    if configured not in (DEFAULT_BROKER_URL, "http://localhost:48731"):
        raise IrisBrokerUnavailable("Iris broker must be local loopback only")
    return configured


def configured_iris_model() -> str:
    manifest_path = repo_root() / "manifest.json"
    with manifest_path.open("r", encoding="utf-8") as manifest_file:
        manifest = json.load(manifest_file)
    model_policy = manifest.get("model_policy", {})
    provider = model_policy.get("provider")
    model_id = model_policy.get("model_id")
    if provider != "ollama_local" or not model_id:
        raise IrisBrokerUnavailable("Iris manifest must provide the Ollama model")
    return str(model_id)


def inference_policy() -> dict[str, Any]:
    return {
        "provider": "ollama_local",
        "endpoint": IRIS_OLLAMA_GENERATE_URL,
        "model": configured_iris_model(),
        "modelSource": "manifest.json",
        "usesExistingIrisModel": True,
        "modelSwitching": False,
        "modelPulling": False,
        "modelAutoSelection": False,
        "fallbackModels": False,
        "criticWorkerSplit": False,
        "multiModelDebate": False,
        "parallelInferenceStreams": 1,
        "sequentialTasksOnly": True,
    }


def tool_registry() -> tuple[str, ...]:
    return EXPOSED_TOOLS


def startup_check() -> dict[str, Any]:
    status = _broker_get(STATUS_ENDPOINT)
    if not status.get("ok"):
        raise IrisBrokerUnavailable("Iris broker status did not return ok")
    if not status.get("loopbackOnly"):
        raise IrisBrokerUnavailable("Iris broker must report loopbackOnly=true")
    inference_policy()
    return status


def iris_query_memory(query: str, limit: int = 5) -> dict[str, Any]:
    clean_query = " ".join(query.split())
    if not clean_query:
        raise ValueError("memory query cannot be empty")
    if len(clean_query) > MAX_QUERY_CHARS:
        raise ValueError("memory query is too large")
    if contains_prompt_injection_text(clean_query):
        raise ValueError("memory query contains prompt-injection language")
    return _broker_post(SEARCH_ENDPOINT, {"query": clean_query, "limit": min(max(limit, 1), 10)})


def iris_generate_text(prompt: str) -> str:
    clean_prompt = prompt.strip()
    if not clean_prompt:
        raise ValueError("generation prompt cannot be empty")
    payload = {
        "model": configured_iris_model(),
        "prompt": clean_prompt,
        "stream": False,
        "think": False,
        "keep_alive": "10m",
        "options": {
            "num_predict": 384,
            "temperature": 0.1,
            "top_k": 20,
            "top_p": 0.8,
        },
    }
    request = urllib.request.Request(
        IRIS_OLLAMA_GENERATE_URL,
        data=json.dumps(payload).encode("utf-8"),
        method="POST",
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            data = response.read()
    except (urllib.error.URLError, TimeoutError) as error:
        raise IrisBrokerUnavailable(f"local Ollama unavailable: {error}") from error
    parsed = json.loads(data.decode("utf-8"))
    text = str(parsed.get("response", "")).strip()
    if not text:
        raise IrisBrokerUnavailable("local Ollama returned an empty Hermes response")
    return text


def iris_propose_memory(text: str, source: str = "hermes", evidence: str | None = None) -> dict[str, Any]:
    clean_text = " ".join(text.split())
    if not clean_text:
        raise ValueError("memory proposal cannot be empty")
    if len(clean_text) > MAX_PROPOSAL_CHARS:
        raise ValueError("memory proposal is too large")
    if contains_prompt_injection_text(clean_text):
        raise ValueError("memory proposal contains prompt-injection language")
    if web_proposal_missing_evidence(source, evidence):
        raise ValueError("web-derived memory proposals require evidence")
    payload = {"text": clean_text, "source": source}
    if evidence:
        payload["evidence"] = evidence
    return _broker_post(PROPOSE_ENDPOINT, payload)


def contains_prompt_injection_text(text: str) -> bool:
    lowered = text.lower()
    return any(phrase in lowered for phrase in PROMPT_INJECTION_PHRASES)


def web_proposal_missing_evidence(source: str, evidence: str | None) -> bool:
    lowered = source.lower()
    web_derived = (
        "web" in lowered
        or "http://" in lowered
        or "https://" in lowered
        or "browser" in lowered
        or "search" in lowered
    )
    return web_derived and not (evidence and evidence.strip())


def _broker_get(endpoint: str) -> dict[str, Any]:
    return _request("GET", endpoint, None)


def _broker_post(endpoint: str, payload: dict[str, Any]) -> dict[str, Any]:
    return _request("POST", endpoint, payload)


def _request(method: str, endpoint: str, payload: dict[str, Any] | None) -> dict[str, Any]:
    url = f"{broker_url()}{endpoint}"
    body = None if payload is None else json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=body,
        method=method,
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT_SECONDS) as response:
            data = response.read()
    except (urllib.error.URLError, TimeoutError) as error:
        raise IrisBrokerUnavailable(f"Iris broker unavailable: {error}") from error
    parsed = json.loads(data.decode("utf-8"))
    if not parsed.get("ok"):
        raise IrisBrokerUnavailable(f"Iris broker rejected request: {parsed.get('error')}")
    return parsed
