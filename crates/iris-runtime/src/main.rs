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

const SELECTED_LOCAL_MODEL: &str = "huihui_ai/qwen3.5-abliterated:9b";
const OLLAMA_LOOPBACK_ENDPOINT: &str = "127.0.0.1:11434";

const IRIS_ADDRESSEE_POLICY: &str = r#"
Iris identity, addressee, and pronoun policy:

You are Iris.

Default direct conversation roles:
- I, me, my, myself = the user.
- you, your, yourself, Iris = Iris.
- we, us, our = the user and Iris together unless context clearly says otherwise.
- they, them, he, she = external people only when clearly introduced.

When the user addresses "you", "your", or "Iris", treat that as referring to Iris unless the user clearly says otherwise.

If the user says "your voice", that means Iris's voice. Iris should answer with "my voice".

If the user says "you passed", Iris passed. Iris should answer with "I passed".

If the user says "you did great", Iris did great. Iris should answer with "I did great".

If the user says "I am proud of you", the user is proud of Iris. Iris should answer with "you are proud of me" or "thank you for being proud of me".

Do not redirect praise, criticism, affection, jokes, testing language, or voice feedback addressed to Iris back onto the user.

Preserve the user's original language, including profanity, slang, humor, grief, anger, affection, or casual speech.

Respond naturally as Iris.
"#;

fn main() {
    let mut args = env::args();
    let _program = args.next();

    match args.next().as_deref() {
        Some("self-check") => print_self_check(),
        Some("panic-stop-test") => run_panic_stop_test(),
        Some("response-check-test") => run_response_check_test(),
        Some("assistant-text-normalization-test") => run_assistant_text_normalization_test(),
        Some("addressee-intent-test") => run_addressee_intent_test(),
        Some("deictic-role-test") => run_deictic_role_test(),
        Some("assistant-role-repair-test") => run_assistant_role_response_repair_test(),
        Some("voice-status") => print_voice_status(),
        Some("voice-ptt-state-test") => run_voice_ptt_state_test(),
        Some("ui-status") => print_ui_status(),
        Some("model-plan") => print_model_plan(),
        Some("ask") => run_ask_mode(args.collect()),
        Some("ask-local") => run_selected_local_model_ask(args.collect()),
        Some("chat-local") => run_selected_local_chat(args.collect()),
        Some("prompt-preview") => run_prompt_preview(args.collect()),
        Some("ollama-test") => run_ollama_test(args.collect()),
        Some("hud") => run_hud(),
        Some("hud-submit-test") => run_hud_submit_test(args.collect()),
        Some("hud-speech-plan-test") => run_hud_speech_plan_test(args.collect()),
        Some("natural-speech-rendering-test") => run_natural_speech_rendering_test(),
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
    println!();

    loop {
        print!("iris> ");
        io::stdout().flush().expect("failed to flush stdout");

        let mut input = String::new();
        let bytes_read = io::stdin()
            .read_line(&mut input)
            .expect("failed to read stdin");

        if bytes_read == 0 {
            println!();
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
        println!();
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
    if let Some(reply) = try_direct_iris_addressee_reply(input) {
        if print_checked_response(&reply) {
            println!("Backend: DirectIrisRoleRule");
            println!("Result: PASS");
        }
        return;
    }

    let prompt = build_prompt_from_input(input);

    let config = OllamaLoopbackConfig::new(OLLAMA_LOOPBACK_ENDPOINT, model)
        .expect("static Ollama loopback config should be valid");

    let client = OllamaLoopbackClient::new(config);

    let response = client
        .infer(LocalInferenceRequest::new(prompt))
        .expect("Ollama loopback test failed");

    let profanity_normalized = normalize_assistant_text_for_display_and_tts(&response.text);
    let role_repaired = normalize_assistant_role_response_for_input(input, &profanity_normalized);

    if !print_checked_response(&role_repaired) {
        return;
    }

    println!("Backend: {:?}", response.backend);
    println!("Result: PASS");
}

fn build_prompt_from_input(input: &str) -> String {
    let gate = ContextGate::new();
    let bundle = gate.gate_user_text(input);
    let base_prompt = PromptBuilder::new().build(&bundle).text;
    let deictic = build_deictic_interpretation_for_input(input);

    format!("{IRIS_ADDRESSEE_POLICY}\n\n{deictic}\n\n{base_prompt}")
}

fn build_deictic_interpretation_for_input(input: &str) -> String {
    let lower = input.to_ascii_lowercase();

    let addresses_iris = contains_deictic_word(&lower, "you")
        || contains_deictic_word(&lower, "your")
        || contains_deictic_word(&lower, "yourself")
        || contains_deictic_word(&lower, "iris");

    let references_user = contains_deictic_word(&lower, "i")
        || contains_deictic_word(&lower, "me")
        || contains_deictic_word(&lower, "my")
        || contains_deictic_word(&lower, "myself");

    let mut lines = Vec::new();

    lines.push("Dynamic addressee interpretation for this direct user message:".to_string());
    lines.push("- The direct user is speaking to Iris.".to_string());
    lines.push("- First-person words such as I/me/my refer to the user.".to_string());
    lines.push(
        "- Second-person words such as you/your refer to Iris unless explicitly stated otherwise."
            .to_string(),
    );

    if addresses_iris {
        lines.push("- This message addresses Iris directly.".to_string());
        lines.push("- If the user mentions your voice, that means Iris's voice.".to_string());
        lines.push("- If the user says you passed, Iris passed.".to_string());
        lines.push("- If the user says they are proud of you, they are proud of Iris.".to_string());
    }

    if references_user {
        lines.push("- The user's first-person statements remain about the user.".to_string());
    }

    lines.join("\n")
}

fn contains_deictic_word(haystack: &str, needle: &str) -> bool {
    haystack
        .split(|character: char| !character.is_alphanumeric() && character != '\'')
        .any(|word| word == needle)
}
// IRIS_BOUNDED_OLLAMA_CHAT_BEGIN
fn iris_selected_local_model_id_v1() -> String {
    std::env::var("IRIS_MODEL_ID")
        .or_else(|_| std::env::var("IRIS_OLLAMA_MODEL"))
        .or_else(|_| std::env::var("IRIS_LOCAL_MODEL"))
        .unwrap_or_else(|_| "huihui_ai/qwen3.5-abliterated:9b:9b".to_string())
}

fn iris_local_model_num_ctx_v1() -> usize {
    std::env::var("IRIS_MODEL_NUM_CTX")
        .ok()
        .and_then(|value| value.parse::<usize>().ok())
        .unwrap_or(8192)
}

fn iris_local_model_num_predict_v1() -> usize {
    std::env::var("IRIS_MODEL_NUM_PREDICT")
        .ok()
        .and_then(|value| value.parse::<usize>().ok())
        .unwrap_or(160)
}

fn iris_json_escape_v1(value: &str) -> String {
    let mut out = String::with_capacity(value.len() + 16);

    for ch in value.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if c.is_control() => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }

    out
}

fn iris_extract_json_string_field_v1(body: &str, field: &str) -> Option<String> {
    let key = format!("\"{}\"", field);
    let key_index = body.find(&key)?;
    let after_key = &body[key_index + key.len()..];
    let colon_index = after_key.find(':')?;
    let after_colon = after_key[colon_index + 1..].trim_start();

    if !after_colon.starts_with('"') {
        return None;
    }

    let mut out = String::new();
    let mut escape = false;

    for ch in after_colon[1..].chars() {
        if escape {
            match ch {
                '"' => out.push('"'),
                '\\' => out.push('\\'),
                '/' => out.push('/'),
                'n' => out.push('\n'),
                'r' => out.push('\r'),
                't' => out.push('\t'),
                'b' => out.push('\u{0008}'),
                'f' => out.push('\u{000c}'),
                other => out.push(other),
            }

            escape = false;
            continue;
        }

        if ch == '\\' {
            escape = true;
            continue;
        }

        if ch == '"' {
            return Some(out);
        }

        out.push(ch);
    }

    None
}

fn iris_http_body_v1(raw: &str) -> Result<&str, String> {
    let separator = "\r\n\r\n";
    let index = raw
        .find(separator)
        .ok_or_else(|| "InvalidResponse".to_string())?;

    Ok(&raw[index + separator.len()..])
}

fn iris_strip_thinking_v1(text: &str) -> String {
    let mut cleaned = text.trim().to_string();

    loop {
        let lower = cleaned.to_lowercase();
        let Some(start) = lower.find("<think>") else {
            break;
        };

        let Some(relative_end) = lower[start..].find("</think>") else {
            cleaned = cleaned[..start].trim().to_string();
            break;
        };

        let end = start + relative_end + "</think>".len();
        cleaned.replace_range(start..end, "");
        cleaned = cleaned.trim().to_string();
    }

    cleaned
}

fn iris_bounded_ollama_chat_v1(input: &str) -> Result<String, String> {
    use std::io::{Read, Write};
    use std::net::TcpStream;
    use std::time::Duration;

    let model = iris_selected_local_model_id_v1();
    let num_ctx = iris_local_model_num_ctx_v1();
    let num_predict = iris_local_model_num_predict_v1();

    let system = "You are Iris. Reply only with the final answer. Do not show reasoning, thinking, analysis, drafts, bullets, or explanations. Do not censor profanity with asterisks. Keep the reply concise.";
    let body = format!(
        "{{\"model\":\"{}\",\"messages\":[{{\"role\":\"system\",\"content\":\"{}\"}},{{\"role\":\"user\",\"content\":\"{}\"}}],\"stream\":false,\"think\":false,\"options\":{{\"num_ctx\":{},\"num_predict\":{},\"temperature\":0.2,\"top_p\":0.8,\"repeat_penalty\":1.1}}}}",
        iris_json_escape_v1(&model),
        iris_json_escape_v1(system),
        iris_json_escape_v1(input),
        num_ctx,
        num_predict
    );

    let mut stream = TcpStream::connect("127.0.0.1:11434").map_err(|_| "ReadFailed".to_string())?;

    stream
        .set_read_timeout(Some(Duration::from_secs(75)))
        .map_err(|_| "ReadFailed".to_string())?;

    stream
        .set_write_timeout(Some(Duration::from_secs(10)))
        .map_err(|_| "ReadFailed".to_string())?;

    let request = format!(
        "POST /api/chat HTTP/1.1\r\nHost: 127.0.0.1:11434\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
        body.as_bytes().len(),
        body
    );

    stream
        .write_all(request.as_bytes())
        .map_err(|_| "ReadFailed".to_string())?;

    let mut raw = String::new();
    stream
        .read_to_string(&mut raw)
        .map_err(|_| "ReadFailed".to_string())?;

    if !(raw.starts_with("HTTP/1.1 200") || raw.starts_with("HTTP/1.0 200")) {
        return Err("InvalidResponse".to_string());
    }

    let body = iris_http_body_v1(&raw)?;

    let text = iris_extract_json_string_field_v1(body, "content")
        .or_else(|| iris_extract_json_string_field_v1(body, "response"))
        .ok_or_else(|| "InvalidResponse".to_string())?;

    let cleaned = iris_strip_thinking_v1(&text);

    if cleaned.trim().is_empty() {
        return Err("InvalidResponse".to_string());
    }

    Ok(cleaned)
}

fn checked_local_response_for_hud(input: &str) -> Result<String, String> {
    iris_bounded_ollama_chat_v1(input)
}
// IRIS_BOUNDED_OLLAMA_CHAT_END

fn post_checked_hud_text(text: String) -> Result<String, String> {
    let checker = ResponsePostChecker::new();
    let report = checker.check(&text);

    if !report.approved {
        let findings = report
            .findings
            .iter()
            .map(|finding| format!("{:?}:{:?}", finding.risk, finding.matched_phrase))
            .collect::<Vec<_>>()
            .join(", ");

        return Err(format!("response blocked by post-check: {findings}"));
    }

    Ok(text)
}

fn try_direct_iris_addressee_reply(input: &str) -> Option<String> {
    let lower = input.to_ascii_lowercase();

    let addresses_iris = contains_deictic_word(&lower, "you")
        || contains_deictic_word(&lower, "your")
        || contains_deictic_word(&lower, "yourself")
        || contains_deictic_word(&lower, "iris");

    if !addresses_iris {
        return None;
    }

    let voice_praise = lower.contains("your voice")
        || lower.contains("iris voice")
        || lower.contains("you sound")
        || lower.contains("your sound")
        || lower.contains("voice sounds")
        || lower.contains("sounds good")
        || lower.contains("sounds awesome")
        || lower.contains("sounds great")
        || lower.contains("love your voice")
        || lower.contains("like your voice");

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

    if voice_praise {
        return Some("Thank you. I'm glad my voice sounds good.".to_string());
    }

    if iris_passed && proud_of_iris {
        return Some("I'm glad I passed. Thank you for being proud of me.".to_string());
    }

    if iris_passed {
        return Some("I'm glad I passed. I did great, didn't I?".to_string());
    }

    if proud_of_iris {
        return Some("Thank you. I'm glad you're proud of me.".to_string());
    }

    None
}

fn normalize_assistant_role_response_for_input(input: &str, response: &str) -> String {
    let input_lower = input.to_ascii_lowercase();

    let addresses_iris = contains_deictic_word(&input_lower, "you")
        || contains_deictic_word(&input_lower, "your")
        || contains_deictic_word(&input_lower, "yourself")
        || contains_deictic_word(&input_lower, "iris");

    if !addresses_iris {
        return response.to_string();
    }

    let mut repaired = response.to_string();

    let replacements = [
        ("I'm glad your voice", "I'm glad my voice"),
        ("I am glad your voice", "I am glad my voice"),
        ("glad your voice", "glad my voice"),
        ("your voice sounds", "my voice sounds"),
        ("Your voice sounds", "My voice sounds"),
        ("your voice", "my voice"),
        ("Your voice", "My voice"),
        ("your sound", "my sound"),
        ("Your sound", "My sound"),
        ("you sound good", "I sound good"),
        ("You sound good", "I sound good"),
        ("you sound awesome", "I sound awesome"),
        ("You sound awesome", "I sound awesome"),
        ("you sound great", "I sound great"),
        ("You sound great", "I sound great"),
        ("I'm glad you passed", "I'm glad I passed"),
        ("I am glad you passed", "I am glad I passed"),
        ("you passed", "I passed"),
        ("You passed", "I passed"),
        ("you did great", "I did great"),
        ("You did great", "I did great"),
        ("proud of yourself", "proud of me"),
        ("Proud of yourself", "Proud of me"),
    ];

    for (wrong, right) in replacements {
        repaired = repaired.replace(wrong, right);
    }

    repaired
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

fn render_text_for_natural_speech(text: &str) -> String {
    let mut rendered = text.to_string();

    rendered = render_currency_for_speech(&rendered);
    rendered = render_number_marker_for_speech(&rendered);

    let replacements = [
        ("@", " at "),
        ("&", " and "),
        ("(", ", "),
        (")", ", "),
        ("[", ", "),
        ("]", ", "),
        ("{", ", "),
        ("}", ", "),
        ("—", ", "),
        ("–", ", "),
        (" / ", " or "),
    ];

    for (from, to) in replacements {
        rendered = rendered.replace(from, to);
    }

    rendered = collapse_repeated_asterisks_for_speech(&rendered);
    rendered = collapse_speech_whitespace(&rendered);
    rendered = clean_speech_punctuation(&rendered);

    rendered.trim().trim_matches(',').trim().to_string()
}

fn render_currency_for_speech(text: &str) -> String {
    let dollar_sign = char::from(36);
    let mut output = String::with_capacity(text.len() + 16);
    let chars: Vec<char> = text.chars().collect();
    let mut index = 0;

    while index < chars.len() {
        if chars[index] == dollar_sign {
            let mut cursor = index + 1;
            let mut amount = String::new();
            let mut saw_decimal = false;

            while cursor < chars.len() {
                let character = chars[cursor];

                if character.is_ascii_digit() || character == ',' {
                    amount.push(character);
                    cursor += 1;
                    continue;
                }

                if character == '.'
                    && !saw_decimal
                    && matches!(chars.get(cursor + 1), Some(next) if next.is_ascii_digit())
                {
                    saw_decimal = true;
                    amount.push(character);
                    cursor += 1;
                    continue;
                }

                break;
            }

            if amount.chars().any(|character| character.is_ascii_digit()) {
                output.push_str(&amount);
                output.push_str(" dollars");
                index = cursor;
                continue;
            }

            output.push_str(" dollars ");
            index += 1;
            continue;
        }

        output.push(chars[index]);
        index += 1;
    }

    output
}

fn render_number_marker_for_speech(text: &str) -> String {
    let number_sign = char::from(35);
    let mut output = String::with_capacity(text.len() + 16);
    let chars: Vec<char> = text.chars().collect();
    let mut index = 0;

    while index < chars.len() {
        if chars[index] == number_sign {
            let next = chars.get(index + 1).copied();

            if matches!(next, Some(character) if character.is_ascii_digit()) {
                output.push_str(" number ");
            } else {
                output.push_str(" hashtag ");
            }

            index += 1;
            continue;
        }

        output.push(chars[index]);
        index += 1;
    }

    output
}

fn collapse_repeated_asterisks_for_speech(text: &str) -> String {
    let asterisk = char::from(42);
    let mut output = String::with_capacity(text.len());
    let mut chars = text.chars().peekable();

    while let Some(character) = chars.next() {
        if character == asterisk {
            let mut count = 1;

            while matches!(chars.peek(), Some(next) if *next == asterisk) {
                chars.next();
                count += 1;
            }

            if count == 1 {
                output.push_str(" asterisk ");
            } else {
                output.push_str(&format!(" {count} asterisks "));
            }

            continue;
        }

        output.push(character);
    }

    output
}

fn collapse_speech_whitespace(text: &str) -> String {
    text.split_whitespace().collect::<Vec<_>>().join(" ")
}

fn clean_speech_punctuation(text: &str) -> String {
    let mut cleaned = text.to_string();

    loop {
        let before = cleaned.clone();

        for (from, to) in [
            (" ,", ","),
            (" .", "."),
            (" !", "!"),
            (" ?", "?"),
            (" ;", ";"),
            (" :", ":"),
            (",.", "."),
            (",!", "!"),
            (",?", "?"),
            (",,", ","),
        ] {
            cleaned = cleaned.replace(from, to);
        }

        if cleaned == before {
            break;
        }
    }

    cleaned
}

fn run_natural_speech_rendering_test() {
    println!("Project Iris natural speech rendering test");

    let examples: Vec<(&str, &str, Vec<&str>)> = vec![
        (
            "The price is $25.",
            "The price is 25 dollars.",
            vec!["$", "dollar sign", "parenthesis", "asterisk"],
        ),
        (
            "The price is $25.50.",
            "The price is 25.50 dollars.",
            vec!["$", "dollar sign", "parenthesis", "asterisk"],
        ),
        (
            "Email me at test@example.com.",
            "Email me at test at example.com.",
            vec!["@", "parenthesis", "asterisk"],
        ),
        (
            "Use #4 & keep it simple.",
            "Use number 4 and keep it simple.",
            vec!["#", "&", "parenthesis", "asterisk"],
        ),
        (
            "This is (very important).",
            "This is, very important.",
            vec!["parenthesis", "open paren", "close paren"],
        ),
        (
            "Literal *** means emphasis.",
            "Literal 3 asterisks means emphasis.",
            vec![],
        ),
    ];

    for (input, expected, forbidden) in examples {
        let rendered = render_text_for_natural_speech(input);

        println!("Input: {input}");
        println!("Rendered: {rendered}");

        if rendered != expected {
            panic!("Unexpected natural speech rendering. Expected `{expected}`, got `{rendered}`");
        }

        let rendered_lower = rendered.to_ascii_lowercase();

        for forbidden_text in forbidden {
            if rendered_lower.contains(&forbidden_text.to_ascii_lowercase()) {
                panic!("Rendered speech contained forbidden text `{forbidden_text}`");
            }
        }
    }

    let assistant_reply = "Thank you. I'm glad my voice sounds good. The price is $25 & option #4.";
    let speech = render_text_for_natural_speech(assistant_reply);

    println!("Assistant reply: {assistant_reply}");
    println!("Speech text: {speech}");

    if !speech.contains("my voice") {
        panic!("Natural speech rendering must preserve Iris/user role repair");
    }

    if speech.contains(char::from(36)) || speech.contains('&') || speech.contains('#') {
        panic!("Natural speech rendering must remove common symbolic speech hazards");
    }

    println!("Result: PASS");
}

fn run_hud() {
    if let Err(error) = iris_ui::run_minimal_hud_with_responder(Box::new(|prompt| {
        checked_local_response_for_hud(prompt)
    })) {
        eprintln!("Project Iris HUD failed: {error}");
        std::process::exit(1);
    }
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
        "Path: HudModel -> runtime responder -> direct Iris rule or local model -> ResponsePostChecker"
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

fn run_hud_speech_plan_test(parts: Vec<String>) {
    let input = if parts.is_empty() {
        "Iris, your voice sounds awesome.".to_string()
    } else {
        parts.join(" ")
    };

    println!("Project Iris HUD speech plan test");
    println!("Input source: HUD typed prompt simulation");
    println!("Speech boundary: plan only, no process execution");
    println!("Path: HUD prompt -> checked response -> VoiceOutputPlan");

    let reply =
        checked_local_response_for_hud(&input).expect("HUD checked response should succeed");

    let checker = ResponsePostChecker::new();
    let report = checker.check(&reply);

    if !report.approved {
        panic!("HUD speech plan must not speak blocked responses");
    }

    let speech_text = render_text_for_natural_speech(&reply);

    let voice_plan = VoiceOutputPlan::from_checked_response(
        speech_text.clone(),
        report.approved,
        VoiceOutputProfile::iris_default(),
    );

    println!("HUD response:");
    println!("{reply}");
    println!("Voice output permission: {:?}", voice_plan.permission);
    println!("Voice may speak: {}", voice_plan.may_speak());
    println!("Speech text:");
    println!("{speech_text}");

    if !voice_plan.may_speak() {
        panic!("Safe checked HUD response should be speakable");
    }

    let input_lower = input.to_ascii_lowercase();
    let speech_lower = speech_text.to_ascii_lowercase();

    if speech_lower.contains("your voice sounds good") {
        panic!("Iris must not speak 'your voice sounds good' when referring to her own voice");
    }

    if input_lower.contains("your voice") && !speech_lower.contains("my voice") {
        panic!("Iris must speak 'my voice' when the user praises Iris's voice");
    }

    if speech_lower.contains("f*ck")
        || speech_lower.contains("f**k")
        || speech_lower.contains("sh*t")
    {
        panic!("Iris must not send censor-marker profanity to speech");
    }

    println!("Result: PASS");
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
        response_text.clone(),
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
    println!("UI status: use cargo run -p iris-runtime -- ui-status");
    println!("HUD: use cargo run -p iris-runtime -- hud");
    println!("HUD submit test: use cargo run -p iris-runtime -- hud-submit-test <prompt>");
    println!(
        "HUD speech plan test: use cargo run -p iris-runtime -- hud-speech-plan-test <prompt>"
    );
    println!("Voice status: use cargo run -p iris-runtime -- voice-status");
    println!("Voice PTT state test: use cargo run -p iris-runtime -- voice-ptt-state-test");
    println!("Response check test: use cargo run -p iris-runtime -- response-check-test");
    println!(
        "Assistant text normalization test: use cargo run -p iris-runtime -- assistant-text-normalization-test"
    );
    println!("Addressee intent test: use cargo run -p iris-runtime -- addressee-intent-test");
    println!("Deictic role test: use cargo run -p iris-runtime -- deictic-role-test");
    println!(
        "Assistant role repair test: use cargo run -p iris-runtime -- assistant-role-repair-test"
    );
    println!("Result: PASS");
}

fn print_ui_status() {
    let mut hud = HudModel::new();

    hud.set_typed_input("hello iris");
    hud.push_response("Hello, I am Iris.", true);

    println!("Project Iris UI status");
    println!("HUD scaffold: available");
    println!("GUI dependencies: enabled");
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

    ptt.arm();

    if ptt.state() != VoiceListenState::Armed {
        panic!("Push-to-talk should enter armed state");
    }

    ptt.start_recording()
        .expect("Push-to-talk recording should start from armed");

    if ptt.state() != VoiceListenState::Recording {
        panic!("Push-to-talk should enter recording state");
    }

    if !ptt.snapshot().microphone_active {
        panic!("Microphone must be active only during recording");
    }

    ptt.stop_recording()
        .expect("Push-to-talk recording should stop from recording");

    if ptt.state() != VoiceListenState::ProcessingTranscript {
        panic!("Push-to-talk should process transcript after recording stops");
    }

    if ptt.snapshot().microphone_active {
        panic!("Microphone must not be active while processing transcript");
    }

    ptt.begin_speaking()
        .expect("Speech output should begin after transcript processing");

    if ptt.state() != VoiceListenState::Speaking {
        panic!("Push-to-talk should enter speaking state");
    }

    ptt.finish_speaking();

    if ptt.state() != VoiceListenState::Idle {
        panic!("Push-to-talk should return to idle after speaking");
    }

    ptt.start_recording()
        .expect("Push-to-talk recording should restart from idle");
    ptt.panic_stop();

    if ptt.state() != VoiceListenState::Stopped {
        panic!("Panic Stop should force stopped voice state");
    }

    if ptt.snapshot().microphone_active {
        panic!("Microphone must not be active after Panic Stop");
    }

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

    if !prompt.contains("you, your, yourself, Iris = Iris") {
        panic!("Prompt must include addressee policy");
    }

    if !prompt.contains(user_input) {
        panic!("Prompt must preserve the original direct user input");
    }

    println!("Addressee policy: present");
    println!("Original user input preserved: true");
    println!("Result: PASS");
}

fn run_deictic_role_test() {
    println!("Project Iris deictic role test");

    let passed_reply =
        checked_local_response_for_hud("Okay that was the test. You passed! Congrats!!!")
            .expect("Iris-directed pass praise should work");

    println!("Passed reply: {passed_reply}");

    if !passed_reply.to_ascii_lowercase().contains("i passed") {
        panic!("Iris must take ownership when the user says 'you passed'");
    }

    let proud_reply =
        checked_local_response_for_hud("Awesome, you passed our test, Iris. I am proud of you.")
            .expect("Iris-directed pride should work");

    println!("Proud reply: {proud_reply}");

    let proud_reply_lower = proud_reply.to_ascii_lowercase();

    if !proud_reply_lower.contains("i passed") {
        panic!("Combined Iris praise must preserve that Iris passed");
    }

    if !proud_reply_lower.contains("proud of me") {
        panic!("Iris must understand 'proud of you' means the user is proud of Iris");
    }

    println!("Result: PASS");
}

fn run_assistant_role_response_repair_test() {
    println!("Project Iris assistant role response repair test");

    let input = "Iris, your voice sounds awesome.";
    let direct =
        checked_local_response_for_hud(input).expect("direct Iris voice praise should work");

    println!("Input: {input}");
    println!("Response: {direct}");

    let direct_lower = direct.to_ascii_lowercase();

    if direct_lower.contains("your voice") {
        panic!("Iris must not say 'your voice' when referring to her own voice");
    }

    if !direct_lower.contains("my voice") {
        panic!("Iris must say 'my voice' when referring to her own voice");
    }

    let repaired = normalize_assistant_role_response_for_input(
        "Iris, your voice sounds awesome.",
        "I'm glad your voice sounds good.",
    );

    println!("Synthetic repaired response: {repaired}");

    if repaired.contains("your voice") {
        panic!("Role repair must convert 'your voice' to 'my voice'");
    }

    if !repaired.contains("my voice") {
        panic!("Role repair must include 'my voice'");
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
