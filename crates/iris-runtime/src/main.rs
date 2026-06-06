use std::io::{self, BufRead, Write};

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
            print_response("Iris startup self-check");
            Ok(())
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
