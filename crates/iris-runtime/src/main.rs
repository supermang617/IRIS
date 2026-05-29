use iris_cognition::CognitionStub;
use iris_context_gate::ContextGate;
use iris_policy::{
    CLIPBOARD_ACCESS, EXECUTOR, INPUT_SIMULATION, PLUGINS, RUNTIME_NETWORK,
    SCREEN_CONTENT_AUTHORITY, SYSTEM_CONTROL,
};

fn main() {
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
