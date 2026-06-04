# Signed Windows Installer Decision

Produced by Alejandro Pinto.

Contact: super.mangmail@gmail.com

## Recommendation

Use **MSIX with App Installer** as the signed Windows installer target, and keep
the current SHA-verified PowerShell ZIP installer as the fallback path until
production signing is ready.

## Why MSIX/App Installer

MSIX is the modern Windows package identity format. Microsoft documents it as
supporting reliable install/uninstall, differential updates, and optional
containerized behavior. App Installer provides a familiar user-facing install
and update flow for signed MSIX packages distributed outside the Store.

This path fits Iris because:

- uninstall/upgrade behavior is owned by Windows instead of custom scripts;
- App Installer can provide a beginner-friendly flow;
- production signing has a clear Microsoft-supported path;
- the package can preserve the same local-only Iris runtime boundary;
- no cloud/API dependency is added to Iris runtime.

## Why Not WiX First

WiX is a strong MSI toolchain, but it is not built into Windows and would add a
new installer dependency. MSI is appropriate for enterprise-style installers,
but it gives Iris less direct access to App Installer update behavior and does
not solve signing by itself.

## Why Not Inno Setup Or NSIS First

Inno Setup and NSIS are practical EXE installer builders, but both are external
dependencies and produce custom installer behavior that Iris would need to own
and harden. They are useful fallback choices if MSIX blocks on Tauri/full-trust
desktop packaging, but they are not the cleanest first signed path.

## Signing Implications

Windows requires MSIX packages to be signed and trusted on the target device.
For local testing, a self-signed certificate works only after the certificate is
trusted on that machine. For production distribution, use a publicly trusted
code-signing path such as Microsoft Azure Artifact Signing or an OV/EV code
signing certificate.

Local testing can use a self-signed certificate in the current user's
certificate store. That removes the local build blocker, but it does not make
the MSIX production-trusted for other users. Production distribution still needs
Azure Artifact Signing, Microsoft Store signing, or a CA-issued code-signing
certificate.

The release may include `iris-windows.msix`, `iris-windows.msix.sha256`,
`iris-msix-signing.cer`, and `iris-msix-signing.cer.sha256` when a local test
certificate is used. This proves the packaging path, but a beginner should still
use the ZIP installer unless they understand certificate trust.

Windows App Installer/MSIX deployment checks the app package signing chain. On
test machines, the certificate generally must be trusted for app deployment,
often in the Local Machine certificate stores. That trust step can require
administrator approval. A production trusted certificate avoids this manual
trust step.

## First Implemented Slice

This repository now includes:

- `scripts/package_windows_msix.ps1`
- `scripts/test_windows_signed_installer_readiness.ps1`
- `release/dist/iris-msix-readiness.txt` generated during readiness checks

The MSIX script is guarded:

- `-ReadinessOnly` reports tool/signing status and exits successfully for CI or
  local diagnostics.
- A real MSIX build fails closed unless `makeappx.exe`, `signtool.exe`, the
  portable ZIP, its SHA256 file, and signing inputs are available.
- It verifies the portable ZIP SHA before staging package contents.

## Safety Boundary

The signed installer path must not change Iris runtime permissions:

- no runtime external network;
- no clipboard control;
- no browser/window automation;
- no shell/process execution tools exposed to Iris;
- no model-output-driven command execution;
- no local memory exposure outside Iris-owned boundaries.

Installer tooling may run during packaging or explicit user installation only.
That is separate from Iris runtime capability.
