use std::{
    ffi::OsString,
    fs,
    io::{self, BufRead, Write},
    path::{Path, PathBuf},
    process::Command,
};

#[derive(Debug, Clone, PartialEq, Eq)]
struct PythonLaunch {
    executable: PathBuf,
    prefix_args: Vec<OsString>,
}

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

    println!(
        "{} {} initialized.",
        snapshot.project_name, snapshot.project_version
    );
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
        "Model policy: fixed_role_models=2, separate_vision_model=true, fallback_models_allowed={}, runtime_external_network={}, loopback_only={}",
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

    let vision_settings = iris_ollama::OllamaSettings::from_vision_manifest(&manifest)?;
    iris_ollama::OllamaClient::new(vision_settings)?
        .warm_visual_model()
        .map_err(|error| format!("Ollama/vision-model health check failed: {error}"))?;
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
            workspace_root.join("profiles/hermes_agent_0_18_0.json"),
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
    let agent_browser = workspace_root
        .join(".iris-runtime/browser/node_modules/agent-browser/bin/agent-browser-win32-x64.exe");
    require_nonempty_file("agent-browser", &agent_browser)?;
    let browser_executable = find_browser_executable(workspace_root)?;
    require_nonempty_file("Chrome browser", &browser_executable)?;

    let browser = Command::new(&agent_browser)
        .arg("--version")
        .output()
        .map_err(|err| format!("failed to start agent-browser version check: {err}"))?;
    if !browser.status.success()
        || String::from_utf8_lossy(&browser.stdout).trim() != "agent-browser 0.33.2"
    {
        return Err("agent-browser version does not match the pinned runtime".into());
    }
    Ok(())
}

fn find_browser_executable(workspace_root: &Path) -> Result<PathBuf, String> {
    if let Some(configured) = std::env::var_os("IRIS_BROWSER_EXECUTABLE_PATH") {
        let configured = PathBuf::from(configured);
        if !configured.is_absolute() || !configured.is_file() {
            return Err(
                "IRIS_BROWSER_EXECUTABLE_PATH must name an absolute existing compatible Chrome/Chromium executable"
                    .to_string(),
            );
        }
        return Ok(configured);
    }
    for (variable, relative) in [
        ("ProgramFiles", "Google/Chrome/Application/chrome.exe"),
        ("ProgramFiles(x86)", "Google/Chrome/Application/chrome.exe"),
        ("LOCALAPPDATA", "Google/Chrome/Application/chrome.exe"),
    ] {
        if let Some(root) = std::env::var_os(variable) {
            let candidate = PathBuf::from(root).join(relative);
            if candidate.is_file() {
                return Ok(candidate);
            }
        }
    }
    let development_fallback =
        workspace_root.join(".iris-runtime/browser/browsers/chrome-149.0.7827.115/chrome.exe");
    if development_fallback.is_file() {
        return Ok(development_fallback);
    }
    Err(
        "Google Chrome is required for Iris browser tools. Install Google.Chrome with WinGet."
            .to_string(),
    )
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
    let hermes_site = workspace_root.join(".iris-runtime/hermes/.venv/Lib/site-packages");
    let voice_site = workspace_root.join(".iris-runtime/voice/Lib/site-packages");
    require_directory("Hermes package layer", &hermes_site)?;
    require_directory("voice package layer", &voice_site)?;
    let hermes_probe = format!(
        "import importlib.metadata as m,pathlib,sys; import acp,acp_adapter,jwt; site=pathlib.Path({:?}).resolve(); mods=(acp,acp_adapter,jwt); origins=[pathlib.Path(x.__file__).resolve() for x in mods]; ok=sys.version_info[:2]==(3,13) and m.version('hermes-agent')=='0.18.0' and m.version('agent-client-protocol')=='0.9.0' and m.version('PyJWT')=='2.13.0' and all(site == p or site in p.parents for p in origins); raise SystemExit(0 if ok else 1)",
        hermes_site.to_string_lossy()
    );
    run_python313_probe(&hermes_site, &hermes_probe)
        .map_err(|error| format!("Hermes Python package audit failed: {error}"))?;
    let voice_probe = format!(
        "import importlib.metadata as m,pathlib,sys; import kokoro_onnx,numpy,onnxruntime,soundfile; site=pathlib.Path({:?}).resolve(); mods=(kokoro_onnx,numpy,onnxruntime,soundfile); origins=[pathlib.Path(x.__file__).resolve() for x in mods]; ok=sys.version_info[:2]==(3,13) and m.version('kokoro-onnx')=='0.5.0' and m.version('soundfile')=='0.14.0' and m.version('numpy')=='2.5.1' and m.version('onnxruntime')=='1.28.0' and all(site == p or site in p.parents for p in origins); raise SystemExit(0 if ok else 1)",
        voice_site.to_string_lossy()
    );
    run_python313_probe(&voice_site, &voice_probe)
        .map_err(|error| format!("voice Python package audit failed: {error}"))?;

    for script in [
        workspace_root.join("tools/kokoro_tts.py"),
        workspace_root.join("plugins/hermes_sidecar/sidecar.py"),
        workspace_root.join("plugins/memory/iris_broker/provider.py"),
    ] {
        let code = format!(
            "import py_compile; py_compile.compile({:?}, doraise=True)",
            script.to_string_lossy()
        );
        run_python313_probe(&voice_site, &code)
            .map_err(|error| format!("failed to validate {}: {error}", script.display()))?;
    }
    Ok(())
}

fn require_directory(label: &str, path: &Path) -> Result<(), String> {
    if !path.is_dir() {
        return Err(format!("missing {label}: {}", path.display()));
    }
    if fs::read_dir(path)
        .map_err(|err| format!("failed to inspect {label} {}: {err}", path.display()))?
        .next()
        .is_none()
    {
        return Err(format!("{label} is empty: {}", path.display()));
    }
    Ok(())
}

fn run_python313_probe(site_packages: &Path, code: &str) -> Result<(), String> {
    let mut failures = Vec::new();
    for candidate in python313_candidates() {
        let mut command = Command::new(&candidate.executable);
        command
            .args(&candidate.prefix_args)
            .args(["-S", "-c", code])
            .env("PYTHONPATH", site_packages)
            .env("PYTHONNOUSERSITE", "1")
            .env("PYTHONDONTWRITEBYTECODE", "1")
            .env_remove("PYTHONHOME");
        match command.output() {
            Ok(output) if output.status.success() => return Ok(()),
            Ok(output) => failures.push(format!(
                "{}: {}",
                candidate.executable.display(),
                String::from_utf8_lossy(&output.stderr).trim()
            )),
            Err(error) => failures.push(format!("{}: {error}", candidate.executable.display())),
        }
    }
    Err(format!(
        "exact external Python 3.13 with the Iris-owned package layer was not usable ({})",
        failures.join("; ")
    ))
}

fn python313_candidates() -> Vec<PythonLaunch> {
    let mut candidates = Vec::new();
    if let Some(configured) = std::env::var_os("IRIS_PYTHON") {
        push_python_candidate(
            &mut candidates,
            PythonLaunch {
                executable: PathBuf::from(configured),
                prefix_args: Vec::new(),
            },
        );
    }
    push_python_candidate(
        &mut candidates,
        PythonLaunch {
            executable: PathBuf::from("py"),
            prefix_args: vec![OsString::from("-3.13")],
        },
    );
    for (variable, relative) in [
        ("LOCALAPPDATA", "Programs/Python/Python313/python.exe"),
        ("ProgramFiles", "Python313/python.exe"),
    ] {
        if let Some(root) = std::env::var_os(variable) {
            push_python_candidate(
                &mut candidates,
                PythonLaunch {
                    executable: PathBuf::from(root).join(relative),
                    prefix_args: Vec::new(),
                },
            );
        }
    }
    if let Some(local_app_data) = std::env::var_os("LOCALAPPDATA") {
        push_uv_python_candidates(
            &mut candidates,
            &PathBuf::from(local_app_data).join("uv/python"),
        );
    }
    if let Some(app_data) = std::env::var_os("APPDATA") {
        push_uv_python_candidates(&mut candidates, &PathBuf::from(app_data).join("uv/python"));
    }
    for executable in ["python3.13", "python"] {
        push_python_candidate(
            &mut candidates,
            PythonLaunch {
                executable: PathBuf::from(executable),
                prefix_args: Vec::new(),
            },
        );
    }
    candidates
}

fn push_uv_python_candidates(candidates: &mut Vec<PythonLaunch>, root: &Path) {
    let Ok(entries) = fs::read_dir(root) else {
        return;
    };
    let mut executables = entries
        .flatten()
        .filter(|entry| {
            entry
                .file_name()
                .to_string_lossy()
                .starts_with("cpython-3.13")
        })
        .map(|entry| entry.path().join("python.exe"))
        .collect::<Vec<_>>();
    executables.sort();
    for executable in executables {
        push_python_candidate(
            candidates,
            PythonLaunch {
                executable,
                prefix_args: Vec::new(),
            },
        );
    }
}

fn push_python_candidate(candidates: &mut Vec<PythonLaunch>, candidate: PythonLaunch) {
    if !candidates.contains(&candidate) {
        candidates.push(candidate);
    }
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
    let mut stdin_lock = stdin.lock();
    let mut stdout = io::stdout();

    run_interactive_session(&mut stdin_lock, &mut stdout, model_response)
}

fn run_interactive_session<R, W, F>(
    reader: &mut R,
    writer: &mut W,
    mut responder: F,
) -> Result<(), String>
where
    R: BufRead,
    W: Write,
    F: FnMut(&str) -> Result<iris_core_types::AssistantResponse, String>,
{
    let mut hud = iris_ui::LocalHud::new();

    loop {
        write!(writer, "iris> ").map_err(|err| err.to_string())?;
        writer.flush().map_err(|err| err.to_string())?;

        let mut line = String::new();
        let bytes = reader.read_line(&mut line).map_err(|err| err.to_string())?;
        if bytes == 0 {
            writeln!(writer).map_err(|err| err.to_string())?;
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
                writeln!(writer, "Panic Stop active. Local cognition is paused.")
                    .map_err(|err| err.to_string())?;
            }
            ":reset" => {
                hud.reset_after_panic_stop();
                writeln!(writer, "Panic Stop cleared. Local cognition is available.")
                    .map_err(|err| err.to_string())?;
            }
            ":status" => {
                let state = if hud.is_panic_stopped() {
                    "Panic Stop active"
                } else {
                    "Ready"
                };
                writeln!(writer, "Status: {state}").map_err(|err| err.to_string())?;
                for line in iris_ui::safety_status_lines() {
                    writeln!(writer, "- {line}").map_err(|err| err.to_string())?;
                }
            }
            _ => {
                if hud.is_panic_stopped() {
                    writeln!(
                        writer,
                        "Panic Stop is active. Use :reset before sending another request."
                    )
                    .map_err(|err| err.to_string())?;
                    continue;
                }
                let response = match responder(text) {
                    Ok(response) => response,
                    Err(error) => iris_core_types::AssistantResponse::text_only(format!(
                        "Local model unavailable: {error}"
                    )),
                };
                writeln!(writer, "{}", response.text).map_err(|err| err.to_string())?;
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
    let settings = iris_ollama::OllamaSettings::from_vision_manifest(&manifest)?;
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

    #[test]
    fn interactive_panic_stop_blocks_model_calls_until_reset() {
        let mut input =
            io::Cursor::new(b"first\n:panic\nblocked\n:status\n:reset\nsecond\n:quit\n");
        let mut output = Vec::new();
        let mut calls = Vec::new();

        run_interactive_session(&mut input, &mut output, |text| {
            calls.push(text.to_string());
            Ok(iris_core_types::AssistantResponse::text_only(format!(
                "response:{text}"
            )))
        })
        .expect("interactive session");

        assert_eq!(calls, ["first", "second"]);
        let output = String::from_utf8(output).expect("utf-8 output");
        assert!(output.contains("Panic Stop active. Local cognition is paused."));
        assert!(
            output.contains("Panic Stop is active. Use :reset before sending another request.")
        );
        assert!(output.contains("Status: Panic Stop active"));
        assert!(output.contains("Panic Stop cleared. Local cognition is available."));
        assert!(!output.contains("response:blocked"));
    }
}
