# Iris v0.1.1 Public Launch Checklist

Use this checklist before sending Iris to a manual tester.

## Release

- Release URL: https://github.com/supermang617/IRIS/releases/tag/v0.1.1
- Required assets:
  - `iris-windows.zip`
  - `iris-windows.zip.sha256`
- ZIP SHA256:
  `15a9e17aa89deadd3561b1a41068295288034851de06124e9cb4880a1d0fcfad`

## Beginner Steps

1. Download `iris-windows.zip` and `iris-windows.zip.sha256`.
2. Put both files in a clean folder.
3. Verify the ZIP:

```powershell
$expected = (Get-Content .\iris-windows.zip.sha256 -Raw).Split(" ")[0]
$actual = (Get-FileHash .\iris-windows.zip -Algorithm SHA256).Hash.ToLowerInvariant()
if ($expected -ne $actual) { throw "SHA256 mismatch" }
```

4. Extract the ZIP:

```powershell
Expand-Archive .\iris-windows.zip -DestinationPath .\iris -Force
Set-Location .\iris
```

5. Run setup and start Iris:

```powershell
.\Iris Setup Wizard.bat
.\Start Iris.bat
```

## Prerequisites

Mark each item `PASS`, `FAIL`, or `BLOCKED`.

| Check | Expected result | Result | Notes |
| --- | --- | --- | --- |
| Windows | Windows 10 or Windows 11. |  |  |
| WebView2 | Microsoft Edge WebView2 Runtime is installed. |  |  |
| Ollama | Ollama is installed and reachable on `127.0.0.1:11434`. |  |  |
| Model | `huihui_ai/gemma-4-abliterated:e2b` is available in Ollama. |  |  |
| Kokoro optional speech | Python can import `kokoro_onnx` and `soundfile` when speech is tested. |  |  |
| Local-only boundary | No cloud API, telemetry, non-loopback binding, or secret is required. |  |  |

## Manual Test Results

Mark each item `PASS`, `FAIL`, or `BLOCKED`.

| Check | Expected result | Result | Notes |
| --- | --- | --- | --- |
| SHA verification | ZIP hash matches `iris-windows.zip.sha256`. |  |  |
| Extracted files | Launchers, docs, configs, models, profiles, and capabilities are present. |  |  |
| Preflight | `.\Check Iris Preflight.bat` reports prerequisites without installing or downloading. |  |  |
| Setup wizard | `.\Iris Setup Wizard.bat` reports setup status and clear repair guidance. |  |  |
| Self-check | `.\Start Iris.ps1 --self-check` exits successfully. |  |  |
| Desktop launch | `.\Start Iris.bat` opens the Iris desktop window. |  |  |
| Text ask | Iris answers through local Ollama or reports the local prerequisite clearly. |  |  |
| Image probe | Iris handles a local image prompt or reports the local prerequisite clearly. |  |  |
| Voice | Kokoro speech works when optional speech prerequisites are installed. |  |  |
| Hermes boundary | Dashboard JSON shows Hermes enabled as an Iris-owned sandboxed research/RAG helper with no acting tools. |  |  |
| Shutdown/relaunch | Iris closes and opens again cleanly. |  |  |

## Bug Report Format

Use the manual tester issue template when filing a report. Include:

- Release URL and ZIP SHA256.
- Windows version.
- Which checklist row failed.
- Exact command or action.
- Visible error text or screenshot.
- Prerequisite status for WebView2, Ollama, model, Python, Kokoro packages,
  microphone, speakers, and camera.
- Whether the failure happened from the clean extracted ZIP or a development
  checkout.

Iris v0.1.1 remains local-first and Safe mode remains non-agentic. Do not report
missing cloud login, telemetry, clipboard control, mouse/keyboard control, or
general window control as release blockers. Agentic file, PowerShell, process,
and isolated browser work is intentionally available only after an explicit
session approval.
