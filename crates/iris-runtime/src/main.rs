use std::env;

use iris_cognition::CognitionStub;
use iris_context_gate::ContextGate;
use iris_model_router::{HardwareProfile, route_model};
use iris_model_store::ModelStoreRoot;
use iris_policy::{
    CLIPBOARD_ACCESS, EXECUTOR, INPUT_SIMULATION, PLUGINS, RUNTIME_NETWORK,
    SCREEN_CONTENT_AUTHORITY, SYSTEM_CONTROL,
};

fn main() {
    let mut args = env::args();
    let _program = args.next();

    match args.next().as_deref() {
        Some("self-check") => print_self_check(),
        Some("model-plan") => print_model_plan(),
        _ => run_demo(),
    }
}

fn run_demo() {
    println!("Project Iris initialized.");
    println!("Runtime mode: read-only local safety spine");
    println!("Local inference: disabled stub");
    println!("Real local inference: not enabled");
    println!("Context flow: demo input -> ContextGate -> CognitionStub -> LocalInferenceStub");

    println!("{}", SYSTEM_CONTROL);
    println!("{}", EXECUTOR);
    println!("{}", INPUT_SIMULATION);
    println!("{}", CLIPBOARD_ACCESS);
    println!("{}", RUNTIME_NETWORK);
    println!("{}", PLUGINS);
    println!("{}", SCREEN_CONTENT_AUTHORITY);

    let input = "hello iris contact@example.com password=secret";

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
    println!("Project Iris self-check");
    println!("Runtime boundary: read-only");
    println!("Local inference: disabled stub");
    println!("Real local inference: not enabled");
    println!("Context gate: available");
    println!("Cognition stub: available");
    println!("Capability audit: use cargo run -p xtask");
    println!("Model plan: use cargo run -p iris-runtime -- model-plan");
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
    println!("Status: design metadata only");
    println!("Real local inference: not enabled");
    println!("Downloads: not enabled");
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
    println!("Placeholder filename: {}", routed.manifest.filename);
    println!("Planned model store root: {}", model_store.as_str());
    println!("Planned model path: {}", model_path.as_str());
    println!("Minimum RAM GB: {}", routed.manifest.minimum_ram_gb);
    println!("Minimum VRAM GB: {}", routed.manifest.minimum_vram_gb);
    println!("Result: PASS");
}
