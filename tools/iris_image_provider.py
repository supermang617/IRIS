import base64
import json
import os
import sys
import urllib.error
import urllib.request


OPENAI_IMAGES_URL = "https://api.openai.com/v1/images/generations"
DEFAULT_MODEL = "gpt-image-2"
DEFAULT_SIZE = "1024x1024"
DEFAULT_QUALITY = "auto"
DEFAULT_OUTPUT_FORMAT = "png"
MAX_PROMPT_CHARS = 2000
MAX_IMAGE_BYTES = 25 * 1024 * 1024
MAX_PROVIDER_RESPONSE_BYTES = ((MAX_IMAGE_BYTES + 2) // 3) * 4 + 512 * 1024


def main() -> int:
    try:
        request = json.loads(sys.stdin.read() or "{}")
        prompt = str(request.get("prompt", "")).strip()
        if not prompt:
            raise ValueError("image prompt cannot be empty")
        if len(prompt) > MAX_PROMPT_CHARS:
            raise ValueError(f"image prompt must be {MAX_PROMPT_CHARS} characters or less")

        provider = os.environ.get("IRIS_IMAGE_PROVIDER", "openai").strip().lower()
        if provider != "openai":
            raise ValueError("unsupported image provider; set IRIS_IMAGE_PROVIDER=openai")

        response = generate_openai_image(prompt)
        emit({"ok": True, **response})
        return 0
    except Exception as error:
        emit({"ok": False, "error": str(error)})
        return 1


def generate_openai_image(prompt: str) -> dict:
    api_key = os.environ.get("OPENAI_API_KEY", "").strip()
    if not api_key:
        raise RuntimeError("OPENAI_API_KEY is not configured for Iris image generation")

    model = os.environ.get("IRIS_IMAGE_MODEL", DEFAULT_MODEL).strip() or DEFAULT_MODEL
    size = os.environ.get("IRIS_IMAGE_SIZE", DEFAULT_SIZE).strip() or DEFAULT_SIZE
    quality = os.environ.get("IRIS_IMAGE_QUALITY", DEFAULT_QUALITY).strip() or DEFAULT_QUALITY
    output_format = (
        os.environ.get("IRIS_IMAGE_OUTPUT_FORMAT", DEFAULT_OUTPUT_FORMAT).strip().lower()
        or DEFAULT_OUTPUT_FORMAT
    )

    payload = {
        "model": model,
        "prompt": prompt,
        "size": size,
        "quality": quality,
        "output_format": output_format,
        "n": 1,
    }
    request = urllib.request.Request(
        OPENAI_IMAGES_URL,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
            "User-Agent": "Project-Iris/1.0 image-provider",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=180) as response:
            response_bytes = response.read(MAX_PROVIDER_RESPONSE_BYTES + 1)
            if len(response_bytes) > MAX_PROVIDER_RESPONSE_BYTES:
                raise RuntimeError("OpenAI Images API response exceeded the Iris size limit")
            parsed = json.loads(response_bytes.decode("utf-8"))
    except urllib.error.HTTPError as error:
        detail = error.read(801).decode("utf-8", errors="replace")
        raise RuntimeError(f"OpenAI Images API returned HTTP {error.code}: {detail[:800]}") from error

    data = parsed.get("data") or []
    if not data or not isinstance(data[0], dict):
        raise RuntimeError("OpenAI Images API returned no image data")
    image_b64 = data[0].get("b64_json")
    if not image_b64:
        raise RuntimeError("OpenAI Images API returned no base64 image")
    image_bytes = base64.b64decode(image_b64, validate=True)
    if not image_bytes or len(image_bytes) > MAX_IMAGE_BYTES:
        raise RuntimeError("generated image must be non-empty and no larger than 25 MB")
    return {
        "provider": "openai_images_api",
        "model": model,
        "size": size,
        "quality": quality,
        "mime": f"image/{output_format}",
        "image_b64": image_b64,
        "revised_prompt": data[0].get("revised_prompt") or "",
    }


def emit(payload: dict) -> None:
    sys.stdout.write(json.dumps(payload, separators=(",", ":")) + "\n")
    sys.stdout.flush()


if __name__ == "__main__":
    raise SystemExit(main())
