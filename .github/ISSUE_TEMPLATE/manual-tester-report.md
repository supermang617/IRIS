---
name: Iris v0.1.1 manual tester report
about: Report a manual test result from the Iris v0.1.1 portable Windows release
title: "[v0.1.1 manual test] "
labels: bug, manual-test
assignees: ""
---

## Release

- Release URL: https://github.com/supermang617/IRIS/releases/tag/v0.1.1
- ZIP SHA256: `15a9e17aa89deadd3561b1a41068295288034851de06124e9cb4880a1d0fcfad`
- Did the downloaded ZIP match `iris-windows.zip.sha256`? PASS / FAIL / BLOCKED

## Environment

- Windows version:
- Install location or clean extract folder:
- WebView2 installed: PASS / FAIL / BLOCKED
- Ollama installed: PASS / FAIL / BLOCKED
- Ollama reachable on `127.0.0.1:11434`: PASS / FAIL / BLOCKED
- `huihui_ai/gemma-4-abliterated:e2b` available: PASS / FAIL / BLOCKED
- Python installed: PASS / FAIL / BLOCKED
- `kokoro_onnx` importable: PASS / FAIL / BLOCKED
- `soundfile` importable: PASS / FAIL / BLOCKED
- Microphone available: PASS / FAIL / BLOCKED
- Speakers available: PASS / FAIL / BLOCKED
- Camera available: PASS / FAIL / BLOCKED

## Checklist Results

| Check | Result | Notes |
| --- | --- | --- |
| SHA verification | PASS / FAIL / BLOCKED |  |
| Extracted files present | PASS / FAIL / BLOCKED |  |
| `.\Check Iris Preflight.bat` | PASS / FAIL / BLOCKED |  |
| `.\Iris Setup Wizard.bat` | PASS / FAIL / BLOCKED |  |
| `.\Start Iris.ps1 --self-check` | PASS / FAIL / BLOCKED |  |
| `.\Start Iris.bat` desktop launch | PASS / FAIL / BLOCKED |  |
| Local Ollama text ask | PASS / FAIL / BLOCKED |  |
| Image probe | PASS / FAIL / BLOCKED |  |
| Voice/Kokoro speech | PASS / FAIL / BLOCKED |  |
| Hermes/local-only boundary | PASS / FAIL / BLOCKED |  |
| Shutdown/relaunch | PASS / FAIL / BLOCKED |  |

## Failure Details

- Failed checklist row:
- Exact command or action:
- Visible error text:

```text
paste error text here
```

- Screenshot or short description:
- Did Iris require a cloud API, telemetry, non-loopback service, secret, browser automation, shell execution, clipboard control, or computer control? YES / NO

## Notes

Iris v0.1.1 is local-first and non-agentic. Missing cloud login, telemetry,
browser automation, shell execution, clipboard control, and computer control are
intentional absences, not release blockers.
