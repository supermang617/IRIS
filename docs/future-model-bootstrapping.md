# Future Model Bootstrapping Plan

Status: design note plus selected local test target.

No runtime model downloading happens by default.

## Selected local test target

Default local test model:

huihui_ai/qwen3.5-abliterated:9b

This is the selected Ollama model tag for the user's first local-thinking test path.

## Current boundary

Project Iris runtime remains disabled-stub by default.

Real model calls happen only through explicit test commands:

- cargo run -p iris-runtime -- ollama-test <model> "prompt"
- scripts/test_iris_ollama_loopback.ps1
- scripts/setup_iris_qwen_vl_ollama.ps1

## Model family

The selected target is a Qwen2.5-VL 3B abliterated/uncensored vision-language model variant.

## Backend

Initial backend:

- Ollama loopback
- endpoint: 127.0.0.1:11434

## Not implemented by default

- automatic model download during normal runtime
- Hugging Face direct download inside Iris runtime
- default real inference path
- vision input pipeline
- OCR pipeline
- screen capture
- voice
- TTS

## Safety rule

The selected model may be used for local testing, but Iris must remain read-only and non-agentic.

Iris may respond.

Iris may not act on the computer.




