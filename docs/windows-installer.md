# Iris Windows Portable Install Notes

Produced by Alejandro Pinto.

Contact: super.mangmail@gmail.com

The current public release ships as a portable Windows ZIP. It uses built-in
Windows and PowerShell features only. It does not require WiX, NSIS, Inno
Setup, MSIX packaging, code-signing services, cloud APIs, or installer
downloads.

## What Ships

- `iris-windows-installer.zip`: recommended single-download beginner bundle.
- `iris-windows-installer.zip.sha256`: SHA256 for the beginner bundle.
- `iris-windows.zip`: portable Iris release.
- `iris-windows.zip.sha256`: SHA256 for the portable release.

The beginner bundle contains:

- `Install Iris.bat`
- `install-iris-windows.ps1`
- `iris-windows.zip`
- `iris-windows.zip.sha256`
- `README.txt`

The portable release contains:

- `Install Iris.bat`
- `Install Iris.ps1`
- `Iris Setup Wizard.bat`
- `Check Iris Preflight.bat`

## Beginner Install Behavior

The beginner downloads one ZIP, extracts it, and double-clicks
`Install Iris.bat`. The launcher passes the bundled payload and checksum to the
PowerShell installer. The installer:

- verifies the payload SHA256;
- installs to `%LOCALAPPDATA%\Programs\Iris`;
- creates Desktop and Start Menu shortcuts;
- runs the setup wizard before the final self-check, so missing prerequisites
  can be repaired first;
- launches Iris after a successful install.

The current installer is not signed, so Windows may show a publisher warning.
A production-trusted signed MSIX remains the preferred public-beta path.

## Portable Install Behavior

The public download flow is:

```powershell
$expected = (Get-Content .\iris-windows.zip.sha256 -Raw).Split(" ")[0]
$actual = (Get-FileHash .\iris-windows.zip -Algorithm SHA256).Hash.ToLowerInvariant()
if ($expected -ne $actual) { throw "SHA256 mismatch" }
Expand-Archive .\iris-windows.zip -DestinationPath "$env:USERPROFILE\Iris" -Force
```

From the extracted folder, run:

```powershell
.\Iris Setup Wizard.bat
.\Start Iris.bat
```

The ZIP also includes `Install Iris.bat` and `Install Iris.ps1` for users who
want a per-user copy under `%LOCALAPPDATA%\Programs\Iris` after extraction. That
extracted installer copies Iris-managed release files, runs the installed
self-check, can run the setup wizard, and creates shortcuts:

- Start Menu: `Iris`
- Start Menu: `Iris Setup Wizard`
- Start Menu: `Uninstall Iris`
- Desktop: `Iris`

The normal `Iris` shortcuts target `bin\iris-tauri.exe` directly. The desktop
window opens before local model and voice warm-up, and Iris starts Ollama
hidden in the background when it is not already running. `Start Iris.ps1`
remains the explicit diagnostics and self-check entry point.

## Uninstall And Upgrade

Uninstall is available from the Start Menu shortcut or:

```powershell
& "$env:LOCALAPPDATA\Programs\Iris\Uninstall Iris.ps1"
```

The uninstaller removes Iris shortcuts and known managed release files. It may
leave diagnostics or user-created files behind so user data is not silently
deleted.

Upgrades use the same install command. The installer replaces known managed
release folders and files in the install root, then reruns self-check/setup.
Iris state now uses `%LOCALAPPDATA%\Iris` through `IRIS_DATA_ROOT`, with owned
state under `.iris-data` and logs under `diagnostics`, independent of the
application directory. During upgrade, the launcher copies missing
files from legacy install-root `.iris-data` and `diagnostics` folders without
overwriting newer per-user files or deleting the originals.

The MSIX manifest disables AppData file-system write virtualization and
declares the required `unvirtualizedResources` restricted capability. This
keeps the desktop app, external Python workers, portable updater, and future
MSIX versions on the same real `%LOCALAPPDATA%\Iris` tree instead of a
package-private copy that Windows could remove. A signed two-version upgrade
and uninstall test is appropriate only after a genuine higher production
version exists. The first signed release gate instead installs the exact full
MSIX on a clean VM, launches Iris through its registered Windows identity,
uninstalls it, and proves Iris-created state survives unchanged.

Developer source checkouts remain repo-local when `.git` is present, preserving
the existing source/debug workflow. Explicit `IRIS_DATA_ROOT` overrides both
the source and installed defaults.

For automated smoke tests, use `-SetupNonInteractive` with `-RunSetup` so the
installed setup wizard reports diagnostics without prompting.

## Safety Boundary

The installer does not change Iris runtime permissions. Iris remains local-only:

- no cloud model/API dependency;
- no clipboard access;
- no general window, mouse, or keyboard automation;
- Agentic browser, file, PowerShell, and process tools only through explicit
  Iris session approval and high-risk confirmation;
- no unapproved model-output-driven execution.

The setup wizard can offer allowlisted prerequisite installs or downloads only
when the user chooses to run those repair actions.

## Future Signed Installer

The recommended signed path is MSIX with App Installer. See
`docs/signed-installer-decision.md`.

A true signed `.msix`, `.msi`, or `.exe` installer still needs an installer
toolchain and code-signing certificate. The repository now includes
`scripts\package_windows_msix.ps1` and
`scripts\test_windows_signed_installer_readiness.ps1` so this can move forward
without silently installing tools or weakening Iris runtime safety.

## WinGet Install And Upgrade

The target public package identifier is `AlejandroPinto.Iris`. After a
production-signed semantic release is accepted into Microsoft's
`microsoft/winget-pkgs` community repository, users will be able to run:

```powershell
winget install --id AlejandroPinto.Iris -e
winget upgrade --id AlejandroPinto.Iris -e
```

That command is not public merely because manifests exist in this repository.
It becomes available only after Microsoft validates and accepts a submission.
Run `Update Iris.ps1 -CheckOnly` to see whether the configured WinGet sources
currently expose Iris.

WinGet cannot directly upgrade an unregistered portable ZIP or legacy
PowerShell installation. When the catalog entry exists, `Update Iris.ps1`
copies any missing legacy data/diagnostics into the stable per-user data root,
then performs a one-time registered MSIX install. It neither overwrites newer
state nor removes the originals. Confirm the Start-menu MSIX works before
uninstalling the old managed files.

For a genuinely fresh MSIX install, WinGet displays the one large user-owned
first-run command: pull the configured Ollama model with
`ollama pull huihui_ai/gemma-4-abliterated:e2b`. Iris does not hide that
multi-gigabyte network operation inside application startup. The pinned voice
packages ship as an Iris-owned layer and update with Iris itself.

WinGet upgrades require monotonically increasing package versions and immutable
release URLs. The first production package therefore uses `v1.0.0`, later
upgradeable releases use tags such as `v1.0.1`, and the historical mutable
`v1` download remains a backward-compatible legacy path that must not be used
in a WinGet manifest.

The Iris manifest declares only actual catalog-installable runtime packages:
Google Chrome, WebView2, Ollama, exact Python 3.13, and Tesseract. Rust is a
developer/build dependency. Hermes and voice Python packages ship inside Iris
and run through the external Python 3.13 interpreter, while llama.cpp is
managed inside Ollama. The multi-gigabyte Ollama model remains an explicit
setup-wizard download and is not owned by WinGet.

The launcher persists the measured server-side memory defaults
`OLLAMA_FLASH_ATTENTION=1` and `OLLAMA_KV_CACHE_TYPE=q8_0` at CurrentUser scope
only when no process, user, or machine override exists. When it initializes
either value while Ollama is already running, it restarts Ollama once so the
server inherits the new setting. Concurrency limits remain process-only.

## Package Footprint Decision

Windows packaging removes the six macOS/Linux Agent Browser executables and
retains the required Windows x64 executable. The release test fails if a
foreign-platform binary returns.

Automated release acceptance caps `iris-windows.zip` at 600 MiB and both the
single-download beginner bundle and signed MSIX at 610 MiB. A deliberate
capability or model change that cannot fit those ceilings requires a reviewed
packaging decision, not silent release growth.

Hermes packaging retains only `.venv\Lib\site-packages`. The unused virtual
environment launcher, `pyvenv.cfg`, locale copies, and cache metadata are
omitted; the release uses the independently updateable exact Python 3.13
runtime instead of pretending the build-machine interpreter is portable.

The release ships the pinned Windows agent-browser controller but not a
duplicate browser engine. WinGet installs and updates Google Chrome; Iris
launches it in a separate, domain-contained, nonpersistent session and never
reuses the user's normal browser profile. Headed manual sign-ins last only for
the current session. This removes roughly 415 MiB uncompressed (about
188 MiB from the ZIP in the measured v1 staging build) while retaining the
same browser capability and improving browser security-update cadence.
