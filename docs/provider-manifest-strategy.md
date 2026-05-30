# Provider Manifest Strategy

Status: active.

## Current provider

Ollama loopback runner for local development.

## Current active model

huihui_ai/qwen3.5-abliterated

## Unified one-to-one rule

For the current development target:

text_model_id = vision_model_id = active_model_id

This prevents Iris from loading multiple inference models at once.

## Capability ownership

Iris owns:

- context gating
- memory retrieval
- redaction
- provenance labeling
- evidence labeling
- response safety checks
- TTS routing
- ASR transcript routing

The model owns:

- local reasoning over bounded context
- text response generation
- image understanding when image payload support is validated

The model does not own:

- memory calls
- tool calls
- system actions
- file access
- computer control

