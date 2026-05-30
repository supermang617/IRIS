# Voice Provider Strategy

Status: active.

Iris voice output must be provider-based.

Preferred order:

1. Kokoro local voice provider
2. SAPI fallback on Windows
3. Future local TTS providers behind the same interface

Qwen is the reasoning model. It is not the TTS voice provider.

SAPI is allowed as a temporary fallback and diagnostic baseline only.

The conversation loop should output text once, then hand that text to the selected voice provider.
