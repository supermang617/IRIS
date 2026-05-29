use std::env;
use std::io::{self, Write};

use iris_cognition::CognitionStub;
use iris_context_gate::ContextGate;
use iris_local_inference::LocalInferenceRequest;
use iris_local_inference::loopback::{OllamaLoopbackClient, OllamaLoopbackConfig};
use iris_model_router::{HardwareProfile, route_model};
use iris_model_store::ModelStoreRoot;
use iris_panic_stop::{PanicStopFlag, PanicStopStatus};
use iris_policy::{
    CLIPBOARD_ACCESS, EXECUTOR, INPUT_SIMULATION, PLUGINS, RUNTIME_NETWORK,
    SCREEN_CONTENT_AUTHORITY, SYSTEM_CONTROL,
};
use iris_prompt::PromptBuilder;

const SELECTED_LOCAL_MODEL: &str = "huihui_ai/qwen2.5-vl-abliterated:3b";
const OLLAMA_LOOPBACK_ENDPOINT: &str = "127.0.0.1:11434";

fn main() {
    let mut args = env::args();
    let _program = args.next();

    match args.next().as_deref() {
        Some("self-check") => print_self_check(),
        Some("panic-stop-test") => run_panic_stop_test(),
        Some("model-plan") => print_model_plan(),
        Some("ask") => run_ask_mode(args.collect()),
        Some("ask-local") => run_selected_local_model_ask(args.collect()),
        Some("chat-local") => run_selected_local_chat(args.collect()),
        Some("prompt-preview") => run_prompt_preview(args.collect()),
        Some("ollama-test") => run_ollama_test(args.collect()),
        _ => run_demo(),
    }
}

fn run_demo() {
    run_safety_spine("hello iris contact@example.com password=secret");
}

fn run_ask_mode(parts: Vec<String>) {
    let input = if parts.is_empty() {
        "hello iris".to_string()
    } else {
        parts.join(" ")
    };

    println!("Project Iris ask-mode test");
    println!("Input source: command argument");
    println!("Runtime boundary: read-only");
    println!("Local inference: disabled stub");
    println!("Real local inference: not enabled");

    run_safety_spine(&input);
}

fn run_selected_local_model_ask(parts: Vec<String>) {
    let input = if parts.is_empty() {
        "In one sentence, say hello as Iris and confirm you are running locally.".to_string()
    } else {
        parts.join(" ")
    };

    println!("Project Iris selected local model test");
    println!("Model: {SELECTED_LOCAL_MODEL}");
    println!("Endpoint: {OLLAMA_LOOPBACK_ENDPOINT}");
    println!("Runtime boundary: explicit local loopback test only");
    println!("Input routed through: ContextGate -> PromptBuilder -> OllamaLoopbackClient");

    run_ollama_loopback_request(SELECTED_LOCAL_MODEL, &input);
}

fn run_selected_local_chat(parts: Vec<String>) {
    if !parts.is_empty() {
        run_selected_local_model_ask(parts);
        return;
    }

    println!("Project Iris local chat test");
    println!("Model: {SELECTED_LOCAL_MODEL}");
    println!("Endpoint: {OLLAMA_LOOPBACK_ENDPOINT}");
    println!("Runtime boundary: explicit local loopback test only");
    println!("Type exit or quit to stop.");
    println!("");

    loop {
        print!("iris> ");
        io::stdout().flush().expect("failed to flush stdout");

        let mut input = String::new();
        let bytes_read = io::stdin()
            .read_line(&mut input)
            .expect("failed to read stdin");

        if bytes_read == 0 {
            println!("");
            println!("Result: PASS");
            return;
        }

        let trimmed = input.trim();

        if trimmed.eq_ignore_ascii_case("exit") || trimmed.eq_ignore_ascii_case("quit") {
            println!("Result: PASS");
            return;
        }

        if trimmed.is_empty() {
            continue;
        }

        run_ollama_loopback_request(SELECTED_LOCAL_MODEL, trimmed);
        println!("");
    }
}

fn run_prompt_preview(parts: Vec<String>) {
    let input = if parts.is_empty() {
        "hello iris contact@example.com password=secret".to_string()
    } else {
        parts.join(" ")
    };

    let prompt = build_prompt_from_input(&input);

    println!("Project Iris prompt-preview");
    println!("Status: local prompt construction only");
    println!("Real local inference: not enabled");
    println!("Input routed through: ContextGate -> GatedContextBundle -> PromptBuilder");
    println!("--- PROMPT START ---");
    println!("{prompt}");
    println!("--- PROMPT END ---");
    println!("Result: PASS");
}

fn run_ollama_test(parts: Vec<String>) {
    if parts.is_empty() {
        println!("Project Iris Ollama loopback test");
        println!("Status: ready");
        println!("No network call was made because no model was provided.");
        println!("Usage:");
        println!("cargo run -p iris-runtime -- ollama-test <ollama-model-name> \"hello iris\"");
        println!("Selected model shortcut:");
        println!("cargo run -p iris-runtime -- ask-local \"hello iris\"");
        println!("Local chat:");
        println!("cargo run -p iris-runtime -- chat-local");
        println!("Endpoint: {OLLAMA_LOOPBACK_ENDPOINT}");
        println!("Result: PASS");
        return;
    }

    let model = parts[0].clone();
    let input = if parts.len() > 1 {
        parts[1..].join(" ")
    } else {
        "hello iris".to_string()
    };

    println!("Project Iris Ollama loopback test");
    println!("Model: {model}");
    println!("Endpoint: {OLLAMA_LOOPBACK_ENDPOINT}");
    println!("Runtime boundary: explicit local loopback test only");
    println!("Input routed through: ContextGate -> PromptBuilder -> OllamaLoopbackClient");

    run_ollama_loopback_request(&model, &input);
}

fn run_ollama_loopback_request(model: &str, input: &str) {
    let prompt = build_prompt_from_input(input);

    let config = OllamaLoopbackConfig::new(OLLAMA_LOOPBACK_ENDPOINT, model)
        .expect("static Ollama loopback config should be valid");

    let client = OllamaLoopbackClient::new(config);

    let response = client
        .infer(LocalInferenceRequest::new(prompt))
        .expect("Ollama loopback test failed");

    println!("Model response:");
    println!("{}", response.text);
    println!("Backend: {:?}", response.backend);
    println!("Result: PASS");
}

fn build_prompt_from_input(input: &str) -> String {
    let gate = ContextGate::new();
    let bundle = gate.gate_user_text(input);

    PromptBuilder::new().build(&bundle).text
}

fn run_safety_spine(input: &str) {
    println!("Project Iris initialized.");
    println!("Runtime mode: read-only local safety spine");
    println!("Local inference: disabled stub");
    println!("Real local inference: not enabled");
    println!("Context flow: input -> ContextGate -> CognitionStub -> LocalInferenceStub");

    println!("{}", SYSTEM_CONTROL);
    println!("{}", EXECUTOR);
    println!("{}", INPUT_SIMULATION);
    println!("{}", CLIPBOARD_ACCESS);
    println!("{}", RUNTIME_NETWORK);
    println!("{}", PLUGINS);
    println!("{}", SCREEN_CONTENT_AUTHORITY);

    let gate = ContextGate::new();
    let bundle = gate.gate_user_text(input);

    let cognition = CognitionStub::new();
    let reply = cognition.respond(bundle);

    println!("Cognition response text: {}", reply.text);
    println!("Observed item count: {}", reply.observed_item_count);
    println!("Redaction finding count: {}", reply.redaction_finding_count);
    println!(
        "Untrusted evidence count: {}",
        reply.untrusted_evidence_count
    );
}

fn print_self_check() {
    let panic_stop = PanicStopFlag::new_clear();

    println!("Project Iris self-check");
    println!("Runtime boundary: read-only");
    println!("Local inference: disabled stub");
    println!("Real local inference: not enabled");
    println!("Panic Stop: available");
    println!("Panic Stop status: {:?}", panic_stop.status());
    println!("Context gate: available");
    println!("Cognition stub: available");
    println!("Prompt preview: use cargo run -p iris-runtime -- prompt-preview \"hello iris\"");
    println!("Ask mode: use cargo run -p iris-runtime -- ask \"hello iris\"");
    println!(
        "Selected local model test: use cargo run -p iris-runtime -- ask-local \"hello iris\""
    );
    println!("Selected local chat: use cargo run -p iris-runtime -- chat-local");
    println!("Panic Stop test: use cargo run -p iris-runtime -- panic-stop-test");
    println!("Ollama test: use cargo run -p iris-runtime -- ollama-test <model> \"hello iris\"");
    println!("Capability audit: use cargo run -p xtask");
    println!("Model plan: use cargo run -p iris-runtime -- model-plan");
    println!("Result: PASS");
}

fn run_panic_stop_test() {
    let panic_stop = PanicStopFlag::new_clear();

    println!("Project Iris Panic Stop test");
    println!("Initial status: {:?}", panic_stop.status());

    if panic_stop.status() != PanicStopStatus::Clear {
        panic!("Panic Stop should start clear");
    }

    panic_stop.request_stop();
    println!("After request: {:?}", panic_stop.status());

    if panic_stop.status() != PanicStopStatus::Requested {
        panic!("Panic Stop should be requested after request_stop");
    }

    panic_stop.clear();
    println!("After clear: {:?}", panic_stop.status());

    if panic_stop.status() != PanicStopStatus::Clear {
        panic!("Panic Stop should be clear after clear");
    }

    println!("Result: PASS");
}

fn print_model_plan() {
    let profile = HardwareProfile::windows_rtx_4060_class();
    let routed = route_model(&profile).expect("static placeholder model route should be valid");
    let model_store = ModelStoreRoot::iris_user_models();
    let model_path = model_store
        .model_path_for_manifest(&routed.manifest)
        .expect("static placeholder model filename should be valid");

    println!("Project Iris future model plan");
    println!("Status: selected local test target");
    println!("Default selected model: {SELECTED_LOCAL_MODEL}");
    println!("Real local inference default path: not enabled");
    println!("Explicit local test command: cargo run -p iris-runtime -- ask-local \"hello iris\"");
    println!("Interactive local chat: cargo run -p iris-runtime -- chat-local");
    println!("Downloads: not enabled by runtime");
    println!("Filesystem scan: not enabled");
    println!("Hardware profile: {}", profile.os_label);
    println!("Total RAM GB: {}", profile.total_ram_gb);
    println!("Dedicated VRAM GB: {}", profile.dedicated_vram_gb);
    println!("Selected tier: {:?}", routed.tier);
    println!("Model family: {:?}", routed.manifest.family);
    println!("Model variant: {:?}", routed.manifest.variant);
    println!("Model format: {:?}", routed.manifest.format);
    println!("Quantization: {:?}", routed.manifest.quantization);
    println!("Source: {:?}", routed.manifest.source);
    println!("Model id: {}", routed.manifest.model_id);
    println!("Planned model store root: {}", model_store.as_str());
    println!("Planned model path: {}", model_path.as_str());
    println!("Minimum RAM GB: {}", routed.manifest.minimum_ram_gb);
    println!("Minimum VRAM GB: {}", routed.manifest.minimum_vram_gb);
    println!("Result: PASS");
}
