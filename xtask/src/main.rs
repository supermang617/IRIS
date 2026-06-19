use std::fs;
use std::path::{Path, PathBuf};

fn main() {
    match run_audit() {
        Ok(()) => {
            println!("Project Iris xtask audit passed.");
        }
        Err(error) => {
            eprintln!("Project Iris xtask audit failed: {error}");
            std::process::exit(1);
        }
    }
}

fn run_audit() -> Result<(), String> {
    let root = workspace_root()?;
    assert_required_files(&root)?;
    assert_manifest_policy(&root)?;
    assert_public_docs(&root)?;
    assert_local_diagnostics_are_parseable(&root)?;
    assert_cognition_boundaries(&root)?;
    assert_hermes_phase2_profile(&root)?;
    assert_hermes_agentic_profile(&root)?;
    assert_hermes_acp_runtime(&root)?;
    assert_hermes_browser_runtime(&root)?;
    assert_desktop_ui(&root)?;
    assert_conversational_voice_guards(&root)?;
    assert_dynamic_system_context(&root)?;
    assert_release_hardening(&root)?;
    assert_forbidden_api_absence(&root)?;
    Ok(())
}

fn workspace_root() -> Result<PathBuf, String> {
    std::env::current_dir().map_err(|err| err.to_string())
}

fn assert_required_files(root: &Path) -> Result<(), String> {
    for relative in [
        "AGENTS.md",
        "CONTRIBUTING.md",
        "LICENSE",
        "NOTICE.md",
        "README.md",
        "SPEC.md",
        "SECURITY.md",
        "known-limitations.md",
        "manifest.json",
        "capabilities/v0_1_capability_ledger.toml",
        "crates/iris-paths/Cargo.toml",
        "crates/iris-redaction/Cargo.toml",
        "crates/iris-context-gate/Cargo.toml",
        "crates/iris-cognition/Cargo.toml",
        "crates/iris-config/Cargo.toml",
        "crates/iris-dynamic-context/Cargo.toml",
        "crates/iris-dynamic-context/src/lib.rs",
        "crates/iris-hardware/Cargo.toml",
        "crates/iris-ollama/Cargo.toml",
        "crates/iris-status/Cargo.toml",
        "crates/iris-ui/Cargo.toml",
        "src-tauri/Cargo.toml",
        "src-tauri/tauri.conf.json",
        "src-tauri/icons/icon.ico",
        "app/composer-state.js",
        "app/composer-state.test.mjs",
        "app/dynamic-context-state.js",
        "app/dynamic-context-state.test.mjs",
        "app/speech-output.js",
        "app/speech-output.test.mjs",
        "app/index.html",
        "app/main.js",
        "app/styles.css",
        "docs/adaptive-shell.md",
        "docs/download-and-run.md",
        "docs/dynamic-system-context.md",
        "docs/finish-checklist.md",
        "docs/github-settings.md",
        "docs/installer-preflight.md",
        "docs/iris-architecture.md",
        "docs/manual-test-checklist-v0.1.1.md",
        "docs/manual-end-user-test-v0.1.0.md",
        "docs/signed-installer-decision.md",
        "docs/runtime-orchestration.md",
        "docs/windows-installer.md",
        "scripts/install_iris_windows.ps1",
        "scripts/iris_document_ocr.ps1",
        "scripts/iris_preflight_wizard.ps1",
        "scripts/iris_setup_wizard.ps1",
        "scripts/package_windows_release.ps1",
        "scripts/package_windows_msix.ps1",
        "scripts/provision_hermes_acp.ps1",
        "scripts/provision_iris_browser.ps1",
        "scripts/test_python.ps1",
        "scripts/test_vision_text_diagnostics.ps1",
        "scripts/benchmark_hermes_model.py",
        "scripts/test_windows_beginner_installer.ps1",
        "scripts/test_windows_release_download.ps1",
        "scripts/test_github_v1_release.ps1",
        "scripts/test_windows_msix_signature.ps1",
        "scripts/test_windows_signed_installer_readiness.ps1",
        "scripts/test_windows_installer.ps1",
        ".github/dependabot.yml",
        ".github/workflows/ci.yml",
        ".github/workflows/dependency-review.yml",
        ".github/workflows/release.yml",
        "plugins/hermes_sidecar/sidecar.py",
        "plugins/hermes_acp/iris_acp.py",
        "plugins/hermes_acp/iris_memory_tools.py",
        "plugins/hermes_acp/iris_browser_tools.py",
        "plugins/hermes_acp/test_iris_browser_tools.py",
        "plugins/hermes_acp/test_iris_memory_tools.py",
        "plugins/memory/iris_broker/provider.py",
        "profiles/iris_restricted.json",
        "profiles/iris_agentic.json",
        "profiles/hermes_agent_0_16_0.json",
        "profiles/iris_browser.json",
    ] {
        let path = root.join(relative);
        if !path.exists() {
            return Err(format!("required file missing: {relative}"));
        }
    }
    Ok(())
}

fn assert_desktop_ui(root: &Path) -> Result<(), String> {
    let index = read(root.join("app/index.html"))?;
    let styles = read(root.join("app/styles.css"))?;
    let main = read(root.join("app/main.js"))?;
    let package = read(root.join("package.json"))?;
    let tauri = read(root.join("src-tauri/tauri.conf.json"))?;

    for required in [
        "<textarea",
        "id=\"response-resize-handle\"",
        "role=\"separator\"",
        "class=\"composer-footer\"",
        "class=\"tool-group\"",
        "id=\"panic-button\"",
        "id=\"send-button\"",
    ] {
        if !index.contains(required) {
            return Err(format!("desktop UI shell missing `{required}`"));
        }
    }
    for required in [
        "--response-height",
        ".response-resize-handle",
        ".composer-footer",
        "backdrop-filter: blur(28px)",
        "@media (prefers-reduced-motion: reduce)",
    ] {
        if !styles.contains(required) {
            return Err(format!("desktop UI styling missing `{required}`"));
        }
    }
    for required in [
        "shouldSubmitComposer",
        "startResponseResize",
        "resizeResponseWithKeyboard",
        "iris.responseHeight",
    ] {
        if !main.contains(required) {
            return Err(format!("desktop UI behavior missing `{required}`"));
        }
    }
    if !package.contains("app/composer-state.test.mjs")
        || !tauri.contains("\"height\": 410")
        || !tauri.contains("\"minHeight\": 280")
    {
        return Err(
            "desktop UI tests and production window dimensions must stay enabled".to_string(),
        );
    }
    Ok(())
}

fn assert_conversational_voice_guards(root: &Path) -> Result<(), String> {
    let policy = read(root.join("crates/iris-policy/src/lib.rs"))?;
    let ollama = read(root.join("crates/iris-ollama/src/lib.rs"))?;
    let tauri = read(root.join("src-tauri/src/lib.rs"))?;
    let main = read(root.join("app/main.js"))?;
    let speech = read(root.join("app/speech-chunks.js"))?;
    let kokoro = read(root.join("tools/kokoro_tts.py"))?;

    for (name, content, required) in [
        (
            "runtime response policy",
            policy.as_str(),
            "Do not censor ordinary profanity",
        ),
        (
            "native ASR cancellation",
            tauri.as_str(),
            "cancel_native_asr",
        ),
        (
            "wake-word transcription bias",
            tauri.as_str(),
            "Iris. Hey Iris. Iris wake up.",
        ),
        (
            "stale listener cancellation",
            main.as_str(),
            "cancelActiveAsr",
        ),
        (
            "speech markup normalization",
            speech.as_str(),
            "normalizeSpeechText",
        ),
        (
            "Kokoro leading silence",
            kokoro.as_str(),
            "LEAD_SILENCE_SECONDS = 0.75",
        ),
    ] {
        if !content.contains(required) {
            return Err(format!("{name} missing `{required}`"));
        }
    }
    if ollama.contains("evaluate_output(") {
        return Err(
            "normal Ollama responses must not be censored by the legacy output scanner".to_string(),
        );
    }
    Ok(())
}

fn assert_dynamic_system_context(root: &Path) -> Result<(), String> {
    let manifest = read(root.join("manifest.json"))?;
    let cargo = read(root.join("crates/iris-dynamic-context/Cargo.toml"))?;
    let profile = read(root.join("crates/iris-dynamic-context/src/lib.rs"))?;
    let ollama = read(root.join("crates/iris-ollama/src/lib.rs"))?;
    let tauri = read(root.join("src-tauri/src/lib.rs"))?;
    let app = read(root.join("app/main.js"))?;
    let package = read(root.join("package.json"))?;
    let sidecar = read(root.join("plugins/hermes_sidecar/sidecar.py"))?;
    let docs = read(root.join("docs/dynamic-system-context.md"))?;

    for required in [
        "\"storage_path\": \".iris-data/dynamic_context.json\"",
        "\"stores_raw_text\": false",
        "\"half_life_days\": 30",
        "\"max_observations\": 64",
    ] {
        if !manifest.contains(required) {
            return Err(format!(
                "dynamic context manifest policy missing `{required}`"
            ));
        }
    }
    if cargo.contains("reqwest")
        || cargo.contains("tokio")
        || cargo.contains("regex")
        || cargo.contains("rust-bert")
    {
        return Err("dynamic context must remain deterministic and dependency-light".to_string());
    }
    for required in [
        "DEFAULT_HALF_LIFE_DAYS",
        "DEFAULT_MAX_OBSERVATIONS",
        "profile_serialization_never_contains_raw_user_text",
        "serialized_profile_survives_restart_without_raw_history",
        "current user request, factual accuracy, and explicit user preferences override it",
    ] {
        if !profile.contains(required) {
            return Err(format!(
                "dynamic context implementation missing `{required}`"
            ));
        }
    }
    for required in [
        "respond_with_dynamic_context",
        "format_dynamic_context",
        "dynamic_context_is_advisory_and_precedes_the_current_request",
    ] {
        if !ollama.contains(required) {
            return Err(format!(
                "Ollama dynamic context boundary missing `{required}`"
            ));
        }
    }
    for required in [
        "dynamic_context_status",
        "dynamic_context_set_enabled",
        "dynamic_context_reset",
        "observe_dynamic_context_nonfatal",
        "style_text",
    ] {
        if !tauri.contains(required) {
            return Err(format!("Tauri dynamic context path missing `{required}`"));
        }
    }
    if !app.contains("parseDynamicContextCommand")
        || !app.contains("styleText: originalText")
        || !package.contains("app/dynamic-context-state.test.mjs")
        || !sidecar.contains("\"dynamicContext\"")
        || !docs.contains("It does not store user messages")
    {
        return Err(
            "dynamic context UI controls, Hermes presentation, tests, and privacy docs must remain enabled"
                .to_string(),
        );
    }
    Ok(())
}

fn assert_local_diagnostics_are_parseable(root: &Path) -> Result<(), String> {
    let voice_events = root.join("diagnostics/voice-events.jsonl");
    if !voice_events.exists() {
        return Ok(());
    }
    let content = read(&voice_events)?;
    for (index, line) in content.lines().enumerate() {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        if !looks_like_voice_event_json(trimmed) || contains_invalid_json_escape(trimmed) {
            return Err(format!(
                "diagnostics/voice-events.jsonl line {} is not valid Iris JSONL",
                index + 1
            ));
        }
    }
    Ok(())
}

fn looks_like_voice_event_json(line: &str) -> bool {
    line.starts_with('{')
        && line.ends_with('}')
        && line.contains("\"timestamp_ms\":")
        && line.contains("\"event\":")
        && line.contains("\"detail\":")
}

fn contains_invalid_json_escape(line: &str) -> bool {
    let bytes = line.as_bytes();
    let mut index = 0;
    while index < bytes.len() {
        if bytes[index] == b'\\' {
            let Some(next) = bytes.get(index + 1).copied() else {
                return true;
            };
            match next {
                b'"' | b'\\' | b'/' | b'b' | b'f' | b'n' | b'r' | b't' => index += 2,
                b'u' => {
                    if index + 5 >= bytes.len()
                        || !bytes[index + 2..=index + 5]
                            .iter()
                            .all(u8::is_ascii_hexdigit)
                    {
                        return true;
                    }
                    index += 6;
                }
                _ => return true,
            }
        } else {
            index += 1;
        }
    }
    false
}

fn assert_public_docs(root: &Path) -> Result<(), String> {
    let readme = read(root.join("README.md"))?;
    let contributing = read(root.join("CONTRIBUTING.md"))?;
    let notice = read(root.join("NOTICE.md"))?;
    let license = read(root.join("LICENSE"))?;
    let security = read(root.join("SECURITY.md"))?;
    let spec = read(root.join("SPEC.md"))?;
    let limitations = read(root.join("known-limitations.md"))?;
    let download = read(root.join("docs/download-and-run.md"))?;
    let finish_checklist = read(root.join("docs/finish-checklist.md"))?;
    let architecture = read(root.join("docs/iris-architecture.md"))?;
    let adaptive_shell = read(root.join("docs/adaptive-shell.md"))?;
    let installer = read(root.join("docs/installer-preflight.md"))?;
    let signed_installer = read(root.join("docs/signed-installer-decision.md"))?;
    let runtime_orchestration = read(root.join("docs/runtime-orchestration.md"))?;
    let windows_installer = read(root.join("docs/windows-installer.md"))?;
    let ci = read(root.join(".github/workflows/ci.yml"))?;
    let release = read(root.join(".github/workflows/release.yml"))?;
    let dependabot = read(root.join(".github/dependabot.yml"))?;
    let github_settings = read(root.join("docs/github-settings.md"))?;
    let manual_checklist = read(root.join("docs/manual-test-checklist-v0.1.1.md"))?;
    let manual_end_user_test = read(root.join("docs/manual-end-user-test-v0.1.0.md"))?;
    let launcher = read(root.join("Start Iris.ps1"))?;
    let package_script = read(root.join("scripts/package_windows_release.ps1"))?;
    let preflight_script = read(root.join("scripts/iris_preflight_wizard.ps1"))?;
    let setup_script = read(root.join("scripts/iris_setup_wizard.ps1"))?;
    let windows_installer_script = read(root.join("scripts/install_iris_windows.ps1"))?;
    let github_release_smoke = read(root.join("scripts/test_github_v1_release.ps1"))?;

    for (name, content) in [
        ("README.md", &readme),
        ("CONTRIBUTING.md", &contributing),
        ("NOTICE.md", &notice),
        ("SPEC.md", &spec),
        ("docs/download-and-run.md", &download),
    ] {
        if !content.contains("Produced by Alejandro Pinto") {
            return Err(format!("{name} must credit Alejandro Pinto"));
        }
    }
    for (name, content) in [
        ("README.md", &readme),
        ("CONTRIBUTING.md", &contributing),
        ("NOTICE.md", &notice),
        ("SECURITY.md", &security),
        ("docs/download-and-run.md", &download),
    ] {
        if !content.contains("super.mangmail@gmail.com") {
            return Err(format!("{name} must include the public contact email"));
        }
    }
    if !license.contains("MIT License") || !license.contains("Alejandro Pinto") {
        return Err("LICENSE must be MIT and credit Alejandro Pinto".to_string());
    }
    for required in [
        "Hermes",
        "enabled for local memory query/proposal by default",
        "iris_query_memory",
        "iris_propose_memory",
        "OneDrive",
        ".iris-memory-archive.enc",
    ] {
        if !readme.contains(required) {
            return Err(format!(
                "README.md missing public integration note `{required}`"
            ));
        }
    }
    for forbidden in ["No persistent memory.", "No plugins."] {
        if limitations.contains(forbidden) || readme.contains(forbidden) {
            return Err(format!(
                "public docs contain stale limitation `{forbidden}`"
            ));
        }
    }
    for (name, content) in [
        ("known-limitations.md", limitations.as_str()),
        ("docs/download-and-run.md", download.as_str()),
        ("docs/iris-architecture.md", architecture.as_str()),
        (
            "docs/runtime-orchestration.md",
            runtime_orchestration.as_str(),
        ),
        ("docs/adaptive-shell.md", adaptive_shell.as_str()),
    ] {
        if content.contains("v0.1") {
            return Err(format!(
                "{name} contains stale current-release v0.1 language"
            ));
        }
    }
    if !security.contains("Hermes raw memory database/file access")
        || !security.contains("Hermes OneDrive access")
    {
        return Err("SECURITY.md missing Hermes boundary notes".to_string());
    }
    if !contributing.contains("Bug fixes")
        || !contributing.contains("Avoid Without Explicit Approval")
    {
        return Err("CONTRIBUTING.md must describe bug-fix contribution scope".to_string());
    }
    if !notice.contains("Ollama") || !notice.contains("Kokoro") || !notice.contains("Whisper") {
        return Err("NOTICE.md must include third-party model/runtime notices".to_string());
    }
    for required in [
        "cargo fmt --all -- --check",
        "cargo build --workspace",
        "cargo test --workspace",
        "cargo clippy --workspace",
        "npm run test:voice",
        "npm run test:python",
        "cargo run -p xtask",
        "git diff --check",
    ] {
        if !ci.contains(required) {
            return Err(format!("CI GitHub Actions workflow missing `{required}`"));
        }
    }
    for required in [
        "v[0-9]+",
        "gh release download v1",
        "scripts\\package_windows_release.ps1",
        "scripts\\test_windows_release_download.ps1",
        "scripts\\test_windows_beginner_installer.ps1",
        "release/dist/iris-windows-installer.zip",
        "release/dist/iris-windows-installer.zip.sha256",
        "Download `iris-windows-installer.zip`",
        "Double-click `Install Iris.bat`",
        "release/dist/iris-windows.zip",
        "release/dist/iris-windows.zip.sha256",
        "contents: write",
    ] {
        if !release.contains(required) {
            return Err(format!(
                "release GitHub Actions workflow missing `{required}`"
            ));
        }
    }
    for required in [
        "package-ecosystem: cargo",
        "package-ecosystem: github-actions",
        "package-ecosystem: npm",
    ] {
        if !dependabot.contains(required) {
            return Err(format!("Dependabot config missing `{required}`"));
        }
    }
    if !download.contains("git clone https://github.com/supermang617/IRIS.git")
        || !download.contains("docs/manual-test.md")
        || !download.contains("Bug fixes")
    {
        return Err(
            "download guide must describe cloning, manual testing, and bug-fix scope".to_string(),
        );
    }
    for required in [
        "Iris Production Readiness Checklist",
        "Beginner Installer Acceptance",
        "Installed-App Manual Acceptance",
        "Publish `v1`",
        "Move/update only the single `v1` tag",
        "scripts\\test_github_v1_release.ps1",
        "Production-Trusted Installer",
    ] {
        if !finish_checklist.contains(required) {
            return Err(format!("finish checklist missing `{required}`"));
        }
    }
    if !architecture.contains("That is not fully active in v1")
        || !architecture.contains("prompt-injection defense")
        || !architecture.contains("OneDrive is currently a policy target")
    {
        return Err("architecture doc must distinguish current Iris/Hermes/OneDrive capability from future memory roaming".to_string());
    }
    if !installer.contains("Iris Setup Wizard.bat")
        || !installer.contains("ollama pull huihui_ai/gemma-4-abliterated:e2b")
        || !installer.contains("never installs or downloads")
        || !installer.contains("Tesseract")
    {
        return Err(
            "installer doc must describe setup wizard repairs and read-only preflight".to_string(),
        );
    }
    for required in [
        "Invoke-PreflightProbe",
        "Stop-ProcessTree",
        "TimeoutSeconds = 20",
        "ollama list failed or timed out",
    ] {
        if !preflight_script.contains(required) {
            return Err(format!(
                "preflight script missing bounded external probe `{required}`"
            ));
        }
    }
    if preflight_script.contains("& ollama list") {
        return Err("preflight script must not call `ollama list` without a timeout".to_string());
    }
    if !setup_script
        .contains("Open Iris after installation; the launcher self-check will verify the configured local model")
    {
        return Err(
            "setup wizard must use beginner-safe noninteractive model-check wording".to_string(),
        );
    }
    if !windows_installer.contains("iris-windows.zip")
        || !windows_installer.contains("iris-windows.zip.sha256")
        || !windows_installer.contains("iris-windows-installer.zip")
        || !windows_installer.contains("%LOCALAPPDATA%\\Programs\\Iris")
        || !windows_installer.contains("setup wizard before the final self-check")
        || !windows_installer.contains("Agentic browser, file, PowerShell, and process tools")
    {
        return Err(
            "windows installer doc must describe ZIP assets, optional install path, and safety boundary"
                .to_string(),
        );
    }
    if !signed_installer.contains("MSIX with App Installer")
        || !signed_installer.contains("makeappx.exe")
        || !signed_installer.contains("signtool.exe")
        || !signed_installer.contains("approval-gated Hermes session")
    {
        return Err(
            "signed installer decision doc must describe MSIX recommendation, tooling, signing, and safety boundary"
                .to_string(),
        );
    }
    if !runtime_orchestration
        .contains("The Iris desktop window opens first, then starts Ollama hidden")
        || !runtime_orchestration.contains("Ollama runs as the local model service")
        || !runtime_orchestration.contains("Safe Hermes remains a restricted Iris-owned sidecar")
        || !runtime_orchestration.contains("pinned Hermes Agent 0.16.0")
        || !runtime_orchestration
            .contains("Agentic action tools: `read_file`, `write_file`, `patch`, `search_files`,")
        || !runtime_orchestration.contains("`terminal`, `process`")
        || !runtime_orchestration.contains("parallelInferenceStreams: 1")
        || !runtime_orchestration.contains("Do not configure Hermes as a Windows startup app yet")
    {
        return Err(
            "runtime orchestration doc must describe Iris/Ollama/Hermes process model and settings"
                .to_string(),
        );
    }
    if !windows_installer_script
        .contains("\"bin\\iris-tauri.exe\") -WorkingDirectory $installRootResolved")
        || windows_installer_script.contains(
            "New-Shortcut -ShortcutPath (Join-Path $DesktopDir \"Iris.lnk\") -TargetPath (Join-Path $installRootResolved \"Start Iris.bat\")",
        )
    {
        return Err(
            "installed Iris shortcuts must launch the GUI executable directly without a console launcher"
                .to_string(),
        );
    }
    for required in [
        "gh release view $Tag",
        "refs/heads/main",
        "refs/tags/$Tag",
        "Remote main and $Tag must point to the same commit",
        "install-iris-windows.ps1.sha256",
        "iris-windows-installer.zip.sha256",
        "iris-windows.zip.sha256",
        "DownloadPayloads",
    ] {
        if !github_release_smoke.contains(required) {
            return Err(format!("GitHub v1 release smoke test missing `{required}`"));
        }
    }
    for (name, content) in [
        ("Start Iris.ps1", launcher.as_str()),
        (
            "scripts/package_windows_release.ps1",
            package_script.as_str(),
        ),
    ] {
        for required in [
            "function Start-OllamaForIris",
            "function Test-OllamaRuntimeCompatible",
            "{ \"library\" }",
            "$env:OLLAMA_CONTEXT_LENGTH",
            "Invoke-WebRequest -Uri \"http://127.0.0.1:11434/api/tags\"",
            "Invoke-WebRequest -Uri \"http://127.0.0.1:11434/api/ps\"",
            "Start-Process -FilePath \"ollama\" -ArgumentList \"serve\" -WindowStyle Hidden",
        ] {
            if !content.contains(required) {
                return Err(format!(
                    "{name} missing Ollama auto-start requirement `{required}`"
                ));
            }
        }
    }
    for required in [
        "Actions default token read-only",
        "contents: write",
        "no unnecessary secrets",
        "Pages source",
        "GitHub default CodeQL setup",
        "Dependabot",
        "Branch Protection Recommendation",
    ] {
        if !github_settings.contains(required) {
            return Err(format!("GitHub settings doc missing `{required}`"));
        }
    }
    for required in [
        "iris-windows.zip",
        "iris-windows.zip.sha256",
        "Start Iris.ps1 --self-check",
        "Ollama text ask",
        "Image probe",
        "Hermes status",
        "Local-only binding",
        "super.mangmail@gmail.com",
    ] {
        if !manual_checklist.contains(required) {
            return Err(format!("manual test checklist missing `{required}`"));
        }
    }
    if !manual_end_user_test
        .contains("Ollama `/api/show` reports the configured model has `vision`")
        || !manual_end_user_test.contains("Hermes should not be opened separately")
        || !manual_end_user_test.contains("install-iris-windows.ps1")
        || !manual_end_user_test.contains("Tesseract document OCR")
    {
        return Err(
            "manual end-user test report must capture installer, Hermes, and image-probe status"
                .to_string(),
        );
    }
    Ok(())
}

fn assert_manifest_policy(root: &Path) -> Result<(), String> {
    let manifest = read(root.join("manifest.json"))?;
    for required in [
        "\"target_platform\": \"windows\"",
        "\"provider\": \"ollama_local\"",
        "\"model_id\": \"huihui_ai/gemma-4-abliterated:e2b\"",
        "\"single_model_only\": true",
        "\"fallback_models_allowed\": false",
        "\"num_ctx_ceiling\": 8192",
        "\"unified_model\": true",
        "\"vision_capable\": true",
        "\"image_input_capable\": true",
        "\"separate_vision_model\": false",
        "\"runtime_external_network\": \"disabled\"",
        "\"reserved_system_memory_ratio\": 0.35",
        "\"provider\": \"kokoro_onnx_python\"",
        "\"voice\": \"af_heart\"",
    ] {
        if !manifest.contains(required) {
            return Err(format!("manifest missing required policy: {required}"));
        }
    }
    Ok(())
}

fn assert_cognition_boundaries(root: &Path) -> Result<(), String> {
    let manifest = read(root.join("crates/iris-cognition/Cargo.toml"))?;
    for forbidden in ["iris-capture", "iris-scene", "iris-voice", "iris-ui"] {
        if manifest.contains(forbidden) {
            return Err(format!(
                "iris-cognition must not depend on forbidden crate {forbidden}"
            ));
        }
    }

    let source = read(root.join("crates/iris-cognition/src/lib.rs"))?;
    for forbidden in ["RawFrame", "RawOcrText", "RawAudio", "ClipboardText"] {
        if source.contains(forbidden) {
            return Err(format!(
                "iris-cognition source must not accept raw observation type {forbidden}"
            ));
        }
    }
    Ok(())
}

fn assert_hermes_phase2_profile(root: &Path) -> Result<(), String> {
    let provider = read(root.join("plugins/memory/iris_broker/provider.py"))?;
    let sidecar = read(root.join("plugins/hermes_sidecar/sidecar.py"))?;
    for required in [
        "DEFAULT_BROKER_URL = \"http://127.0.0.1:48731\"",
        "IRIS_OLLAMA_GENERATE_URL = \"http://127.0.0.1:11434/api/generate\"",
        "STATUS_ENDPOINT = \"/memory/status\"",
        "SEARCH_ENDPOINT = \"/memory/search\"",
        "PROPOSE_ENDPOINT = \"/memory/propose\"",
        "EXPOSED_TOOLS = (\"iris_query_memory\", \"iris_propose_memory\", \"iris_web_research\")",
        "def startup_check()",
        "def _validate_staging_status_counts(",
        "pendingStagingItems",
        "decidedStagingItems",
        "def iris_query_memory(",
        "def iris_propose_memory(",
        "def iris_web_research(",
        "PROMPT_INJECTION_PHRASES",
        "web_proposal_missing_evidence",
        "def inference_policy()",
        "\"modelAutoSelection\": False",
        "\"parallelInferenceStreams\": 1",
        "manifest.json",
        "provider != \"ollama_local\"",
    ] {
        if !provider.contains(required) {
            return Err(format!("Hermes iris_broker provider missing `{required}`"));
        }
    }
    for forbidden in [
        "subprocess",
        "os.system",
        "popen",
        "run(",
        "call(",
        "Popen",
        "pyautogui",
        "keyboard",
        "mouse",
        "pyperclip",
        "clipboard",
        "playwright",
        "selenium",
        "win32gui",
        "win32clipboard",
        "write_text",
        "patch",
    ] {
        if provider.contains(forbidden) {
            return Err(format!(
                "Hermes iris_broker provider contains forbidden acting surface `{forbidden}`"
            ));
        }
    }
    for required in [
        "iris_broker.startup_check()",
        "runtime_status()",
        "ALLOWED_MODES = {\"reason\", \"research\", \"code_suggestion\"}",
        "EXPOSED_TOOLS = [\"iris_query_memory\", \"iris_propose_memory\", \"iris_web_research\"]",
        "ACTING_TOOLS: list[str] = []",
        "sequentialTasksOnly",
        "multiModelDebate",
        "parallelInferenceStreams",
        "contains_prompt_injection_text",
        "should_summarize_memory",
        "iris_broker.iris_generate_text",
        "propose_memory_if_requested",
        "stdin",
        "stdout",
    ] {
        if !sidecar.contains(required) {
            return Err(format!("Hermes sidecar missing `{required}`"));
        }
    }
    for forbidden in [
        "subprocess",
        "os.system",
        "popen",
        "Popen",
        "pyautogui",
        "keyboard",
        "mouse",
        "pyperclip",
        "clipboard",
        "playwright",
        "selenium",
        "win32gui",
        "win32clipboard",
        "write_text",
        "open(",
        "requests",
        "httpx",
    ] {
        if sidecar.contains(forbidden) {
            return Err(format!(
                "Hermes sidecar contains forbidden acting or external surface `{forbidden}`"
            ));
        }
    }

    let profile = read(root.join("profiles/iris_restricted.json"))?;
    for required in [
        "\"name\": \"iris_restricted\"",
        "\"enabled\": true",
        "\"provider\": \"ollama_local\"",
        "\"model_source\": \"manifest.json\"",
        "\"endpoint\": \"http://127.0.0.1:11434/api/generate\"",
        "\"endpoint_source\": \"iris_ollama_default\"",
        "\"uses_existing_iris_model\": true",
        "\"model_switching\": false",
        "\"model_pulling\": false",
        "\"model_auto_selection\": false",
        "\"critic_worker_split\": false",
        "\"multi_model_debate\": false",
        "\"fallback_models\": false",
        "\"parallel_inference_streams\": 1",
        "\"gpu_dogpiling_guard\": \"single_sequential_stream\"",
        "\"hardware_tier_routing\": false",
        "\"model_optimization\": false",
        "\"parallel_hermes_tasks\": false",
        "\"provider\": \"iris_broker\"",
        "\"broker_url\": \"http://127.0.0.1:48731\"",
        "\"startup_status_check\": true",
        "\"fail_closed\": true",
        "\"direct_database_access\": false",
        "\"active_memory_write\": false",
        "\"onedrive_sync_enabled_by_default\": false",
        "\"active_memory_location\": \"local_iris_owned_only\"",
        "\"cold_archive_location\": \"onedrive_encrypted_only\"",
        "\"archive_extension\": \".iris-memory-archive.enc\"",
        "\"export_requires_encryption\": true",
        "\"import_requires_iris_reconciliation\": true",
        "\"hermes_onedrive_access\": false",
        "\"live_sqlite_on_onedrive\": false",
        "\"live_json_memory_on_onedrive\": false",
        "\"export_available\": false",
        "\"acting_tools\": []",
        "\"external_network\": true",
        "\"enabled_by_default\": true",
        "\"lifecycle_owner\": \"iris\"",
        "\"script\": \"plugins/hermes_sidecar/sidecar.py\"",
        "\"transport\": \"stdin_stdout_json\"",
        "\"max_task_chars\": 2000",
        "\"max_response_chars\": 4000",
        "\"runtime_tool_audit\": true",
        "\"startup_fails_on_acting_tools\": true",
        "\"prompt_injection_guard\": true",
        "\"sequential_tasks_only\": true",
        "\"max_broker_request_bytes\": 16384",
        "\"max_memory_query_chars\": 120",
        "\"max_memory_proposal_chars\": 240",
        "\"max_memory_results\": 10",
        "\"research_requires_explicit_user_request\": true",
        "\"code_suggestion_text_only\": true",
    ] {
        if !profile.contains(required) {
            return Err(format!("Hermes restricted profile missing `{required}`"));
        }
    }
    let tools = profile_array_values(&profile, "tools")?;
    if tools
        != [
            "iris_query_memory",
            "iris_propose_memory",
            "iris_web_research",
        ]
    {
        return Err(format!(
            "Hermes restricted profile exposes unexpected tools: {}",
            tools.join(", ")
        ));
    }
    let acting_tools = profile_array_values(&profile, "acting_tools")?;
    if !acting_tools.is_empty() {
        return Err("Hermes restricted profile must expose no acting tools".to_string());
    }
    for forbidden in [
        "terminal",
        "shell",
        "process",
        "command",
        "code_execution",
        "file_write",
        "file_edit",
        "patch",
        "browser",
        "computer",
        "window",
        "clipboard",
        "scheduler",
        "cron",
        "automation_plugin",
    ] {
        if !profile.contains(&format!("\"{forbidden}\"")) {
            return Err(format!(
                "Hermes restricted profile must explicitly forbid `{forbidden}`"
            ));
        }
    }
    Ok(())
}

fn assert_hermes_agentic_profile(root: &Path) -> Result<(), String> {
    let profile = read(root.join("profiles/iris_agentic.json"))?;
    for required in [
        "\"name\": \"iris_agentic\"",
        "\"enabled\": true",
        "\"startup_default\": false",
        "\"requires_explicit_user_session\": true",
        "\"inactivity_timeout_minutes\": 30",
        "\"expires_on_iris_exit\": true",
        "\"expires_on_panic_stop\": true",
        "\"expires_on_mode_change\": true",
        "\"duplicate_sessions_allowed\": false",
        "\"provider\": \"hermes_agent\"",
        "\"version\": \"0.16.0\"",
        "\"transport\": \"acp_stdio\"",
        "\"lifecycle_owner\": \"iris\"",
        "\"local_ollama_only\": true",
        "\"cloud_fallback\": false",
        "\"native_durable_memory\": false",
        "\"boundary\": \"advisory_unrestricted_powershell\"",
        "\"scope_expansion_requires_confirmation\": true",
        "\"authority\": \"iris\"",
        "\"direct_promotion\": false",
        "\"tool_results_are_untrusted_evidence\": true",
        "\"provenance_required\": true",
    ] {
        if !profile.contains(required) {
            return Err(format!("Hermes agentic profile missing `{required}`"));
        }
    }
    let tools = profile_array_values(&profile, "session_approved_tools")?;
    if tools
        != [
            "read_file",
            "write_file",
            "patch",
            "search_files",
            "terminal",
            "process",
            "browser_open",
            "browser_snapshot",
            "browser_click",
            "browser_fill",
            "browser_press",
            "browser_screenshot",
            "browser_get_url",
            "browser_upload",
            "browser_download",
            "browser_close",
        ]
    {
        return Err(format!(
            "Hermes agentic profile exposes unexpected session tools: {}",
            tools.join(", ")
        ));
    }
    let enabled_tools = profile_array_values(&profile, "currently_enabled_tools")?;
    if enabled_tools
        != [
            "iris_query_memory",
            "iris_propose_memory",
            "read_file",
            "write_file",
            "patch",
            "search_files",
            "terminal",
            "process",
            "browser_open",
            "browser_snapshot",
            "browser_click",
            "browser_fill",
            "browser_press",
            "browser_screenshot",
            "browser_get_url",
            "browser_upload",
            "browser_download",
            "browser_close",
        ]
    {
        return Err(format!(
            "Hermes agentic profile exposes unexpected current tools: {}",
            enabled_tools.join(", ")
        ));
    }
    let acting_tools = profile_array_values(&profile, "currently_enabled_acting_tools")?;
    if acting_tools
        != [
            "read_file",
            "write_file",
            "patch",
            "search_files",
            "terminal",
            "process",
            "browser_open",
            "browser_snapshot",
            "browser_click",
            "browser_fill",
            "browser_press",
            "browser_screenshot",
            "browser_get_url",
            "browser_upload",
            "browser_download",
            "browser_close",
        ]
    {
        return Err(format!(
            "Hermes agentic profile exposes unexpected acting tools: {}",
            acting_tools.join(", ")
        ));
    }
    let risks = profile_array_values(&profile, "always_confirm_risks")?;
    for required in [
        "destructive_git",
        "install_or_admin",
        "credentials",
        "consequential_browser_submission",
        "executable_download",
        "payment",
        "sensitive_files",
        "scope_expansion",
    ] {
        if !risks.iter().any(|risk| risk == required) {
            return Err(format!(
                "Hermes agentic profile is missing confirmation risk `{required}`"
            ));
        }
    }
    Ok(())
}

fn assert_hermes_browser_runtime(root: &Path) -> Result<(), String> {
    let profile = read(root.join("profiles/iris_browser.json"))?;
    let provision = read(root.join("scripts/provision_iris_browser.ps1"))?;
    let browser_tools = read(root.join("plugins/hermes_acp/iris_browser_tools.py"))?;
    let safe_provider = read(root.join("plugins/memory/iris_broker/provider.py"))?;
    for required in [
        "\"provider\": \"agent-browser\"",
        "\"version\": \"0.27.2\"",
        "\"chrome_for_testing_version\": \"149.0.7827.115\"",
        "\"headless_default\": true",
        "\"manual_auth_headed_allowed\": true",
        "\"private_network_navigation\": false",
        "\"normal_browser_profile_reuse\": false",
        "\"dedicated_profile\": \".iris-data/hermes-browser/profile\"",
    ] {
        if !profile.contains(required) {
            return Err(format!("Iris browser profile missing `{required}`"));
        }
    }
    for required in [
        "agent-browser@0.27.2",
        "RZNxZFvnspSxSmpjkZjM0Lv69ArwYr8t",
        "1553389900824037aec828effab3051337df57a571e2f8800ee71cf8ed6fa76d",
        "815ac13164ee3a5fa15a0e119fe868ec8d6ef6b3bd16bbe35ddd1da57c515c56",
    ] {
        if !provision.contains(required) {
            return Err(format!("Iris browser provisioner missing `{required}`"));
        }
    }
    for required in [
        "AGENT_BROWSER_PROFILE",
        "AGENT_BROWSER_CONTENT_BOUNDARIES",
        "IRIS_BROWSER_PREVIEW:",
        "Browser navigation to private or local network addresses is blocked.",
        "consequential browser submission",
        "executable download",
    ] {
        if !browser_tools.contains(required) {
            return Err(format!("Iris browser tools missing `{required}`"));
        }
    }
    if safe_provider.contains("bing.com") || safe_provider.contains("_parse_bing_html") {
        return Err("Safe Hermes must not use Bing HTML scraping".to_string());
    }
    Ok(())
}

fn assert_release_hardening(root: &Path) -> Result<(), String> {
    let tauri = read(root.join("src-tauri/tauri.conf.json"))?;
    for required in [
        "\"csp\": \"default-src 'self' ipc: http://ipc.localhost",
        "script-src 'self'",
        "object-src 'none'",
        "frame-src 'none'",
        "form-action 'none'",
    ] {
        if !tauri.contains(required) {
            return Err(format!("Tauri release CSP missing `{required}`"));
        }
    }

    let package = read(root.join("scripts/package_windows_release.ps1"))?;
    let installer = read(root.join("scripts/install_iris_windows.ps1"))?;
    let release_smoke = read(root.join("scripts/test_windows_release_download.ps1"))?;
    let beginner_smoke = read(root.join("scripts/test_windows_beginner_installer.ps1"))?;
    let installer_smoke = read(root.join("scripts/test_windows_installer.ps1"))?;
    for required in [
        ".iris-runtime\\hermes\\.venv",
        ".iris-runtime\\browser\\node_modules",
        ".iris-runtime\\browser\\browsers",
        "volatile_data_packaged = $false",
    ] {
        if !package.contains(required) {
            return Err(format!("release package script missing `{required}`"));
        }
    }
    for required in ["\".iris-runtime\"", ".iris-runtime\\runtime-manifest.json"] {
        if !installer.contains(required) {
            return Err(format!(
                "installer missing packaged runtime rule `{required}`"
            ));
        }
    }
    for required in [
        "iris-windows-installer.zip",
        "Install Iris.bat",
        "-RunSetup",
        "-LaunchAfterInstall",
    ] {
        if !package.contains(required) {
            return Err(format!(
                "release package script missing beginner installer rule `{required}`"
            ));
        }
    }
    for required in [
        "Beginner installer bundle SHA256 mismatch",
        "payload ZIP with an invalid SHA256",
        "setup wizard before the final live self-check",
        "bounded self-check behavior",
    ] {
        if !beginner_smoke.contains(required) {
            return Err(format!(
                "beginner installer smoke test missing `{required}`"
            ));
        }
    }
    for required in [
        "Invoke-SmokeCommand",
        "Stop-ProcessTree",
        "fresh installer smoke",
        "upgrade installer smoke",
        "-SkipSelfCheck",
        "installed Hermes Python probe",
        "timed out after $TimeoutSeconds seconds",
    ] {
        if !installer_smoke.contains(required) {
            return Err(format!(
                "Windows installer smoke test missing bounded command rule `{required}`"
            ));
        }
    }
    for required in [
        "SelfCheckTimeoutSeconds",
        "SkipSelfCheck",
        "IRIS_PREFLIGHT_FAST_LOCAL_ONLY",
        "Installed Iris self-check timed out",
        "Invoke-InstallerProbe",
        "timed out after $TimeoutSeconds seconds",
        "Stop-ProcessTree",
        "installer-self-check.log",
    ] {
        if !installer.contains(required) {
            return Err(format!(
                "installer missing bounded self-check rule `{required}`"
            ));
        }
    }
    for required in [
        "CI release launcher self-check unexpectedly succeeded without runner prerequisites",
        "Test-ExpectedCiPrerequisiteFailure",
    ] {
        if !release_smoke.contains(required) {
            return Err(format!("release ZIP smoke test missing `{required}`"));
        }
    }
    let setup_position = installer
        .find("if ($RunSetup)")
        .ok_or_else(|| "installer missing setup execution".to_string())?;
    let self_check_position = installer
        .find("Invoke-InstalledSelfCheck -InstallRoot")
        .ok_or_else(|| "installer missing final self-check".to_string())?;
    if setup_position > self_check_position {
        return Err("installer must run setup before final self-check".to_string());
    }
    for forbidden_runtime in [
        ".iris-runtime\\hermes\\home",
        ".iris-data",
        ".iris-runtime\\browser\\profile",
        ".iris-runtime\\browser\\downloads",
        ".iris-runtime\\browser\\command-output",
    ] {
        if !release_smoke.contains(forbidden_runtime) {
            return Err(format!(
                "release smoke test must reject volatile runtime path `{forbidden_runtime}`"
            ));
        }
    }

    let ci = read(root.join(".github/workflows/ci.yml"))?;
    for required in [
        "node-version: \"24\"",
        "python-version: \"3.11\"",
        "scripts\\provision_hermes_acp.ps1",
        "scripts\\provision_iris_browser.ps1",
        "npm run test:python",
        "cargo run -p xtask",
        "cargo run -p iris-runtime -- --dashboard-json",
        "cargo clippy --workspace -- -D warnings",
        "iris-dependency-inventory",
    ] {
        if !ci.contains(required) {
            return Err(format!("CI release hardening missing `{required}`"));
        }
    }

    for path in [
        "crates/iris-cognition/Cargo.toml",
        "crates/iris-config/Cargo.toml",
        "crates/iris-context-gate/Cargo.toml",
        "crates/iris-core-types/Cargo.toml",
        "crates/iris-dynamic-context/Cargo.toml",
        "crates/iris-hardware/Cargo.toml",
        "crates/iris-ollama/Cargo.toml",
        "crates/iris-paths/Cargo.toml",
        "crates/iris-policy/Cargo.toml",
        "crates/iris-redaction/Cargo.toml",
        "crates/iris-runtime/Cargo.toml",
        "crates/iris-status/Cargo.toml",
        "crates/iris-ui/Cargo.toml",
        "src-tauri/Cargo.toml",
        "xtask/Cargo.toml",
    ] {
        if !read(root.join(path))?.contains("version = \"1.0.0\"") {
            return Err(format!("{path} must use release version 1.0.0"));
        }
    }
    if !read(root.join("package.json"))?.contains("\"version\": \"1.0.0\"")
        || !tauri.contains("\"version\": \"1.0.0\"")
        || !read(root.join("manifest.json"))?.contains("\"version\": \"v1\"")
        || !read(root.join("crates/iris-core-types/src/lib.rs"))?
            .contains("PROJECT_VERSION: &str = \"v1\"")
        || read(root.join("crates/iris-runtime/src/main.rs"))?
            .contains("Project Iris v0.1 initialized")
        || !read(root.join("scripts/test_vision_text_diagnostics.ps1"))?
            .contains("Project Iris v1 initialized")
    {
        return Err(
            "npm, Tauri, Iris manifest, shared constant, and runtime banner versions must be 1.0.0"
                .to_string(),
        );
    }
    Ok(())
}

fn assert_hermes_acp_runtime(root: &Path) -> Result<(), String> {
    let metadata = read(root.join("profiles/hermes_agent_0_16_0.json"))?;
    for required in [
        "\"version\": \"0.16.0\"",
        "\"release_tag\": \"v2026.6.5\"",
        "\"release_commit\": \"3c231eb3979ab9c57d5cd6d02f1d577a3b718b43\"",
        "\"wheel_sha256\": \"accb5a4a4827b41b3d162d2eb0b5f6db585d942ee23a3678ef21fc94d21c34a2\"",
        "\"sigstore_transparency_entry\": 1737513268",
        "\"trusted_publishing\": true",
        "\"agent_client_protocol\": \"0.9.0\"",
        "\"runtime_root\": \".iris-runtime/hermes\"",
    ] {
        if !metadata.contains(required) {
            return Err(format!("Hermes ACP metadata missing `{required}`"));
        }
    }

    let provision = read(root.join("scripts/provision_hermes_acp.ps1"))?;
    for required in [
        "hermes_agent-0.16.0-py3-none-any.whl",
        "accb5a4a4827b41b3d162d2eb0b5f6db585d942ee23a3678ef21fc94d21c34a2",
        "\"$Wheel[acp]\"",
        "m.version('hermes-agent') == '0.16.0'",
        "m.version('agent-client-protocol') == '0.9.0'",
    ] {
        if !provision.contains(required) {
            return Err(format!("Hermes ACP provisioner missing `{required}`"));
        }
    }

    let launcher = read(root.join("plugins/hermes_acp/iris_acp.py"))?;
    let memory_tools = read(root.join("plugins/hermes_acp/iris_memory_tools.py"))?;
    let action_tools = read(root.join("plugins/hermes_acp/iris_action_tools.py"))?;
    for required in [
        "IRIS_TOOLSET = \"iris-acp-bridge\"",
        "register_iris_memory_tools",
        "disabled_toolsets=DISABLED_TOOLSETS",
        "session_db=None",
        "skip_memory=True",
        "skip_context_files=True",
        "checkpoints_enabled=False",
        "os.environ[\"HERMES_DISABLE_LAZY_INSTALLS\"] = \"1\"",
        "IRIS_MAX_ITERATIONS = 8",
        "IRIS_MAX_TOKENS = 4096",
        "max_iterations=IRIS_MAX_ITERATIONS",
        "max_tokens=IRIS_MAX_TOKENS",
        "reasoning_config={\"enabled\": False}",
        "\"temperature\": 0",
        "\"think\": False",
        "\"num_predict\": IRIS_MAX_TOKENS",
        "tool_names_for_prompt",
        "\"promptScopedTools\": True",
        "\"actingTools\": action_tools",
        "\"nativeDurableMemory\": False",
        "\"mcpAllowed\": False",
        "Iris ACP bridge does not allow MCP servers",
        "IRIS_HERMES_OLLAMA_BASE_URL",
    ] {
        if !launcher.contains(required) {
            return Err(format!("Iris Hermes ACP launcher missing `{required}`"));
        }
    }
    for required in [
        "IRIS_MEMORY_TOOLS = (\"iris_query_memory\", \"iris_propose_memory\")",
        "authority",
        "instructionAuthority",
        "durableMemoryPromoted",
        "requiresUserDecision",
        "IRIS_PROVENANCE:",
    ] {
        if !memory_tools.contains(required) {
            return Err(format!("Iris Hermes memory tools missing `{required}`"));
        }
    }
    for required in [
        "IRIS_ACTION_TOOLS = (",
        "\"read_file\"",
        "\"write_file\"",
        "\"patch\"",
        "\"search_files\"",
        "\"terminal\"",
        "\"process\"",
        "allow_permanent=False",
        "scope expansion",
        "sensitive files",
        "POWERSHELL_DESCRIPTION",
        "\"taskkill.exe\"",
        "_sanitize_subprocess_env",
        "MAX_PROCESS_OUTPUT_CHARS",
        "HERMES_GIT_BASH_PATH",
        "_upstream_file_path",
    ] {
        if !action_tools.contains(required) {
            return Err(format!("Iris Hermes action guards missing `{required}`"));
        }
    }
    for forbidden in [
        "subprocess.run(",
        "subprocess.Popen(",
        "os.system(",
        "shell=True",
    ] {
        if launcher.contains(forbidden) {
            return Err(format!(
                "Iris Hermes ACP launcher contains forbidden execution surface `{forbidden}`"
            ));
        }
    }
    for forbidden in ["shell=True", "cmd.exe", "os.system("] {
        if action_tools.contains(forbidden) {
            return Err(format!(
                "Iris Hermes action adapter contains forbidden execution surface `{forbidden}`"
            ));
        }
    }
    Ok(())
}

fn profile_array_values(input: &str, key: &str) -> Result<Vec<String>, String> {
    let marker = format!("\"{key}\": [");
    let start = input
        .find(&marker)
        .ok_or_else(|| format!("profile array `{key}` missing"))?
        + marker.len();
    let end = input[start..]
        .find(']')
        .ok_or_else(|| format!("profile array `{key}` is unterminated"))?
        + start;
    Ok(input[start..end]
        .split(',')
        .map(|value| value.trim().trim_matches('"').to_string())
        .filter(|value| !value.is_empty())
        .collect())
}

fn assert_forbidden_api_absence(root: &Path) -> Result<(), String> {
    let forbidden_patterns = forbidden_patterns();
    for file in source_files(&root.join("crates"))? {
        let content = read(&file)?;
        for pattern in &forbidden_patterns {
            if is_loopback_inference_file(&file, pattern) {
                continue;
            }
            if is_approved_live_self_check_process_probe(&file, &content, pattern)? {
                continue;
            }
            if is_approved_local_ocr_process_probe(&file, &content, pattern)? {
                continue;
            }
            if content.contains(pattern) {
                return Err(format!(
                    "forbidden API pattern `{pattern}` found in {}",
                    file.display()
                ));
            }
        }
    }
    Ok(())
}

fn is_approved_live_self_check_process_probe(
    file: &Path,
    content: &str,
    pattern: &str,
) -> Result<bool, String> {
    let is_runtime = file
        .components()
        .any(|component| component.as_os_str() == "iris-runtime");
    if !is_runtime || !matches!(pattern, "process::Command" | "Command::new") {
        return Ok(false);
    }
    if !content.contains("fn validate_python_prerequisites") {
        return Ok(false);
    }
    let constructor_count = content.matches("Command::new(").count();
    let python_constructor_count = content.matches("Command::new(\"python\")").count();
    let approved_agentic_probes = [
        "Command::new(&hermes_python)",
        "Command::new(&agent_browser)",
        "fn validate_agentic_prerequisites",
    ];
    if constructor_count != 4
        || python_constructor_count != 2
        || approved_agentic_probes
            .iter()
            .any(|probe| !content.contains(probe))
    {
        return Err(
            "iris-runtime self-check may launch only the four audited prerequisite probes"
                .to_string(),
        );
    }
    Ok(true)
}

fn is_approved_local_ocr_process_probe(
    file: &Path,
    content: &str,
    pattern: &str,
) -> Result<bool, String> {
    let is_ollama = file
        .components()
        .any(|component| component.as_os_str() == "iris-ollama");
    if !is_ollama || !matches!(pattern, "process::Command" | "Command::new") {
        return Ok(false);
    }
    for required in [
        "fn run_tesseract_ocr",
        "fn find_tesseract_executable",
        "IRIS_TESSERACT_EXE",
        "OCR_TIMEOUT",
        "CREATE_NO_WINDOW",
        ".arg(\"stdout\")",
        ".arg(\"--psm\")",
        ".stdout(Stdio::piped())",
        ".stderr(Stdio::piped())",
    ] {
        if !content.contains(required) {
            return Err(format!(
                "local OCR process helper missing audited marker `{required}`"
            ));
        }
    }
    if content.matches("Command::new(").count() != 1 {
        return Err("local OCR may launch only one audited Tesseract process".to_string());
    }
    for forbidden in ["cmd.exe", "powershell", "shell", "/C", "-Command"] {
        if content.contains(forbidden) {
            return Err(format!(
                "local OCR process helper contains forbidden shell marker `{forbidden}`"
            ));
        }
    }
    Ok(true)
}

fn is_loopback_inference_file(file: &Path, pattern: &str) -> bool {
    file.components()
        .any(|component| component.as_os_str() == "iris-ollama")
        && matches!(pattern, "reqwest" | "std::net::")
}

fn forbidden_patterns() -> Vec<String> {
    [
        ("std::process", "::Command"),
        ("process", "::Command"),
        ("Command", "::new"),
        ("std::net", "::"),
        ("Tcp", "Stream"),
        ("Tcp", "Listener"),
        ("Udp", "Socket"),
        ("clipboard", "::"),
        ("ar", "board"),
        ("copy", "pasta"),
        ("Send", "Input"),
        ("mouse", "_event"),
        ("keybd", "_event"),
        ("req", "west"),
        ("ureq", ""),
        ("hyper", "::"),
    ]
    .into_iter()
    .map(|(left, right)| format!("{left}{right}"))
    .collect()
}

fn source_files(root: &Path) -> Result<Vec<PathBuf>, String> {
    let mut files = Vec::new();
    collect_source_files(root, &mut files)?;
    Ok(files)
}

fn collect_source_files(path: &Path, files: &mut Vec<PathBuf>) -> Result<(), String> {
    if !path.exists() {
        return Ok(());
    }
    for entry in fs::read_dir(path).map_err(|err| err.to_string())? {
        let entry = entry.map_err(|err| err.to_string())?;
        let path = entry.path();
        if path.is_dir() {
            collect_source_files(&path, files)?;
        } else if path.extension().is_some_and(|ext| ext == "rs") {
            files.push(path);
        }
    }
    Ok(())
}

fn read(path: impl AsRef<Path>) -> Result<String, String> {
    fs::read_to_string(path.as_ref()).map_err(|err| format!("{}: {err}", path.as_ref().display()))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_root() -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .expect("xtask has workspace parent")
            .to_path_buf()
    }

    #[test]
    fn hermes_restricted_profile_audit_passes() {
        assert_hermes_phase2_profile(&test_root()).unwrap();
    }

    #[test]
    fn hermes_restricted_profile_exposes_only_memory_tools() {
        let profile = read(test_root().join("profiles/iris_restricted.json")).unwrap();
        let tools = profile_array_values(&profile, "tools").unwrap();
        let acting_tools = profile_array_values(&profile, "acting_tools").unwrap();

        assert_eq!(
            tools,
            [
                "iris_query_memory",
                "iris_propose_memory",
                "iris_web_research"
            ]
        );
        assert!(acting_tools.is_empty());
    }

    #[test]
    fn hermes_provider_has_no_acting_code_surface() {
        let provider = read(test_root().join("plugins/memory/iris_broker/provider.py")).unwrap();
        let sidecar = read(test_root().join("plugins/hermes_sidecar/sidecar.py")).unwrap();

        for forbidden in [
            "subprocess",
            "os.system",
            "pyautogui",
            "keyboard",
            "mouse",
            "pyperclip",
            "playwright",
            "selenium",
            "win32gui",
            "win32clipboard",
        ] {
            assert!(
                !provider.contains(forbidden),
                "provider contains forbidden acting surface {forbidden}"
            );
            assert!(
                !sidecar.contains(forbidden),
                "sidecar contains forbidden acting surface {forbidden}"
            );
        }
    }

    #[test]
    fn hermes_profile_declares_phase3_lifecycle_bounds() {
        let profile = read(test_root().join("profiles/iris_restricted.json")).unwrap();

        assert!(profile.contains("\"enabled_by_default\": true"));
        assert!(profile.contains("\"lifecycle_owner\": \"iris\""));
        assert!(profile.contains("\"transport\": \"stdin_stdout_json\""));
        assert!(profile.contains("\"research_requires_explicit_user_request\": true"));
        assert!(profile.contains("\"code_suggestion_text_only\": true"));
    }

    #[test]
    fn hermes_profile_declares_phase4_hardening_bounds() {
        let profile = read(test_root().join("profiles/iris_restricted.json")).unwrap();
        let provider = read(test_root().join("plugins/memory/iris_broker/provider.py")).unwrap();
        let sidecar = read(test_root().join("plugins/hermes_sidecar/sidecar.py")).unwrap();

        assert!(profile.contains("\"runtime_tool_audit\": true"));
        assert!(profile.contains("\"startup_fails_on_acting_tools\": true"));
        assert!(profile.contains("\"prompt_injection_guard\": true"));
        assert!(profile.contains("\"sequential_tasks_only\": true"));
        assert!(provider.contains("PROMPT_INJECTION_PHRASES"));
        assert!(provider.contains("web_proposal_missing_evidence"));
        assert!(sidecar.contains("runtime_status()"));
        assert!(sidecar.contains("sequentialTasksOnly"));
    }

    #[test]
    fn hermes_profile_declares_phase5_single_model_policy() {
        let profile = read(test_root().join("profiles/iris_restricted.json")).unwrap();
        let provider = read(test_root().join("plugins/memory/iris_broker/provider.py")).unwrap();
        let sidecar = read(test_root().join("plugins/hermes_sidecar/sidecar.py")).unwrap();

        assert!(profile.contains("\"endpoint\": \"http://127.0.0.1:11434/api/generate\""));
        assert!(profile.contains("\"uses_existing_iris_model\": true"));
        assert!(profile.contains("\"model_auto_selection\": false"));
        assert!(profile.contains("\"critic_worker_split\": false"));
        assert!(profile.contains("\"multi_model_debate\": false"));
        assert!(profile.contains("\"gpu_dogpiling_guard\": \"single_sequential_stream\""));
        assert!(provider.contains("def inference_policy()"));
        assert!(provider.contains("\"parallelInferenceStreams\": 1"));
        assert!(sidecar.contains("multiModelDebate"));
        assert!(sidecar.contains("parallelInferenceStreams"));
    }

    #[test]
    fn hermes_profile_declares_phase6_onedrive_archive_boundary() {
        let profile = read(test_root().join("profiles/iris_restricted.json")).unwrap();

        assert!(profile.contains("\"onedrive_sync_enabled_by_default\": false"));
        assert!(profile.contains("\"active_memory_location\": \"local_iris_owned_only\""));
        assert!(profile.contains("\"cold_archive_location\": \"onedrive_encrypted_only\""));
        assert!(profile.contains("\"archive_extension\": \".iris-memory-archive.enc\""));
        assert!(profile.contains("\"export_requires_encryption\": true"));
        assert!(profile.contains("\"import_requires_iris_reconciliation\": true"));
        assert!(profile.contains("\"hermes_onedrive_access\": false"));
        assert!(profile.contains("\"live_sqlite_on_onedrive\": false"));
        assert!(profile.contains("\"live_json_memory_on_onedrive\": false"));
        assert!(profile.contains("\"export_available\": false"));
    }

    #[test]
    fn diagnostics_escape_check_allows_valid_json_escapes() {
        assert!(!contains_invalid_json_escape(
            r#"{"timestamp_ms":1,"event":"x","detail":"I didn't say \"no\"","mode":"wake"}"#
        ));
        assert!(looks_like_voice_event_json(
            r#"{"timestamp_ms":1,"event":"x","detail":"ok"}"#
        ));
    }

    #[test]
    fn diagnostics_escape_check_rejects_rust_style_escapes() {
        assert!(contains_invalid_json_escape(
            r#"{"timestamp_ms":1,"event":"x","detail":"I didn\'t"}"#
        ));
        assert!(contains_invalid_json_escape(
            r#"{"timestamp_ms":1,"event":"x","detail":"\u{266a}"}"#
        ));
    }
}
