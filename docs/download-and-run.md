# Download and Run Iris

Produced by Alejandro Pinto.

Contact: super.mangmail@gmail.com

Project Iris is available as a portable Windows ZIP when a release asset named
`iris-windows.zip` is attached to a GitHub Release. The repository license covers
the source code, not third-party model files or downloaded assets.

## Prerequisites

- Windows 10 or Windows 11.
- Microsoft Edge WebView2 Runtime.
- Ollama running locally on `127.0.0.1:11434` with
  `huihui_ai/gemma-4-abliterated:e2b` available.
- Python is required only for Kokoro TTS helper use. The portable ZIP includes
  the Kokoro model and voice files, but Python packages such as `kokoro-onnx`
  and `soundfile` must be installed by the user if TTS helper execution is used.

Iris remains local-only. Runtime model traffic is restricted to local Ollama
loopback. Iris does not add computer automation, shell execution tools, browser
control, clipboard control, plugin execution, or external cloud/API calls.

## Download the Portable ZIP

1. Open the GitHub Release for `supermang617/IRIS`.
2. Download `iris-windows.zip` and `iris-windows.zip.sha256`.
3. Extract `iris-windows.zip` to a normal user folder, for example:

```powershell
Expand-Archive .\iris-windows.zip -DestinationPath "$env:USERPROFILE\Iris"
```

4. Portable ZIP integrity check:

```powershell
$expected = (Get-Content .\iris-windows.zip.sha256 -Raw).Split(" ")[0]
$actual = (Get-FileHash .\iris-windows.zip -Algorithm SHA256).Hash.ToLowerInvariant()
if ($expected -ne $actual) { throw "SHA256 mismatch" }
```

## Run Iris

First run the setup wizard:

```powershell
.\Iris Setup Wizard.bat
```

It checks Windows, RAM, disk space, WebView2, Ollama, the configured model,
Kokoro/Whisper assets, optional Python speech packages, and local-only policy.
It shows PASS/WARN/FAIL steps, official links, and copy/paste repair commands.
If you approve a repair, it can use allowlisted tools such as `winget`, `pip`,
or `ollama pull` to install/download the missing local prerequisite.

For a read-only check that never installs or downloads:

```powershell
.\Check Iris Preflight.bat
```

From the extracted folder:

```powershell
.\Start Iris.bat
```

To install from the extracted folder instead of staying portable:

```powershell
.\Install Iris.bat
```

For a non-destructive startup check:

```powershell
.\Start Iris.ps1 --self-check
```

The launcher fails clearly if bundled files such as `manifest.json`,
`bin\iris-runtime.exe`, `bin\iris-tauri.exe`, Kokoro assets, or Whisper assets
are missing.

## Included Runtime Files

- `Start Iris.bat` and `Start Iris.ps1`
- `Install Iris.bat` and `Install Iris.ps1`
- `Iris Setup Wizard.bat` and `Iris Setup Wizard.ps1`
- `Check Iris Preflight.bat` and `Iris Preflight.ps1`
- `bin\iris-runtime.exe`
- `bin\iris-tauri.exe`
- `manifest.json`
- `models\kokoro\kokoro-v1.0.onnx`
- `models\kokoro\voices-v1.0.bin`
- `models\whisper\ggml-tiny.en.bin`
- `tools\kokoro_tts.py`
- `profiles\iris_restricted.json`
- `capabilities\v0_1_capability_ledger.toml`
- user-facing docs, license, notice, security notes, known limitations, assets

## Source Checkout

Clone the public repository:

```powershell
git clone https://github.com/supermang617/IRIS.git
cd IRIS
```

Or use GitHub's **Code > Download ZIP** button, extract the ZIP, and open PowerShell in the extracted folder.

## Validate the Checkout

Run the repository checks before manual testing:

```powershell
cargo fmt --all -- --check
cargo build --workspace
cargo test --workspace
cargo clippy --workspace
cargo run -p xtask
cargo run -p iris-runtime -- --self-check
cargo run -p iris-runtime -- --dashboard-json
npm install
npm run test:voice
scripts\test_vision_text_diagnostics.ps1
scripts\test_release_model_e2e.ps1
scripts\iris_preflight_wizard.ps1
scripts\iris_setup_wizard.ps1 -NonInteractive
scripts\test_windows_installer.ps1
git diff --check
```

GitHub Actions also runs the lightweight bug checker on pushes and pull requests. It does not launch the desktop runtime, use a microphone, speak audio, access a camera, capture the screen, or call Ollama.

## Run Iris from Source

Console check:

```powershell
cargo run -p iris-runtime -- --ask "What can you do?"
```

Desktop shell:

```powershell
npm run dev
```

Manual Windows launcher from the repository root:

```powershell
.\Start Iris.vbs
```

Then follow `docs/manual-test.md`.

For public v0.1.1 release testing, use
`docs/public-launch-checklist-v0.1.1.md` and the GitHub manual tester issue
template.

## Contribution Boundary

Bug fixes, compatibility repairs, diagnostics fixes, documentation corrections, and safety-preserving tests are welcome. Do not add action tools, model switching, fallback models, external runtime network behavior, or broader feature changes without explicit approval from Alejandro.

## Architecture Notes

See `docs/iris-architecture.md` for the current Iris/Hermes/OneDrive boundary.
See `docs/windows-installer.md` for installer, shortcut, upgrade, and uninstall
behavior.
See `docs/signed-installer-decision.md` for the MSIX/App Installer signing
decision and current toolchain blockers.
See `docs/runtime-orchestration.md` for how Iris, Ollama, and Hermes should run
together during manual testing.
In v0.1, Iris can use local memory and restricted Hermes staging. OneDrive is
not an active live-memory sync feature yet; it is a future encrypted cold-archive
and restore direction.
