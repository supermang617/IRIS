# Model Backend Strategy

Status: architectural clarification.

## Production target

The long-term Project Iris production inference backend is:

llama.cpp / GGUF

Reason:

- supports local GGUF model files
- supports quantized models
- works across Windows, macOS, Linux, and mobile-oriented builds
- avoids requiring users to install Ollama
- fits the one-download local-first product direction

## Current development bridge

The current Windows test backend is:

Ollama loopback at 127.0.0.1:11434

Ollama is used only as a development and smoke-test bridge.

It lets Iris test:

- ContextGate
- PromptBuilder
- selected local model behavior
- response post-check
- text response
- spoken response
- voice transcript routing

without compiling and packaging llama.cpp yet.

## Correct backend path

Current test path:

Iris -> 127.0.0.1 Ollama loopback -> selected Qwen model

Future desktop production path:

Iris -> packaged llama.cpp/GGUF backend -> local model file

Future mobile path:

Iris mobile app -> mobile-compatible llama.cpp/ggml backend -> small local model

## Mobile rule

Phone users should not need Ollama.

Mobile builds must eventually use a bundled or platform-integrated local inference backend.

The likely long-term direction is:

- iOS/macOS: llama.cpp/ggml with Apple acceleration where available
- Android: llama.cpp/ggml Android-compatible backend or equivalent local runtime

## Current selected test model

Selected Windows development model:

huihui_ai/qwen3.5-abliterated:9b:9b

This is not yet the final production packaging decision.

## Do not confuse

Ollama is not the final app runtime.

Ollama is a local developer bridge.

llama.cpp/GGUF remains the production target.





