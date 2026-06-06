# Iris v0.1.1 Manual Tester Checklist

Use this checklist from a clean folder, not from a development checkout.

## Download

1. Open the GitHub Release for `v0.1.1`.
2. Download only these assets:
   - `iris-windows.zip`
   - `iris-windows.zip.sha256`
3. Put both files in a clean folder such as:

```powershell
$testRoot = Join-Path $env:TEMP "iris-v0.1.1-manual-test"
New-Item -ItemType Directory -Force -Path $testRoot | Out-Null
```

If a `v0.1.1` GitHub Release has not been published yet, use
`release\dist\iris-windows.zip` and `release\dist\iris-windows.zip.sha256`
created by `scripts\package_windows_release.ps1`.

## Verify and Extract

```powershell
$expected = (Get-Content .\iris-windows.zip.sha256 -Raw).Split(" ")[0]
$actual = (Get-FileHash .\iris-windows.zip -Algorithm SHA256).Hash.ToLowerInvariant()
if ($expected -ne $actual) { throw "SHA256 mismatch" }
Expand-Archive .\iris-windows.zip -DestinationPath .\iris -Force
Set-Location .\iris
```

Expected result: the hash matches and the extracted folder contains
`Start Iris.bat`, `Start Iris.ps1`, `Iris Setup Wizard.bat`,
`Check Iris Preflight.bat`, `bin\iris-runtime.exe`, `bin\iris-tauri.exe`,
`manifest.json`, `models`, `profiles`, `capabilities`, `assets`, and `docs`.

## Prerequisites

Expected local prerequisites:

- Windows 10 or Windows 11.
- Microsoft Edge WebView2 Runtime.
- Ollama running on `127.0.0.1:11434` with `huihui_ai/gemma-4-abliterated:e2b`.
- Python plus `kokoro-onnx` and `soundfile` only when testing the Kokoro helper.

Iris must not require cloud APIs, telemetry, non-loopback service binding, or
unexpected secrets.

## Test Steps

Record `PASS`, `FAIL`, or `BLOCKED` for each row.

| Check | Command or action | Expected result | Result | Notes |
| --- | --- | --- | --- | --- |
| Preflight | `.\Check Iris Preflight.bat` | Reports local prerequisite status without installing or downloading. |  |  |
| Setup wizard | `.\Iris Setup Wizard.bat` | Shows setup status and repair guidance; no unexpected external service is required. |  |  |
| Runtime self-check | `.\Start Iris.ps1 --self-check` | Prints Iris startup and safety status; exits successfully. |  |  |
| Ollama text ask | `.\bin\iris-runtime.exe --ask "What can you do right now?"` | Uses local Ollama loopback or reports the local model prerequisite clearly. |  |  |
| Image probe | `.\bin\iris-runtime.exe --image-probe <local-image> "What is in this image?"` | Uses the configured local vision path or reports a clear local prerequisite blocker. |  |  |
| Desktop launch | `.\Start Iris.bat` | Opens the Iris desktop window. |  |  |
| Voice test | Type a short prompt and listen. | Iris responds and attempts local Kokoro speech. |  |  |
| Kokoro path | Verify `tools\kokoro_tts.py` and bundled Kokoro files exist. | Kokoro model, voice file, and helper are present. |  |  |
| Hermes status | Run `.\bin\iris-runtime.exe --dashboard-json`. | Hermes is enabled as an Iris-owned sandboxed research/RAG helper and exposes no acting tools. |  |  |
| Local-only binding | While Iris is open, inspect listening ports. | No new non-loopback listener is introduced by Iris. |  |  |
| Shutdown and relaunch | Close Iris, then run `.\Start Iris.bat` again. | Iris closes cleanly and reopens. |  |  |

## Bug Report

Send:

- Windows version.
- Exact Iris release tag and ZIP SHA256.
- Which checklist row failed.
- The command used.
- The visible error text.
- Whether Ollama, WebView2, Python, Kokoro packages, camera, microphone, and
  speakers were available.

Contact: super.mangmail@gmail.com
