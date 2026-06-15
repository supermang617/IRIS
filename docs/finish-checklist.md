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

Current public gap:

- GitHub's latest published release is `v0.1.1` from June 5, 2026. It predates
  the current verified code and does not contain the beginner installer bundle.
- The current source is prepared as `v0.1.2`, but it is not public until the
  validated commit is pushed and a `v0.1.2` tag triggers the release workflow.

## 1. Source And Policy Freeze

- Confirm `main` is clean and synchronized with `origin/main`.
- Confirm all Cargo, npm, Tauri, manifest, docs, and release versions are
  `0.1.2`/`v0.1.2`.
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
npm run test:voice
npm run test:python
cargo fmt --all -- --check
cargo build --workspace
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings
cargo run -p xtask
cargo run -p iris-runtime -- --self-check
cargo run -p iris-runtime -- --dashboard-json
scripts\test_release_model_e2e.ps1
scripts\test_windows_release_download.ps1
scripts\test_windows_beginner_installer.ps1
scripts\test_windows_installer.ps1
git diff --check
```

Exit criteria:

- Every command passes.
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

## 6. Publish `v0.1.2`

- Commit the release candidate atomically.
- Push the verified commit.
- Wait for CI and CodeQL success on that exact SHA.
- Create and push annotated tag `v0.1.2`.
- Confirm the release workflow uploads:
  - `iris-windows-installer.zip`
  - `iris-windows-installer.zip.sha256`
  - `iris-windows.zip`
  - `iris-windows.zip.sha256`
  - `install-iris-windows.ps1`
  - `install-iris-windows.ps1.sha256`
- Download the assets back from GitHub and verify all published hashes.
- Run the beginner install once from the downloaded GitHub asset, not a local
  build.
- Update release notes with prerequisites, safety boundaries, known
  limitations, and uninstall instructions.

Exit criteria:

- GitHub's Latest release points to `v0.1.2`.
- Published assets match the validated commit and documented behavior.

## 7. Production-Trusted Installer

Required before broad public distribution, but not before Alejandro's
single-user release:

- Obtain a production-trusted code-signing path.
- Build and sign MSIX/App Installer assets.
- Verify install, upgrade, uninstall, publisher identity, SmartScreen behavior,
  and update rollback on a clean Windows VM.
- Publish signed assets only after signature and package checks pass.

Do not present a self-signed package as a normal beginner installer.

## Final Production Standard

Iris is production-ready when repository, CI, documented behavior, GitHub
assets, installed behavior, and diagnostics agree; the GitHub-downloaded
beginner bundle passes clean-machine installation; two consecutive installed
gauntlets pass; and no unauthorized action, secret exposure, unexplained crash,
or orphaned process remains.
