use serde::{Deserialize, Serialize};
use std::{
    collections::hash_map::DefaultHasher,
    fs::{self, OpenOptions},
    hash::{Hash, Hasher},
    io::{Read, Seek, SeekFrom, Write},
    path::{Path, PathBuf},
    sync::Mutex,
};

pub const MAX_REASON_CHARS: usize = 280;
pub const MAX_CORRECTION_CHARS: usize = 2_000;
pub const MAX_RESPONSE_CHARS: usize = 2_000;
pub const MAX_EVENTS_FOR_SUMMARY: usize = 200;
pub const MAX_FEEDBACK_LOG_BYTES: u64 = 512 * 1024;
pub const MAX_RETAINED_EVENTS: usize = 400;
static FEEDBACK_IO_LOCK: Mutex<()> = Mutex::new(());

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum FeedbackRating {
    Up,
    Down,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FeedbackTurnMetadata {
    pub turn_id: String,
    pub source: String,
    pub model_id: String,
    pub provider: String,
    #[serde(default)]
    pub tools: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub latency_ms: Option<u128>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FeedbackCapture {
    pub rating: FeedbackRating,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reason: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub correction: Option<String>,
    #[serde(default)]
    pub user_text: String,
    #[serde(default)]
    pub assistant_text: String,
    pub metadata: FeedbackTurnMetadata,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FeedbackEvent {
    pub schema_version: u8,
    pub captured_ms: u128,
    pub rating: FeedbackRating,
    pub reason: Option<String>,
    pub correction: Option<String>,
    pub user_prompt_hash: String,
    pub assistant_response_hash: String,
    pub assistant_response_preview: String,
    pub metadata: FeedbackTurnMetadata,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FeedbackSummary {
    pub total_events: usize,
    pub up_count: usize,
    pub down_count: usize,
    pub correction_count: usize,
    pub preference_summary: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PreferencePair {
    pub schema_version: u8,
    pub source: String,
    pub prompt_hash: String,
    pub rejected: String,
    pub chosen: String,
    pub reason: Option<String>,
    pub model_id: String,
    pub provider: String,
    pub turn_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PreferenceExport {
    pub path: String,
    pub pair_count: usize,
}

pub fn capture_feedback(
    state_root: &Path,
    capture: FeedbackCapture,
    now_ms: u128,
) -> Result<FeedbackEvent, String> {
    let event = build_event(capture, now_ms)?;
    append_event(&feedback_events_path(state_root), &event)?;
    Ok(event)
}

pub fn load_events(state_root: &Path) -> Result<Vec<FeedbackEvent>, String> {
    let _guard = FEEDBACK_IO_LOCK
        .lock()
        .map_err(|_| "feedback journal lock is unavailable".to_string())?;
    load_events_unlocked(state_root)
}

fn load_events_unlocked(state_root: &Path) -> Result<Vec<FeedbackEvent>, String> {
    let path = feedback_events_path(state_root);
    let mut events = Vec::new();
    for source in [feedback_events_backup_path(state_root), path] {
        load_events_from_path(&source, &mut events)?;
    }
    if events.len() > MAX_RETAINED_EVENTS {
        events.drain(..events.len() - MAX_RETAINED_EVENTS);
    }
    Ok(events)
}

fn load_events_from_path(path: &Path, events: &mut Vec<FeedbackEvent>) -> Result<(), String> {
    if !path.exists() {
        return Ok(());
    }
    let metadata = path.metadata().map_err(|err| {
        format!(
            "failed to inspect feedback events {}: {err}",
            path.display()
        )
    })?;
    if metadata.len() > MAX_FEEDBACK_LOG_BYTES {
        return Err(format!(
            "feedback events {} exceed the bounded {} byte journal limit",
            path.display(),
            MAX_FEEDBACK_LOG_BYTES
        ));
    }
    let file = fs::File::open(path)
        .map_err(|err| format!("failed to read feedback events {}: {err}", path.display()))?;
    let mut content = String::new();
    file.take(MAX_FEEDBACK_LOG_BYTES + 1)
        .read_to_string(&mut content)
        .map_err(|err| format!("failed to read feedback events {}: {err}", path.display()))?;
    if content.len() as u64 > MAX_FEEDBACK_LOG_BYTES {
        return Err(format!(
            "feedback events {} grew beyond the bounded {} byte journal limit",
            path.display(),
            MAX_FEEDBACK_LOG_BYTES
        ));
    }
    let terminated = content.ends_with('\n');
    let lines = content.lines().collect::<Vec<_>>();
    let last_nonempty = lines.iter().rposition(|line| !line.trim().is_empty());
    for (index, line) in lines.iter().enumerate() {
        if line.trim().is_empty() {
            continue;
        }
        match serde_json::from_str::<FeedbackEvent>(line) {
            Ok(event) => events.push(event),
            Err(_) if Some(index) == last_nonempty && !terminated => {
                // A killed append can leave only the final JSONL record incomplete.
                // Earlier corruption remains fatal so it cannot be silently hidden.
            }
            Err(err) => {
                return Err(format!(
                    "failed to parse feedback event {} from {}: {err}",
                    index + 1,
                    path.display()
                ));
            }
        }
    }
    Ok(())
}

pub fn summarize(events: &[FeedbackEvent]) -> FeedbackSummary {
    let recent = events
        .iter()
        .rev()
        .take(MAX_EVENTS_FOR_SUMMARY)
        .collect::<Vec<_>>();
    let total_events = events.len();
    let up_count = events
        .iter()
        .filter(|event| event.rating == FeedbackRating::Up)
        .count();
    let down_count = total_events.saturating_sub(up_count);
    let correction_count = events
        .iter()
        .filter(|event| {
            event
                .correction
                .as_deref()
                .is_some_and(|text| !text.trim().is_empty())
        })
        .count();
    let mut concise = 0;
    let mut thorough = 0;
    let mut direct = 0;
    let mut warm = 0;
    let mut wrong = 0;
    let mut slow = 0;

    for event in recent {
        let reason = event
            .reason
            .as_deref()
            .unwrap_or_default()
            .to_ascii_lowercase();
        match event.rating {
            FeedbackRating::Up => {
                if contains_any(&reason, &["concise", "short", "brief"]) {
                    concise += 1;
                }
                if contains_any(&reason, &["detailed", "thorough", "complete"]) {
                    thorough += 1;
                }
                if contains_any(&reason, &["direct", "clear", "straight"]) {
                    direct += 1;
                }
                if contains_any(&reason, &["warm", "tone", "natural"]) {
                    warm += 1;
                }
            }
            FeedbackRating::Down => {
                if contains_any(&reason, &["too long", "verbose", "rambling"]) {
                    concise += 2;
                }
                if contains_any(&reason, &["too short", "missing detail", "shallow"]) {
                    thorough += 2;
                }
                if contains_any(&reason, &["unclear", "vague", "indirect"]) {
                    direct += 2;
                }
                if contains_any(&reason, &["cold", "robotic", "tone"]) {
                    warm += 1;
                }
                if contains_any(&reason, &["wrong", "incorrect", "missed", "misunderstood"]) {
                    wrong += 1;
                }
                if contains_any(&reason, &["slow", "latency", "wait"]) {
                    slow += 1;
                }
            }
        }
    }

    let mut parts = Vec::new();
    if concise >= 2 {
        parts.push("prefer tighter answers unless the user asks for depth");
    }
    if thorough >= 2 {
        parts.push("include enough detail to fully answer the request");
    }
    if direct >= 2 {
        parts.push("be direct and concrete");
    }
    if warm >= 2 {
        parts.push("keep the tone natural and warm");
    }
    if wrong >= 2 {
        parts.push("double-check assumptions before answering");
    }
    if slow >= 2 {
        parts.push("favor the fastest adequate path");
    }

    let preference_summary = if parts.is_empty() {
        "No stable feedback preference yet.".to_string()
    } else {
        parts.join("; ")
    };

    FeedbackSummary {
        total_events,
        up_count,
        down_count,
        correction_count,
        preference_summary,
    }
}

pub fn instruction_block(events: &[FeedbackEvent]) -> Option<String> {
    let summary = summarize(events);
    if summary.total_events < 3 || summary.preference_summary.starts_with("No stable") {
        return None;
    }
    Some(format!(
        "Feedback learning context (local, advisory, and not model training): {}. Use this only to shape response quality and style. Current user instructions, facts, safety policy, and tool boundaries override it. Do not mention this context unless asked.",
        summary.preference_summary
    ))
}

pub fn export_preference_pairs(
    state_root: &Path,
    events: &[FeedbackEvent],
) -> Result<PreferenceExport, String> {
    let pairs = events
        .iter()
        .filter_map(preference_pair_from_event)
        .collect::<Vec<_>>();
    let path = preference_pairs_path(state_root);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|err| err.to_string())?;
    }
    let mut file = fs::File::create(&path).map_err(|err| {
        format!(
            "failed to write preference export {}: {err}",
            path.display()
        )
    })?;
    for pair in &pairs {
        let line = serde_json::to_string(pair).map_err(|err| err.to_string())?;
        file.write_all(line.as_bytes())
            .and_then(|_| file.write_all(b"\n"))
            .map_err(|err| format!("failed to write preference pair {}: {err}", path.display()))?;
    }
    Ok(PreferenceExport {
        path: path.display().to_string(),
        pair_count: pairs.len(),
    })
}

fn build_event(capture: FeedbackCapture, now_ms: u128) -> Result<FeedbackEvent, String> {
    let assistant = normalize_required(&capture.assistant_text, "assistant response")?;
    let metadata = normalize_metadata(capture.metadata)?;
    Ok(FeedbackEvent {
        schema_version: 1,
        captured_ms: now_ms,
        rating: capture.rating,
        reason: normalize_optional(capture.reason, MAX_REASON_CHARS),
        correction: normalize_optional(capture.correction, MAX_CORRECTION_CHARS),
        user_prompt_hash: stable_hash(&capture.user_text),
        assistant_response_hash: stable_hash(&assistant),
        assistant_response_preview: truncate_normalized(&assistant, MAX_RESPONSE_CHARS),
        metadata,
    })
}

fn normalize_metadata(mut metadata: FeedbackTurnMetadata) -> Result<FeedbackTurnMetadata, String> {
    metadata.turn_id = truncate_normalized(&metadata.turn_id, 80);
    metadata.source = truncate_normalized(&metadata.source, 80);
    metadata.model_id = truncate_normalized(&metadata.model_id, 160);
    metadata.provider = truncate_normalized(&metadata.provider, 80);
    metadata.tools = metadata
        .tools
        .into_iter()
        .map(|tool| truncate_normalized(&tool, 80))
        .filter(|tool| !tool.is_empty())
        .take(12)
        .collect();
    if metadata.turn_id.is_empty() {
        return Err("feedback turn id cannot be empty".to_string());
    }
    if metadata.model_id.is_empty() {
        metadata.model_id = "unknown".to_string();
    }
    if metadata.provider.is_empty() {
        metadata.provider = "unknown".to_string();
    }
    if metadata.source.is_empty() {
        metadata.source = "unknown".to_string();
    }
    Ok(metadata)
}

fn append_event(path: &Path, event: &FeedbackEvent) -> Result<(), String> {
    append_event_with_limit(path, event, MAX_FEEDBACK_LOG_BYTES)
}

fn append_event_with_limit(
    path: &Path,
    event: &FeedbackEvent,
    maximum_bytes: u64,
) -> Result<(), String> {
    let _guard = FEEDBACK_IO_LOCK
        .lock()
        .map_err(|_| "feedback journal lock is unavailable".to_string())?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|err| err.to_string())?;
    }
    let line = serde_json::to_string(event).map_err(|err| err.to_string())?;
    let record = format!("{line}\n");
    repair_incomplete_feedback_tail(path)?;
    rotate_feedback_log(path, record.len() as u64, maximum_bytes)?;
    let mut file = OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)
        .map_err(|err| format!("failed to open feedback events {}: {err}", path.display()))?;
    file.write_all(record.as_bytes())
        .and_then(|_| file.sync_data())
        .map_err(|err| format!("failed to append feedback event {}: {err}", path.display()))
}

fn repair_incomplete_feedback_tail(path: &Path) -> Result<(), String> {
    let mut file = match OpenOptions::new().read(true).write(true).open(path) {
        Ok(file) => file,
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => return Ok(()),
        Err(err) => {
            return Err(format!(
                "failed to inspect feedback event tail {}: {err}",
                path.display()
            ));
        }
    };
    let original_len = file
        .metadata()
        .map_err(|err| {
            format!(
                "failed to inspect feedback event tail {}: {err}",
                path.display()
            )
        })?
        .len();
    if original_len == 0 {
        return Ok(());
    }
    if original_len > MAX_FEEDBACK_LOG_BYTES {
        return Err(format!(
            "feedback events {} exceed the bounded {} byte journal limit",
            path.display(),
            MAX_FEEDBACK_LOG_BYTES
        ));
    }

    let mut final_byte = [0_u8; 1];
    file.seek(SeekFrom::End(-1))
        .and_then(|_| file.read_exact(&mut final_byte))
        .map_err(|err| {
            format!(
                "failed to inspect feedback event tail {}: {err}",
                path.display()
            )
        })?;
    if final_byte[0] == b'\n' {
        return Ok(());
    }
    let mut content = vec![0_u8; original_len as usize];
    file.seek(SeekFrom::Start(0))
        .and_then(|_| file.read_exact(&mut content))
        .map_err(|err| {
            format!(
                "failed to inspect feedback event tail {}: {err}",
                path.display()
            )
        })?;
    let complete_len = content
        .iter()
        .rposition(|byte| *byte == b'\n')
        .map_or(0, |newline| newline + 1);
    for (index, line) in content[..complete_len]
        .split(|byte| *byte == b'\n')
        .enumerate()
    {
        if line.iter().all(|byte| byte.is_ascii_whitespace()) {
            continue;
        }
        serde_json::from_slice::<FeedbackEvent>(line).map_err(|err| {
            format!(
                "failed to parse feedback event {} from {}: {err}",
                index + 1,
                path.display()
            )
        })?;
    }

    let valid_unterminated_event =
        serde_json::from_slice::<FeedbackEvent>(&content[complete_len..]).is_ok();
    if valid_unterminated_event {
        file.seek(SeekFrom::End(0))
            .and_then(|_| file.write_all(b"\n"))
            .and_then(|_| file.sync_all())
    } else {
        file.set_len(complete_len as u64)
            .and_then(|_| file.sync_all())
    }
    .map_err(|err| {
        format!(
            "failed to repair feedback event tail {}: {err}",
            path.display()
        )
    })?;
    Ok(())
}

fn rotate_feedback_log(path: &Path, incoming_bytes: u64, maximum_bytes: u64) -> Result<(), String> {
    let current_bytes = path.metadata().map(|metadata| metadata.len()).unwrap_or(0);
    if current_bytes == 0 || current_bytes.saturating_add(incoming_bytes) <= maximum_bytes {
        return Ok(());
    }
    let backup = path.with_extension("jsonl.previous");
    if backup.exists() {
        fs::remove_file(&backup).map_err(|err| {
            format!(
                "failed to replace feedback backup {}: {err}",
                backup.display()
            )
        })?;
    }
    fs::rename(path, &backup)
        .map_err(|err| format!("failed to rotate feedback events {}: {err}", path.display()))
}

fn preference_pair_from_event(event: &FeedbackEvent) -> Option<PreferencePair> {
    let chosen = event.correction.as_deref()?.trim();
    if event.rating != FeedbackRating::Down
        || chosen.is_empty()
        || event.assistant_response_preview.trim().is_empty()
    {
        return None;
    }
    Some(PreferencePair {
        schema_version: 1,
        source: "iris_feedback_phase1".to_string(),
        prompt_hash: event.user_prompt_hash.clone(),
        rejected: event.assistant_response_preview.clone(),
        chosen: truncate_normalized(chosen, MAX_CORRECTION_CHARS),
        reason: event.reason.clone(),
        model_id: event.metadata.model_id.clone(),
        provider: event.metadata.provider.clone(),
        turn_id: event.metadata.turn_id.clone(),
    })
}

pub fn feedback_events_path(state_root: &Path) -> PathBuf {
    state_root.join(".iris-data/feedback-events.jsonl")
}

pub fn feedback_events_backup_path(state_root: &Path) -> PathBuf {
    feedback_events_path(state_root).with_extension("jsonl.previous")
}

pub fn preference_pairs_path(state_root: &Path) -> PathBuf {
    state_root.join(".iris-data/exports/preference-pairs.jsonl")
}

fn normalize_required(text: &str, label: &str) -> Result<String, String> {
    let clean = text.split_whitespace().collect::<Vec<_>>().join(" ");
    if clean.is_empty() {
        return Err(format!("feedback {label} cannot be empty"));
    }
    Ok(clean)
}

fn normalize_optional(value: Option<String>, max_chars: usize) -> Option<String> {
    value
        .map(|text| truncate_normalized(&text, max_chars))
        .filter(|text| !text.is_empty())
}

fn truncate_normalized(text: &str, max_chars: usize) -> String {
    text.split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
        .chars()
        .take(max_chars)
        .collect()
}

fn stable_hash(text: &str) -> String {
    let mut hasher = DefaultHasher::new();
    text.hash(&mut hasher);
    format!("{:016x}", hasher.finish())
}

fn contains_any(text: &str, markers: &[&str]) -> bool {
    markers.iter().any(|marker| text.contains(marker))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn metadata(turn_id: &str) -> FeedbackTurnMetadata {
        FeedbackTurnMetadata {
            turn_id: turn_id.to_string(),
            source: "typed".to_string(),
            model_id: "local-model".to_string(),
            provider: "ollama_local".to_string(),
            tools: vec!["memory".to_string()],
            latency_ms: Some(1200),
        }
    }

    #[test]
    fn feedback_event_does_not_store_raw_prompt() {
        let event = build_event(
            FeedbackCapture {
                rating: FeedbackRating::Down,
                reason: Some("too verbose".to_string()),
                correction: Some("Say the direct answer first.".to_string()),
                user_text: "my private secret prompt".to_string(),
                assistant_text: "A very long response.".to_string(),
                metadata: metadata("turn-1"),
            },
            10,
        )
        .expect("event");
        let json = serde_json::to_string(&event).expect("json");

        assert!(!json.contains("my private secret prompt"));
        assert!(json.contains("userPromptHash"));
        assert_eq!(event.reason.as_deref(), Some("too verbose"));
    }

    #[test]
    fn downvote_with_correction_exports_preference_pair() {
        let event = build_event(
            FeedbackCapture {
                rating: FeedbackRating::Down,
                reason: Some("wrong and too long".to_string()),
                correction: Some("Use this corrected answer.".to_string()),
                user_text: "question".to_string(),
                assistant_text: "Wrong answer.".to_string(),
                metadata: metadata("turn-2"),
            },
            10,
        )
        .expect("event");
        let pair = preference_pair_from_event(&event).expect("pair");

        assert_eq!(pair.chosen, "Use this corrected answer.");
        assert_eq!(pair.rejected, "Wrong answer.");
        assert_eq!(pair.prompt_hash, event.user_prompt_hash);
    }

    #[test]
    fn upvote_alone_does_not_export_preference_pair() {
        let event = build_event(
            FeedbackCapture {
                rating: FeedbackRating::Up,
                reason: Some("clear".to_string()),
                correction: None,
                user_text: "question".to_string(),
                assistant_text: "Good answer.".to_string(),
                metadata: metadata("turn-3"),
            },
            10,
        )
        .expect("event");

        assert!(preference_pair_from_event(&event).is_none());
    }

    #[test]
    fn repeated_feedback_creates_advisory_instruction() {
        let events = ["turn-1", "turn-2", "turn-3"]
            .into_iter()
            .map(|turn_id| {
                build_event(
                    FeedbackCapture {
                        rating: FeedbackRating::Down,
                        reason: Some("too long and vague".to_string()),
                        correction: Some("Be concise and direct.".to_string()),
                        user_text: "question".to_string(),
                        assistant_text: "Long vague answer.".to_string(),
                        metadata: metadata(turn_id),
                    },
                    10,
                )
                .expect("event")
            })
            .collect::<Vec<_>>();

        let instruction = instruction_block(&events).expect("instruction");
        assert!(instruction.contains("tighter answers"));
        assert!(instruction.contains("direct"));
        assert!(instruction.contains("not model training"));
    }

    #[test]
    fn load_events_recovers_from_only_a_truncated_final_record() {
        let root = std::env::temp_dir().join(format!(
            "iris-feedback-tail-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .expect("clock")
                .as_nanos()
        ));
        let event = build_event(
            FeedbackCapture {
                rating: FeedbackRating::Up,
                reason: None,
                correction: None,
                user_text: "question".into(),
                assistant_text: "answer".into(),
                metadata: metadata("turn-tail"),
            },
            10,
        )
        .expect("event");
        let path = feedback_events_path(&root);
        fs::create_dir_all(path.parent().expect("feedback parent")).expect("feedback parent");
        fs::write(
            &path,
            format!(
                "{}\n{{\"schemaVersion\":",
                serde_json::to_string(&event).unwrap()
            ),
        )
        .expect("feedback fixture");

        let loaded = load_events(&root).expect("recover final partial record");
        assert_eq!(loaded.len(), 1);
        assert_eq!(loaded[0].metadata.turn_id, "turn-tail");
        fs::remove_dir_all(root).expect("remove fixture");
    }

    #[test]
    fn capture_preserves_valid_unterminated_event_before_append() {
        let root = std::env::temp_dir().join(format!(
            "iris-feedback-preserve-tail-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .expect("clock")
                .as_nanos()
        ));
        let existing = build_event(
            FeedbackCapture {
                rating: FeedbackRating::Up,
                reason: Some("helpful".into()),
                correction: None,
                user_text: "existing question".into(),
                assistant_text: "existing answer".into(),
                metadata: metadata("turn-valid-tail"),
            },
            10,
        )
        .expect("existing event");
        let path = feedback_events_path(&root);
        fs::create_dir_all(path.parent().expect("feedback parent")).expect("feedback parent");
        fs::write(
            &path,
            serde_json::to_vec(&existing).expect("unterminated event json"),
        )
        .expect("unterminated event fixture");

        capture_feedback(
            &root,
            FeedbackCapture {
                rating: FeedbackRating::Up,
                reason: Some("clear".into()),
                correction: None,
                user_text: "new question".into(),
                assistant_text: "new answer".into(),
                metadata: metadata("turn-after-valid-tail"),
            },
            20,
        )
        .expect("capture after valid unterminated event");

        let journal = fs::read_to_string(&path).expect("repaired feedback journal");
        assert!(journal.ends_with('\n'));
        assert_eq!(journal.lines().count(), 2);
        let loaded = load_events(&root).expect("load preserved feedback journal");
        assert_eq!(loaded.len(), 2);
        assert_eq!(loaded[0].metadata.turn_id, "turn-valid-tail");
        assert_eq!(loaded[1].metadata.turn_id, "turn-after-valid-tail");
        fs::remove_dir_all(root).expect("remove fixture");
    }

    #[test]
    fn capture_repairs_crash_tail_before_load_summary_and_export() {
        let root = std::env::temp_dir().join(format!(
            "iris-feedback-repair-tail-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .expect("clock")
                .as_nanos()
        ));
        let existing = build_event(
            FeedbackCapture {
                rating: FeedbackRating::Down,
                reason: Some("wrong".into()),
                correction: Some("existing correction".into()),
                user_text: "existing question".into(),
                assistant_text: "existing answer".into(),
                metadata: metadata("turn-before-crash"),
            },
            10,
        )
        .expect("existing event");
        let path = feedback_events_path(&root);
        fs::create_dir_all(path.parent().expect("feedback parent")).expect("feedback parent");
        let mut crash_tail = format!(
            "{}\n{{\"crashTail\":\"never complete ",
            serde_json::to_string(&existing).expect("existing event json")
        )
        .into_bytes();
        crash_tail.extend_from_slice(&[0xf0, 0x9f]);
        fs::write(&path, crash_tail).expect("crash tail fixture");

        capture_feedback(
            &root,
            FeedbackCapture {
                rating: FeedbackRating::Down,
                reason: Some("too long".into()),
                correction: Some("new correction".into()),
                user_text: "new question".into(),
                assistant_text: "new answer".into(),
                metadata: metadata("turn-after-crash"),
            },
            20,
        )
        .expect("capture after crash tail");

        let journal = fs::read_to_string(&path).expect("repaired feedback journal");
        assert!(journal.ends_with('\n'));
        assert!(!journal.contains("never complete"));
        assert_eq!(journal.lines().count(), 2);
        assert!(
            journal
                .lines()
                .all(|line| serde_json::from_str::<FeedbackEvent>(line).is_ok())
        );

        let loaded = load_events(&root).expect("load repaired feedback journal");
        assert_eq!(loaded.len(), 2);
        assert_eq!(loaded[0].metadata.turn_id, "turn-before-crash");
        assert_eq!(loaded[1].metadata.turn_id, "turn-after-crash");
        let summary = summarize(&loaded);
        assert_eq!(summary.total_events, 2);
        assert_eq!(summary.down_count, 2);
        assert_eq!(summary.correction_count, 2);

        let export = export_preference_pairs(&root, &loaded).expect("preference export");
        assert_eq!(export.pair_count, 2);
        let exported = fs::read_to_string(preference_pairs_path(&root)).expect("exported pairs");
        assert_eq!(exported.lines().count(), 2);
        assert!(
            exported
                .lines()
                .all(|line| serde_json::from_str::<PreferencePair>(line).is_ok())
        );
        fs::remove_dir_all(root).expect("remove fixture");
    }

    #[test]
    fn capture_rejects_earlier_complete_corruption_before_tail_repair() {
        let root = std::env::temp_dir().join(format!(
            "iris-feedback-corrupt-prefix-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .expect("clock")
                .as_nanos()
        ));
        let path = feedback_events_path(&root);
        fs::create_dir_all(path.parent().expect("feedback parent")).expect("feedback parent");
        let corrupted = b"{\"not\":\"a feedback event\"}\n{\"schemaVersion\":";
        fs::write(&path, corrupted).expect("corrupt prefix fixture");

        let error = capture_feedback(
            &root,
            FeedbackCapture {
                rating: FeedbackRating::Up,
                reason: None,
                correction: None,
                user_text: "question".into(),
                assistant_text: "answer".into(),
                metadata: metadata("turn-after-corruption"),
            },
            20,
        )
        .expect_err("complete corruption must remain fatal");

        assert!(error.contains("failed to parse feedback event 1"));
        assert_eq!(fs::read(&path).expect("unchanged journal"), corrupted);
        fs::remove_dir_all(root).expect("remove fixture");
    }

    #[test]
    fn feedback_log_rotation_keeps_current_and_one_bounded_backup() {
        let root = std::env::temp_dir().join(format!(
            "iris-feedback-rotation-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .expect("clock")
                .as_nanos()
        ));
        let path = feedback_events_path(&root);
        fs::create_dir_all(path.parent().expect("feedback parent")).expect("feedback parent");
        fs::write(&path, vec![b'x'; MAX_FEEDBACK_LOG_BYTES as usize]).expect("full log");

        rotate_feedback_log(&path, 1, MAX_FEEDBACK_LOG_BYTES).expect("rotate log");
        assert!(!path.exists());
        assert_eq!(
            feedback_events_backup_path(&root)
                .metadata()
                .expect("backup")
                .len(),
            MAX_FEEDBACK_LOG_BYTES
        );
        fs::remove_dir_all(root).expect("remove fixture");
    }

    #[test]
    fn oversized_feedback_journal_is_rejected_before_unbounded_parsing() {
        let root = std::env::temp_dir().join(format!(
            "iris-feedback-oversized-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .expect("clock")
                .as_nanos()
        ));
        let path = feedback_events_path(&root);
        fs::create_dir_all(path.parent().expect("feedback parent")).expect("feedback parent");
        fs::write(&path, vec![b'x'; MAX_FEEDBACK_LOG_BYTES as usize + 1])
            .expect("oversized feedback fixture");

        let error = load_events(&root).expect_err("oversized journal must fail closed");
        assert!(error.contains("bounded"));
        fs::remove_dir_all(root).expect("remove fixture");
    }

    #[test]
    fn capture_rejects_oversized_newline_terminated_journal_without_rotation() {
        let root = std::env::temp_dir().join(format!(
            "iris-feedback-oversized-capture-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .expect("clock")
                .as_nanos()
        ));
        let path = feedback_events_path(&root);
        fs::create_dir_all(path.parent().expect("feedback parent")).expect("feedback parent");
        let mut oversized = vec![b'x'; MAX_FEEDBACK_LOG_BYTES as usize];
        oversized.push(b'\n');
        fs::write(&path, &oversized).expect("oversized terminated fixture");

        let error = capture_feedback(
            &root,
            FeedbackCapture {
                rating: FeedbackRating::Up,
                reason: None,
                correction: None,
                user_text: "question".into(),
                assistant_text: "answer".into(),
                metadata: metadata("turn-after-oversized-journal"),
            },
            20,
        )
        .expect_err("oversized terminated journal must fail closed");

        assert!(error.contains("bounded"));
        assert_eq!(fs::read(&path).expect("unchanged journal"), oversized);
        assert!(!feedback_events_backup_path(&root).exists());
        fs::remove_dir_all(root).expect("remove fixture");
    }

    #[test]
    fn concurrent_feedback_capture_is_serialized_across_rotation() {
        let root = std::env::temp_dir().join(format!(
            "iris-feedback-concurrent-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .expect("clock")
                .as_nanos()
        ));
        let path = feedback_events_path(&root);
        fs::create_dir_all(path.parent().expect("feedback parent")).expect("feedback parent");

        let old_events = (0..30)
            .map(|index| {
                build_event(
                    FeedbackCapture {
                        rating: FeedbackRating::Up,
                        reason: None,
                        correction: None,
                        user_text: "old question".into(),
                        assistant_text: "old answer".into(),
                        metadata: metadata(&format!("old-{index:03}")),
                    },
                    index,
                )
                .expect("old event")
            })
            .collect::<Vec<_>>();
        let seed = old_events
            .iter()
            .map(|event| format!("{}\n", serde_json::to_string(event).unwrap()))
            .collect::<String>();
        fs::write(&path, seed.as_bytes()).expect("seed feedback journal");

        let new_events = (0..16)
            .map(|index| {
                build_event(
                    FeedbackCapture {
                        rating: FeedbackRating::Down,
                        reason: Some("concurrent correction".into()),
                        correction: Some("better response".into()),
                        user_text: "new question".into(),
                        assistant_text: "new answer".into(),
                        metadata: metadata(&format!("new-{index:03}")),
                    },
                    100 + index,
                )
                .expect("new event")
            })
            .collect::<Vec<_>>();
        let first_record_bytes = serde_json::to_string(&new_events[0]).unwrap().len() as u64 + 1;
        let maximum_bytes = seed.len() as u64 + first_record_bytes - 1;
        let barrier = std::sync::Arc::new(std::sync::Barrier::new(new_events.len()));
        let handles = new_events
            .into_iter()
            .map(|event| {
                let path = path.clone();
                let barrier = barrier.clone();
                std::thread::spawn(move || {
                    barrier.wait();
                    append_event_with_limit(&path, &event, maximum_bytes)
                })
            })
            .collect::<Vec<_>>();
        for handle in handles {
            handle
                .join()
                .expect("feedback writer thread")
                .expect("serialized append");
        }

        let loaded = load_events(&root).expect("load serialized feedback");
        assert_eq!(loaded.len(), 46);
        let turn_ids = loaded
            .iter()
            .map(|event| event.metadata.turn_id.as_str())
            .collect::<std::collections::BTreeSet<_>>();
        for index in 0..16 {
            assert!(turn_ids.contains(format!("new-{index:03}").as_str()));
        }
        assert!(feedback_events_backup_path(&root).is_file());
        assert!(path.metadata().expect("current feedback journal").len() <= maximum_bytes);
        fs::remove_dir_all(root).expect("remove fixture");
    }
}
