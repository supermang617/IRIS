# Contributing

Produced by Alejandro Pinto.

Project Iris is currently open for bug fixes, diagnostics fixes, documentation fixes, compatibility fixes, and safety-preserving test coverage.

Contact: super.mangmail@gmail.com

## Allowed Contributions

- Bug fixes.
- Failing-test fixes.
- Local Windows compatibility fixes.
- Documentation corrections.
- Security hardening that preserves the no-action runtime invariant.
- Test coverage for existing behavior.

## Avoid Without Explicit Approval

- New action tools.
- Mouse, keyboard, browser, clipboard, window, shell, process, or automation control.
- Model switching, model pulling, fallback models, or multi-model debate.
- External/cloud network behavior.
- New dependencies.
- UI redesigns.
- Feature expansions beyond the current safety envelope.
- Changes that weaken Hermes restrictions.
- Live memory storage under OneDrive.

## Validation Before a PR

Run from `C:\Projects\IRIS`:

```powershell
cargo fmt --all -- --check
cargo build --workspace
cargo test --workspace
cargo clippy --workspace
cargo run -p xtask
npm run test:voice
git diff --check
```

Manual runtime testing is described in `docs/manual-test.md`.

GitHub Actions runs the lightweight bug checker on pushes and pull requests. That CI validates source, tests, and repository audits, but it does not launch the desktop runtime, use a microphone, speak audio, access a camera, capture the screen, or call Ollama. Manual runtime testing still matters for changes that affect the app loop.
