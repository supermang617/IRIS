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

Thumbprint signing searches `CurrentUser\My` first and then
`LocalMachine\My`. When the selected signing certificate is in the machine
store, the packager passes the machine-store switch to `signtool`; current-user
signing keeps the default store behavior. The selected certificate still needs
an accessible private key and code-signing usage. Readiness also rejects a
missing or expired private key, a subject that differs from the exact MSIX
publisher, or a PFX that cannot be opened. A completed package is accepted only
after Authenticode trust, the RFC 3161 timestamp, and `signtool verify` pass.
The semantic release remains a private draft until the clean-VM lifecycle
gauntlet produces evidence tied to that exact MSIX hash and signer; the
separate publisher verifies that evidence before making the release public.

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
- Production signing uses an RFC 3161 SHA-256 timestamp so the signature can
  remain verifiable after the signing certificate expires.
- It verifies the portable ZIP SHA before staging package contents.
- Readiness-only mode exits unsuccessfully when production prerequisites are
  missing unless the caller explicitly requests a non-blocking diagnostic.
- Signed semantic builds can generate schema-valid WinGet manifests with
  immutable versioned GitHub Release URLs.

## WinGet Publication Boundary

WinGet's public community source does not accept PowerShell/script installers.
Iris must first have a production-signed MSIX (or another supported signed
installer type), published under the first immutable semantic tag `v1.0.0`.
Later releases increment that version normally.

Repository tooling generates a submission bundle, but publication still
requires:

1. validate the manifests with `winget validate`;
2. test the first release's install, registered launch, uninstall, and state
   preservation in Windows Sandbox or a clean VM;
3. submit the version folder to `microsoft/winget-pkgs`;
4. wait for automated checks and Microsoft moderator acceptance.

The first genuine higher semantic release adds the in-place upgrade and
rollback test from the prior immutable production package. Iris does not build
an artificial lower version merely to simulate that future boundary.

See `docs/winget-release.md` for the exact release and submission sequence.

## Safety Boundary

The signed installer path must not change Iris runtime permissions:

- no cloud model/API runtime;
- no clipboard control;
- no general window automation;
- Agentic browser, shell, and process tools only through the reviewed,
  approval-gated Hermes session;
- no model-output-driven high-risk action without separate confirmation;
- no local memory exposure outside Iris-owned boundaries.

The production manifest uses Microsoft's desktop6
`FileSystemWriteVirtualization=disabled` setting with the
`unvirtualizedResources` restricted capability. Iris needs one shared
`%LOCALAPPDATA%\Iris` state root that is visible to its desktop process,
external Python workers, and migration tooling and that is not removed as
virtualized package state. Static manifest tests are required, followed by a
signed full-release MSIX WACK and VM install/registered-launch/uninstall test
before first publication. The disposable-guest gate invokes WACK against the
exact resolved package and lifecycle schema 3 binds the MSIX and WACK report
hashes. A real two-version upgrade test begins with the first genuine higher
semantic release.

Installer tooling may run during packaging or explicit user installation only.
That is separate from Iris runtime capability.
