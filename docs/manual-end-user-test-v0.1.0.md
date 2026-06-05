# Iris v0.1.0 Manual End-User Test Report

Produced by Alejandro Pinto.

Contact: super.mangmail@gmail.com

This report captures the latest Windows end-user test from the uploaded GitHub
Release assets. It is written for testers who are new to GitHub and want to know
what should work before filing a bug.

## Source Tested

- Release tag: `v0.1.0`
- Repository: `https://github.com/supermang617/IRIS`
- Downloaded assets: `iris-windows.zip`, `iris-windows.zip.sha256`,
  `install-iris-windows.ps1`, `install-iris-windows.ps1.sha256`,
  `iris-windows.msix`, `iris-windows.msix.sha256`,
  `iris-msix-signing.cer`, and `iris-msix-signing.cer.sha256`
- Clean extraction folder:
  `%TEMP%\iris-manual-release-03578418fa644b5a8d9a05e25cc887b8`

## Results

- PASS: Uploaded release assets downloaded from GitHub.
- PASS: ZIP SHA256 verification passed.
- PASS: Public installer wrapper installed Iris to
  `%LOCALAPPDATA%\Programs\Iris`.
- PASS: Installer now exits cleanly after a successful setup run.
- PASS: Start Menu and Desktop shortcuts were created.
- PASS: Installed setup wizard completed in non-interactive mode.
- PASS: Installed desktop shell launched `iris-tauri.exe`.
- PASS: Launch did not create any new non-loopback listeners.
- PASS: Installed text ask returned a local Ollama response.
- PASS: Kokoro assets and Python voice packages were detected by preflight.
- PASS: Ollama `/api/show` reports the configured model has `vision`
  capability.
- PASS: Image probe identified a known red-circle fixture.
- PASS: Hermes remains gated by default and should not be opened separately.
- PASS: Local self-signed MSIX signature validation passed on the test machine.
- BLOCKED: Document-image/OCR probing is not reliable on the configured model.

Capability note: Ollama `/api/tags` may omit `vision` for
`huihui_ai/gemma-4-abliterated:e2b`, but `ollama show` and `/api/show` report
`completion`, `vision`, `audio`, `tools`, and `thinking`. Iris preflight uses
`/api/show` for this check.

Document-image note: direct Ollama image calls and Iris runtime image probes
both failed simple OCR fixtures such as `ALPHA 742`. The model can inspect
images, but the document-image milestone should stay blocked until a local model
or prompt path reliably reads known document fixtures.

## Beginner Manual Test Checklist

1. Download `iris-windows.zip`, `iris-windows.zip.sha256`,
   `install-iris-windows.ps1`, and `install-iris-windows.ps1.sha256` from the
   GitHub Release.
2. Put those four files in one folder, such as `Downloads\Iris`.
3. Right-click the folder background, choose "Open in Terminal", and run:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install-iris-windows.ps1 -SourceZip .\iris-windows.zip -Sha256Path .\iris-windows.zip.sha256 -RunSetup -SetupNonInteractive
   ```

4. Confirm the installer says Iris was installed to
   `%LOCALAPPDATA%\Programs\Iris`.
5. Open "Iris Setup Wizard" from the Start Menu and confirm each item is PASS or
   an understandable WARN.
6. Open "Iris" from the Start Menu or Desktop shortcut.
7. Confirm the desktop window opens.
8. From a terminal, test text:

   ```powershell
   & "$env:LOCALAPPDATA\Programs\Iris\bin\iris-runtime.exe" --ask "In one sentence, say what Iris can do right now."
   ```

9. From a terminal, test self-check:

   ```powershell
   & "$env:LOCALAPPDATA\Programs\Iris\Start Iris.ps1" --self-check
   ```

10. From a terminal, test the runtime dashboard status:

    ```powershell
    & "$env:LOCALAPPDATA\Programs\Iris\bin\iris-runtime.exe" --dashboard-json
    ```

    Hermes should remain disabled unless explicitly enabled from the Iris desktop
    shell; it should not expose acting tools.

11. Mark image probe as passing only when the setup wizard reports the
    configured Ollama model has `vision` capability and known local test images
    are described correctly.

## Hermes Runtime Shape

Hermes should not be opened separately by a beginner tester. It is a hidden,
Iris-owned sidecar that starts only when Iris gates are explicitly enabled. Iris
owns the final response path, the memory broker, and safety audit. Ollama may
run in the background because it is the local model service.

## Bug Reports

When filing a bug, include:

- Windows version.
- RAM amount.
- Whether Ollama is running.
- Output from `ollama list`.
- Output from "Iris Setup Wizard".
- The exact command that failed.
- Any Iris diagnostics/log files from the installed folder.
