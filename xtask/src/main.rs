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
    assert_cognition_boundaries(&root)?;
    assert_forbidden_api_absence(&root)?;
    Ok(())
}

fn workspace_root() -> Result<PathBuf, String> {
    std::env::current_dir().map_err(|err| err.to_string())
}

fn assert_required_files(root: &Path) -> Result<(), String> {
    for relative in [
        "AGENTS.md",
        "SPEC.md",
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
    ] {
        let path = root.join(relative);
        if !path.exists() {
            return Err(format!("required file missing: {relative}"));
        }
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
