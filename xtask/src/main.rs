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
        "docs/installer-preflight.md",
        "docs/iris-architecture.md",
        "scripts/iris_preflight_wizard.ps1",
        "scripts/iris_setup_wizard.ps1",
        ".github/workflows/bug-check.yml",
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

fn assert_public_docs(root: &Path) -> Result<(), String> {
    let readme = read(root.join("README.md"))?;
    let contributing = read(root.join("CONTRIBUTING.md"))?;
    let notice = read(root.join("NOTICE.md"))?;
    let license = read(root.join("LICENSE"))?;
    let security = read(root.join("SECURITY.md"))?;
    let spec = read(root.join("SPEC.md"))?;
    let limitations = read(root.join("known-limitations.md"))?;
    let download = read(root.join("docs/download-and-run.md"))?;
    let architecture = read(root.join("docs/iris-architecture.md"))?;
    let installer = read(root.join("docs/installer-preflight.md"))?;
    let ci = read(root.join(".github/workflows/bug-check.yml"))?;

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
        "disabled by default",
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
        "cargo run -p xtask",
        "npm run test:voice",
    ] {
        if !ci.contains(required) {
            return Err(format!(
                "bug-check GitHub Actions workflow missing `{required}`"
            ));
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
    if !architecture.contains("That is not fully active in v0.1")
        || !architecture.contains("prompt-injection defense")
        || !architecture.contains("OneDrive is currently a policy target")
    {
        return Err("architecture doc must distinguish current Iris/Hermes/OneDrive capability from future memory roaming".to_string());
    }
    if !installer.contains("Iris Setup Wizard.bat")
        || !installer.contains("ollama pull huihui_ai/gemma-4-abliterated:e2b")
        || !installer.contains("never installs or downloads")
    {
        return Err(
            "installer doc must describe setup wizard repairs and read-only preflight".to_string(),
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
        "EXPOSED_TOOLS = (\"iris_query_memory\", \"iris_propose_memory\")",
        "def startup_check()",
        "def iris_query_memory(",
        "def iris_propose_memory(",
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
        "EXPOSED_TOOLS = [\"iris_query_memory\", \"iris_propose_memory\"]",
        "ACTING_TOOLS: list[str] = []",
        "sequentialTasksOnly",
        "multiModelDebate",
        "parallelInferenceStreams",
        "contains_prompt_injection_text",
        "stdin",
        "stdout",
        "No files edited, commands run, or tests executed",
        "No external browsing was performed",
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
        "\"enabled\": false",
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
        "\"external_network\": false",
        "\"enabled_by_default\": false",
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
    if tools != ["iris_query_memory", "iris_propose_memory"] {
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

        assert_eq!(tools, ["iris_query_memory", "iris_propose_memory"]);
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

        assert!(profile.contains("\"enabled_by_default\": false"));
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
}
