# Windows Iris Shell

Iris is no longer tracking the cross-platform Adaptive Shell plan in this workspace.

The current build is a slim Windows prototype with:

- one configured model: `qwen3.5:9b`
- one provider boundary: `ollama_local`
- one context ceiling: `8192`
- no fallback model selection
- no model downloads
- no background network behavior
- typed text inference through loopback-only Ollama
- future image input through the same configured vision-capable model
- native local Whisper ASR feeding the same text path
- Kokoro `af_heart` speech output

The dashboard contract is available through:

```powershell
cargo run -p iris-runtime -- --dashboard-json
```

The Tauri shell consumes the same contract and shows the compact Iris input/output console. Typed input and native ASR transcripts are gated before they are sent to the configured local model.
