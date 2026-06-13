use std::{
    fs,
    io::{self, BufRead, Write},
    path::Path,
    process::Command,
};

fn main() {
    if let Err(error) = run() {
        eprintln!("Project Iris runtime error: {error}");
        std::process::exit(1);
    }
}

fn run() -> Result<(), String> {
    let args = std::env::args().skip(1).collect::<Vec<_>>();
    match args.first().map(String::as_str) {
        Some("--ask") => {
            let text = args
                .get(1)
                .ok_or_else(|| "--ask requires one text argument".to_string())?;
            print_startup_banner()?;
            print_response(text);
            Ok(())
        }
        Some("--image-probe") => {
            let image_path = args
                .get(1)
                .ok_or_else(|| "--image-probe requires an image path".to_string())?;
            let prompt = args
                .get(2)
                .ok_or_else(|| "--image-probe requires a direct user prompt".to_string())?;
            print_startup_banner()?;
            print_image_probe_response(image_path, prompt);
            Ok(())
        }
        Some("--interactive") => run_interactive(),
        Some("--dashboard-json") => {
            let snapshot = current_dashboard_snapshot()?;
            let json = serde_json::to_string_pretty(&snapshot).map_err(|err| err.to_string())?;
            println!("{json}");
            Ok(())
        }
        Some("--self-check") | None => {
            print_startup_banner()?;
            run_live_self_check()
        }
        Some("--help") | Some("-h") => {
            print_help();
            Ok(())
        }
        Some(other) => Err(format!("unsupported Iris runtime option: {other}")),
    }
}

fn print_startup_banner() -> Result<(), String> {
    let snapshot = current_dashboard_snapshot()?;

    println!("Project Iris v0.1 initialized.");
    println!("{}", snapshot.core_invariant);
    println!("Safety status:");
    for line in iris_ui::safety_status_lines() {
        println!("- {line}");
    }
    println!(
        "Windows Iris: platform={}, model={}, provider={}, num_ctx_ceiling={}",
        snapshot.platform, snapshot.model.id, snapshot.model.provider, snapshot.num_ctx_ceiling
    );
    println!(
        "Model policy: single_model_only=true, fallback_models_allowed={}, runtime_external_network={}, loopback_only={}",
        snapshot.model.fallback_models_allowed,
        snapshot.model.runtime_external_network,
        snapshot.model.loopback_only
    );
    println!("Hardware basis: {}", snapshot.hardware.basis);
    Ok(())
}

fn current_dashboard_snapshot() -> Result<iris_status::DashboardSnapshot, String> {
    let cwd = std::env::current_dir().map_err(|err| err.to_string())?;
    let manifest_path = iris_config::find_manifest_path(&cwd)?;
    let manifest = iris_config::load_manifest_from_workspace(&cwd)?;
    let hardware = iris_hardware::scan_system();
    let _workspace_root = manifest_path
        .parent()
        .ok_or_else(|| "manifest path has no parent".to_string())?;
    Ok(iris_status::build_dashboard_snapshot(&manifest, &hardware))
}

fn run_live_self_check() -> Result<(), String> {
    let cwd = std::env::current_dir().map_err(|err| err.to_string())?;
    let manifest_path = iris_config::find_manifest_path(&cwd)?;
    let workspace_root = manifest_path
        .parent()
        .ok_or_else(|| "manifest path has no parent".to_string())?;
    let manifest = iris_config::load_manifest_from_workspace(&cwd)?;

    validate_runtime_prerequisites(workspace_root, &manifest)?;
    validate_python_prerequisites(workspace_root)?;
    validate_agentic_prerequisites(workspace_root)?;

    let settings = iris_ollama::OllamaSettings::from_manifest(&manifest)?;
    let client = iris_ollama::OllamaClient::new(settings)?;
    let health_prompt = iris_ui::gate_typed_text("Reply with exactly: IRIS_SELF_CHECK_OK");
    client
        .health_check(&health_prompt)
        .map_err(|error| format!("Ollama/model health check failed: {error}"))?;

    println!("Iris live self-check passed.");
    Ok(())
}

fn validate_runtime_prerequisites(
    workspace_root: &Path,
    manifest: &iris_config::ProjectManifest,
) -> Result<(), String> {
    for (label, path) in [
        (
            "Kokoro model",
            workspace_root.join(&manifest.tts_policy.model_path),
        ),
        (
            "Kokoro voices",
            workspace_root.join(&manifest.tts_policy.voices_path),
        ),
        (
            "Kokoro helper",
            workspace_root.join(&manifest.tts_policy.helper_path),
        ),
        (
            "Whisper ASR model",
            workspace_root.join("models/whisper/ggml-tiny.en.bin"),
        ),
        (
            "Hermes restricted profile",
            workspace_root.join("profiles/iris_restricted.json"),
        ),
        (
            "Hermes sidecar",
            workspace_root.join("plugins/hermes_sidecar/sidecar.py"),
        ),
        (
            "Hermes memory broker provider",
            workspace_root.join("plugins/memory/iris_broker/provider.py"),
        ),
        (
            "Hermes Agent profile",
            workspace_root.join("profiles/hermes_agent_0_16_0.json"),
        ),
        (
            "Hermes agentic profile",
            workspace_root.join("profiles/iris_agentic.json"),
        ),
        (
            "Hermes browser profile",
            workspace_root.join("profiles/iris_browser.json"),
        ),
        (
            "Hermes ACP bridge",
            workspace_root.join("plugins/hermes_acp/iris_acp.py"),
        ),
        (
            "Hermes ACP action tools",
            workspace_root.join("plugins/hermes_acp/iris_action_tools.py"),
        ),
        (
            "Hermes ACP browser tools",
            workspace_root.join("plugins/hermes_acp/iris_browser_tools.py"),
        ),
        (
            "Hermes ACP memory tools",
            workspace_root.join("plugins/hermes_acp/iris_memory_tools.py"),
        ),
    ] {
        require_nonempty_file(label, &path)?;
    }

    let profile_path = workspace_root.join("profiles/iris_restricted.json");
    let profile_bytes = fs::read(&profile_path)
        .map_err(|err| format!("failed to read {}: {err}", profile_path.display()))?;
    let profile: serde_json::Value = serde_json::from_slice(&profile_bytes)
        .map_err(|err| format!("invalid Hermes restricted profile JSON: {err}"))?;
    if profile.get("enabled").and_then(serde_json::Value::as_bool) != Some(true) {
        return Err("Hermes restricted profile must be enabled".to_string());
    }
    let tools = profile
        .get("tools")
        .and_then(serde_json::Value::as_array)
        .ok_or_else(|| "Hermes restricted profile tools are missing".to_string())?;
    for required in [
        "iris_query_memory",
        "iris_propose_memory",
        "iris_web_research",
    ] {
        if !tools.iter().any(|tool| tool.as_str() == Some(required)) {
            return Err(format!(
                "Hermes restricted profile is missing required tool {required}"
            ));
        }
    }
    Ok(())
}

fn validate_agentic_prerequisites(workspace_root: &Path) -> Result<(), String> {
    let hermes_python = workspace_root.join(".iris-runtime/hermes/.venv/Scripts/python.exe");
    let agent_browser = workspace_root
        .join(".iris-runtime/browser/node_modules/agent-browser/bin/agent-browser-win32-x64.exe");
    let chrome =
        workspace_root.join(".iris-runtime/browser/browsers/chrome-149.0.7827.115/chrome.exe");
    for (label, path) in [
        ("Hermes Agent Python", hermes_python.as_path()),
        ("agent-browser", agent_browser.as_path()),
        ("Chrome for Testing", chrome.as_path()),
    ] {
        require_nonempty_file(label, path)?;
    }

    let hermes = Command::new(&hermes_python)
        .args([
            "-c",
            "import importlib.metadata as m; print(m.version('hermes-agent')); print(m.version('agent-client-protocol'))",
        ])
        .output()
        .map_err(|err| format!("failed to start Hermes Agent version check: {err}"))?;
    if !hermes.status.success()
        || String::from_utf8_lossy(&hermes.stdout)
            .lines()
            .collect::<Vec<_>>()
            != ["0.16.0", "0.9.0"]
    {
        return Err("Hermes Agent or ACP package version does not match the pinned runtime".into());
    }

    let browser = Command::new(&agent_browser)
        .arg("--version")
        .output()
        .map_err(|err| format!("failed to start agent-browser version check: {err}"))?;
    if !browser.status.success()
        || String::from_utf8_lossy(&browser.stdout).trim() != "agent-browser 0.27.2"
    {
        return Err("agent-browser version does not match the pinned runtime".into());
    }
    Ok(())
}

fn require_nonempty_file(label: &str, path: &Path) -> Result<(), String> {
    let metadata =
        fs::metadata(path).map_err(|err| format!("missing {label} {}: {err}", path.display()))?;
    if !metadata.is_file() || metadata.len() == 0 {
        return Err(format!(
            "{label} is not a non-empty file: {}",
            path.display()
        ));
    }
    Ok(())
}

fn validate_python_prerequisites(workspace_root: &Path) -> Result<(), String> {
    let output = Command::new("python")
        .args(["-c", "import kokoro_onnx, numpy, soundfile"])
        .output()
        .map_err(|err| format!("failed to start Python prerequisite check: {err}"))?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!(
            "Python voice prerequisites are unavailable: {}",
            stderr.trim()
        ));
    }

    for script in [
        workspace_root.join("tools/kokoro_tts.py"),
        workspace_root.join("plugins/hermes_sidecar/sidecar.py"),
        workspace_root.join("plugins/memory/iris_broker/provider.py"),
    ] {
        let status = Command::new("python")
            .args(["-m", "py_compile"])
            .arg(&script)
            .status()
            .map_err(|err| format!("failed to validate {}: {err}", script.display()))?;
        if !status.success() {
            return Err(format!(
                "Python prerequisite is invalid: {}",
                script.display()
            ));
        }
    }
    Ok(())
}

fn print_response(text: &str) {
    match model_response(text) {
        Ok(response) => println!("{}", response.text),
        Err(error) => println!("Local model unavailable: {error}"),
    }
}

fn print_image_probe_response(image_path: &str, prompt: &str) {
    match image_probe_response(image_path, prompt) {
        Ok(response) => println!("{}", response.text),
        Err(error) => println!("Local image probe unavailable: {error}"),
    }
}

fn run_interactive() -> Result<(), String> {
    print_startup_banner()?;
    println!("Iris typed HUD ready.");
    println!("Controls: :panic stops local cognition, :reset resumes it, :quit exits.");

    let stdin = io::stdin();
    let mut hud = iris_ui::LocalHud::new();
    let mut stdout = io::stdout();

    loop {
        write!(stdout, "iris> ").map_err(|err| err.to_string())?;
        stdout.flush().map_err(|err| err.to_string())?;

        let mut line = String::new();
        let bytes = stdin
            .lock()
            .read_line(&mut line)
            .map_err(|err| err.to_string())?;
        if bytes == 0 {
            println!();
            break;
        }

        let text = line.trim();
        if text.is_empty() {
            continue;
        }

        match text {
            ":quit" | ":exit" => break,
            ":panic" => {
                hud.panic_stop();
                println!("Panic Stop active. Dummy cognition is cancelled.");
            }
            ":reset" => {
                hud.reset_after_panic_stop();
                println!("Panic Stop cleared. Dummy cognition is available.");
            }
            ":status" => {
                let state = if hud.is_panic_stopped() {
                    "Panic Stop active"
                } else {
                    "Ready"
                };
                println!("Status: {state}");
                for line in iris_ui::safety_status_lines() {
                    println!("- {line}");
                }
            }
            _ => {
                let response = match model_response(text) {
                    Ok(response) => response,
                    Err(error) => iris_core_types::AssistantResponse::text_only(format!(
                        "Local model unavailable: {error}"
                    )),
                };
                println!("{}", response.text);
            }
        }
    }

    Ok(())
}

fn model_response(text: &str) -> Result<iris_core_types::AssistantResponse, String> {
    let cwd = std::env::current_dir().map_err(|err| err.to_string())?;
    let manifest = iris_config::load_manifest_from_workspace(&cwd)?;
    let settings = iris_ollama::OllamaSettings::from_manifest(&manifest)?;
    let client = iris_ollama::OllamaClient::new(settings)?;
    let gated_context = iris_ui::gate_typed_text(text);
    Ok(client.respond(&gated_context))
}

fn image_probe_response(
    image_path: &str,
    prompt: &str,
) -> Result<iris_core_types::AssistantResponse, String> {
    let cwd = std::env::current_dir().map_err(|err| err.to_string())?;
    let manifest = iris_config::load_manifest_from_workspace(&cwd)?;
    let settings = iris_ollama::OllamaSettings::from_manifest(&manifest)?;
    let client = iris_ollama::OllamaClient::new(settings)?;
    Ok(client.respond_to_image_probe(image_path, prompt))
}

fn print_help() {
    println!("Project Iris local text runtime");
    println!("Usage:");
    println!("  iris-runtime --self-check");
    println!("  iris-runtime --ask \"typed HUD text\"");
    println!("  iris-runtime --image-probe \"path-to-image\" \"direct user prompt\"");
    println!("  iris-runtime --interactive");
    println!("  iris-runtime --dashboard-json");
}

#[cfg(test)]
mod tests {
    use super::*;

    fn unique_temp_dir() -> std::path::PathBuf {
        std::env::temp_dir().join(format!(
            "iris-runtime-test-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .expect("clock")
                .as_nanos()
        ))
    }

    #[test]
    fn require_nonempty_file_rejects_missing_and_empty_files() {
        let root = unique_temp_dir();
        fs::create_dir_all(&root).expect("temp directory");
        let missing = root.join("missing.bin");
        assert!(require_nonempty_file("fixture", &missing).is_err());

        let empty = root.join("empty.bin");
        fs::write(&empty, []).expect("empty fixture");
        assert!(require_nonempty_file("fixture", &empty).is_err());

        let full = root.join("full.bin");
        fs::write(&full, [1_u8]).expect("full fixture");
        assert!(require_nonempty_file("fixture", &full).is_ok());

        fs::remove_dir_all(root).expect("remove temp directory");
    }
}
