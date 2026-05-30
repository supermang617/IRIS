# Kokoro Provider Discovery

Status: active.

Kokoro must be wired from discovered local paths, not guesses.

Discovery command:

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\discover_iris_kokoro_provider.ps1

Rules:

- no network use
- no installs during discovery
- no hardcoded provider path until verified
- keep SAPI as fallback only
- keep voice providers swappable
