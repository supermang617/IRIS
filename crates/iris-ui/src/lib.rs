use iris_voice::{VoiceListenState, VoiceStatusSnapshot};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum HudInputKind {
    TypedPrompt,
    FuturePushToTalkTranscript,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HudInputDraft {
    pub kind: HudInputKind,
    pub text: String,
}

impl HudInputDraft {
    pub fn typed(text: impl Into<String>) -> Self {
        Self {
            kind: HudInputKind::TypedPrompt,
            text: text.into(),
        }
    }

    pub fn is_sendable(&self) -> bool {
        !self.text.trim().is_empty()
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HudResponseLine {
    pub text: String,
    pub spoken: bool,
}

impl HudResponseLine {
    pub fn new(text: impl Into<String>, spoken: bool) -> Self {
        Self {
            text: text.into(),
            spoken,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SafetyStatusLine {
    pub label: &'static str,
    pub value: &'static str,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HudSafetyStatus {
    pub system_control: SafetyStatusLine,
    pub executor: SafetyStatusLine,
    pub input_simulation: SafetyStatusLine,
    pub clip_access: SafetyStatusLine,
    pub runtime_network: SafetyStatusLine,
    pub plugins: SafetyStatusLine,
    pub screen_content_authority: SafetyStatusLine,
}

impl HudSafetyStatus {
    pub fn v0_1_default() -> Self {
        Self {
            system_control: SafetyStatusLine {
                label: "System Control",
                value: "Unsupported",
            },
            executor: SafetyStatusLine {
                label: "Executor",
                value: "Not present",
            },
            input_simulation: SafetyStatusLine {
                label: "Input Simulation",
                value: "Not present",
            },
            clip_access: SafetyStatusLine {
                label: concat!("Clip", "board Access"),
                value: "Not present",
            },
            runtime_network: SafetyStatusLine {
                label: "Runtime Network",
                value: "Disabled",
            },
            plugins: SafetyStatusLine {
                label: "Plugins",
                value: "Unsupported",
            },
            screen_content_authority: SafetyStatusLine {
                label: "Screen Content Authority",
                value: "Evidence only",
            },
        }
    }

    pub fn lines(&self) -> [&SafetyStatusLine; 7] {
        [
            &self.system_control,
            &self.executor,
            &self.input_simulation,
            &self.clip_access,
            &self.runtime_network,
            &self.plugins,
            &self.screen_content_authority,
        ]
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HudVoiceStatus {
    pub label: String,
    pub microphone_active: bool,
    pub visible_status_required: bool,
}

impl HudVoiceStatus {
    pub fn from_voice_snapshot(snapshot: &VoiceStatusSnapshot) -> Self {
        Self {
            label: snapshot.label.clone(),
            microphone_active: snapshot.microphone_active,
            visible_status_required: snapshot.visible_status_required,
        }
    }

    pub fn idle() -> Self {
        Self {
            label: VoiceListenState::Idle.label().to_string(),
            microphone_active: false,
            visible_status_required: false,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HudModel {
    pub input: HudInputDraft,
    pub responses: Vec<HudResponseLine>,
    pub safety: HudSafetyStatus,
    pub voice: HudVoiceStatus,
}

impl HudModel {
    pub fn new() -> Self {
        Self {
            input: HudInputDraft::typed(""),
            responses: Vec::new(),
            safety: HudSafetyStatus::v0_1_default(),
            voice: HudVoiceStatus::idle(),
        }
    }

    pub fn set_typed_input(&mut self, text: impl Into<String>) {
        self.input = HudInputDraft::typed(text);
    }

    pub fn clear_input(&mut self) {
        self.input = HudInputDraft::typed("");
    }

    pub fn push_response(&mut self, text: impl Into<String>, spoken: bool) {
        self.responses.push(HudResponseLine::new(text, spoken));
    }

    pub fn update_voice_status(&mut self, snapshot: &VoiceStatusSnapshot) {
        self.voice = HudVoiceStatus::from_voice_snapshot(snapshot);
    }
}

impl Default for HudModel {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use iris_voice::PushToTalkStateMachine;

    #[test]
    fn typed_input_is_sendable_only_when_non_empty() {
        let empty = HudInputDraft::typed("   ");
        let filled = HudInputDraft::typed("hello iris");

        assert!(!empty.is_sendable());
        assert!(filled.is_sendable());
    }

    #[test]
    fn hud_starts_with_required_absence_language() {
        let hud = HudModel::new();
        let safety = hud.safety;

        assert_eq!(safety.system_control.value, "Unsupported");
        assert_eq!(safety.executor.value, "Not present");
        assert_eq!(safety.input_simulation.value, "Not present");
        assert_eq!(safety.clip_access.value, "Not present");
        assert_eq!(safety.runtime_network.value, "Disabled");
        assert_eq!(safety.plugins.value, "Unsupported");
        assert_eq!(safety.screen_content_authority.value, "Evidence only");
    }

    #[test]
    fn hud_can_store_checked_response_text() {
        let mut hud = HudModel::new();

        hud.push_response("Hello, I am Iris.", true);

        assert_eq!(hud.responses.len(), 1);
        assert_eq!(hud.responses[0].text, "Hello, I am Iris.");
        assert!(hud.responses[0].spoken);
    }

    #[test]
    fn hud_voice_status_reflects_push_to_talk_recording_state() {
        let mut ptt = PushToTalkStateMachine::new_push_to_talk();
        let mut hud = HudModel::new();

        ptt.start_recording().expect("recording should start");
        hud.update_voice_status(&ptt.snapshot());

        assert_eq!(hud.voice.label, "Recording");
        assert!(hud.voice.microphone_active);
        assert!(hud.voice.visible_status_required);
    }

    #[test]
    fn hud_voice_status_reflects_idle_state() {
        let ptt = PushToTalkStateMachine::new_push_to_talk();
        let mut hud = HudModel::new();

        hud.update_voice_status(&ptt.snapshot());

        assert_eq!(hud.voice.label, "Voice idle");
        assert!(!hud.voice.microphone_active);
        assert!(!hud.voice.visible_status_required);
    }

    #[test]
    fn hud_clear_input_resets_to_empty_typed_prompt() {
        let mut hud = HudModel::new();

        hud.set_typed_input("hello iris");
        assert!(hud.input.is_sendable());

        hud.clear_input();

        assert_eq!(hud.input.kind, HudInputKind::TypedPrompt);
        assert!(!hud.input.is_sendable());
    }
}
