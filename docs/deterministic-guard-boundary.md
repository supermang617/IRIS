# Deterministic Guard Boundary

Status: active.

The foundation guard must be deterministic.

It checks build health, runtime safety, model config, addressee intent, deictic ownership, and xtask audit.

It must not depend on live model wording, Kokoro playback, microphone input, HUD timing, or diagnostic dry-run state.

Live voice/text smoke checks are separate and manual:

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\smoke_iris_live_voice_text_manual.ps1

The voice/text milestone guard is a preflight gate. It proves the repo is safe to move into the next milestone.

Next milestone: open back-and-forth typed and spoken conversation.
