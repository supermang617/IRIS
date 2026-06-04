# Iris Windows Installer Plan

Produced by Alejandro Pinto.

Contact: super.mangmail@gmail.com

The current installer milestone uses built-in Windows and PowerShell features
only. It does not require WiX, NSIS, Inno Setup, MSIX packaging, code-signing
services, cloud APIs, or installer downloads.

## What Ships

- `iris-windows.zip`: portable Iris release.
- `iris-windows.zip.sha256`: SHA256 for the portable release.
- `install-iris-windows.ps1`: per-user installer wrapper.
- `install-iris-windows.ps1.sha256`: SHA256 for the installer wrapper.

The portable release also contains:

- `Install Iris.bat`
- `Install Iris.ps1`
- `Iris Setup Wizard.bat`
- `Check Iris Preflight.bat`

## Install Behavior

The installer is per-user and defaults to:

```text
%LOCALAPPDATA%\Programs\Iris
```

It copies Iris-managed release files, runs the installed self-check, can run the
setup wizard, and creates shortcuts:

- Start Menu: `Iris`
- Start Menu: `Iris Setup Wizard`
- Start Menu: `Uninstall Iris`
- Desktop: `Iris`

The installer writes `install-manifest.json` so upgrades and diagnostics can see
where Iris was installed from. It replaces only known Iris-managed release
folders and files. It does not delete arbitrary user files.

## SHA Verification

Recommended install from the downloaded ZIP:

```powershell
.\install-iris-windows.ps1 -SourceZip .\iris-windows.zip -Sha256Path .\iris-windows.zip.sha256 -RunSetup
```

This verifies the ZIP hash before extraction and installation.

If the user has already extracted `iris-windows.zip`, they can run:

```powershell
.\Install Iris.bat
```

The extracted installer still runs the installed self-check and setup wizard,
but the strongest download-integrity check is the `-SourceZip` flow above.

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

- no cloud/API dependency;
- no external runtime network;
- no clipboard access;
- no browser/window automation;
- no model-output-driven command execution;
- no runtime computer automation.

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
