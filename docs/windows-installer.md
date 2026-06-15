# Iris Windows Portable Install Notes

Produced by Alejandro Pinto.

Contact: super.mangmail@gmail.com

The current public release ships as a portable Windows ZIP. It uses built-in
Windows and PowerShell features only. It does not require WiX, NSIS, Inno
Setup, MSIX packaging, code-signing services, cloud APIs, or installer
downloads.

## What Ships

- `iris-windows.zip`: portable Iris release.
- `iris-windows.zip.sha256`: SHA256 for the portable release.

The portable release also contains:

- `Install Iris.bat`
- `Install Iris.ps1`
- `Iris Setup Wizard.bat`
- `Check Iris Preflight.bat`

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
