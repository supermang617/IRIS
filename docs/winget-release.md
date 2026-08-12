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

The owner-dispatched release workflow supports a PFX-based production signing
path through the protected `iris-production-release` environment:

- `IRIS_SIGNING_PFX_BASE64`: base64-encoded production signing PFX
- `IRIS_SIGNING_PFX_PASSWORD`: PFX password
- `IRIS_MSIX_PUBLISHER`: exact certificate subject used by the MSIX identity

Store these as environment secrets, not repository secrets. Require an owner
reviewer, protect `main`, and set `IRIS_PRODUCTION_GATE_CONFIGURED=true` only
after those controls are verified. The workflow requires the requested
semantic tag to equal the current `main` head, does not run from a tag push,
keeps signing in a read-only job with no persisted repository credential,
deletes the temporary PFX after signing, transfers hashes and artifacts through
run-scoped transient caches to a separate no-PFX draft job, deletes only those
exact cache keys after use, and creates a private draft only. A public trusted certificate or
Microsoft-hosted trusted signing path is still an owner-controlled
prerequisite.

Dispatch the first full production release only after the 1.0.0 release commit
is on protected `main` and protected tag `v1.0.0` points to that exact commit:

```powershell
gh workflow run release.yml `
  --repo supermang617/IRIS `
  --ref main `
  -f tag=v1.0.0
```

The publisher needs a local GitHub CLI credential with repository
administration-read access (for protection, environment, and immutable-release
preflights) and release write access. Local PFX builds must obtain the password
from an interactive secure value or a process-scoped secret environment
variable; never commit it or place it on a command line saved in shell history.

## Build And Validate Locally

```powershell
scripts\package_windows_release.ps1
scripts\package_windows_msix.ps1 `
  -Publisher "CN=YOUR EXACT CERTIFICATE SUBJECT" `
  -Version "1.0.0.0" `
  -PfxPath "C:\secure\iris-signing.pfx" `
  -PfxPassword $env:IRIS_SIGNING_PFX_PASSWORD
scripts\test_windows_msix_signature.ps1 `
  -ExpectedPackageVersion "1.0.0.0" `
  -ExpectedPublisher "CN=YOUR EXACT CERTIFICATE SUBJECT"
scripts\generate_winget_manifests.ps1 `
  -PackageVersion "1.0.0" `
  -MsixPath "release\dist\iris-windows.msix" `
  -ExpectedPublisher "CN=YOUR EXACT CERTIFICATE SUBJECT"
```

Generated submission files are under:

```text
release\dist\winget\manifests\a\AlejandroPinto\Iris\1.0.0
```

The portable ZIP/PowerShell installer cannot be submitted directly because the
public `winget-pkgs` repository does not accept script installers.

## Pre-Submission Gate

Before submission:

1. Run the complete Iris automated gauntlet.
2. Install the signed MSIX on a clean Windows user/VM.
3. For the first production release, verify install, registered Windows
   activation, uninstall, shortcuts, model setup, voice, vision, memory, and
   Agentic browser using the exact full release artifact.
4. Confirm Iris itself creates `%LOCALAPPDATA%\Iris` and that the state survives
   uninstall unchanged.
5. Confirm the packaged application does not attempt to write under the
   read-only MSIX installation directory.
6. Confirm the signed production MSIX install/registered-launch/uninstall
   sequence on a clean Windows VM. Static tests verify the required
   `desktop6:FileSystemWriteVirtualization=disabled` declaration and
   `unvirtualizedResources` capability, but only a real signed package can
   prove that Windows preserves the shared `%LOCALAPPDATA%\Iris` state root.
7. Run `winget validate --manifest <generated-version-folder>`.
8. Run the official `microsoft/winget-pkgs` Windows Sandbox test.

Do not create a lower artificial Iris package. When the first genuine higher
semantic release exists, add an in-place upgrade and rollback test from the
previous immutable production release before submitting that newer version.

### Disposable Guest Lifecycle Gauntlet

Copy the exact full production-signed MSIX from the private GitHub draft into a
clean Windows VM, then run the guest-side lifecycle gauntlet from that VM:

```powershell
$testContext = "iris-disposable-guest-$([guid]::NewGuid().ToString('N'))"
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\test_windows_msix_lifecycle_guest.ps1 `
  -MsixPath "C:\IrisTest\iris-windows.msix" `
  -ExpectedPublisher "CN=YOUR EXACT CERTIFICATE SUBJECT" `
  -ExpectedVersion "1.0.0.0" `
  -TestContextId $testContext `
  -WackReportPath "C:\IrisTest\iris-v1.0.0-wack.xml" `
  -EvidencePath "C:\IrisTest\iris-msix-lifecycle-evidence.json" `
  -ConfirmDisposableTestGuest
```

The script fails before installation unless the host looks like a virtual
machine, the elevated interactive confirmation and unique test context are
supplied, both output paths are new, no Iris MSIX is registered, and
`%LOCALAPPDATA%\Iris` does not already exist. It validates the trusted
signature and exact manifest identity, invokes `appcert.exe` against that exact
resolved MSIX, requires `REPORT.OVERALL_RESULT=PASS`, installs the release,
launches Iris through its registered AppUserModel identity to create an
Iris-owned probe, uninstalls the exact package with application-data
preservation, and proves the probe survived unchanged. Lifecycle schema 3
contains the exact release version and MSIX hash, the identical
`wack_package_sha256`, WACK report hash and length, signer, registered
application identity, and state-probe hash. The script never deletes the Iris
state root.

The semantic-tag workflow creates and verifies a private draft; it cannot make
that draft public. Copy the evidence out of the disposable guest and publish
only the exact tested draft artifact:

```powershell
$commit = git rev-parse "v1.0.0^{commit}"
scripts\publish_github_versioned_release.ps1 `
  -Tag "v1.0.0" `
  -ExpectedCommit $commit `
  -ReleaseRunId 1234567890 `
  -ExpectedPublisher "CN=YOUR EXACT CERTIFICATE SUBJECT" `
  -ExpectedSignerThumbprint "0123456789abcdef0123456789abcdef01234567" `
  -LifecycleEvidencePath "C:\IrisTest\iris-msix-lifecycle-evidence.json" `
  -WackReportPath "C:\IrisTest\iris-v1.0.0-wack.xml"
```

Use the exact successful workflow run ID shown by `gh run list --workflow
release.yml`; do not use a later run merely because it has the same commit.
Replace the example thumbprint with the real 40-hex thumbprint from the
production signing certificate.
The publisher rejects stale evidence or WACK output, a non-PASS or unsafe XML
report, a report/package hash that is not bound by lifecycle schema 3, a
different release hash, signer, publisher, version, package identity, tag
commit, workflow run, provenance, or draft asset. It requires the retained
unsigned and signed provenance files, verifies their SHA-256 binding, and
requires the draft to publish both. It attaches the lifecycle evidence, WACK
report, and both checksums without overwrite, verifies protection settings and
the recorded owner approval, publishes it, then requires GitHub to report the
public release as Latest and immutable. It verifies GitHub's signed release
attestation for the MSIX, lifecycle evidence and checksum, WACK report and
checksum, WinGet bundle, and both provenance files, then downloads the public
MSIX anonymously and verifies its hash.
Discard the disposable guest only after the evidence has been copied and
publication verification has completed.

After publication succeeds, make a separate verified commit that updates
`site/release-manifest.json`, site metadata and JSON-LD, `site/llms.txt`,
`site/sitemap.xml`, semantic download URLs, and checksums. Until then, keep the
site truthfully describing the historical public `v1` release.

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

- WinGet package dependencies: Google Chrome, WebView2, Ollama, exact Python
  3.13, and Tesseract OCR.
- Iris release: Iris executables, Kokoro, Whisper, Hermes and voice pinned
  Python packages, the Windows Agent Browser controller, and their pinned
  integration code. The Chrome engine updates through its Google package and
  always runs in a separate Iris-owned, nonpersistent, domain-contained session.
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
