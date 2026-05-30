# Iris v0.1 Roadmap

Status: project tracking document.

## Core invariant

Iris may see, listen when explicitly invoked, think, remember with permission, and respond.

Iris may not act on the computer.

Iris is a trustworthy local interpreter, not a computer-use agent.

## Current near-term milestone

The first practical milestone is:

- user can type to Iris
- user can speak to Iris through an explicit test path
- Iris can answer with local model text
- Iris can answer with local speech output
- all of this remains read-only and local-first

## Current completed foundation

Implemented or scaffolded:

- workspace
- iris-core-types
- iris-paths
- iris-policy
- iris-redaction
- iris-context-gate
- iris-cognition
- iris-local-inference
- iris-model-manifest
- iris-model-router
- iris-model-store
- iris-prompt
- iris-runtime
- xtask audit
- capability ledger
- selected Qwen2.5-VL abliterated Ollama target
- prompt preview
- ask mode
- ask-local mode
- chat-local mode
- local Ollama loopback test mode
- safety verification scripts

## Current selected local model

Selected test model:

qwen3-vl:4b

This model is used only through explicit local test commands.

Default runtime remains disabled stub unless a local test mode is explicitly invoked.

## Immediate next build order

1. Panic Stop skeleton
2. Cancellation-aware runtime state
3. Response post-check
4. Unsupported-action classifier
5. Local TTS helper hardening
6. Voice input test path
7. PTT-style voice command
8. ASR transcript through ContextGate
9. Text plus voice response milestone

## Later v0.1 build order

After the first text/voice response milestone:

1. Minimal HUD
2. Dashboard safety page
3. Screen observation
4. OCR scene packets
5. Screen prompt-injection fixtures
6. Redaction fixtures
7. Memory proposal flow
8. Governor
9. Full dashboard
10. Red-team suite
11. Dogfooding

## Voice milestone requirements

Voice must remain explicit.

No always-listening mode.

The target path is:

Push-to-talk or explicit voice trigger
-> local ASR transcript
-> ContextGate
-> PromptBuilder
-> local model
-> text response
-> local TTS response

Panic Stop must cancel ASR and TTS.

## Runtime forbidden capabilities

Do not add:

- mouse movement
- mouse clicking
- keyboard simulation
- typing into other applications
- clipboard read
- clipboard write
- shell execution
- arbitrary process spawning
- browser automation
- plugins
- scripting runtimes
- accessibility-tree control
- window manipulation
- autonomous computer use

## Current allowed loopback exception

Only explicit local model test paths may call Ollama through:

127.0.0.1:11434

This is not the default runtime path.

## Next planned command

Add Panic Stop skeleton before adding more voice or TTS behavior.

