# Voice Contract Health Guard

Status: active.

This guard prevents the recurring voice-script failure class.

It checks:

- all voice PowerShell scripts parse cleanly
- nested PowerShell calls use AnchorWordsCsv
- raw repeated AnchorWords calls are not used
- Kokoro provider resolution works
- optional deterministic simulated voice-to-Kokoro no-play milestone works

Run:

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify_iris_voice_contract_health.ps1 -RunSimulatedMilestone

Live microphone recognition is intentionally separate. If deterministic simulation passes but live mic fails, calibrate Windows microphone input instead of rewriting scripts again.
