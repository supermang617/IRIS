# Voice Milestone Routing

Status: active.

Current milestone:

voice input -> transcript -> Qwen response -> Kokoro speech

scripts/ask_iris_local_speak.ps1 exists as a compatibility bridge for older listener routing.
The current milestone script owns the actual model response and Kokoro speech step.

Expected spoken phrase for the current boundary:

Testing now, Iris local voice test.

Qwen remains the reasoning model. Kokoro remains the preferred local TTS provider. SAPI remains fallback.
