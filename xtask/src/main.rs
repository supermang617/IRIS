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
        "crates/iris-hardware/Cargo.toml",
        "crates/iris-ollama/Cargo.toml",
        "crates/iris-status/Cargo.toml",
        "crates/iris-ui/Cargo.toml",
        "src-tauri/Cargo.toml",
        "src-tauri/tauri.conf.json",
        "src-tauri/icons/icon.ico",
        "app/index.html",
        "docs/adaptive-shell.md",
        "docs/download-and-run.md",
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
        "scripts/test_windows_release_download.ps1",
        "scripts/test_windows_msix_signature.ps1",
        "scripts/test_windows_signed_installer_readiness.ps1",
        "scripts/test_windows_installer.ps1",
        ".github/dependabot.yml",
        ".github/workflows/ci.yml",
        ".github/workflows/dependency-review.yml",
        ".github/workflows/release.yml",
        "plugins/hermes_sidecar/sidecar.py",
        "plugins/memory/iris_broker/provider.py",
        "profiles/iris_restricted.json",
    ] {
        let path = root.join(relative);
        if !path.exists() {
            return Err(format!("required file missing: {relative}"));
        }
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
        "git diff --check",
    ] {
        if !ci.contains(required) {
            return Err(format!("CI GitHub Actions workflow missing `{required}`"));
        }
    }
    for required in [
        "v[0-9]+.[0-9]+.[0-9]+",
        "scripts\\package_windows_release.ps1",
        "scripts\\test_windows_release_download.ps1",
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
        "Phase 1: Manual Desktop Readiness",
        "Start Iris.ps1 -SelfCheck",
        "docs/manual-test.md",
        "No fallback models",
        "No autonomous computer use",
    ] {
        if !finish_checklist.contains(required) {
            return Err(format!("finish checklist missing `{required}`"));
        }
    }
    if !architecture.contains("That is not fully active in v0.1")
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
    if !windows_installer.contains("iris-windows.zip")
        || !windows_installer.contains("iris-windows.zip.sha256")
        || !windows_installer.contains("%LOCALAPPDATA%\\Programs\\Iris")
        || !windows_installer.contains("no runtime computer automation")
    {
        return Err(
            "windows installer doc must describe ZIP assets, optional install path, and safety boundary"
                .to_string(),
        );
    }
    if !signed_installer.contains("MSIX with App Installer")
        || !signed_installer.contains("makeappx.exe")
        || !signed_installer.contains("signtool.exe")
        || !signed_installer.contains("no runtime external network")
    {
        return Err(
            "signed installer decision doc must describe MSIX recommendation, tooling, signing, and safety boundary"
                .to_string(),
        );
    }
    if !runtime_orchestration
        .contains("The Iris launcher starts Ollama hidden/minimized when needed")
        || !runtime_orchestration.contains("Ollama runs as the local model service")
        || !runtime_orchestration.contains("Hermes remains a restricted Iris-owned sidecar")
        || !runtime_orchestration.contains("parallelInferenceStreams: 1")
        || !runtime_orchestration.contains("Do not configure Hermes as a Windows startup app yet")
    {
        return Err(
            "runtime orchestration doc must describe Iris/Ollama/Hermes process model and settings"
                .to_string(),
        );
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
            "Invoke-WebRequest -Uri \"http://127.0.0.1:11434/api/tags\"",
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
