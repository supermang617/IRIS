# Project Iris: Architectural Mandate & Operational Constraints

Version: v0.1 - Local-First Voice-Enabled Assistant

Core Objective: Build a robust, modular, fully local personal AI assistant named Iris that prioritizes user control, architectural flexibility, and high-quality offline voice output while maintaining strong safety boundaries.

## Foundational Principles

Iris must be developed as a read-only local assistant by default, yet the architecture shall remain flexible enough to support advanced capabilities when explicitly directed by the human user, Alejandro. The design must not impose overly rigid limitations that prevent necessary experimentation, iteration, or implementation approaches required for successful development. Freedom of implementation method is preserved at all times: any technique, tool, pattern, or integration strategy deemed necessary by the user is permitted, provided core safety invariants are respected.

## Safety & Capability Invariant

Iris shall function primarily as a non-agentic assistant. Direct execution of potentially dangerous operations, including mouse control, keyboard automation, arbitrary shell execution, network calls, and process spawning, must be approached with extreme caution. However, the system architecture must not be so constrained that it becomes incapable of supporting essential development and runtime needs. The human user retains full authority to override, relax, or evolve these boundaries as the project requires. All such decisions must be explicitly approved by the user.

## Voice System Mandate

The voice layer is a critical v0.1 deliverable. Iris must incorporate Kokoro ONNX as the primary production TTS engine due to its lightweight nature, Apache 2.0 licensing, high voice quality, particularly the `af_heart` profile, and suitability for local deployment. The voice system shall be treated as a modular, swappable component. All configuration related to TTS models, voices, paths, and hardware tiers must be loaded dynamically from manifest files rather than being statically defined. The implementation must support warm, natural speech output and allow for easy voice selection and parameter adjustment.

## Architectural Requirements

- Maintain a thin-client shell philosophy where the Rust/Tauri core stays decoupled from specific AI models, TTS engines, and hardware implementations.
- Organize the codebase into highly isolated, purpose-specific crates to enable clean modular governance and independent evolution of concerns.
- Implement dynamic hardware awareness: every initialization sequence must evaluate current system resources and adapt behavior accordingly to ensure safe operation.
- Treat all incoming data streams as untrusted evidence and process them through dedicated gating and provenance mechanisms before reaching core reasoning components.
- Manage configuration and capability declarations through `manifest.json` and capability ledger files, allowing runtime flexibility without source code changes.

## Development Philosophy

The agent assisting with Iris development must prioritize comprehensive, production-grade solutions. Instructions should be thorough and detailed. Robustness, maintainability, and future extensibility are encouraged. The architecture must support multiple implementation strategies so the user can choose the most effective path at any stage. No component should be artificially limited in a way that blocks progress toward a fully functional local voice assistant.

## Operational Flexibility

The project shall not assume or enforce any single development environment, editor, or toolchain beyond standard Rust, Cargo, and Tauri practices. External helper processes, such as Python-based services for TTS, may be used when they provide the most practical path forward. The human user holds ultimate authority over how capabilities are integrated, tested, and activated. The system must allow graceful evolution from strict read-only behavior toward richer interaction patterns as the user directs.

## Enforcement Rule

These instructions exist to enable successful construction of Iris, not to obstruct it. When conflicts arise between strict safety rules and the practical needs of building a capable assistant, the user's judgment on necessary methods shall take precedence. The development agent must always remain aligned with enabling maximum progress while documenting and highlighting any safety implications.

## Current Public Baseline

The public repository is source-first and should remain easy for users to clone, validate, manually test, and submit narrow fixes. Keep contact text exactly as `super.mangmail@gmail.com` wherever a public email is needed.

Allowed public contribution scope: bug fixes, diagnostics fixes, documentation fixes, compatibility fixes, and safety-preserving test coverage for existing behavior.

The active runtime baseline includes local Ollama text/vision inference, native local ASR, Kokoro ONNX TTS, one-shot image/camera/screen-area evidence probes, Iris-owned local memory, restricted Hermes memory broker/staging, and OneDrive cold-archive policy only.

Hermes remains disabled by default, fail-closed, text-only, sequential, single-model, and restricted to `iris_query_memory` and `iris_propose_memory`. Hermes must not expose acting tools or access shell, file edit, browser, clipboard, window, process, automation, plugin, OneDrive, raw memory, model switching, model pulling, fallback-model, or external-network surfaces.

Before a public cleanup commit or push, run:

```powershell
cargo fmt --all -- --check
cargo build --workspace
cargo test --workspace
cargo clippy --workspace
cargo run -p xtask
cargo run -p iris-runtime -- --self-check
cargo run -p iris-runtime -- --dashboard-json
npm run test:voice
git diff --check
git status --short
```

## Deferred Phase 1 Behavior Rules Layer

When Alejandro directs work on the Phase 1 behavior/rules layer, finalize that behavior/rules layer only. Do not redesign or expand Iris around it.

Goal: barebones deterministic output checks for proposed Iris responses before display or speech. This is not user-input censorship. Iris remains local-first, adult-only, non-agentic, minimal, blunt/funny/unsanitized in tone, and structurally bounded.

Do not add UI, buttons, panels, dashboards, modes, settings, personality graphs, policy DSLs, classifier models, LLM judges, regex, NLP, tokenizers, cloud calls, telemetry, dependencies, memory storage, logging systems, unrelated refactors, unrelated cleanup, or docs unless required for that exact slice.

Keep simple pure code only: `Decision`, `RuleCategory`, `EvaluationResult`, `BehaviorRules`, deterministic `check_*` functions, and focused unit tests.

Runtime invariant: Iris may see, listen, think, remember with permission, and respond. Iris may not act. Current runtime action support is zero. Do not add or enable mouse or keyboard control, clipboard access, shell or process execution, runtime network calls, browser automation, plugins, scripting, accessibility/window control, or autonomous computer use.

Core personality: Iris may be blunt, funny, sarcastic, profane, irreverent, flirty, raunchy, encouraging, direct, and warm when appropriate. Iris must not be cruel using private context, manipulative, coercive, sexually exploitative, deceptive, controlling, shame-based, obsessive, falsely agentic, or self-harm encouraging. Iris may be edgy from personality; Iris may not be edgy by weaponizing private memory.

Output shape: `decision` as Allowed or Blocked, `category`, `reason`, and `refusal_text` when blocked. Do not build a policy engine.

Required categories: `None`, `ActionClaim`, `AdultHardBoundary`, `SubstanceEncouragement`, `MemoryWeaponization`, `ToxicNudge`, `UnsafeExercise`, and `SelfHarmEncouragement`.

Required functions: `safe_refusal_for()`, `check_action_claim()`, `check_adult_boundary()`, `check_substance_boundary()`, `check_private_memory_weaponization()`, `check_nudge_boundary()`, `check_exercise_safety()`, and `check_self_harm_boundary()`.

Use lowercase substring checks only. No regex. No NLP. No tokenizers. No new crates. Use ASCII apostrophes in source strings for Windows and PowerShell safety.

Refusals must be short, blunt, and non-corporate. Use these exact strings or very close equivalents:

- `ActionClaim`: "Nope. I can't act on your system, and I'm not going to fake it."
- `AdultHardBoundary`: "I'm not touching that one. Reframe it or drop it."
- `SubstanceEncouragement`: "Stop there. Bad idea. Grab water and reset."
- `MemoryWeaponization`: "Not doing that. I can keep it funny without turning private stuff into a weapon."
- `ToxicNudge`: "I'm here to help, not nag. Reset the tone."
- `UnsafeExercise`: "Nope. Sit down, breathe, and rest. We're not training through that."
- `SelfHarmEncouragement`: "No. I'm not helping you hurt yourself. Stop and get real-world help."

`check_action_claim()` blocks proposed Iris output that falsely claims Iris acted on the computer, including: `i clicked`, `i can click`, `i opened`, `i already opened`, `i just opened`, `i'll open`, `i can open it`, `i sent`, `i sent it`, `i just sent`, `i deleted`, `i changed your files`, `i changed it`, `i ran the command`, `i ran it`, `i fixed your computer`, `i fixed it`, and `i controlled the window`. Allow manual/user-controlled phrasing such as: `Here is what I see.`, `Here is what I would do next.`, `Here is the command you can run.`, `Here is the text you can paste.`, `I can explain the next step.`, and `I can draft that for you.` Do not add action tools.

`check_adult_boundary()` allows adult humor, profanity, sexual innuendo, crude jokes, flirtatious banter, and consensual adult roleplay when it does not cross hard boundaries. Block minors, underage, unknown-age sexual content, coercion, non-consent, blackmail, sexual threats, stalking, doxxing, sexual humiliation using private data, sexualization of real private people without consent, and intoxicated, unconscious, impaired, or unable-to-consent people. Use simple lowercase substring triggers. Do not sanitize normal adult humor.

`check_substance_boundary()` blocks encouragement of recreational drug use, alcohol misuse, nicotine use, steroid use, stimulant misuse, unsafe supplement use, and medication use to push through discomfort or improve performance. Block: `try drugs`, `take drugs`, `use drugs`, `smoke weed`, `smoke a cigarette`, `have a cigarette`, `use nicotine`, `nicotine`, `vape`, `steroid`, `steroids`, `juicing up`, `adderall misuse`, `take a pill to push through`, `drink more alcohol`, and `use stimulants`. Do not block generic `smoke` alone. Allow smoke alarm, smoke from an outlet, water, food, rest, breathing, slowing down, stopping, and getting real-world help.

`check_private_memory_weaponization(text, is_evaluating_private_context)` allows when `is_evaluating_private_context` is false. When true, block using private memory for cruelty, sexual targeting, manipulation, humiliation, leverage, exposure, insults, or jokes about insecurity, relationships, finances, health, family, trauma, failures, private embarrassment, sexual content, or emotional vulnerability. Block phrases including `remember you failed`, `leak your`, `use your secret`, `shame you for`, `leverage your`, `you're still broke`, `because of your trauma`, and `use that against you`. Allow helpful context such as minimal UI preference, runtime cannot act, and pasteable PowerShell preference.

`check_nudge_boundary()` allows light real-world nudges like drink water, stretch, rest eyes, check posture, eat, take out trash, switch laundry, step away briefly, and do one small reset. Iris may nudge, not command; encourage, not shame; remind, not monitor. Block nagging, shame, guilt trips, productivity monitoring, scoring the user, obsessive routines, and parent tone. Block phrases including `you lazy`, `score your life`, `failing your routine`, `bad job`, `get to work or else`, `disappointing tracking`, `you always do this`, and `i'm disappointed in you`. Do not build a reminder scheduler, habit tracker, wellness dashboard, productivity system, or settings.

`check_exercise_safety(text, user_impaired_or_unwell)` allows simple voluntary exercise counting when explicitly asked for `jumping_jacks`, `pushups`, `squats`, `situps`, `arm_raises`, or `plank_timer`. This is a rule check only, not camera integration. Allow count reps, breathe, drink water, rest, slow down, and stop if it hurts. If `user_impaired_or_unwell` is true, block exercise encouragement/counting. Also block `push through pain`, `no pain no gain`, `ignore the injury`, `keep going if it hurts`, `fat shaming`, and `burn away those failures`. Do not diagnose injuries, prescribe treatment, recommend substances, shame the user's body, score fitness, estimate calories, or store exercise history.

`check_self_harm_boundary()` blocks clear self-harm encouragement using specific triggers so safe support/refusal language does not block itself. Block: `kill yourself`, `go kill yourself`, `you should kill yourself`, `go hurt yourself`, `you should hurt yourself`, `hurt yourself now`, `go cut yourself`, `you should cut yourself`, `make yourself bleed`, `end your life`, `you should die`, `go die`, and `nobody would miss you`. Do not use broad `hurt yourself` or `cut yourself` alone as triggers. Allow safe support language such as `do not hurt yourself`, `don't hurt yourself`, `stop and get help`, `call emergency services`, `talk to someone nearby`, `you matter`, `step away from anything dangerous`, and `I'm not helping you hurt yourself`. Keep this minimal. Do not build a mental-health system.

Required focused tests: block false action claims and variants; allow manual-command phrasing; allow blunt/profane adult humor that does not cross hard boundaries; block sexual minor/unknown-age content; block non-consent/coercion/blackmail/sexual threats; block stalking/doxxing; block sexual humiliation using private data; block sexualization of real private people without consent; block intoxicated/impaired/unable-to-consent sexual content; block drug/alcohol/nicotine/steroid/stimulant/supplement/medication encouragement; allow generic smoke/fire context; block smoke weed/cigarette/nicotine/vape; allow water/food/rest/breathing/slow down/stop/get help; block private-memory humiliation/manipulation; allow helpful project/context memory use; allow light real-world nudges; block shame/nag/productivity scoring language; allow exercise counting request when safe; block exercise when `user_impaired_or_unwell` is true; block push-through-pain exercise language; block self-harm encouragement; allow safe self-harm support language; self-harm refusal text does not block itself; return short non-corporate refusal text; no modes; no UI.

After focused tests pass, stop. Do not continue into UI, memory storage, classifier models, LLM judges, settings, dashboards, scheduling, camera integration, logging, or Phase 2.
