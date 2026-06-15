use serde::{Deserialize, Serialize};
use std::collections::BTreeSet;

pub const PROFILE_VERSION: u8 = 1;
pub const DEFAULT_HALF_LIFE_DAYS: u32 = 30;
pub const DEFAULT_MAX_OBSERVATIONS: u32 = 64;
const MIN_WORDS: usize = 3;
const UPDATE_WEIGHT: f32 = 0.28;
const DAY_MS: f32 = 86_400_000.0;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DynamicContextProfile {
    pub version: u8,
    pub enabled: bool,
    pub observation_count: u32,
    pub updated_ms: u64,
    pub average_sentence_words: f32,
    pub vocabulary_diversity: f32,
    pub complexity: f32,
    pub formality: f32,
    pub directness: f32,
    pub wit: f32,
    pub analytical: f32,
    pub expressiveness: f32,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DynamicContextSummary {
    pub enabled: bool,
    pub observation_count: u32,
    pub updated_ms: u64,
    pub sentence_style: String,
    pub vocabulary_style: String,
    pub tone: String,
}

#[derive(Debug, Clone, Copy)]
struct TextMetrics {
    average_sentence_words: f32,
    vocabulary_diversity: f32,
    complexity: f32,
    formality: f32,
    directness: f32,
    wit: f32,
    analytical: f32,
    expressiveness: f32,
}

impl Default for DynamicContextProfile {
    fn default() -> Self {
        Self {
            version: PROFILE_VERSION,
            enabled: true,
            observation_count: 0,
            updated_ms: 0,
            average_sentence_words: 14.0,
            vocabulary_diversity: 0.55,
            complexity: 0.45,
            formality: 0.50,
            directness: 0.50,
            wit: 0.30,
            analytical: 0.50,
            expressiveness: 0.40,
        }
    }
}

impl DynamicContextProfile {
    pub fn with_enabled(enabled: bool) -> Self {
        Self {
            enabled,
            ..Self::default()
        }
    }

    pub fn observe(
        &mut self,
        text: &str,
        now_ms: u64,
        half_life_days: u32,
        max_observations: u32,
    ) -> bool {
        if !self.enabled {
            return false;
        }
        let Some(metrics) = analyze(text) else {
            return false;
        };
        let current = self.decayed(now_ms, half_life_days);
        *self = current;
        let weight = if self.observation_count == 0 {
            1.0
        } else {
            UPDATE_WEIGHT
        };
        self.average_sentence_words = blend(
            self.average_sentence_words,
            metrics.average_sentence_words,
            weight,
        );
        self.vocabulary_diversity = blend(
            self.vocabulary_diversity,
            metrics.vocabulary_diversity,
            weight,
        );
        self.complexity = blend(self.complexity, metrics.complexity, weight);
        self.formality = blend(self.formality, metrics.formality, weight);
        self.directness = blend(self.directness, metrics.directness, weight);
        self.wit = blend(self.wit, metrics.wit, weight);
        self.analytical = blend(self.analytical, metrics.analytical, weight);
        self.expressiveness = blend(self.expressiveness, metrics.expressiveness, weight);
        self.observation_count = self
            .observation_count
            .saturating_add(1)
            .min(max_observations.max(1));
        self.updated_ms = now_ms;
        true
    }

    pub fn decayed(&self, now_ms: u64, half_life_days: u32) -> Self {
        if self.observation_count == 0 || now_ms <= self.updated_ms {
            return self.clone();
        }
        let elapsed_days = (now_ms - self.updated_ms) as f32 / DAY_MS;
        let retention = 0.5_f32.powf(elapsed_days / half_life_days.max(1) as f32);
        let neutral = Self::with_enabled(self.enabled);
        Self {
            version: PROFILE_VERSION,
            enabled: self.enabled,
            observation_count: self.observation_count,
            updated_ms: self.updated_ms,
            average_sentence_words: blend(
                neutral.average_sentence_words,
                self.average_sentence_words,
                retention,
            ),
            vocabulary_diversity: blend(
                neutral.vocabulary_diversity,
                self.vocabulary_diversity,
                retention,
            ),
            complexity: blend(neutral.complexity, self.complexity, retention),
            formality: blend(neutral.formality, self.formality, retention),
            directness: blend(neutral.directness, self.directness, retention),
            wit: blend(neutral.wit, self.wit, retention),
            analytical: blend(neutral.analytical, self.analytical, retention),
            expressiveness: blend(neutral.expressiveness, self.expressiveness, retention),
        }
    }

    pub fn instruction_block(&self, now_ms: u64, half_life_days: u32) -> Option<String> {
        if !self.enabled || self.observation_count == 0 {
            return None;
        }
        let profile = self.decayed(now_ms, half_life_days);
        let sentence_style = sentence_style(profile.average_sentence_words, profile.complexity);
        let vocabulary_style = vocabulary_style(profile.vocabulary_diversity, profile.complexity);
        let tone = tone_labels(&profile).join(", ");
        Some(format!(
            "Dynamic communication context (locally inferred, advisory, and decaying): Prefer {sentence_style} with {vocabulary_style}. Match a {tone} tone lightly. Use this only for presentation; the current user request, factual accuracy, and explicit user preferences override it. Do not imitate errors or mention this context unless asked."
        ))
    }

    pub fn summary(&self, now_ms: u64, half_life_days: u32) -> DynamicContextSummary {
        let profile = self.decayed(now_ms, half_life_days);
        DynamicContextSummary {
            enabled: profile.enabled,
            observation_count: profile.observation_count,
            updated_ms: profile.updated_ms,
            sentence_style: sentence_style(profile.average_sentence_words, profile.complexity)
                .to_string(),
            vocabulary_style: vocabulary_style(profile.vocabulary_diversity, profile.complexity)
                .to_string(),
            tone: tone_labels(&profile).join(", "),
        }
    }

    pub fn reset(&mut self) {
        let enabled = self.enabled;
        *self = Self::with_enabled(enabled);
    }
}

fn analyze(text: &str) -> Option<TextMetrics> {
    let words = normalized_words(text);
    if words.len() < MIN_WORDS {
        return None;
    }
    let sentence_count = text
        .chars()
        .filter(|character| matches!(character, '.' | '!' | '?' | '\n'))
        .count()
        .max(1);
    let word_count = words.len() as f32;
    let average_sentence_words = (word_count / sentence_count as f32).clamp(3.0, 40.0);
    let unique_words = words.iter().collect::<BTreeSet<_>>().len() as f32;
    let vocabulary_diversity = (unique_words / word_count).clamp(0.0, 1.0);
    let long_word_ratio = words
        .iter()
        .filter(|word| word.chars().count() >= 8)
        .count() as f32
        / word_count;
    let clause_ratio = marker_ratio(
        &words,
        &[
            "although",
            "because",
            "however",
            "instead",
            "otherwise",
            "specifically",
            "therefore",
            "unless",
            "whereas",
            "while",
            "which",
        ],
    );
    let sentence_complexity = ((average_sentence_words - 7.0) / 20.0).clamp(0.0, 1.0);
    let complexity =
        (sentence_complexity * 0.35 + long_word_ratio * 1.8 + clause_ratio * 2.2).clamp(0.0, 1.0);

    let formal = marker_ratio(
        &words,
        &[
            "accordingly",
            "consequently",
            "furthermore",
            "however",
            "regarding",
            "specifically",
            "therefore",
        ],
    );
    let casual = marker_ratio(
        &words,
        &[
            "awesome", "cool", "gonna", "gotta", "haha", "hey", "lol", "nah", "okay", "wanna",
            "yeah",
        ],
    );
    let contractions = words.iter().filter(|word| word.contains('\'')).count() as f32 / word_count;
    let formality = (0.50 + formal * 2.5 - casual * 2.5 - contractions * 1.4).clamp(0.0, 1.0);

    let lower = text.to_ascii_lowercase();
    let direct_markers = [
        "do ", "fix ", "give me", "i need", "i want", "keep ", "make ", "run ", "show me",
        "start ", "stop ", "tell me", "we need",
    ];
    let hedge_markers = [
        "could you",
        "maybe",
        "perhaps",
        "possibly",
        "would you mind",
    ];
    let direct_hits = direct_markers
        .iter()
        .filter(|marker| lower.contains(**marker))
        .count() as f32;
    let hedge_hits = hedge_markers
        .iter()
        .filter(|marker| lower.contains(**marker))
        .count() as f32;
    let directness = (0.42 + direct_hits * 0.13 - hedge_hits * 0.14).clamp(0.0, 1.0);

    let wit = (0.22
        + marker_ratio(
            &words,
            &[
                "funny",
                "haha",
                "humor",
                "joke",
                "lol",
                "roast",
                "sarcastic",
                "witty",
            ],
        ) * 3.2
        + text.matches("?!").count() as f32 * 0.08)
        .clamp(0.0, 1.0);
    let analytical = (0.34
        + marker_ratio(
            &words,
            &[
                "analyze",
                "because",
                "compare",
                "diagnostic",
                "evidence",
                "metric",
                "precise",
                "reason",
                "test",
                "therefore",
                "tradeoff",
                "why",
            ],
        ) * 3.0)
        .clamp(0.0, 1.0);
    let uppercase_words = text
        .split_whitespace()
        .filter(|word| {
            word.chars().count() >= 3
                && word.chars().any(|character| character.is_alphabetic())
                && word
                    .chars()
                    .filter(|character| character.is_alphabetic())
                    .all(|character| character.is_uppercase())
        })
        .count() as f32;
    let expressiveness = (0.30
        + text.matches('!').count() as f32 * 0.08
        + uppercase_words / word_count * 1.6
        + marker_ratio(
            &words,
            &[
                "absolutely",
                "amazing",
                "hate",
                "love",
                "really",
                "seriously",
                "terrible",
                "very",
            ],
        ) * 1.8)
        .clamp(0.0, 1.0);

    Some(TextMetrics {
        average_sentence_words,
        vocabulary_diversity,
        complexity,
        formality,
        directness,
        wit,
        analytical,
        expressiveness,
    })
}

fn normalized_words(text: &str) -> Vec<String> {
    text.split_whitespace()
        .filter_map(|word| {
            let clean = word
                .trim_matches(|character: char| !character.is_alphanumeric() && character != '\'')
                .to_lowercase();
            (!clean.is_empty()).then_some(clean)
        })
        .collect()
}

fn marker_ratio(words: &[String], markers: &[&str]) -> f32 {
    if words.is_empty() {
        return 0.0;
    }
    let hits = words
        .iter()
        .filter(|word| markers.contains(&word.as_str()))
        .count();
    hits as f32 / words.len() as f32
}

fn blend(previous: f32, next: f32, next_weight: f32) -> f32 {
    previous * (1.0 - next_weight) + next * next_weight
}

fn sentence_style(average_sentence_words: f32, complexity: f32) -> &'static str {
    match (average_sentence_words, complexity) {
        (length, score) if length <= 9.0 && score < 0.48 => "short, straightforward sentences",
        (length, score) if length >= 20.0 || score >= 0.68 => {
            "longer, layered sentences when useful"
        }
        _ => "medium-length, clear sentences",
    }
}

fn vocabulary_style(diversity: f32, complexity: f32) -> &'static str {
    if diversity >= 0.72 && complexity >= 0.55 {
        "precise, varied vocabulary"
    } else if diversity <= 0.42 && complexity <= 0.38 {
        "plain vocabulary"
    } else {
        "balanced vocabulary"
    }
}

fn tone_labels(profile: &DynamicContextProfile) -> Vec<&'static str> {
    let mut labels = Vec::new();
    if profile.directness >= 0.54 {
        labels.push("direct");
    }
    if profile.formality >= 0.62 {
        labels.push("formal");
    } else if profile.formality <= 0.43 {
        labels.push("casual");
    }
    if profile.analytical >= 0.56 {
        labels.push("analytical");
    }
    if profile.wit >= 0.54 {
        labels.push("witty");
    }
    if profile.expressiveness >= 0.58 {
        labels.push("expressive");
    }
    if labels.is_empty() {
        labels.push("natural");
    }
    labels.truncate(3);
    labels
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn direct_analytical_language_updates_the_next_turn_profile() {
        let mut profile = DynamicContextProfile::default();
        assert!(profile.observe(
            "We need to test this precisely because the diagnostics expose the real tradeoff.",
            1_000,
            DEFAULT_HALF_LIFE_DAYS,
            DEFAULT_MAX_OBSERVATIONS
        ));

        let instruction = profile
            .instruction_block(1_001, DEFAULT_HALF_LIFE_DAYS)
            .expect("instruction");
        assert!(instruction.contains("direct"));
        assert!(instruction.contains("analytical"));
        assert!(instruction.contains("current user request"));
    }

    #[test]
    fn recent_style_replaces_old_style_instead_of_locking_forever() {
        let mut profile = DynamicContextProfile::default();
        profile.observe(
            "Therefore, please provide a comprehensive analysis regarding the architectural consequences.",
            1_000,
            DEFAULT_HALF_LIFE_DAYS,
            DEFAULT_MAX_OBSERVATIONS,
        );
        for index in 1..=8 {
            profile.observe(
                "Yeah, keep it short and direct please.",
                1_000 + index,
                DEFAULT_HALF_LIFE_DAYS,
                DEFAULT_MAX_OBSERVATIONS,
            );
        }

        let summary = profile.summary(2_000, DEFAULT_HALF_LIFE_DAYS);
        assert!(summary.sentence_style.contains("short"));
        assert!(summary.tone.contains("direct"));
        assert!(summary.tone.contains("casual"));
    }

    #[test]
    fn old_profiles_decay_toward_neutral() {
        let mut profile = DynamicContextProfile::default();
        profile.observe(
            "Please therefore provide a comprehensive and extraordinarily detailed analytical explanation.",
            1_000,
            DEFAULT_HALF_LIFE_DAYS,
            DEFAULT_MAX_OBSERVATIONS,
        );
        let future = 1_000 + (DEFAULT_HALF_LIFE_DAYS as u64 * 6 * 86_400_000);
        let decayed = profile.decayed(future, DEFAULT_HALF_LIFE_DAYS);

        assert!((decayed.formality - 0.50).abs() < (profile.formality - 0.50).abs());
        assert!(
            (decayed.average_sentence_words - 14.0).abs()
                < (profile.average_sentence_words - 14.0).abs()
        );
    }

    #[test]
    fn profile_serialization_never_contains_raw_user_text() {
        let secret = "private-token-7f91";
        let mut profile = DynamicContextProfile::default();
        profile.observe(
            &format!("Analyze this carefully because {secret} must remain private."),
            1_000,
            DEFAULT_HALF_LIFE_DAYS,
            DEFAULT_MAX_OBSERVATIONS,
        );
        let json = serde_json::to_string(&profile).expect("json");

        assert!(!json.contains(secret));
        assert!(!json.contains("Analyze this carefully"));
    }

    #[test]
    fn serialized_profile_survives_restart_without_raw_history() {
        let mut profile = DynamicContextProfile::default();
        profile.observe(
            "Keep the response concise, direct, and analytical because the test matters.",
            1_000,
            DEFAULT_HALF_LIFE_DAYS,
            DEFAULT_MAX_OBSERVATIONS,
        );
        let json = serde_json::to_string(&profile).expect("serialize");
        let restored: DynamicContextProfile = serde_json::from_str(&json).expect("restore");

        assert_eq!(restored.observation_count, 1);
        assert_eq!(
            restored.instruction_block(1_001, DEFAULT_HALF_LIFE_DAYS),
            profile.instruction_block(1_001, DEFAULT_HALF_LIFE_DAYS)
        );
        assert!(!json.contains("test matters"));
    }

    #[test]
    fn disabled_or_too_short_input_does_not_update() {
        let mut disabled = DynamicContextProfile::with_enabled(false);
        assert!(!disabled.observe(
            "Analyze this now.",
            1_000,
            DEFAULT_HALF_LIFE_DAYS,
            DEFAULT_MAX_OBSERVATIONS
        ));
        assert!(
            disabled
                .instruction_block(1_001, DEFAULT_HALF_LIFE_DAYS)
                .is_none()
        );

        let mut enabled = DynamicContextProfile::default();
        assert!(!enabled.observe(
            "yes",
            1_000,
            DEFAULT_HALF_LIFE_DAYS,
            DEFAULT_MAX_OBSERVATIONS
        ));
        assert_eq!(enabled.observation_count, 0);
    }
}
