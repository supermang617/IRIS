# Future Model Bootstrapping Plan

Status: design note only.

This is not implemented yet.

No runtime networking, model downloading, Hugging Face access, Ollama calls, LM Studio calls, llama.cpp bindings, hardware probing, or hardware telemetry should be added until explicitly approved.

## Default future model target

Default future model source:

- Hugging Face community GGUF builds by bartowski

Default future model variant:

- abliterated or uncensored Qwen-family GGUF builds

Default future format:

- GGUF

Default future backend category:

- local-only backend such as llama.cpp or another approved local runtime

Important:

- Do not assume every Qwen model is abliterated.
- Do not assume every bartowski GGUF build is appropriate.
- Exact repository names, filenames, licenses, quantization, hashes, and expected memory use must be verified before implementation.
- The default plan may change if quality, license, safety, or hardware testing shows a better model choice.

## Candidate model family

Project Iris currently plans around the Qwen model family because it has multiple practical size tiers.

Candidate size tiers:

- Micro / edge: 0.5B to 2B
- Mobile / standard desktop: 3B to 9B
- High-end local desktop: 14B to 35B

## Preferred quantization direction

Future GGUF targets should prioritize efficient quantization.

Preferred default quantization target:

- Q4_K_M

This may change after testing.

## Future dynamic hardware discovery

Potential future crate:

- iris-hardware

Purpose:

- read system memory
- read operating system
- detect dedicated VRAM when available
- choose a safe model profile
- avoid thermal-heavy defaults

This crate must remain read-only.

It must not require administrator privileges.

It must not run shell commands.

It must not spawn external processes.

It must not upload telemetry.

## Candidate routing matrix

| Hardware tier | Candidate model | Quantization | Notes |
|---|---|---|---|
| 16 GB+ VRAM or high unified memory | Qwen abliterated 14B class GGUF | Q4_K_M | High-end local desktop |
| 8 GB VRAM | Qwen abliterated 8B class GGUF | Q4_K_M | RTX 4060 class target |
| 4 GB VRAM or strong mobile | Qwen abliterated 4B class GGUF | Q4_K_M | Lightweight local assistant |
| Under 4 GB | Qwen abliterated 0.5B to 1.5B class GGUF | Q4_K_M | Edge/mobile fallback |

Exact model names, quantization, hashes, and download sources must be verified before implementation.

## Future model manifest

Potential future path:

~/.iris/models/

Potential manifest fields:

- model_id
- family
- variant
- parameter_size
- quantization
- filename
- sha256
- source
- source_repo
- license
- minimum_ram_gb
- minimum_vram_gb
- recommended_backend

## Future provisioning rule

Automatic model download must be opt-in.

Before any network access is implemented, Iris must require explicit approval.

The future download pipeline must:

- use trusted sources only
- verify SHA256 before use
- save only inside approved Iris model directories
- never execute downloaded files
- never upload telemetry
- never require user API keys for normal local use
- support manual model placement as the safest path

## Implementation order later

1. Add model manifest types.
2. Add read-only hardware profile types.
3. Add deterministic model routing table.
4. Add local model presence check.
5. Add hash verification.
6. Add explicit user-approved download mode.
7. Add real 127.0.0.1 local inference backend.
8. Add runtime tests.
9. Add manual user test command.

## Important boundary

Current Project Iris inference remains disabled stub behavior only.

Real local inference is not implemented yet.

Networking is not approved yet.

This document is a future plan, not current runtime behavior.
