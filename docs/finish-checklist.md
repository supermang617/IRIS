# Iris Finish Checklist

This is the practical order for finishing the current Windows Iris prototype without drifting into extra systems.

## Phase 1: Manual Desktop Readiness

Goal: make Iris easy to verify from Alejandro's desktop with the current runtime.

- Keep `Start Iris.vbs` and `Start Iris.ps1` as the manual launch path.
- Run `Start Iris.ps1 -SelfCheck` before manual testing.
- Confirm preflight reports local prerequisites clearly: WebView2, Ollama, configured model, Kokoro assets, Whisper asset, Python TTS packages, and local-only manifest policy.
- Confirm `cargo run -p xtask` and `cargo run -p iris-runtime -- --self-check` pass from the launcher self-check.
- Open Iris from the desktop shortcut or `C:\Projects\IRIS\Start Iris.vbs`.
- Complete `docs/manual-test.md` using typed text, push-to-talk, wake word, interruption, image, camera, screen-area, video-frame, and document attachment checks.
- Record only real failures found during manual testing; do not add new features during this phase.

Exit criteria:

- Self-check passes or reports a specific local prerequisite that must be installed.
- Desktop shell opens without the old dashboard or dev-server connection-refused page.
- Text, voice, TTS, wake word, interruption, and one-shot evidence probes are manually tested.

## Phase 2: Voice Loop Stabilization

Goal: make the core hands-free loop reliable before adding behavior.

- Fix only failures observed in Phase 1 voice diagnostics.
- Prioritize native ASR start/stop reliability, wake-word detection, interruption while speaking, and transcript quality.
- Keep WebView speech recognition out of the runtime path.
- Keep Kokoro `af_heart` as the production voice.
- Retest with `docs/manual-test.md` after each targeted fix.

Exit criteria:

- Wake word arms by default.
- `Iris`, `stop`, and `Iris stop` interrupt speech reliably enough for daily manual use.
- Typed text and push-to-talk still work after voice fixes.

## Phase 3: Evidence Probe Tightening

Goal: keep vision useful but bounded.

- Verify image, camera, screen-area, video-frame, and document attachments stay one-shot and user initiated.
- Confirm all observed content remains untrusted evidence.
- Improve failure messages for missing camera, unsupported files, missing OCR, or model vision issues.
- Do not add continuous screen capture, background monitoring, clipboard reads, or automation.

Exit criteria:

- Each evidence input has a clear manual test and a clear failure path.
- No evidence path can become an instruction or an acting permission.

## Phase 4: Local Memory and Hermes RAG

Goal: make Hermes useful as a research, local RAG, and memory-transfer helper while keeping computer-control surfaces out.

- Keep Hermes enabled by default for Iris-owned local memory query and staged memory proposal.
- Keep exposed Hermes tools limited to `iris_query_memory`, `iris_propose_memory`, and `iris_web_research`.
- Route natural Iris online/research requests through Hermes.
- Confirm proposals stay staged until Iris/user approval.
- Confirm OneDrive remains cold archive policy only.
- Support manual desktop commands for Hermes status, local reasoning, local research, code suggestion text, staging, accept, and reject.

Exit criteria:

- `cargo run -p iris-runtime -- --dashboard-json` reports Hermes as enabled sandboxed research/RAG with no acting tools.
- Manual testing shows Hermes can query approved memory and propose staged memory.
- Manual testing shows Iris can route online/research requests through Hermes web research.
- Manual testing shows Hermes cannot write active memory without explicit accept and cannot access OneDrive.

## Phase 5: Release Hardening

Goal: make the source-first Windows release boring to validate.

- Run the full public validation sequence from `AGENTS.md`.
- Keep installer and ZIP flows aligned with `docs/download-and-run.md`.
- Keep CI limited to source, diagnostics, docs, compatibility, and safety-preserving tests.
- Update public docs only for behavior that is actually implemented and tested.

Exit criteria:

- Full validation passes.
- Manual desktop test results are current.
- Public docs do not claim future behavior as active behavior.

## Explicit Non-Goals Until Later

- No new model routing.
- No fallback models.
- No cloud model/API calls.
- No clipboard access.
- Browser automation only inside an approved Agentic Session with the dedicated
  Iris profile and confirmation gates.
- No arbitrary acting plugins.
- No autonomous computer use.
- No new dashboards or settings panels unless a tested manual failure requires one.
