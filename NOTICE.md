# Notices and Credits

Produced by Alejandro Pinto.

Contact: super.mangmail@gmail.com

Project Iris is built on local-first, open tooling and local model infrastructure. This notice is not a substitute for reviewing each dependency license before redistribution.

## Core Tooling and Libraries

- Rust and Cargo.
- Tauri.
- Node.js/npm and the Node.js test runner for frontend state tests.
- GitHub Actions for public bug-check CI.
- Ollama for local model serving.
- Kokoro ONNX TTS assets and the Python `kokoro-onnx` helper path.
- Whisper local ASR model/runtime.
- Rust crates listed in `Cargo.lock`.
- JavaScript packages listed in `package-lock.json`.

## Model and Asset Notice

The configured local Ollama model identity is `huihui_ai/gemma-4-abliterated:e2b`. Ollama model blobs are not checked into this repository. Confirm the model license and redistribution terms before publishing model files, screenshots, recordings, demos, or packaged builds that include model artifacts.

Kokoro and Whisper model files under `models/` may have their own license terms. Confirm those terms before redistributing assets.

## Repository License

Repository source code is licensed under the license file in this repository. Third-party dependencies, models, and assets remain governed by their own licenses.
