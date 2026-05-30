# Chat Local Routing Policy

Status: active.

The chat-local command must use the same bounded local response path as HUD.

Reason: HUD already validates addressee intent, deictic ownership, bounded local model use, and post-check behavior.

chat-local must not maintain a separate raw Ollama parser unless that parser has its own tests.

Provider rule: model, STT, TTS, vision, memory, and UI transport should stay swappable behind stable interfaces.
