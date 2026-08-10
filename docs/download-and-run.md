# Download and Run Iris

Produced by Alejandro Pinto.

Contact: super.mangmail@gmail.com

Project Iris is distributed through GitHub Releases. The recommended beginner
download is `iris-windows-installer.zip`. The portable `iris-windows.zip`
remains available for advanced/manual use. The repository license covers the
source code, not third-party model files or downloaded assets.

## Prerequisites

- Windows 10 or Windows 11.
- Microsoft Edge WebView2 Runtime.
- Ollama running locally on `127.0.0.1:11434` with
  `huihui_ai/gemma-4-abliterated:e2b` available.
- Exact Python 3.13 is required for the pinned Hermes Agent and image-provider
  packages included in the Iris release, and for Python-backed Kokoro helper
  use. The portable ZIP includes the pinned package tree plus Kokoro model and
  voice files; the setup wizard verifies the compatible interpreter.
- Tesseract OCR is required only for document-image OCR. Iris uses it locally
  for explicit user-selected document images and treats OCR text as untrusted
  evidence.

Model traffic remains local to Ollama loopback. Safe mode does not act.
An explicitly approved Agentic Session can use the packaged Hermes file,
PowerShell, process, and isolated browser tools. High-risk actions require
separate confirmation, the browser uses an isolated, nonpersistent Iris session, and clipboard,
mouse, keyboard, general window control, arbitrary plugins, and cloud model APIs
remain unavailable.

Dynamic system context is local and enabled by default. Enter `dynamic context`
for status, or use `dynamic context off`, `dynamic context on`, and
`dynamic context reset` for control. The profile stores aggregate metrics only,
not prompt or attachment text.

## Beginner Install

1. Open the [latest Iris release](https://github.com/supermang617/IRIS/releases/latest).
2. Download `iris-windows-installer.zip`.
3. Extract the ZIP.
4. Double-click `Install Iris.bat`.
5. Follow the setup wizard. Approve only the prerequisite repairs you want it
   to perform.

The beginner bundle contains the Iris payload ZIP, its SHA256 file, the
installer, and a double-click launcher. The installer verifies the payload
before copying anything, installs Iris for the current user under
`%LOCALAPPDATA%\Programs\Iris`, creates Desktop and Start Menu shortcuts, runs
the setup wizard, performs a live self-check, and opens Iris after success.

Windows may display a SmartScreen warning because the current PowerShell/Batch
installer is not code-signed. Do not bypass a publisher warning unless the
files came from the official `supermang617/IRIS` GitHub release and the release
checks have passed.

## WinGet Availability

The planned package identifier is `AlejandroPinto.Iris`. These commands become
the preferred install and upgrade path only after a production-signed package
is accepted into Microsoft's public WinGet catalog:

```powershell
winget install --id AlejandroPinto.Iris -e
winget upgrade --id AlejandroPinto.Iris -e
```

If `winget show --id AlejandroPinto.Iris -e` reports no package, Iris has not
yet completed that external catalog review; use the verified GitHub bundle
above. Repository-generated manifests alone do not make the command public.

On a fresh WinGet install, complete the explicit local model setup shown in the
package notes, then launch Iris from the Windows Start menu:

```powershell
ollama pull huihui_ai/gemma-4-abliterated:e2b
```

The first production WinGet-compatible Iris release uses immutable semantic
tag `v1.0.0`; later releases increment it. Rust is not an end-user dependency. Hermes' pinned packages ship with
Iris and use WinGet-managed Python 3.13, llama inference ships with Ollama, and
the selected Ollama model remains an explicit first-run download rather than a
WinGet payload.

## Portable/Advanced Download

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

## Portable Setup And Run

First run the setup wizard:

```powershell
.\Iris Setup Wizard.bat
```

It checks Windows, RAM, disk space, WebView2, Ollama, the configured model,
Tesseract OCR, Kokoro/Whisper assets, exact Python 3.13, the Iris-owned
hash-locked voice package layer, and local-only policy. It shows
PASS/WARN/FAIL steps, official links, and
copy/paste repair commands. If you approve a repair, it can use allowlisted
tools such as `winget` or `ollama pull` to install/download the missing local
prerequisite. A damaged Iris-owned Python package layer is repaired by updating
or reinstalling Iris, not by changing global Python packages.

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

After installation, use the `Iris` Desktop or Start Menu shortcut. It launches
the GUI directly without opening a command prompt; Ollama and voice warm-up run
behind the visible Iris window.

Installed memories, generated images, and settings use
`%LOCALAPPDATA%\Iris\.iris-data`; diagnostics use
`%LOCALAPPDATA%\Iris\diagnostics`. Both are separate from application binaries. The installer
preserves missing files from older install-root `.iris-data` and `diagnostics`
folders without deleting the originals.

A developer source checkout (detected by its `.git` entry) keeps the historical
repo-local `.iris-data` and `diagnostics` layout. An explicit `IRIS_DATA_ROOT`
always wins. Extracted portable and installed builds default to
`%LOCALAPPDATA%\Iris`.

The launcher applies measured local defaults without replacing an existing
process, CurrentUser, or machine override. On first run it persists
`OLLAMA_FLASH_ATTENTION=1` and `OLLAMA_KV_CACHE_TYPE=q8_0` for the current user
so the separately running Ollama server can inherit them. If Ollama was already
running when those values were first initialized, Iris restarts that server
once to apply them. `OLLAMA_NUM_PARALLEL=1` and
`OLLAMA_MAX_LOADED_MODELS=1` remain process-only so Iris does not globally
restrict other Ollama clients.

For a non-destructive startup check:

```powershell
.\Start Iris.ps1 -SelfCheck
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
- `tools\iris_image_provider.py`
- `profiles\iris_restricted.json`
- `profiles\iris_agentic.json`
- `.iris-runtime\hermes` pinned Hermes Agent environment
- `.iris-runtime\browser` pinned Windows agent-browser runtime; the browser
  engine is system Google Chrome installed/updated by WinGet, always in
  a separate domain-contained session; manual sign-ins do not persist after close
- `capabilities\v0_1_capability_ledger.toml`
- user-facing docs, license, notice, security notes, known limitations, assets

## Optional Image Generation

Image generation is disabled until a dedicated provider credential is
configured. Set `OPENAI_API_KEY` in the Windows user environment to enable the
default OpenAI Images API provider. Optional settings are `IRIS_IMAGE_MODEL`,
`IRIS_IMAGE_SIZE`, `IRIS_IMAGE_QUALITY`, and `IRIS_IMAGE_OUTPUT_FORMAT`.

Generated images require an Iris approval click, are saved under
`.iris-data\generated-images`, and are previewed inside Iris. Iris does not use
ChatGPT web UI automation for image generation.

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
cargo build --workspace --locked
cargo test --workspace --locked
cargo clippy --workspace --all-targets --locked -- -D warnings
cargo run --locked -p xtask
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

Then follow `docs/manual-test.md`. For the bounded end-user release acceptance
path, also use `docs/manual-end-user-test.md`.

For release testing, use `docs/finish-checklist.md` and the GitHub manual tester
issue template.

## Contribution Boundary

Bug fixes, compatibility repairs, diagnostics fixes, documentation corrections, and safety-preserving tests are welcome. Do not add action tools, model switching, fallback models, external runtime network behavior, or broader feature changes without explicit approval from Alejandro.

## Architecture Notes

See `docs/iris-architecture.md` for the current Iris/Hermes/local-memory boundary.
See `docs/windows-installer.md` for installer, shortcut, upgrade, and uninstall
behavior.
See `docs/signed-installer-decision.md` for the MSIX/App Installer signing
decision and current toolchain blockers.
See `docs/runtime-orchestration.md` for how Iris, Ollama, and Hermes should run
together during manual testing.
In v1, Iris can use local memory and restricted Hermes staging. Cloud-sync
storage is not part of Iris memory or archive behavior; memory remains
Iris-owned and local.
