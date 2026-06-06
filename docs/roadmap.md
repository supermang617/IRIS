# Project Iris Roadmap

## Current Direction

Move fast on one Windows Iris prototype while keeping the public repository easy to test and safe to fix.

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
5. Keep image, camera, and screen-area probes narrow, one-shot, and evidence-only for the same Gemma model.
6. Keep the restricted Iris-owned memory broker and Hermes staging path disabled by default, fail-closed, and auditable.
7. Improve public download and contribution flow through source-first docs, minimal CI, and conservative notices.
8. Split `src-tauri/src/lib.rs` into behavior-preserving modules after the public baseline is stable.
9. Do not add system control, clipboard access, acting plugins, fallback models, or background network behavior.

## Implemented Memory Baseline

Memory is now present only as an Iris-owned local broker/staging foundation. Hermes may query approved memory, propose memory to staging, and perform restricted text-only web research through `iris_query_memory`, `iris_propose_memory`, and `iris_web_research`; it cannot write active memory, inspect raw memory files, access OneDrive, run commands, edit files, use the clipboard, control browsers/windows, or operate the computer.

OneDrive remains cold archive only. Archive paths must end with `.iris-memory-archive.enc`, export is unavailable until real encryption is implemented, and live JSON/SQLite memory stores must not be placed under OneDrive.
