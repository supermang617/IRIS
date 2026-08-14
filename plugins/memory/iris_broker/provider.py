from __future__ import annotations

import hashlib
import json
import os
import re
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any


IRIS_OLLAMA_GENERATE_URL = "http://127.0.0.1:11434/api/generate"
IRIS_OLLAMA_TAGS_URL = "http://127.0.0.1:11434/api/tags"
IRIS_OLLAMA_SHOW_URL = "http://127.0.0.1:11434/api/show"
STATUS_ENDPOINT = "/memory/status"
SEARCH_ENDPOINT = "/memory/search"
PROPOSE_ENDPOINT = "/memory/propose"
REQUEST_TIMEOUT_SECONDS = 5
MAX_OLLAMA_IDENTITY_RESPONSE_BYTES = 1024 * 1024
MAX_OLLAMA_GENERATION_RESPONSE_BYTES = 4 * 1024 * 1024
MAX_IRIS_GENERATION_TOKENS = 2048
WEB_TIMEOUT_SECONDS = 10
MAX_QUERY_CHARS = 120
MAX_PROPOSAL_CHARS = 240
EXPOSED_TOOLS = ("iris_query_memory", "iris_propose_memory", "iris_web_research")
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


def _consume_broker_access_from_environment() -> tuple[str, str]:
    endpoint = os.environ.pop("IRIS_HERMES_BROKER_URL", "").strip()
    token = os.environ.pop("IRIS_HERMES_BROKER_TOKEN", "").strip()
    return endpoint, token


_CONFIGURED_BROKER_URL, _CONFIGURED_BROKER_TOKEN = _consume_broker_access_from_environment()
_CONFIGURED_MODEL_LOCK_JSON = os.environ.pop("IRIS_OLLAMA_MODEL_LOCK_JSON", "").strip()
_CONFIGURED_MODEL_STORE_ATTESTATION_JSON = os.environ.pop(
    "IRIS_OLLAMA_VERIFIED_MODEL_STORE_ATTESTATION_JSON", ""
).strip()


class IrisBrokerUnavailable(RuntimeError):
    pass


def repo_root() -> Path:
    return Path(__file__).resolve().parents[3]


def broker_url() -> str:
    configured = _CONFIGURED_BROKER_URL
    if not configured:
        raise IrisBrokerUnavailable("Iris broker endpoint was not provided by Iris")
    try:
        parsed = urllib.parse.urlsplit(configured)
        port = parsed.port
    except ValueError as error:
        raise IrisBrokerUnavailable("Iris broker endpoint is invalid") from error
    if (
        parsed.scheme != "http"
        or parsed.hostname != "127.0.0.1"
        or port is None
        or port == 0
        or parsed.username is not None
        or parsed.password is not None
        or parsed.path not in ("", "/")
        or parsed.query
        or parsed.fragment
    ):
        raise IrisBrokerUnavailable("Iris broker must be local loopback only")
    return f"http://127.0.0.1:{port}"


def broker_token() -> str:
    token = _CONFIGURED_BROKER_TOKEN
    if len(token) != 64 or any(character not in "0123456789abcdefABCDEF" for character in token):
        raise IrisBrokerUnavailable("Iris broker credential was not provided by Iris")
    return token


def configured_iris_model_lock() -> dict[str, Any]:
    if not _CONFIGURED_MODEL_LOCK_JSON:
        raise IrisBrokerUnavailable("Iris model identity lock was not provided by Iris")
    try:
        lock = json.loads(_CONFIGURED_MODEL_LOCK_JSON)
    except json.JSONDecodeError as error:
        raise IrisBrokerUnavailable("Iris model identity lock is invalid") from error
    expected = {
        "schema_version", "provider", "model_id", "manifest_digest",
        "model_layer_digest", "total_bytes", "family", "parameter_size",
        "quantization_level", "required_capabilities", "general_vision_verified",
    }
    if not isinstance(lock, dict) or set(lock) != expected:
        raise IrisBrokerUnavailable("Iris model identity lock schema is invalid")
    if lock.get("schema_version") != 1 or lock.get("provider") != "ollama_local":
        raise IrisBrokerUnavailable("Iris model identity lock provider is invalid")
    manifest_digest = lock.get("manifest_digest")
    model_layer_digest = lock.get("model_layer_digest")
    if (
        not isinstance(manifest_digest, str)
        or len(manifest_digest) != 64
        or any(character not in "0123456789abcdef" for character in manifest_digest)
        or not isinstance(model_layer_digest, str)
        or not model_layer_digest.startswith("sha256:")
        or len(model_layer_digest) != 71
        or any(character not in "0123456789abcdef" for character in model_layer_digest[7:])
    ):
        raise IrisBrokerUnavailable("Iris model identity lock digest is invalid")
    required_capabilities = lock.get("required_capabilities")
    if (
        any(
            not isinstance(lock.get(field), str) or not lock[field].strip()
            for field in ("model_id", "family", "parameter_size", "quantization_level")
        )
        or type(lock.get("total_bytes")) is not int
        or lock["total_bytes"] <= 0
        or not isinstance(required_capabilities, list)
        or not required_capabilities
        or any(not isinstance(value, str) or not value for value in required_capabilities)
        or len(set(required_capabilities)) != len(required_capabilities)
        or not isinstance(lock.get("general_vision_verified"), bool)
    ):
        raise IrisBrokerUnavailable("Iris model identity lock fields are invalid")

    manifest_path = repo_root() / "manifest.json"
    with manifest_path.open("r", encoding="utf-8") as manifest_file:
        manifest = json.load(manifest_file)
    model_policy = manifest.get("model_policy", {})
    if (
        model_policy.get("provider") != lock["provider"]
        or model_policy.get("model_id") != lock["model_id"]
        or model_policy.get("architecture") != lock["family"]
        or model_policy.get("parameter_size") != lock["parameter_size"]
    ):
        raise IrisBrokerUnavailable("Iris manifest differs from the parent-provided model lock")
    return lock


def configured_iris_model() -> str:
    return str(configured_iris_model_lock()["model_id"])


def _ollama_manifest_path(models_root: Path, model_id: str) -> Path:
    if not re.fullmatch(
        r"[A-Za-z0-9._-]+(?:/[A-Za-z0-9._-]+)?:[A-Za-z0-9._-]+",
        model_id,
    ):
        raise IrisBrokerUnavailable("Iris model identity is not a safe Ollama tag")
    name, tag = model_id.split(":", 1)
    if "/" in name:
        namespace, model = name.split("/", 1)
    else:
        namespace, model = "library", name
    return models_root / "manifests" / "registry.ollama.ai" / namespace / model / tag


def _path_key(value: str | Path) -> str:
    text = str(value)
    if not Path(text).is_absolute() or "\x00" in text:
        raise IrisBrokerUnavailable("Ollama model source must be an absolute path")
    normalized = os.path.abspath(os.path.normpath(text))
    if normalized.startswith("\\\\?\\"):
        normalized = normalized[4:]
    return os.path.normcase(normalized).rstrip("\\/")


def _modelfile_model_source(modelfile: Any) -> Path:
    if not isinstance(modelfile, str):
        raise IrisBrokerUnavailable("Ollama /api/show did not report a Modelfile")
    source: str | None = None
    in_multiline_value = False
    for raw_line in modelfile.splitlines():
        line = raw_line.strip()
        is_comment = not in_multiline_value and line.startswith("#")
        if not in_multiline_value and not is_comment and line:
            parts = line.split(None, 1)
            if parts[0].casefold() == "from":
                if source is not None:
                    raise IrisBrokerUnavailable(
                        "Ollama /api/show returned more than one active FROM source"
                    )
                if len(parts) != 2 or not parts[1].strip():
                    raise IrisBrokerUnavailable(
                        "Ollama /api/show returned an empty FROM source"
                    )
                value = parts[1].strip()
                if value.startswith('"') or value.endswith('"'):
                    if len(value) < 2 or not (value.startswith('"') and value.endswith('"')):
                        raise IrisBrokerUnavailable(
                            "Ollama /api/show returned a malformed FROM source"
                        )
                    value = value[1:-1]
                if not value or "\x00" in value:
                    raise IrisBrokerUnavailable(
                        "Ollama /api/show returned an empty FROM source"
                    )
                source = value
        if not is_comment and line.count('"""') % 2 == 1:
            in_multiline_value = not in_multiline_value
    if in_multiline_value:
        raise IrisBrokerUnavailable(
            "Ollama /api/show returned an unterminated multiline value"
        )
    if source is None:
        raise IrisBrokerUnavailable(
            "Ollama /api/show did not report an active FROM source"
        )
    return Path(source)


def _configured_model_store_attestation(lock: dict[str, Any]) -> dict[str, Any]:
    if not _CONFIGURED_MODEL_STORE_ATTESTATION_JSON:
        raise IrisBrokerUnavailable(
            "Iris verified model-store attestation was not provided by Iris"
        )
    try:
        attestation = json.loads(_CONFIGURED_MODEL_STORE_ATTESTATION_JSON)
    except json.JSONDecodeError as error:
        raise IrisBrokerUnavailable(
            "Iris verified model-store attestation is invalid"
        ) from error
    expected = {
        "schema_version",
        "model_id",
        "models_root",
        "manifest_digest",
        "model_layer_digest",
        "descriptors",
    }
    if not isinstance(attestation, dict) or set(attestation) != expected:
        raise IrisBrokerUnavailable(
            "Iris verified model-store attestation schema is invalid"
        )
    if (
        attestation.get("schema_version") != 1
        or attestation.get("model_id") != lock["model_id"]
        or attestation.get("manifest_digest") != lock["manifest_digest"]
        or attestation.get("model_layer_digest") != lock["model_layer_digest"]
        or not isinstance(attestation.get("models_root"), str)
        or not isinstance(attestation.get("descriptors"), list)
        or not attestation["descriptors"]
    ):
        raise IrisBrokerUnavailable(
            "Iris verified model-store attestation differs from the model lock"
        )
    _path_key(attestation["models_root"])
    return attestation


def assert_iris_ollama_model_store(
    lock: dict[str, Any], show: dict[str, Any]
) -> None:
    attestation = _configured_model_store_attestation(lock)
    models_root = Path(attestation["models_root"])
    manifest_path = _ollama_manifest_path(models_root, lock["model_id"])
    try:
        with manifest_path.open("rb") as manifest_file:
            manifest_bytes = manifest_file.read(MAX_OLLAMA_IDENTITY_RESPONSE_BYTES + 1)
    except OSError as error:
        raise IrisBrokerUnavailable(
            f"Iris verified model-store manifest is unavailable: {error}"
        ) from error
    if len(manifest_bytes) > MAX_OLLAMA_IDENTITY_RESPONSE_BYTES:
        raise IrisBrokerUnavailable("Iris verified model-store manifest is too large")
    if hashlib.sha256(manifest_bytes).hexdigest() != lock["manifest_digest"]:
        raise IrisBrokerUnavailable(
            "Iris verified model-store manifest differs from the model lock"
        )
    try:
        manifest = json.loads(manifest_bytes)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise IrisBrokerUnavailable(
            "Iris verified model-store manifest is invalid"
        ) from error
    if (
        not isinstance(manifest, dict)
        or not isinstance(manifest.get("config"), dict)
        or not isinstance(manifest.get("layers"), list)
        or not manifest["layers"]
    ):
        raise IrisBrokerUnavailable("Iris verified model-store manifest is invalid")
    descriptors = [manifest["config"], *manifest["layers"]]
    evidence = attestation["descriptors"]
    if len(descriptors) != len(evidence):
        raise IrisBrokerUnavailable("Iris verified model-store layout changed")
    total_bytes = 0
    locked_model_layers = 0
    for descriptor, expected in zip(descriptors, evidence, strict=True):
        if (
            not isinstance(descriptor, dict)
            or not isinstance(expected, dict)
            or set(expected)
            != {
                "media_type",
                "digest",
                "size",
                "modified_unix_ns",
                "created_unix_ns",
            }
            or descriptor.get("mediaType") != expected.get("media_type")
            or descriptor.get("digest") != expected.get("digest")
            or descriptor.get("size") != expected.get("size")
            or type(descriptor.get("size")) is not int
            or descriptor["size"] <= 0
        ):
            raise IrisBrokerUnavailable("Iris verified model-store layout changed")
        digest = descriptor["digest"]
        if (
            not isinstance(digest, str)
            or not re.fullmatch(r"sha256:[a-f0-9]{64}", digest)
        ):
            raise IrisBrokerUnavailable("Iris verified model-store digest is invalid")
        total_bytes += descriptor["size"]
        if (
            descriptor["mediaType"] == "application/vnd.ollama.image.model"
            and digest == lock["model_layer_digest"]
        ):
            locked_model_layers += 1
        blob = models_root / "blobs" / digest.replace(":", "-", 1)
        try:
            metadata = blob.stat()
        except OSError as error:
            raise IrisBrokerUnavailable(
                f"Iris verified model-store blob is unavailable: {error}"
            ) from error
        created_unix_ns = getattr(metadata, "st_birthtime_ns", metadata.st_ctime_ns)
        if (
            not blob.is_file()
            or metadata.st_size != descriptor["size"]
            or type(expected.get("modified_unix_ns")) is not int
            or metadata.st_mtime_ns != expected["modified_unix_ns"]
            or (
                expected.get("created_unix_ns") is not None
                and created_unix_ns != expected["created_unix_ns"]
            )
        ):
            raise IrisBrokerUnavailable("Iris verified model-store metadata changed")
    if total_bytes != lock["total_bytes"] or locked_model_layers != 1:
        raise IrisBrokerUnavailable("Iris verified model-store layout changed")
    expected_source = models_root / "blobs" / lock["model_layer_digest"].replace(
        ":", "-", 1
    )
    actual_source = _modelfile_model_source(show.get("modelfile"))
    if _path_key(actual_source) != _path_key(expected_source):
        raise IrisBrokerUnavailable(
            "Ollama /api/show model source differs from Iris's verified model store"
        )


def _ollama_json_request(url: str, *, payload: dict[str, Any] | None = None) -> dict[str, Any]:
    body = None if payload is None else json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=body,
        method="GET" if payload is None else "POST",
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT_SECONDS) as response:
            data = response.read(MAX_OLLAMA_IDENTITY_RESPONSE_BYTES + 1)
    except (urllib.error.URLError, TimeoutError) as error:
        raise IrisBrokerUnavailable(f"local Ollama identity check unavailable: {error}") from error
    if len(data) > MAX_OLLAMA_IDENTITY_RESPONSE_BYTES:
        raise IrisBrokerUnavailable("local Ollama identity response is too large")
    try:
        parsed = json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise IrisBrokerUnavailable("local Ollama identity response is invalid") from error
    if not isinstance(parsed, dict):
        raise IrisBrokerUnavailable("local Ollama identity response is invalid")
    return parsed


def assert_iris_ollama_model_identity() -> dict[str, Any]:
    lock = configured_iris_model_lock()
    tags = _ollama_json_request(IRIS_OLLAMA_TAGS_URL)
    candidates = [
        model for model in tags.get("models", [])
        if isinstance(model, dict)
        and (model.get("name") == lock["model_id"] or model.get("model") == lock["model_id"])
    ]
    if len(candidates) != 1:
        raise IrisBrokerUnavailable("configured Iris model is missing or ambiguous in Ollama")
    tag_model = candidates[0]
    show = _ollama_json_request(IRIS_OLLAMA_SHOW_URL, payload={"model": lock["model_id"]})
    if tag_model.get("digest") != lock["manifest_digest"]:
        raise IrisBrokerUnavailable("configured Ollama model digest differs from the Iris lock")
    if tag_model.get("size") != lock["total_bytes"]:
        raise IrisBrokerUnavailable("configured Ollama model byte count differs from the Iris lock")
    for source, details in (("/api/tags", tag_model.get("details")), ("/api/show", show.get("details"))):
        if not isinstance(details, dict) or any(
            details.get(field) != lock[field]
            for field in ("family", "parameter_size", "quantization_level")
        ):
            raise IrisBrokerUnavailable(f"configured Ollama model metadata from {source} differs from the Iris lock")
    capabilities = show.get("capabilities")
    if not isinstance(capabilities, list) or any(
        capability not in capabilities for capability in lock["required_capabilities"]
    ):
        raise IrisBrokerUnavailable("configured Ollama model is missing locked capabilities")
    assert_iris_ollama_model_store(lock, show)
    return lock


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
    if not status.get("authenticated"):
        raise IrisBrokerUnavailable("Iris broker must report authenticated=true")
    _validate_staging_status_counts(status)
    inference_policy()
    assert_iris_ollama_model_identity()
    return status


def _validate_staging_status_counts(status: dict[str, Any]) -> None:
    required = ("stagingItems", "pendingStagingItems", "decidedStagingItems")
    if any(key not in status for key in required):
        raise IrisBrokerUnavailable("Iris broker status must report explicit staging counts")
    total = status.get("stagingItems")
    pending = status.get("pendingStagingItems")
    decided = status.get("decidedStagingItems")
    if not all(isinstance(value, int) and value >= 0 for value in (total, pending, decided)):
        raise IrisBrokerUnavailable("Iris broker staging counts must be non-negative integers")
    if pending + decided != total:
        raise IrisBrokerUnavailable("Iris broker staging counts are inconsistent")


def iris_query_memory(query: str, limit: int = 5) -> dict[str, Any]:
    clean_query = " ".join(query.split())
    if not clean_query:
        raise ValueError("memory query cannot be empty")
    if len(clean_query) > MAX_QUERY_CHARS:
        raise ValueError("memory query is too large")
    if contains_prompt_injection_text(clean_query):
        raise ValueError("memory query contains prompt-injection language")
    return _broker_post(SEARCH_ENDPOINT, {"query": clean_query, "limit": min(max(limit, 1), 10)})


def iris_generate_text(
    prompt: str,
    *,
    max_tokens: int = 384,
    temperature: float = 0.1,
) -> str:
    clean_prompt = prompt.strip()
    if not clean_prompt:
        raise ValueError("generation prompt cannot be empty")
    if (
        type(max_tokens) is not int
        or max_tokens <= 0
        or max_tokens > MAX_IRIS_GENERATION_TOKENS
    ):
        raise ValueError(
            f"generation max_tokens must be between 1 and {MAX_IRIS_GENERATION_TOKENS}"
        )
    if (
        isinstance(temperature, bool)
        or not isinstance(temperature, (int, float))
        or not 0 <= float(temperature) <= 2
    ):
        raise ValueError("generation temperature must be between 0 and 2")
    lock = assert_iris_ollama_model_identity()
    payload = {
        "model": lock["model_id"],
        "prompt": clean_prompt,
        "stream": False,
        "think": False,
        "keep_alive": "10m",
        "options": {
            "num_predict": max_tokens,
            "temperature": float(temperature),
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
        timeout_seconds = 60 if max_tokens <= 384 else 180
        with urllib.request.urlopen(request, timeout=timeout_seconds) as response:
            data = response.read(MAX_OLLAMA_GENERATION_RESPONSE_BYTES + 1)
    except (urllib.error.URLError, TimeoutError) as error:
        raise IrisBrokerUnavailable(f"local Ollama unavailable: {error}") from error
    if len(data) > MAX_OLLAMA_GENERATION_RESPONSE_BYTES:
        raise IrisBrokerUnavailable("local Ollama generation response is too large")
    try:
        parsed = json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise IrisBrokerUnavailable("local Ollama generation response is invalid") from error
    if not isinstance(parsed, dict):
        raise IrisBrokerUnavailable("local Ollama generation response is invalid")
    response_text = parsed.get("response")
    if not isinstance(response_text, str):
        raise IrisBrokerUnavailable("local Ollama generation response is invalid")
    text = response_text.strip()
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
    raise IrisBrokerUnavailable(
        "Safe Hermes supports recognized primary-source lookups only. "
        "Start an Agentic Session for isolated browser research."
    )


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
    except (urllib.error.URLError, TimeoutError) as error:
        raise IrisBrokerUnavailable(
            f"Primary-source release lookup unavailable: {error}"
        ) from error
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
    return _broker_post(PROPOSE_ENDPOINT, payload, allow_rejection=True)


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


def _broker_post(
    endpoint: str,
    payload: dict[str, Any],
    allow_rejection: bool = False,
) -> dict[str, Any]:
    return _request("POST", endpoint, payload, allow_rejection=allow_rejection)


def _request(
    method: str,
    endpoint: str,
    payload: dict[str, Any] | None,
    *,
    allow_rejection: bool = False,
) -> dict[str, Any]:
    url = f"{broker_url()}{endpoint}"
    body = None if payload is None else json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=body,
        method=method,
        headers={
            "Authorization": f"Bearer {broker_token()}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT_SECONDS) as response:
            data = response.read()
    except (urllib.error.URLError, TimeoutError) as error:
        raise IrisBrokerUnavailable(f"Iris broker unavailable: {error}") from error
    parsed = json.loads(data.decode("utf-8"))
    if not parsed.get("ok") and not allow_rejection:
        raise IrisBrokerUnavailable(f"Iris broker rejected request: {parsed.get('error')}")
    return parsed
