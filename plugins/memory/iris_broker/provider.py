from __future__ import annotations

import json
import html
import base64
import os
import re
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any


DEFAULT_BROKER_URL = "http://127.0.0.1:48731"
IRIS_OLLAMA_GENERATE_URL = "http://127.0.0.1:11434/api/generate"
STATUS_ENDPOINT = "/memory/status"
SEARCH_ENDPOINT = "/memory/search"
PROPOSE_ENDPOINT = "/memory/propose"
REQUEST_TIMEOUT_SECONDS = 5
WEB_TIMEOUT_SECONDS = 10
MAX_QUERY_CHARS = 120
MAX_PROPOSAL_CHARS = 240
EXPOSED_TOOLS = ("iris_query_memory", "iris_propose_memory", "iris_web_research")
IRIS_HERMES_WEB_SEARCH_URL = "https://www.bing.com/search"
GITHUB_API_URL = "https://api.github.com"
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


def iris_web_research(query: str, limit: int = 5) -> dict[str, Any]:
    clean_query = " ".join(query.split())
    if not clean_query:
        raise ValueError("web research query cannot be empty")
    if len(clean_query) > MAX_QUERY_CHARS:
        clean_query = clean_query[:MAX_QUERY_CHARS].strip()
    if contains_prompt_injection_text(clean_query):
        raise ValueError("web research query contains prompt-injection language")
    authoritative = _authoritative_release_lookup(clean_query)
    if authoritative:
        return {
            "query": clean_query,
            "results": authoritative[: min(max(limit, 1), 5)],
        }
    params = urllib.parse.urlencode({"q": clean_query})
    request = urllib.request.Request(
        f"{IRIS_HERMES_WEB_SEARCH_URL}?{params}",
        method="GET",
        headers={
            "User-Agent": "Mozilla/5.0 Project-Iris-Hermes/0.1",
            "Accept": "text/html",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=WEB_TIMEOUT_SECONDS) as response:
            data = response.read(256_000)
    except (urllib.error.URLError, TimeoutError) as error:
        raise IrisBrokerUnavailable(f"Hermes web research unavailable: {error}") from error
    html_text = data.decode("utf-8", errors="replace")
    return {
        "query": clean_query,
        "results": _parse_bing_html(html_text, min(max(limit, 1), 5)),
    }


def _authoritative_release_lookup(query: str) -> list[dict[str, str]]:
    repo = _release_repo_for_query(query)
    if not repo:
        return []
    request = urllib.request.Request(
        f"{GITHUB_API_URL}/repos/{repo}/releases/latest",
        method="GET",
        headers={
            "User-Agent": "Project-Iris-Hermes/0.1",
            "Accept": "application/vnd.github+json",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=WEB_TIMEOUT_SECONDS) as response:
            data = response.read(128_000)
    except (urllib.error.URLError, TimeoutError):
        return []
    parsed = json.loads(data.decode("utf-8"))
    name = str(parsed.get("name") or parsed.get("tag_name") or "").strip()
    tag = str(parsed.get("tag_name") or "").strip()
    url = str(parsed.get("html_url") or "").strip()
    published = str(parsed.get("published_at") or "").strip()
    body = " ".join(str(parsed.get("body") or "").split())
    snippet_parts = []
    if tag:
        snippet_parts.append(f"tag {tag}")
    if published:
        snippet_parts.append(f"published {published}")
    if body:
        snippet_parts.append(body[:420])
    return [{
        "title": f"{repo} latest release: {name}".strip(),
        "url": url,
        "snippet": "; ".join(snippet_parts),
    }]


def _release_repo_for_query(query: str) -> str:
    lowered = query.lower()
    if "ollama" in lowered and "release" in lowered:
        return "ollama/ollama"
    return ""


def _parse_bing_html(html_text: str, limit: int) -> list[dict[str, str]]:
    results = []
    blocks = re.split(r'<li[^>]+class="[^"]*b_algo[^"]*"', html_text)
    for block in blocks[1:]:
        link_match = re.search(r'<h2[^>]*>\s*<a[^>]+href="([^"]+)"[^>]*>(.*?)</a>\s*</h2>', block, re.I | re.S)
        if not link_match:
            continue
        snippet_match = re.search(r'<p[^>]*>(.*?)</p>', block, re.I | re.S)
        url = _clean_bing_url(html.unescape(link_match.group(1)))
        title = _plain_html_text(link_match.group(2))
        snippet = _plain_html_text(snippet_match.group(1)) if snippet_match else ""
        if title:
            results.append({"title": title[:180], "url": url[:500], "snippet": snippet[:500]})
        if len(results) >= limit:
            break
    return results


def _plain_html_text(value: str) -> str:
    text = re.sub(r"<[^>]+>", " ", value)
    return " ".join(html.unescape(text).split())


def _clean_bing_url(url: str) -> str:
    parsed = urllib.parse.urlparse(url)
    encoded = urllib.parse.parse_qs(parsed.query).get("u", [""])[0]
    if encoded.startswith("a1"):
        payload = encoded[2:]
        padding = "=" * (-len(payload) % 4)
        try:
            decoded = base64.urlsafe_b64decode(f"{payload}{padding}").decode("utf-8")
            if decoded.startswith(("http://", "https://")):
                return decoded
        except (ValueError, UnicodeDecodeError):
            pass
    return url


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
