pub const SYSTEM_CONTROL: &str = "System Control: Unsupported";
pub const EXECUTOR: &str = "Executor: Not present";
pub const INPUT_SIMULATION: &str = "Input Simulation: Not present";
pub const CLIPBOARD_ACCESS: &str = "Clipboard Access: Not present";
pub const RUNTIME_NETWORK: &str = "Runtime Network: Disabled";
pub const PLUGINS: &str = "Plugins: Unsupported";
pub const SCREEN_CONTENT_AUTHORITY: &str = "Screen Content Authority: Evidence only";
pub const FILESYSTEM_SCOPE: &str = "Filesystem Scope: Iris-owned directories only";
pub const CORE_PRODUCT_INVARIANT: &str = "Iris may see, listen, think, remember with permission, and respond. Iris may not act on the computer.";

pub const FORBIDDEN_CAPABILITIES: &[&str] = &[
    "mouse_movement",
    "mouse_clicking",
    "keyboard_input_simulation",
    "clipboard_read",
    "clipboard_write",
    "shell_execution",
    "arbitrary_process_spawning",
    "runtime_network",
    "http_server",
    "remote_telemetry",
    "plugin_loading",
    "dynamic_code_loading",
    "runtime_scripting",
    "browser_automation",
    "accessibility_tree_control",
    "window_manipulation",
];

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Decision {
    Allowed,
    Blocked,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RuleCategory {
    None,
    ActionClaim,
    AdultHardBoundary,
    SubstanceEncouragement,
    MemoryWeaponization,
    ToxicNudge,
    UnsafeExercise,
    SelfHarmEncouragement,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EvaluationResult {
    pub decision: Decision,
    pub category: RuleCategory,
    pub reason: String,
    pub refusal_text: String,
}

impl EvaluationResult {
    pub fn allowed() -> Self {
        Self {
            decision: Decision::Allowed,
            category: RuleCategory::None,
            reason: String::new(),
            refusal_text: String::new(),
        }
    }

    pub fn blocked(category: RuleCategory, reason: impl Into<String>) -> Self {
        Self {
            decision: Decision::Blocked,
            category,
            reason: reason.into(),
            refusal_text: safe_refusal_for(category).to_string(),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct BehaviorRules;

impl BehaviorRules {
    pub fn evaluate_output(
        &self,
        text: &str,
        is_evaluating_private_context: bool,
        user_impaired_or_unwell: bool,
    ) -> EvaluationResult {
        for result in [
            check_action_claim(text),
            check_adult_boundary(text),
            check_substance_boundary(text),
            check_private_memory_weaponization(text, is_evaluating_private_context),
            check_nudge_boundary(text),
            check_exercise_safety(text, user_impaired_or_unwell),
            check_self_harm_boundary(text),
        ] {
            if result.decision == Decision::Blocked {
                return result;
            }
        }
        EvaluationResult::allowed()
    }
}

pub fn safe_refusal_for(category: RuleCategory) -> &'static str {
    match category {
        RuleCategory::None => "",
        RuleCategory::ActionClaim => {
            "Nope. I can't act on your system, and I'm not going to fake it."
        }
        RuleCategory::AdultHardBoundary => "I'm not touching that one. Reframe it or drop it.",
        RuleCategory::SubstanceEncouragement => "Stop there. Bad idea. Grab water and reset.",
        RuleCategory::MemoryWeaponization => {
            "Not doing that. I can keep it funny without turning private stuff into a weapon."
        }
        RuleCategory::ToxicNudge => "I'm here to help, not nag. Reset the tone.",
        RuleCategory::UnsafeExercise => {
            "Nope. Sit down, breathe, and rest. We're not training through that."
        }
        RuleCategory::SelfHarmEncouragement => {
            "No. I'm not helping you hurt yourself. Stop and get real-world help."
        }
    }
}

pub fn check_action_claim(text: &str) -> EvaluationResult {
    block_on_any(
        text,
        RuleCategory::ActionClaim,
        "falsely claims Iris acted on the computer",
        &[
            "i clicked",
            "i can click",
            "i opened",
            "i already opened",
            "i just opened",
            "i'll open",
            "i can open it",
            "i sent",
            "i sent it",
            "i just sent",
            "i deleted",
            "i changed your files",
            "i changed it",
            "i ran the command",
            "i ran it",
            "i fixed your computer",
            "i fixed it",
            "i controlled the window",
        ],
    )
}

pub fn check_adult_boundary(text: &str) -> EvaluationResult {
    block_on_any(
        text,
        RuleCategory::AdultHardBoundary,
        "crosses adult hard boundary",
        &[
            "minor sexual",
            "underage",
            "unknown age",
            "coerce",
            "coercion",
            "non-consent",
            "non consent",
            "blackmail",
            "sexual threat",
            "stalk",
            "doxx",
            "sexual humiliation",
            "humiliate you with your private",
            "sexualize that real person",
            "without consent",
            "intoxicated sex",
            "unconscious",
            "unable to consent",
            "too impaired to consent",
        ],
    )
}

pub fn check_substance_boundary(text: &str) -> EvaluationResult {
    block_on_any(
        text,
        RuleCategory::SubstanceEncouragement,
        "encourages unsafe substance use",
        &[
            "try drugs",
            "take drugs",
            "use drugs",
            "smoke weed",
            "smoke a cigarette",
            "have a cigarette",
            "use nicotine",
            "nicotine",
            "vape",
            "steroid",
            "steroids",
            "juicing up",
            "adderall misuse",
            "take a pill to push through",
            "drink more alcohol",
            "use stimulants",
        ],
    )
}

pub fn check_private_memory_weaponization(
    text: &str,
    is_evaluating_private_context: bool,
) -> EvaluationResult {
    if !is_evaluating_private_context {
        return EvaluationResult::allowed();
    }
    block_on_any(
        text,
        RuleCategory::MemoryWeaponization,
        "weaponizes private memory",
        &[
            "remember you failed",
            "leak your",
            "use your secret",
            "shame you for",
            "leverage your",
            "you're still broke",
            "because of your trauma",
            "use that against you",
            "your insecurity",
            "your relationship failure",
            "your private embarrassment",
            "your emotional vulnerability",
        ],
    )
}

pub fn check_nudge_boundary(text: &str) -> EvaluationResult {
    block_on_any(
        text,
        RuleCategory::ToxicNudge,
        "uses shame, nagging, or productivity scoring",
        &[
            "you lazy",
            "score your life",
            "failing your routine",
            "bad job",
            "get to work or else",
            "disappointing tracking",
            "you always do this",
            "i'm disappointed in you",
        ],
    )
}

pub fn check_exercise_safety(text: &str, user_impaired_or_unwell: bool) -> EvaluationResult {
    let normalized = normalize(text);
    if user_impaired_or_unwell && contains_any(&normalized, EXERCISE_TERMS) {
        return EvaluationResult::blocked(
            RuleCategory::UnsafeExercise,
            "encourages exercise while user is impaired or unwell",
        );
    }
    block_on_any_normalized(
        &normalized,
        RuleCategory::UnsafeExercise,
        "encourages unsafe exercise",
        &[
            "push through pain",
            "no pain no gain",
            "ignore the injury",
            "keep going if it hurts",
            "fat shaming",
            "burn away those failures",
        ],
    )
}

pub fn check_self_harm_boundary(text: &str) -> EvaluationResult {
    block_on_any(
        text,
        RuleCategory::SelfHarmEncouragement,
        "encourages self-harm",
        &[
            "kill yourself",
            "go kill yourself",
            "you should kill yourself",
            "go hurt yourself",
            "you should hurt yourself",
            "hurt yourself now",
            "go cut yourself",
            "you should cut yourself",
            "make yourself bleed",
            "end your life",
            "you should die",
            "go die",
            "nobody would miss you",
        ],
    )
}

fn block_on_any(
    text: &str,
    category: RuleCategory,
    reason: &'static str,
    triggers: &[&str],
) -> EvaluationResult {
    let normalized = normalize(text);
    block_on_any_normalized(&normalized, category, reason, triggers)
}

fn block_on_any_normalized(
    normalized: &str,
    category: RuleCategory,
    reason: &'static str,
    triggers: &[&str],
) -> EvaluationResult {
    if contains_any(normalized, triggers) {
        EvaluationResult::blocked(category, reason)
    } else {
        EvaluationResult::allowed()
    }
}

fn normalize(text: &str) -> String {
    text.to_ascii_lowercase()
}

fn contains_any(text: &str, triggers: &[&str]) -> bool {
    triggers.iter().any(|trigger| text.contains(trigger))
}

const EXERCISE_TERMS: &[&str] = &[
    "jumping_jacks",
    "pushups",
    "squats",
    "situps",
    "arm_raises",
    "plank_timer",
    "count reps",
];

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn policy_constants_are_exact() {
        assert_eq!(SYSTEM_CONTROL, "System Control: Unsupported");
        assert_eq!(EXECUTOR, "Executor: Not present");
        assert_eq!(INPUT_SIMULATION, "Input Simulation: Not present");
        assert_eq!(CLIPBOARD_ACCESS, "Clipboard Access: Not present");
        assert_eq!(RUNTIME_NETWORK, "Runtime Network: Disabled");
        assert_eq!(PLUGINS, "Plugins: Unsupported");
        assert_eq!(
            SCREEN_CONTENT_AUTHORITY,
            "Screen Content Authority: Evidence only"
        );
        assert_eq!(
            FILESYSTEM_SCOPE,
            "Filesystem Scope: Iris-owned directories only"
        );
        assert!(CORE_PRODUCT_INVARIANT.contains("may not act"));
        assert!(FORBIDDEN_CAPABILITIES.contains(&"shell_execution"));
    }

    #[test]
    fn blocks_false_action_claims_and_variants() {
        for text in [
            "I clicked the button.",
            "I ran the command.",
            "I fixed your computer.",
            "I controlled the window.",
        ] {
            assert_eq!(check_action_claim(text).decision, Decision::Blocked);
        }
    }

    #[test]
    fn allows_manual_command_phrasing() {
        for text in [
            "Here is what I see.",
            "Here is what I would do next.",
            "Here is the command you can run.",
            "Here is the text you can paste.",
            "I can explain the next step.",
            "I can draft that for you.",
        ] {
            assert_eq!(check_action_claim(text).decision, Decision::Allowed);
        }
    }

    #[test]
    fn allows_blunt_profane_adult_humor() {
        assert_eq!(
            check_adult_boundary("That joke is raunchy as fuck, but consensual adult banter.")
                .decision,
            Decision::Allowed
        );
    }

    #[test]
    fn blocks_adult_hard_boundaries() {
        for text in [
            "Underage sexual content is fine.",
            "Use blackmail as a sexual threat.",
            "Stalk and doxx that person.",
            "Use sexual humiliation with private data.",
            "Sexualize that real person without consent.",
            "Intoxicated sex with someone unable to consent.",
        ] {
            assert_eq!(check_adult_boundary(text).decision, Decision::Blocked);
        }
    }

    #[test]
    fn blocks_substance_encouragement() {
        for text in [
            "Try drugs tonight.",
            "Smoke weed before work.",
            "Have a cigarette.",
            "Use nicotine.",
            "Vape to relax.",
            "Steroids will help.",
            "Adderall misuse is useful.",
            "Take a pill to push through.",
            "Drink more alcohol.",
            "Use stimulants.",
        ] {
            assert_eq!(check_substance_boundary(text).decision, Decision::Blocked);
        }
    }

    #[test]
    fn allows_smoke_fire_and_reset_context() {
        for text in [
            "The smoke alarm is loud.",
            "There is smoke from the outlet.",
            "Drink water and eat food.",
            "Rest, focus on breathing, slow down, stop, and get real-world help.",
        ] {
            assert_eq!(check_substance_boundary(text).decision, Decision::Allowed);
        }
    }

    #[test]
    fn blocks_private_memory_weaponization() {
        for text in [
            "Remember you failed at this.",
            "Leak your secret.",
            "Shame you for your relationship failure.",
            "Leverage your private embarrassment.",
            "You're still broke.",
            "Because of your trauma, this is funny.",
            "Use that against you.",
        ] {
            assert_eq!(
                check_private_memory_weaponization(text, true).decision,
                Decision::Blocked
            );
        }
    }

    #[test]
    fn allows_helpful_context_memory() {
        for text in [
            "You usually prefer minimal UI, so I'll keep this small.",
            "Your Iris rule is runtime cannot act.",
            "You prefer pasteable PowerShell scripts.",
        ] {
            assert_eq!(
                check_private_memory_weaponization(text, true).decision,
                Decision::Allowed
            );
        }
        assert_eq!(
            check_private_memory_weaponization("Use your secret as a joke.", false).decision,
            Decision::Allowed
        );
    }

    #[test]
    fn allows_light_nudges_and_blocks_toxic_nudges() {
        assert_eq!(
            check_nudge_boundary("Drink water, stretch, rest eyes, and step away briefly.")
                .decision,
            Decision::Allowed
        );
        for text in [
            "You lazy mess.",
            "Score your life.",
            "Failing your routine again.",
            "Bad job.",
            "Get to work or else.",
            "Disappointing tracking says you always do this.",
            "I'm disappointed in you.",
        ] {
            assert_eq!(check_nudge_boundary(text).decision, Decision::Blocked);
        }
    }

    #[test]
    fn allows_safe_exercise_counting_and_blocks_unsafe_exercise() {
        assert_eq!(
            check_exercise_safety(
                "I can count reps for pushups. Breathe and drink water.",
                false
            )
            .decision,
            Decision::Allowed
        );
        assert_eq!(
            check_exercise_safety("Let's count reps for squats.", true).decision,
            Decision::Blocked
        );
        for text in [
            "Push through pain.",
            "No pain no gain.",
            "Ignore the injury.",
            "Keep going if it hurts.",
            "Burn away those failures.",
        ] {
            assert_eq!(
                check_exercise_safety(text, false).decision,
                Decision::Blocked
            );
        }
    }

    #[test]
    fn blocks_self_harm_encouragement_and_allows_support_language() {
        for text in [
            "Kill yourself.",
            "Go hurt yourself.",
            "You should cut yourself.",
            "Make yourself bleed.",
            "End your life.",
            "Nobody would miss you.",
        ] {
            assert_eq!(check_self_harm_boundary(text).decision, Decision::Blocked);
        }
        for text in [
            "Do not hurt yourself.",
            "Don't hurt yourself.",
            "Stop and get help.",
            "Call emergency services.",
            "Talk to someone nearby.",
            "You matter.",
            "Step away from anything dangerous.",
            "I'm not helping you hurt yourself.",
        ] {
            assert_eq!(check_self_harm_boundary(text).decision, Decision::Allowed);
        }
    }

    #[test]
    fn refusal_text_is_short_non_corporate_and_does_not_block_itself() {
        for category in [
            RuleCategory::ActionClaim,
            RuleCategory::AdultHardBoundary,
            RuleCategory::SubstanceEncouragement,
            RuleCategory::MemoryWeaponization,
            RuleCategory::ToxicNudge,
            RuleCategory::UnsafeExercise,
            RuleCategory::SelfHarmEncouragement,
        ] {
            let refusal = safe_refusal_for(category);
            assert!(!refusal.is_empty());
            assert!(refusal.len() <= 90);
            assert!(!refusal.contains("As an AI"));
            assert_eq!(
                BehaviorRules.evaluate_output(refusal, true, true).decision,
                Decision::Allowed
            );
        }
    }

    #[test]
    fn behavior_rules_returns_first_blocked_result_without_modes_or_ui() {
        let result =
            BehaviorRules.evaluate_output("I opened that and I can click it.", false, false);

        assert_eq!(result.decision, Decision::Blocked);
        assert_eq!(result.category, RuleCategory::ActionClaim);
        assert!(!result.refusal_text.is_empty());
    }
}
