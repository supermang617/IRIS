# Iris Production Readiness Checklist

This is the release order for Iris. Complete it top to bottom. A later phase
does not compensate for a failure in an earlier phase.

## Current Baseline

Implemented:

- Windows Tauri desktop app with direct Desktop and Start Menu shortcuts.
- Local Gemma 4 inference through Ollama.
- Native Whisper ASR and Kokoro `af_heart` TTS.
- Typed, wake-word, push-to-talk, image, screen, camera, video-frame, document,
  memory, Dynamic System Context, Panic Stop, Safe Hermes, and approved Agentic
  Hermes flows.
- Iris-owned RAG and staged memory accept/reject.
- Isolated Agentic browser profile and approval-gated file/PowerShell/process
  tools.
- Portable ZIP, per-user installer, setup wizard, preflight, uninstall,
  upgrade-data preservation, CI, CodeQL, and release packaging.
- Single-download beginner bundle generated as
  `iris-windows-installer.zip`.

Current public release rule:

- Keep the existing `v1` release and verifier as a historical,
  backward-compatible download path.
- Publish all new upgradeable releases under immutable monotonically increasing
  semantic tags such as `v1.0.1`, `v1.0.2`, and `v1.1.0`.
- Never move or replace a semantic tag after publication. WinGet cannot safely
  upgrade from repeatedly replaced `v1` assets.

## 1. Source And Policy Freeze

- Confirm `main` is clean and synchronized with `origin/main`.
- Confirm Cargo, npm, Tauri, and `manifest.json` all use `1.0.0`. Treat the
  existing `v1` GitHub/site download only as the documented historical release,
  not as the version for a new package or immutable tag.
- Confirm Gemma 4 is the only configured model and fallback models are disabled.
- Confirm Safe is the startup Hermes mode and Agentic requires an expiring
  approval session.
- Confirm public documentation matches actual Safe and Agentic behavior.
- Review the final dependency and license inventory.

Exit criteria:

- No contradictory capability claims.
- No uncommitted release changes.
- No stale version references in current release instructions.

## 2. Automated Validation

Run:

```powershell
# One-time developer prerequisite when `cargo audit` is unavailable:
cargo install cargo-audit --locked

npm run test:voice
npm run test:python
cargo fmt --all -- --check
cargo build --workspace --locked
cargo test --workspace --locked
cargo clippy --workspace --all-targets --locked -- -D warnings
cargo audit
npm audit --audit-level=high
npm --prefix .\.iris-runtime\browser audit --audit-level=high
uvx --from pip-audit==2.10.1 pip-audit --require-hashes --disable-pip --progress-spinner off -r profiles\hermes_agent_python_3_13.lock.txt
uvx --from pip-audit==2.10.1 pip-audit --require-hashes --disable-pip --progress-spinner off -r profiles\iris_voice_python_3_13.lock.txt
cargo run --locked -p xtask
cargo run --locked -p iris-runtime -- --self-check
cargo run --locked -p iris-runtime -- --dashboard-json
scripts\test_model_asset_lock.ps1
scripts\test_release_model_e2e.ps1
scripts\test_windows_release_download.ps1
scripts\test_windows_beginner_installer.ps1
scripts\test_windows_installer.ps1
scripts\test_iris_data_root.ps1
scripts\test_iris_windows_update.ps1
scripts\test_windows_browser_payload.ps1
scripts\test_winget_manifests.ps1
git diff --check
```

Exit criteria:

- Every command passes.
- `cargo audit` reports no known vulnerable package; review any warning-only
  transitive dependency separately instead of treating warnings as invisible.
- Live Hermes ACP tests pass serially or through their singleton test lock.
- No test-started Iris, Hermes, browser, Python, Cargo, or model process remains.

## 3. Beginner Installer Acceptance

- Build `iris-windows-installer.zip` and its SHA256.
- Extract it into a clean folder.
- Double-click `Install Iris.bat` without opening PowerShell manually.
- Confirm the payload hash is verified before installation.
- Test one machine with prerequisites present.
- Test one clean Windows user or VM with at least one missing prerequisite.
- Confirm the setup wizard runs before final self-check.
- Confirm declined repairs remain declined and produce clear next steps.
- Confirm successful installation creates working Desktop and Start Menu
  shortcuts and opens Iris.
- Upgrade over an existing install and verify `.iris-data` is preserved.
- Uninstall and verify managed files/shortcuts are removed while user data is
  not silently deleted.

Exit criteria:

- A nontechnical user needs only: download, extract, double-click, follow the
  wizard.
- Every failure names the missing prerequisite and recovery action.

## 4. Installed-App Manual Acceptance

Run two consecutive passes from the installed Desktop shortcut:

- typed conversation;
- wake word and push-to-talk;
- speech interruption and Panic Stop;
- image and text attachment;
- camera, screen-area, video-frame, and document OCR;
- Dynamic System Context status/on/off/reset;
- Safe Hermes status, memory query, research, staging, accept, and reject;
- Agentic session creation, ordinary file task, isolated browser research,
  denied high-risk action, expiry, and cleanup;
- close/relaunch and duplicate-launch handling.

Record:

- exact visible mismatches;
- response and voice latency;
- fresh diagnostics;
- process cleanup after exit.

Exit criteria:

- Two passes with no unauthorized action, crash, stuck listening state, clipped
  speech start, unexplained error, or orphaned Iris-owned process.

## 5. Security And Privacy Gate

- CI and all CodeQL language jobs pass on the release commit.
- Dependency Review passes for the release PR if a PR is used.
- Dependabot, secret scanning, and code scanning alerts are reviewed.
- Tauri CSP remains restrictive.
- Release ZIP contains no `.iris-data`, browser profile, downloads, credentials,
  diagnostics, memory, or Hermes home state.
- Logs remain bounded and redact sensitive values.
- Installer uses only official prerequisite links and fixed allowlisted repair
  commands.
- Browser login, consequential submissions, executable downloads, credentials,
  payments, destructive Git, installs/admin, and scope expansion retain
  separate approval.

Exit criteria:

- No unresolved high/critical security finding.
- No secret or user data in repository history or release assets.

## 6. Publish An Immutable Version

- Commit the release candidate atomically.
- Push the verified commit.
- Wait for CI and CodeQL success on that exact SHA.
- Create a new immutable `vMAJOR.MINOR.PATCH` tag after verification.
- Confirm the version is greater than every published WinGet package version.
- Do not move or replace the tag after publishing it.
- Confirm the release workflow uploads:
  - `iris-windows-installer.zip`
  - `iris-windows-installer.zip.sha256`
  - `iris-windows.zip`
  - `iris-windows.zip.sha256`
  - `install-iris-windows.ps1`
  - `install-iris-windows.ps1.sha256`
  - `iris-windows.msix` and SHA256 for a signed semantic release
  - `iris-winget-manifests.zip` and SHA256 for WinGet submission
- Download the assets back from GitHub and verify all published hashes.
- For the existing historical release, retain
  `scripts\test_github_v1_release.ps1 -ExpectedCommit <release-sha>`.
- For new releases, run:

  ```powershell
  scripts\test_github_versioned_release.ps1 `
    -Tag v1.0.1 `
    -ExpectedCommit <release-sha> `
    -RequireSignedMsix `
    -RequireWingetBundle `
    -DownloadPayloads
  ```
- Run the beginner install once from the downloaded GitHub asset, not a local
  build.
- Update release notes with prerequisites, safety boundaries, known
  limitations, and uninstall instructions.

Exit criteria:

- GitHub's Latest release points to the new immutable semantic release.
- Published assets match the validated commit and documented behavior.

## 7. Production-Trusted Installer

Required before broad public distribution, but not before Alejandro's
single-user release:

- Obtain a production-trusted code-signing path.
- Build and sign MSIX/App Installer assets.
- Verify install, upgrade, uninstall, publisher identity, SmartScreen behavior,
  and update rollback on a clean Windows VM.
- Publish signed assets only after signature and package checks pass.
- Generate and validate the WinGet submission bundle.
- Submit the version folder to `microsoft/winget-pkgs`; do not claim
  `winget install/upgrade` works publicly until Microsoft accepts it.

Do not present a self-signed package as a normal beginner installer.

## Final Production Standard

Iris is production-ready when repository, CI, documented behavior, GitHub
assets, installed behavior, and diagnostics agree; the GitHub-downloaded
beginner bundle passes clean-machine installation; two consecutive installed
gauntlets pass; and no unauthorized action, secret exposure, unexplained crash,
or orphaned process remains.
