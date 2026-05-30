# Model Runtime Strategy

Status: locked for current development.

## Current runner

Ollama is the current development runner.

Ollama is not the final Iris product identity.

## Current model

huihui_ai/qwen3.5-abliterated:9b

## Current architecture

Unified dense multimodal model.

One active inference model at a time.

## Manifest rule

Model strings must live in local config files.

Runtime code must not hardcode the selected model.

## Current context clamp

8192 tokens.

## Future model updates

Future model swaps happen by changing the manifest and rerunning validation.

Any attempt to move to Omni-class or MoE-class models requires formal hardware re-validation and is considered non-compliant for the current 8GB VRAM development target unless explicitly approved later.
