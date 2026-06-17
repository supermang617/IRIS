# Windows Iris Shell

Iris is no longer tracking the cross-platform Adaptive Shell plan in this workspace.

The current build is a focused Windows v1 release with:

- one configured model: `huihui_ai/gemma-4-abliterated:e2b`
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

The Tauri shell consumes the same contract and presents a compact desktop
assistant surface:

- response content above the prompt composer;
- a multiline composer with Enter to send and Shift+Enter for a new line;
- compact attachment, camera, screen, memory, microphone, and Panic Stop icons
  along the bottom edge of the composer;
- a pointer- and keyboard-accessible divider for resizing the response pane;
- one translucent window backdrop with low-opacity content layers for stable
  Windows performance.

Typed input and native ASR transcripts are gated before they are sent to the
configured local model.
