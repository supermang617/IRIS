# First Text and Voice Milestone

Status: validation command added.

Milestone target:

- typed prompt to Iris
- explicit one-shot voice input to Iris
- local model response through Ollama loopback
- response post-check before output
- text response printed
- checked response spoken locally

Safety boundary:

- no mouse control
- no keyboard control
- no clipboard access
- no shell execution inside Iris runtime
- no browser automation
- no autonomous computer use
- no always-listening mode

Primary validation command:

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify_iris_text_voice_milestone.ps1

Current selected model:

qwen3-vl:4b

