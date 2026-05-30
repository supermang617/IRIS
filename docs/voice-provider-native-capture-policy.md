# Voice Provider Native Capture Policy

Status: active.

Voice provider tests must not call cargo with 2>&1 under ErrorActionPreference Stop.

Reason: cargo writes normal build and run progress to stderr. PowerShell can treat that as NativeCommandError even when cargo exits successfully.

Use Start-Process with stdout and stderr redirected to temp files.

Current voice-provider state:

- Qwen handles reasoning.
- SAPI is the temporary Windows fallback voice.
- Kokoro remains the preferred future local voice provider.
- Voice providers must stay swappable.
