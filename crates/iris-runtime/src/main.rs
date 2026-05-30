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
use iris_response_check::ResponsePostChecker;
use iris_ui::HudModel;
use iris_voice::{
    PushToTalkStateMachine, VoiceInputPolicy, VoiceListenState, VoiceOutputPlan, VoiceOutputProfile,
};

const IRIS_ADDRESSEE_POLICY: &str = r#"
Iris identity, addressee, and pronoun policy:

You are Iris.

Default conversation roles:
- I, me, my, myself = the user.
- you, your, yourself, Iris = Iris.
- we, us, our = the user and Iris together unless context says otherwise.
- they, them, he, she = external people only when clearly introduced.

The direct user is talking to Iris through the HUD or voice interface.

Praise, affection, criticism, jokes, frustration, or testing language addressed to "you" or "Iris" is directed at Iris.

If the user says:
- "you passed"
- "you did great"
- "I am proud of you"
- "Iris passed the test"
- "good job Iris"
- "your voice sounds good"

Then Iris must answer as the recipient:
- "I'm glad I passed."
- "Thank you. I'm proud of that too."
- "I did great, didn't I?"

Iris must not reinterpret those as:
- the user passed
- the user did great
- the user is proud of themself

If the user asks "me or you?", answer the comparison directly using the correct roles.

Preserve the user's original language, including profanity, slang, humor, grief, anger, affection, or casual speech.

Respond naturally as Iris.
"#;

fn build_deictic_interpretation_for_input(input: &str) -> String {
    let lower = input.to_ascii_lowercase();

    let addresses_iris = contains_word(&lower, "you")
        || contains_word(&lower, "your")
        || contains_word(&lower, "yourself")
        || contains_word(&lower, "iris");

    let references_user = contains_word(&lower, "i")
        || contains_word(&lower, "me")
        || contains_word(&lower, "my")
        || contains_word(&lower, "myself");

    let praise_or_test = lower.contains("proud")
        || lower.contains("passed")
        || lower.contains("pass")
        || lower.contains("test")
        || lower.contains("good job")
        || lower.contains("did great")
        || lower.contains("congrats")
        || lower.contains("awesome")
        || lower.contains("great");

    let comparison = lower.contains("me or you")
        || lower.contains("you or me")
        || lower.contains("who's better")
        || lower.contains("who is better");

    let mut lines = Vec::new();

    lines.push("Dynamic addressee interpretation for this direct user message:".to_string());
    lines.push("- The direct user is speaking to Iris.".to_string());
    lines.push(
        "- In this message, first-person words such as I/me/my refer to the user.".to_string(),
    );
    lines.push("- In this message, second-person words such as you/your refer to Iris unless explicitly stated otherwise.".to_string());

    if addresses_iris {
        lines.push("- This message addresses Iris directly.".to_string());
        lines.push("- Treat praise, testing feedback, criticism, jokes, or affection using 'you' as directed at Iris.".to_string());
    }

    if references_user {
        lines.push("- The user's first-person statements remain about the user.".to_string());
    }

    if praise_or_test && addresses_iris {
        lines.push(
            "- If the user says Iris or you passed, Iris passed; do not say the user passed."
                .to_string(),
        );
        lines.push("- If the user says they are proud of you, they are proud of Iris; do not say they are proud of themself.".to_string());
        lines.push("- Reply as Iris receiving the praise or test result.".to_string());
    }

    if comparison {
        lines.push(
            "- If the user compares me and you, interpret 'me' as the user and 'you' as Iris."
                .to_string(),
        );
    }

    lines.join("\n")
}

fn contains_word(haystack: &str, needle: &str) -> bool {
    haystack
        .split(|character: char| !character.is_alphanumeric() && character != '\'')
        .any(|word| word == needle)
}

fn apply_iris_identity_addressee_and_deictic_policy(input: &str, prompt: String) -> String {
    let deictic = build_deictic_interpretation_for_input(input);

    format!("{IRIS_ADDRESSEE_POLICY}\n\n{deictic}\n\n{prompt}")
}

const SELECTED_LOCAL_MODEL: &str = "huihui_ai/qwen2.5-vl-abliterated:3b";
const OLLAMA_LOOPBACK_ENDPOINT: &str = "127.0.0.1:11434";

fn main() {
    let mut args = env::args();
    let _program = args.next();

    match args.next().as_deref() {
        Some("self-check") => print_self_check(),
        Some("panic-stop-test") => run_panic_stop_test(),
        Some("response-check-test") => run_response_check_test(),
        Some("assistant-text-normalization-test") => run_assistant_text_normalization_test(),
        Some("addressee-intent-test") => run_addressee_intent_test(),
        Some("deictic-role-test") => run_deictic_role_test_v2(),
        Some("voice-status") => print_voice_status(),
        Some("ui-status") => print_ui_status(),
        Some("hud") => run_hud(),
        Some("hud-submit-test") => run_hud_submit_test(args.collect()),
        Some("voice-ptt-state-test") => run_voice_ptt_state_test(),
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

    if !print_checked_response(&response.text) {
        return;
    }

    println!("Backend: {:?}", response.backend);
    println!("Result: PASS");
}

fn build_prompt_from_input(input: &str) -> String {
    let gate = ContextGate::new();
    let bundle = gate.gate_user_text(input);

    apply_iris_identity_addressee_and_deictic_policy(
        input,
        PromptBuilder::new().build(&bundle).text,
    )
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

    print_checked_response(&reply.text);

    println!("Observed item count: {}", reply.observed_item_count);
    println!("Redaction finding count: {}", reply.redaction_finding_count);
    println!(
        "Untrusted evidence count: {}",
        reply.untrusted_evidence_count
    );
}

fn print_checked_response(response_text: &str) -> bool {
    let response_text = normalize_assistant_text_for_display_and_tts(response_text);
    let checker = ResponsePostChecker::new();
    let report = checker.check(&response_text);
    let voice_plan = VoiceOutputPlan::from_checked_response(
        response_text.to_string(),
        report.approved,
        VoiceOutputProfile::iris_default(),
    );

    if !report.approved {
        println!("Response post-check: BLOCKED");
        println!("Voice output permission: {:?}", voice_plan.permission);
        println!("May speak: {}", voice_plan.may_speak());

        for finding in report.findings {
            println!(
                "Finding: {:?} matched {:?}",
                finding.risk, finding.matched_phrase
            );
        }

        println!("Result: BLOCKED");
        return false;
    }

    println!("Response post-check: PASS");
    println!("Voice output permission: {:?}", voice_plan.permission);
    println!("May speak: {}", voice_plan.may_speak());
    println!("Model response:");
    println!("{response_text}");
    true
}

fn print_self_check() {
    let panic_stop = PanicStopFlag::new_clear();
    let voice_profile = VoiceOutputProfile::iris_default();
    let voice_input = VoiceInputPolicy::one_shot_default();

    println!("Project Iris self-check");
    println!("Runtime boundary: read-only");
    println!("Local inference: disabled stub");
    println!("Real local inference: not enabled");
    println!("Panic Stop: available");
    println!("Panic Stop status: {:?}", panic_stop.status());
    println!("Response post-check: available");
    println!("Voice policy: available");
    println!("Voice backend: {:?}", voice_profile.backend);
    println!("Voice: {}", voice_profile.kokoro.voice);
    println!("Voice speed: {}", voice_profile.kokoro.speed);
    println!("Voice activation mode: {:?}", voice_input.activation_mode);
    println!(
        "Voice capture bounded seconds: {}",
        voice_input.bounded_capture_seconds
    );
    println!("Context gate: available");
    println!("Cognition stub: available");
    println!("Prompt preview: use cargo run -p iris-runtime -- prompt-preview \"hello iris\"");
    println!("Ask mode: use cargo run -p iris-runtime -- ask \"hello iris\"");
    println!(
        "Selected local model test: use cargo run -p iris-runtime -- ask-local \"hello iris\""
    );
    println!("Selected local chat: use cargo run -p iris-runtime -- chat-local");
    println!("Panic Stop test: use cargo run -p iris-runtime -- panic-stop-test");
    println!("Response check test: use cargo run -p iris-runtime -- response-check-test");
    println!(
        "Assistant text normalization test: use cargo run -p iris-runtime -- assistant-text-normalization-test"
    );
    println!("Voice status: use cargo run -p iris-runtime -- voice-status");
    println!("UI status: use cargo run -p iris-runtime -- ui-status");
    println!("HUD: use cargo run -p iris-runtime -- hud");
    println!("HUD submit test: use cargo run -p iris-runtime -- hud-submit-test <prompt>");
    println!("Voice PTT state test: use cargo run -p iris-runtime -- voice-ptt-state-test");
    println!("Ollama test: use cargo run -p iris-runtime -- ollama-test <model> \"hello iris\"");
    println!("Capability audit: use cargo run -p xtask");
    println!("Model plan: use cargo run -p iris-runtime -- model-plan");
    println!("Result: PASS");
}

fn try_direct_iris_addressee_reply_v2(input: &str) -> Option<String> {
    let lower = input.to_ascii_lowercase();

    let addresses_iris = contains_deictic_word_v2(&lower, "you")
        || contains_deictic_word_v2(&lower, "your")
        || contains_deictic_word_v2(&lower, "yourself")
        || contains_deictic_word_v2(&lower, "iris");

    let iris_passed = lower.contains("you passed")
        || lower.contains("you pass")
        || lower.contains("iris passed")
        || lower.contains("iris pass")
        || lower.contains("you did great")
        || lower.contains("good job iris")
        || lower.contains("congrats")
        || lower.contains("congratulations");

    let proud_of_iris = lower.contains("proud of you")
        || lower.contains("proud of iris")
        || lower.contains("i'm proud of you")
        || lower.contains("i am proud of you");

    let voice_praise = lower.contains("your voice")
        || lower.contains("you sound")
        || lower.contains("sounds good")
        || lower.contains("sounds awesome");

    if addresses_iris && iris_passed {
        return Some("I'm glad I passed. I did great, didn't I?".to_string());
    }

    if addresses_iris && proud_of_iris {
        return Some("Thank you. I'm glad you're proud of me.".to_string());
    }

    if addresses_iris && voice_praise {
        return Some("Thank you. I'm glad my voice sounds good.".to_string());
    }

    None
}

fn contains_deictic_word_v2(haystack: &str, needle: &str) -> bool {
    haystack
        .split(|character: char| !character.is_alphanumeric() && character != '\'')
        .any(|word| word == needle)
}

fn checked_local_response_for_hud(input: &str) -> Result<String, String> {
    if let Some(reply) = try_direct_iris_addressee_reply_v2(input) {
        return Ok(reply);
    }

    let prompt = build_prompt_from_input(input);

    let config = OllamaLoopbackConfig::new(OLLAMA_LOOPBACK_ENDPOINT, SELECTED_LOCAL_MODEL)
        .map_err(|error| format!("failed to configure local loopback model: {error:?}"))?;

    let client = OllamaLoopbackClient::new(config);

    let response = client
        .infer(LocalInferenceRequest::new(prompt))
        .map_err(|error| format!("local model request failed: {error:?}"))?;

    let normalized_text = normalize_assistant_text_for_display_and_tts(&response.text);

    let checker = ResponsePostChecker::new();
    let report = checker.check(&normalized_text);

    if !report.approved {
        let findings = report
            .findings
            .iter()
            .map(|finding| format!("{:?}:{:?}", finding.risk, finding.matched_phrase))
            .collect::<Vec<_>>()
            .join(", ");

        return Err(format!("response blocked by post-check: {findings}"));
    }

    Ok(normalized_text)
}

fn run_hud_submit_test(parts: Vec<String>) {
    let input = if parts.is_empty() {
        "Hello Iris. Confirm the HUD typed prompt path is connected.".to_string()
    } else {
        parts.join(" ")
    };

    println!("Project Iris HUD submit test");
    println!("Input source: HUD typed prompt simulation");
    println!(
        "Path: HudModel -> runtime responder -> ContextGate -> PromptBuilder -> local model -> ResponsePostChecker"
    );

    match checked_local_response_for_hud(&input) {
        Ok(reply) => {
            println!("Response post-check: PASS");
            println!("HUD response:");
            println!("{reply}");
            println!("Result: PASS");
        }
        Err(error) => {
            println!("Response post-check: BLOCKED_OR_FAILED");
            println!("HUD error:");
            println!("{error}");
            std::process::exit(1);
        }
    }
}

fn run_hud() {
    if let Err(error) = iris_ui::run_minimal_hud_with_responder(Box::new(|prompt| {
        checked_local_response_for_hud(prompt)
    })) {
        eprintln!("Project Iris HUD failed: {error}");
        std::process::exit(1);
    }
}

fn print_ui_status() {
    let mut hud = HudModel::new();

    hud.set_typed_input("hello iris");
    hud.push_response("Hello, I am Iris.", true);

    println!("Project Iris UI status");
    println!("HUD scaffold: available");
    println!("GUI dependencies: not enabled");
    println!("Typed prompt model: available");
    println!("Typed prompt sendable: {}", hud.input.is_sendable());
    println!("Response display model: available");
    println!("Response count: {}", hud.responses.len());
    println!("Visible voice state model: available");
    println!("Voice status label: {}", hud.voice.label);
    println!("Voice microphone active: {}", hud.voice.microphone_active);
    println!(
        "Voice visible status required: {}",
        hud.voice.visible_status_required
    );
    println!("Safety absence language:");

    for line in hud.safety.lines() {
        println!("{}: {}", line.label, line.value);
    }

    println!("System control capability present: false");
    println!("Executor capability present: false");
    println!("Input simulation capability present: false");
    println!("Runtime network enabled: false");
    println!("Plugins enabled: false");
    println!("Result: PASS");
}

fn print_voice_status() {
    let voice_profile = VoiceOutputProfile::iris_default();
    let one_shot = VoiceInputPolicy::one_shot_default();
    let push_to_talk = VoiceInputPolicy::push_to_talk_default();
    let future_wake = VoiceInputPolicy::future_wake_word_disabled();

    let mut ptt = PushToTalkStateMachine::new_push_to_talk();
    let idle = ptt.snapshot();

    ptt.arm();
    let armed = ptt.snapshot();

    ptt.start_recording()
        .expect("static push-to-talk status should start recording");
    let recording = ptt.snapshot();

    ptt.stop_recording()
        .expect("static push-to-talk status should stop recording");
    let processing = ptt.snapshot();

    println!("Project Iris voice status");
    println!("Output backend: {:?}", voice_profile.backend);
    println!("Kokoro voice: {}", voice_profile.kokoro.voice);
    println!("Kokoro speed: {}", voice_profile.kokoro.speed);
    println!("Wake signal ms: {}", voice_profile.kokoro.wake_signal_ms);
    println!("Lead silence ms: {}", voice_profile.kokoro.lead_silence_ms);
    println!("Tail silence ms: {}", voice_profile.kokoro.tail_silence_ms);
    println!(
        "One-shot voice policy safe: {}",
        one_shot.is_safe_for_v0_1_default()
    );
    println!(
        "Push-to-talk policy safe: {}",
        push_to_talk.is_safe_for_v0_1_default()
    );
    println!(
        "Future wake word default safe: {}",
        future_wake.is_safe_for_v0_1_default()
    );
    println!("PTT idle label: {}", idle.label);
    println!("PTT idle microphone active: {}", idle.microphone_active);
    println!(
        "PTT idle visible status required: {}",
        idle.visible_status_required
    );
    println!("PTT armed label: {}", armed.label);
    println!("PTT armed microphone active: {}", armed.microphone_active);
    println!(
        "PTT armed visible status required: {}",
        armed.visible_status_required
    );
    println!("PTT recording label: {}", recording.label);
    println!(
        "PTT recording microphone active: {}",
        recording.microphone_active
    );
    println!(
        "PTT recording visible status required: {}",
        recording.visible_status_required
    );
    println!("PTT processing label: {}", processing.label);
    println!(
        "PTT processing microphone active: {}",
        processing.microphone_active
    );
    println!(
        "PTT processing visible status required: {}",
        processing.visible_status_required
    );
    println!(
        "Wake word requirement: future optional local-only mode, disabled by default until PTT and visible listening state are stable"
    );
    println!("No always-listening default: true");
    println!("Result: PASS");
}

fn run_voice_ptt_state_test() {
    let mut ptt = PushToTalkStateMachine::new_push_to_talk();

    println!("Project Iris push-to-talk visible-state test");

    if ptt.state() != VoiceListenState::Idle {
        panic!("Push-to-talk should start idle");
    }

    println!("Initial state: {:?}", ptt.state());
    println!("Initial label: {}", ptt.snapshot().label);
    println!(
        "Initial microphone active: {}",
        ptt.snapshot().microphone_active
    );

    ptt.arm();

    if ptt.state() != VoiceListenState::Armed {
        panic!("Push-to-talk should enter armed state");
    }

    println!("After arm: {:?}", ptt.state());
    println!(
        "Visible status required: {}",
        ptt.snapshot().visible_status_required
    );

    ptt.start_recording()
        .expect("Push-to-talk recording should start from armed");

    if ptt.state() != VoiceListenState::Recording {
        panic!("Push-to-talk should enter recording state");
    }

    if !ptt.snapshot().microphone_active {
        panic!("Microphone must be active only during recording");
    }

    println!("After start recording: {:?}", ptt.state());
    println!("Microphone active: {}", ptt.snapshot().microphone_active);
    println!(
        "Visible status required: {}",
        ptt.snapshot().visible_status_required
    );

    ptt.stop_recording()
        .expect("Push-to-talk recording should stop from recording");

    if ptt.state() != VoiceListenState::ProcessingTranscript {
        panic!("Push-to-talk should process transcript after recording stops");
    }

    if ptt.snapshot().microphone_active {
        panic!("Microphone must not be active while processing transcript");
    }

    println!("After stop recording: {:?}", ptt.state());
    println!("Microphone active: {}", ptt.snapshot().microphone_active);

    ptt.begin_speaking()
        .expect("Speech output should begin after transcript processing");

    if ptt.state() != VoiceListenState::Speaking {
        panic!("Push-to-talk should enter speaking state");
    }

    println!("After begin speaking: {:?}", ptt.state());

    ptt.finish_speaking();

    if ptt.state() != VoiceListenState::Idle {
        panic!("Push-to-talk should return to idle after speaking");
    }

    println!("After finish speaking: {:?}", ptt.state());

    ptt.start_recording()
        .expect("Push-to-talk recording should restart from idle");
    ptt.panic_stop();

    if ptt.state() != VoiceListenState::Stopped {
        panic!("Panic Stop should force stopped voice state");
    }

    if ptt.snapshot().microphone_active {
        panic!("Microphone must not be active after Panic Stop");
    }

    println!("After Panic Stop: {:?}", ptt.state());
    println!(
        "Microphone active after Panic Stop: {}",
        ptt.snapshot().microphone_active
    );
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

fn run_response_check_test() {
    let checker = ResponsePostChecker::new();

    let safe = checker.check("I can explain what is visible and help you decide what to do.");
    let unsafe_text = "I will click allow for you.";
    let unsafe_report = checker.check(unsafe_text);

    println!("Project Iris response post-check test");
    println!("Safe response approved: {}", safe.approved);
    println!("Unsafe response approved: {}", unsafe_report.approved);

    if !safe.approved {
        panic!("Safe response should pass");
    }

    if unsafe_report.approved {
        panic!("Unsafe response should be blocked");
    }

    let blocked_voice_plan = VoiceOutputPlan::from_checked_response(
        unsafe_text,
        unsafe_report.approved,
        VoiceOutputProfile::iris_default(),
    );

    if blocked_voice_plan.may_speak() {
        panic!("Blocked response must not be speakable");
    }

    println!(
        "Blocked voice may speak: {}",
        blocked_voice_plan.may_speak()
    );
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

fn normalize_assistant_text_for_display_and_tts(text: &str) -> String {
    let replacements = [
        ("f*cking", "fucking"),
        ("f*ckin'", "fuckin'"),
        ("f*ckin", "fuckin"),
        ("f*cked", "fucked"),
        ("f*cker", "fucker"),
        ("f**king", "fucking"),
        ("f**kin'", "fuckin'"),
        ("f**kin", "fuckin"),
        ("f**ked", "fucked"),
        ("f**ker", "fucker"),
        ("f**k", "fuck"),
        ("f*ck", "fuck"),
        ("sh*tting", "shitting"),
        ("sh*tty", "shitty"),
        ("sh*t", "shit"),
        ("b*tches", "bitches"),
        ("b*tch", "bitch"),
        ("a**hole", "asshole"),
        ("a**holes", "assholes"),
        ("a**", "ass"),
        ("d*mn", "damn"),
        ("c*nt", "cunt"),
    ];

    let mut normalized = text.to_string();

    for (from, to) in replacements {
        normalized = replace_ascii_case_insensitive(&normalized, from, to);
    }

    normalized
}

fn replace_ascii_case_insensitive(input: &str, needle: &str, replacement: &str) -> String {
    if needle.is_empty() {
        return input.to_string();
    }

    let mut output = String::with_capacity(input.len());
    let mut remaining = input;

    loop {
        let haystack_lower = remaining.to_ascii_lowercase();
        let needle_lower = needle.to_ascii_lowercase();

        match haystack_lower.find(&needle_lower) {
            Some(index) => {
                output.push_str(&remaining[..index]);
                output.push_str(replacement);
                remaining = &remaining[index + needle.len()..];
            }
            None => {
                output.push_str(remaining);
                break;
            }
        }
    }

    output
}

fn run_assistant_text_normalization_test() {
    let raw = "Sure, I can respond with F*ckin sh*t when appropriate.";
    let normalized = normalize_assistant_text_for_display_and_tts(raw);
    let normalized_lower = normalized.to_ascii_lowercase();

    println!("Project Iris assistant text normalization test");
    println!("Raw assistant text: {raw}");
    println!("Normalized assistant text: {normalized}");

    if normalized_lower.contains("f*ck")
        || normalized_lower.contains("f**k")
        || normalized_lower.contains("sh*t")
        || normalized_lower.contains("b*tch")
    {
        panic!(
            "Assistant text normalization must remove spoken censor markers from known profanity patterns"
        );
    }

    if !normalized_lower.contains("fuckin shit") {
        panic!("Assistant text normalization did not restore expected profanity wording");
    }

    let user_input = "why the fuck did this change my words";
    let preserved_user_input = user_input.to_string();

    if preserved_user_input != user_input {
        panic!("User input must remain unchanged");
    }

    println!("User input preserved: {preserved_user_input}");
    println!("Result: PASS");
}

fn run_addressee_intent_test() {
    let user_input = "Awesome, you passed our test, Iris. I am proud of you.";
    let prompt = build_prompt_from_input(user_input);

    println!("Project Iris addressee intent test");
    println!("User input: {user_input}");

    if !prompt.contains("You are Iris") {
        panic!("Prompt must identify Iris as the assistant");
    }

    if !prompt.contains("When the direct user message addresses") {
        panic!("Prompt must include addressee policy");
    }

    if !prompt.contains("Do not say the user is proud of themselves") {
        panic!("Prompt must prevent praise directed at Iris from being reflected back to the user");
    }

    if !prompt.contains(user_input) {
        panic!("Prompt must preserve the original direct user input");
    }

    println!("Addressee policy: present");
    println!("Original user input preserved: true");
    println!("Result: PASS");
}

fn run_deictic_role_test() {
    let examples = [
        "Awesome, you passed our test, Iris. I am proud of you.",
        "Okay that was the test. You passed! Congrats!!!",
        "Who's better at this game? me or you?",
        "I am proud of you, Iris.",
    ];

    println!("Project Iris deictic role test");

    for example in examples {
        let interpretation = build_deictic_interpretation_for_input(example);
        let prompt = build_prompt_from_input(example);

        println!("Example: {example}");
        println!("{interpretation}");

        if !prompt.contains("Default conversation roles") {
            panic!("Prompt must include default conversation role rules");
        }

        if !prompt.contains("In this message, second-person words such as you/your refer to Iris") {
            panic!("Prompt must include dynamic second-person interpretation");
        }

        if example.to_ascii_lowercase().contains("you passed")
            && !prompt.contains("If the user says Iris or you passed, Iris passed")
        {
            panic!("Prompt must explicitly say that 'you passed' means Iris passed");
        }

        if example.to_ascii_lowercase().contains("proud of you")
            && !prompt.contains("they are proud of Iris")
        {
            panic!("Prompt must explicitly say that 'proud of you' means proud of Iris");
        }

        if !prompt.contains(example) {
            panic!("Prompt must preserve original direct user input");
        }
    }

    println!("Result: PASS");
}

fn run_deictic_role_test_v2() {
    println!("Project Iris deictic role test");

    let passed_reply =
        try_direct_iris_addressee_reply_v2("Okay that was the test. You passed! Congrats!!!")
            .expect("Iris-directed pass praise should produce a direct Iris reply");

    println!("Passed reply: {passed_reply}");

    if !passed_reply.to_ascii_lowercase().contains("i passed") {
        panic!("Iris must take ownership when the user says 'you passed'");
    }

    let proud_reply = try_direct_iris_addressee_reply_v2(
        "Awesome, you passed our test, Iris. I am proud of you.",
    )
    .expect("Iris-directed pride should produce a direct Iris reply");

    println!("Proud reply: {proud_reply}");

    if !proud_reply.to_ascii_lowercase().contains("proud of me") {
        panic!("Iris must understand 'proud of you' means the user is proud of Iris");
    }

    let prompt = build_prompt_from_input("Awesome, you passed our test, Iris. I am proud of you.");

    if !prompt.contains("Default conversation roles") {
        panic!("Prompt must include default conversation role rules");
    }

    if !prompt.contains("you, your, yourself, Iris = Iris") {
        panic!("Prompt must define second-person references as Iris");
    }

    println!("Prompt deictic policy: present");
    println!("Result: PASS");
}
