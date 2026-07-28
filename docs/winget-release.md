# Iris WinGet Release And Upgrade Path

Produced by Alejandro Pinto.

Contact: super.mangmail@gmail.com

## User Outcome

After the first manifest is accepted into the public WinGet community catalog:

```powershell
winget install --id AlejandroPinto.Iris -e
winget upgrade --id AlejandroPinto.Iris -e
```

Until that acceptance happens, these commands correctly report that the
package is unavailable. Use the SHA-verified GitHub installer in the meantime.

## Version Rule

Every WinGet release must have a new monotonically increasing semantic version:

- Git tag and release: `vMAJOR.MINOR.PATCH`
- WinGet `PackageVersion`: `MAJOR.MINOR.PATCH`
- MSIX version: `MAJOR.MINOR.PATCH.0`
- Installer URL:
  `https://github.com/supermang617/IRIS/releases/download/vMAJOR.MINOR.PATCH/iris-windows.msix`

Never move or replace a semantic release tag after publication. Never use the
mutable historical `v1` URL in a WinGet manifest.

## Repository Signing Configuration

The release workflow supports a PFX-based production signing path through
GitHub Actions secrets:

- `IRIS_SIGNING_PFX_BASE64`: base64-encoded production signing PFX
- `IRIS_SIGNING_PFX_PASSWORD`: PFX password
- `IRIS_MSIX_PUBLISHER`: exact certificate subject used by the MSIX identity

The workflow does not expose these values. It deletes the temporary PFX after
signing. A public trusted certificate or Microsoft-hosted trusted signing path
is still an owner-controlled prerequisite.

## Build And Validate Locally

```powershell
scripts\package_windows_release.ps1
scripts\package_windows_msix.ps1 `
  -Publisher "CN=YOUR EXACT CERTIFICATE SUBJECT" `
  -Version "1.0.1.0" `
  -PfxPath "C:\secure\iris-signing.pfx"
scripts\test_windows_msix_signature.ps1 `
  -ExpectedPackageVersion "1.0.1.0" `
  -ExpectedPublisher "CN=YOUR EXACT CERTIFICATE SUBJECT"
scripts\generate_winget_manifests.ps1 `
  -PackageVersion "1.0.1" `
  -MsixPath "release\dist\iris-windows.msix"
```

Generated submission files are under:

```text
release\dist\winget\manifests\a\AlejandroPinto\Iris\1.0.1
```

The portable ZIP/PowerShell installer cannot be submitted directly because the
public `winget-pkgs` repository does not accept script installers.

## Pre-Submission Gate

Before submission:

1. Run the complete Iris automated gauntlet.
2. Install the signed MSIX on a clean Windows user/VM.
3. Verify first install, second-version upgrade, rollback behavior, uninstall,
   shortcuts, model setup, voice, vision, memory, and Agentic browser.
4. Confirm `%LOCALAPPDATA%\Iris` survives the application upgrade.
5. Confirm the packaged application does not attempt to write under the
   read-only MSIX installation directory.
6. Confirm a signed two-version MSIX install/upgrade/uninstall sequence on a
   clean Windows VM. Static tests verify the required
   `desktop6:FileSystemWriteVirtualization=disabled` declaration and
   `unvirtualizedResources` capability, but only a real signed package can
   prove that Windows preserves the shared `%LOCALAPPDATA%\Iris` state root.
7. Run `winget validate --manifest <generated-version-folder>`.
8. Run the official `microsoft/winget-pkgs` Windows Sandbox test.

## External Submission

Install Microsoft's manifest helper if desired:

```powershell
winget install --id Microsoft.WingetCreate -e
```

Then fork `microsoft/winget-pkgs`, place the generated version folder at the
matching `manifests\a\AlejandroPinto\Iris\<version>` path, and submit one pull
request for that version. Microsoft performs automated validation, installer
testing, and moderator review before the package enters the public catalog.

No repository script should claim this external submission or acceptance has
already occurred.

## Dependency Ownership

- WinGet package dependencies: Microsoft Edge, WebView2, Ollama, exact Python
  3.13, and Tesseract OCR.
- Iris release: Iris executables, Kokoro, Whisper, Hermes and voice pinned
  Python packages, the Windows Agent Browser controller, and their pinned
  integration code. The Edge engine updates through its Microsoft package and
  always runs with a separate Iris-owned profile.
- Ollama: its bundled llama inference runtime.
- Setup wizard: the selected Ollama model blob.
- Rust: source-build tooling only; end users do not need it.

`winget upgrade --all` may upgrade separately cataloged dependencies, but an
Iris release should still be tested against supported dependency versions.
Hermes and model compatibility must move through a tested Iris release rather
than an unbounded independent upgrade.

Portable ZIP and legacy PowerShell installs are not registered WinGet
packages. After catalog acceptance, their `Update Iris.ps1` performs a
one-time `winget install` migration. Before installation it copies missing
legacy `.iris-data` and `diagnostics` files into `%LOCALAPPDATA%\Iris` without
overwriting newer state or deleting the originals. Confirm the Start-menu MSIX
works before running the old installation's uninstaller; the old uninstaller
also preserves per-user data.

A fresh MSIX cannot silently pull the separately licensed multi-gigabyte model
or install PyPI voice packages. WinGet installation notes therefore provide
the explicit first-run commands:

```powershell
ollama pull huihui_ai/gemma-4-abliterated:e2b
```

The pinned voice packages already ship with Iris. After the model command
completes, launch Iris from the Windows Start menu.
