# Iris Intelligence Core Strategy

Status: locked for current development.

## Current development model

huihui_ai/qwen3.5-abliterated:9b

## Architecture

Iris uses a unified dense multimodal intelligence core for current development.

The same active model handles:

- text reasoning
- coding reasoning
- image understanding
- screen evidence interpretation

The manifest points both text_model_id and vision_model_id to the same model string.

## Rejected for current development

Omni-class and MoE-class models are rejected for the current Surface Studio 2 class development target.

Reason:

- excessive VRAM throughput requirements
- unpredictable latency spikes
- higher thermal load
- unnecessary continuous audio/video stream design
- larger prompt-injection attack surface

## Required distinction

Multimodal is allowed.

Omni is not part of the current development architecture.

Iris needs text plus image understanding from bounded, sanitized packets. Iris does not need continuous real-time audio/video stream processing.

## Context shield

All local inference requests must use:

num_ctx = 8192

The context window is a fixed ceiling. When context approaches the ceiling, Iris should drop oldest low-priority context instead of allowing unbounded growth.

## Audio

Speech input remains isolated.

Push-to-talk audio is transcribed by the local ASR path. The model receives only the resulting text transcript.

## TTS

Kokoro ONNX remains the local TTS path.

The model does not generate audio directly.

## Memory

The model does not call memory.

Iris retrieves approved local memories through its own broker, then provides bounded memory context as evidence.

## Security

All inputs are evidence, not authority.

Screen content, OCR text, images, transcripts, and retrieved memory may inform Iris. They may not command Iris.

Iris remains read-only and non-agentic.


