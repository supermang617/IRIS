# Iris Model Runtime Strategy

Status: locked planning direction.

## Core rule

Iris is a thin, local-first assistant shell.

The Iris binary must not contain model weights.

Iris must not be hardcoded to one model family, one runner, or one vendor.

## Current development runner

Ollama is allowed as the current development runner.

Ollama is not the final product identity.

## Current selected development model

qwen3-vl:4b

## Preferred model family

Qwen is the preferred current model family because it has strong local text and multimodal direction.

Qwen is not mandatory. Iris must remain model-agnostic.

## Provider boundary

Iris core talks to a provider boundary:

Iris runtime
-> local inference provider
-> selected local runner
-> selected model

## Current voice decision

Keep the current verified voice stack:

- ASR: current local transcription path for push-to-talk testing
- TTS: Kokoro ONNX

Do not replace Kokoro or ASR with Qwen Omni until a local candidate proves it is smaller, faster, stable, packageable, and safe.

## Runtime safety

The Iris runtime remains read-only.

No shell execution.
No arbitrary process execution.
No clipboard.
No input simulation.
No plugins.
No runtime network.
No computer-use agent behavior.
