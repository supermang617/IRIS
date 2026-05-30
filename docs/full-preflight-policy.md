# Full Preflight Policy

Status: active.

The full preflight runs deterministic checks and then attempts the manual live voice/text smoke.

Manual live voice smoke is non-blocking inside full preflight.

Reason: live voice output can fail because of local audio state, Kokoro state, device state, or Windows playback state. That should be logged, not allowed to invalidate deterministic build and runtime-safety checks.

Hard deterministic gate:

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify_iris_foundation_guard.ps1

Full preflight:

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify_iris_full_preflight.ps1

Strict manual voice smoke:

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\smoke_iris_live_voice_text_manual.ps1
