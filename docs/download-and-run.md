# Download and Run Iris

Produced by Alejandro Pinto.

Contact: super.mangmail@gmail.com

Project Iris is published source-first. The repository license covers the source code, not third-party model files or downloaded assets.

## Prerequisites

- Windows 10 or Windows 11.
- Git, Rust/Cargo, Node.js/npm, and WebView2 Runtime.
- Ollama running locally with `huihui_ai/gemma-4-abliterated:e2b` available.
- Python for the Kokoro helper, with `kokoro-onnx` and `soundfile` installed.
- Local ASR and TTS assets under `models/`, including `models/whisper/ggml-tiny.en.bin` and the Kokoro assets declared in `manifest.json`.
- `libclang` available for `whisper-rs` builds. The local developer checkout pins `LIBCLANG_PATH` in `.cargo/config.toml`; other machines may need to set that path to their own LLVM or Python clang package.

## Get the Source

Clone the public repository:

```powershell
git clone https://github.com/supermang617/IRIS.git
cd IRIS
```

Or use GitHub's **Code > Download ZIP** button, extract the ZIP, and open PowerShell in the extracted folder.

## Validate the Checkout

Run the repository checks before manual testing:

```powershell
cargo fmt --all -- --check
cargo build --workspace
cargo test --workspace
cargo clippy --workspace
cargo run -p xtask
cargo run -p iris-runtime -- --self-check
cargo run -p iris-runtime -- --dashboard-json
npm install
npm run test:voice
git diff --check
```

GitHub Actions also runs the lightweight bug checker on pushes and pull requests. It does not launch the desktop runtime, use a microphone, speak audio, access a camera, capture the screen, or call Ollama.

## Run Iris

Console check:

```powershell
cargo run -p iris-runtime -- --ask "What can you do?"
```

Desktop shell:

```powershell
npm run dev
```

Manual Windows launcher from the repository root:

```powershell
.\Start Iris.vbs
```

Then follow `docs/manual-test.md`.

## Contribution Boundary

Bug fixes, compatibility repairs, diagnostics fixes, documentation corrections, and safety-preserving tests are welcome. Do not add action tools, model switching, fallback models, external runtime network behavior, or broader feature changes without explicit approval from Alejandro.
