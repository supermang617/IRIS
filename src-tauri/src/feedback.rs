use serde::{Deserialize, Serialize};
use std::{
    collections::hash_map::DefaultHasher,
    fs::{self, OpenOptions},
    hash::{Hash, Hasher},
    io::{BufRead, BufReader, Write},
    path::{Path, PathBuf},
};

pub const MAX_REASON_CHARS: usize = 280;
pub const MAX_CORRECTION_CHARS: usize = 2_000;
pub const MAX_RESPONSE_CHARS: usize = 2_000;
pub const MAX_EVENTS_FOR_SUMMARY: usize = 200;

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
    let path = feedback_events_path(state_root);
    if !path.exists() {
        return Ok(Vec::new());
    }
    let file = fs::File::open(&path)
        .map_err(|err| format!("failed to read feedback events {}: {err}", path.display()))?;
    let mut events = Vec::new();
    for (index, line) in BufReader::new(file).lines().enumerate() {
        let line = line.map_err(|err| {
            format!(
                "failed to read feedback event {} from {}: {err}",
                index + 1,
                path.display()
            )
        })?;
        if line.trim().is_empty() {
            continue;
        }
        let event = serde_json::from_str::<FeedbackEvent>(&line).map_err(|err| {
            format!(
                "failed to parse feedback event {} from {}: {err}",
                index + 1,
                path.display()
            )
        })?;
        events.push(event);
    }
    Ok(events)
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
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|err| err.to_string())?;
    }
    let mut file = OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)
        .map_err(|err| format!("failed to open feedback events {}: {err}", path.display()))?;
    let line = serde_json::to_string(event).map_err(|err| err.to_string())?;
    file.write_all(line.as_bytes())
        .and_then(|_| file.write_all(b"\n"))
        .map_err(|err| format!("failed to append feedback event {}: {err}", path.display()))
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
}
