---
name: Iris Windows release manual tester report
about: Report a manual test result from the latest Iris Windows release
title: "[Windows release manual test] "
labels: bug, manual-test
assignees: ""
---

## Release

- Release URL: https://github.com/supermang617/IRIS/releases/latest
- Release tag:
- Download used: beginner installer / portable ZIP
- Did the downloaded asset match its `.sha256` file? PASS / FAIL / BLOCKED

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
| `Install Iris.bat` beginner flow | PASS / FAIL / BLOCKED |  |
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
- Did Iris require a cloud model API, telemetry, non-loopback service, or
  clipboard control? YES / NO
- Did Agentic file, browser, or PowerShell behavior occur without an approved
  Agentic Session? YES / NO

## Notes

Iris is local-first. Safe mode remains non-agentic. Agentic file, browser,
PowerShell, and process work is available only in an explicitly approved,
expiring session with additional confirmation for high-risk actions.
