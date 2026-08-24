Iris {{VERSION}} is a local-first Windows AI assistant with natural voice, bounded image and OCR assistance, private memory, Ollama, and approval-gated Hermes agent tools.

> **WinGet catalog status:** not yet submitted or public. The included manifest bundle is ready for separate review and submission; `winget install` and `winget upgrade` remain unavailable until Microsoft accepts the package and the catalog entry is independently verified.

## Highlights

- Low-latency local conversation with streaming text and sentence-level Kokoro speech.
- Onset-aware spoken interruption with bounded confirmation, immediate Panic Stop cancellation, and no claim of unverified acoustic echo cancellation.
- Local image/document OCR and high-confidence simple color or shape checks; camera and screen evidence remains one-shot and provenance-bound.
- Private Iris-owned memory plus Safe and explicitly approved Agentic Hermes sessions.
- Automatic GPU/RAM placement for Ollama while keeping required runtime headroom.
- Update-safe user state under `%LOCALAPPDATA%\Iris`.
- Pinned local voice, browser, and Hermes runtimes for reproducible Windows installs.

## Downloads

| File | Use |
| --- | --- |
| `iris-windows-installer.zip` | Guided first-time setup bundle; checksum-verified but not Authenticode-signed |
| `iris-windows.msix` | Recommended production-trusted signed x64 package after prerequisites |
| `iris-windows.zip` | Advanced portable package |
| `iris-winget-manifests.zip` | Exact WinGet submission manifests for this release |
| `iris-unsigned-build.json` | Runner, tool, and dependency-lock provenance |
| `iris-signed-build.json` | Protected-workflow provenance for every signed draft asset |
| `iris-msix-lifecycle-evidence.json` | Clean-VM install, registered launch, uninstall, and state-preservation evidence |
| `iris-windows-wack-report.xml` | WACK report for the exact signed MSIX; `REPORT.OVERALL_RESULT=PASS` |
| `iris-windows-wack-report.xml.sha256` | SHA-256 binding for the published WACK report |

Every distribution payload and external release-gate report has a matching `.sha256` file. The release also includes the public signing certificate and its checksum; the signed-build provenance binds the unsigned build/tool/lock record by SHA-256 and is independently tied to the exact protected Actions run. Lifecycle schema 3 binds the WACK package hash to the release MSIX and the published WACK report hash to the clean-VM test.

## Requirements

- Windows 10 version 2004 (build 19041) or newer, x64.
- Google Chrome for isolated Hermes browser tools and the Microsoft Edge
  WebView2 Runtime for the Iris desktop shell.
- Exact Python 3.13 for the pinned Hermes and image-provider layers.
- A microphone and speakers or headset for voice features; a camera only for explicit one-shot camera capture.
- [Ollama](https://ollama.com/) and the configured local model for text and bounded image assistance.
- Tesseract OCR only when document-image OCR is needed.
- Several gigabytes of free storage for Iris runtimes and the Ollama model.

## Install

### Guided setup before WinGet acceptance

1. Download `iris-windows-installer.zip`.
2. Extract it.
3. Double-click `Install Iris.bat`.
4. Follow the setup wizard.

The guided installer verifies the packaged payload checksum before installation
but is not Authenticode-signed. Use the signed MSIX below for the
production-trusted package path after prerequisites are installed. Advanced
users can use `iris-windows.zip` directly.

### Signed MSIX

After installing the prerequisites above, download `iris-windows.msix`, verify
it, and open it with Windows App Installer. The direct MSIX does not run the
beginner bundle's setup wizard. Once Microsoft accepts Iris into WinGet,
`winget install --id AlejandroPinto.Iris -e` installs the declared package
dependencies.

## Verify the download

```powershell
Get-FileHash .\iris-windows.msix -Algorithm SHA256
Get-Content .\iris-windows.msix.sha256
Get-AuthenticodeSignature .\iris-windows.msix |
  Select-Object Status, StatusMessage, @{Name="Signer";Expression={$_.SignerCertificate.Subject}}
```

The SHA-256 must match the release checksum and `Status` must be `Valid` before installation.

## Updates, uninstall, and user data

- A newer signed MSIX with the same identity, publisher, and certificate upgrades the installed app in place.
- Windows Settings can uninstall the MSIX.
- Iris intentionally keeps user-owned state under `%LOCALAPPDATA%\Iris` across application upgrades and uninstall so an app update does not erase memory or diagnostics.
- After Microsoft accepts the package, use `winget upgrade --id AlejandroPinto.Iris -e`.
- This first production release proves the exact signed package can install, launch through its registered Windows identity, uninstall, and preserve Iris-created state. In-place upgrade acceptance is deferred until the first genuine higher semantic release exists; no artificial lower package is produced.

## Privacy and safety

Normal assistant inference, speech, memory, and diagnostics stay on the Windows device. Iris does not operate a telemetry service or cloud memory account. Explicit web research, approved browser work, update checks, and package downloads contact their named external services. Agentic tools are session-bound, approval-gated, audited locally, and stoppable with Panic Stop. See the [privacy policy](https://github.com/supermang617/IRIS/blob/{{TAG}}/PRIVACY.md) and [security policy](https://github.com/supermang617/IRIS/blob/{{TAG}}/SECURITY.md).

## Known limitations

- Initial setup still requires Ollama and a local model download.
- Camera, microphone, speaker, Bluetooth, and driver behavior varies by device.
- Camera, image, and screen inference uses the separately digest-locked `qwen3.5:4b` model while companion chat, tools, and Hermes remain on Gemma. Iris requires a raw red-circle visual-runtime canary at startup and fails broad vision closed if that canary does not pass.
- Spoken interruption currently uses local onset detection plus transcript confirmation; true acoustic echo cancellation is not claimed until physical speaker/headset evidence justifies and validates it.
- The WinGet command is unavailable until Microsoft merges the submission and the public catalog propagates.

## Documentation and changes

- [Download and run](https://github.com/supermang617/IRIS/blob/{{TAG}}/docs/download-and-run.md)
- [Manual test guide](https://github.com/supermang617/IRIS/blob/{{TAG}}/docs/manual-test.md)
- [Runtime architecture](https://github.com/supermang617/IRIS/blob/{{TAG}}/docs/runtime-orchestration.md)
- [Known limitations](https://github.com/supermang617/IRIS/blob/{{TAG}}/known-limitations.md)
- [Full changelog for {{TAG}}](https://github.com/supermang617/IRIS/commits/{{TAG}})
