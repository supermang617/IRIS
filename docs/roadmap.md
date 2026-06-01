# Project Iris Roadmap

## Current Direction

Move fast on one Windows Iris prototype for Alejandro's system.

Out of scope for this workspace:

- extra platform folders
- multi-tier model selection
- dev-vs-user model split
- remote model registries
- fallback model behavior

## Active Model

```text
huihui_ai/gemma-4-abliterated:e2b
```

The active model is vision-capable. Iris must use this same model for future image/vision work; do not add a separate vision model.

## Next Slices

1. Keep text inference stable through the local Ollama loopback path.
2. Stabilize native local ASR wake-word voice sessions, including the interruption word `Iris` while Iris is speaking.
3. Tune native Whisper capture/transcription quality if manual tests show missed wake words, delayed turns, or bad transcripts.
4. Stabilize Kokoro `af_heart` playback latency and interruption behavior in the manual test loop.
5. Add a narrow image-input probe path for the same Gemma model, without screen capture or system control.
6. Add the deferred barebones in-memory memory core from `docs/memory-core-phase1.md`.
7. Do not add system control, clipboard access, plugins, fallback models, or background network behavior.

## Deferred Memory Core

Memory is required, but it is not the current blocking milestone. The approved Phase 1 memory scope is stored in `docs/memory-core-phase1.md` and must remain a small in-memory, auditable, non-agentic core when implemented.
