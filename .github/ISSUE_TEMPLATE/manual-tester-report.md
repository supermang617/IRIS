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
- Exact Python 3.13 installed: PASS / FAIL / BLOCKED
- Iris-owned voice layer audit: PASS / FAIL / BLOCKED
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
| `.\Start Iris.ps1 -SelfCheck` | PASS / FAIL / BLOCKED |  |
| `.\Start Iris.bat` desktop launch | PASS / FAIL / BLOCKED |  |
| Local Ollama text ask | PASS / FAIL / BLOCKED |  |
| Image probe | PASS / FAIL / BLOCKED |  |
| Voice/Kokoro speech | PASS / FAIL / BLOCKED |  |
| Speech interruption before playback | PASS / FAIL / BLOCKED |  |
| Speech interruption during playback | PASS / FAIL / BLOCKED |  |
| Hermes/local-only boundary | PASS / FAIL / BLOCKED |  |
| Shutdown/relaunch | PASS / FAIL / BLOCKED |  |

## Acoustic Interruption Matrix

Test the word `Iris`, `stop`, and `Iris stop` while Iris is speaking. Record
false self-interruptions as well as missed interruptions.

| Output / microphone setup | Volume | Distance | Result | False self-interruptions / latency notes |
| --- | --- | --- | --- | --- |
| Headset | 25% / 50% / 75% | normal | PASS / FAIL / BLOCKED |  |
| Laptop speakers + built-in mic | 25% / 50% / 75% | normal | PASS / FAIL / BLOCKED |  |
| External speakers + microphone | 25% / 50% / 75% | near / far | PASS / FAIL / BLOCKED |  |
| Noisy room | 25% / 50% / 75% | near / far | PASS / FAIL / BLOCKED |  |

Iris reports `aec=false` today. Do not record the acoustic matrix as fully
passed unless every tested configuration is named; near-field gating is not
the same as true acoustic echo cancellation.

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
