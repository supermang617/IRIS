#[derive(Debug, Clone, PartialEq, Eq)]
pub enum VoiceActivationMode {
    TypedPrompt,
    OneShotVoice,
    PushToTalk,
    FutureWakeWordDisabledByDefault,
}

impl VoiceActivationMode {
    pub fn is_live_microphone_mode(&self) -> bool {
        matches!(
            self,
            Self::OneShotVoice | Self::PushToTalk | Self::FutureWakeWordDisabledByDefault
        )
    }

    pub fn is_v0_1_default_allowed(&self) -> bool {
        matches!(
            self,
            Self::TypedPrompt | Self::OneShotVoice | Self::PushToTalk
        )
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum VoiceBackend {
    KokoroOnnx,
    WindowsSpeechFallback,
    TextOnly,
}

#[derive(Debug, Clone, PartialEq)]
pub struct KokoroVoiceProfile {
    pub voice: String,
    pub speed: f32,
    pub wake_signal_ms: u32,
    pub lead_silence_ms: u32,
    pub tail_silence_ms: u32,
}

impl KokoroVoiceProfile {
    pub fn iris_default() -> Self {
        Self {
            voice: "af_heart".to_string(),
            speed: 0.95,
            wake_signal_ms: 900,
            lead_silence_ms: 300,
            tail_silence_ms: 300,
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct VoiceOutputProfile {
    pub backend: VoiceBackend,
    pub kokoro: KokoroVoiceProfile,
}

impl VoiceOutputProfile {
    pub fn iris_default() -> Self {
        Self {
            backend: VoiceBackend::KokoroOnnx,
            kokoro: KokoroVoiceProfile::iris_default(),
        }
    }

    pub fn text_only() -> Self {
        Self {
            backend: VoiceBackend::TextOnly,
            kokoro: KokoroVoiceProfile::iris_default(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SpeechPermission {
    AllowedCheckedResponse,
    BlockedByPostCheck,
    EmptyText,
}

#[derive(Debug, Clone, PartialEq)]
pub struct VoiceOutputPlan {
    pub text: String,
    pub profile: VoiceOutputProfile,
    pub permission: SpeechPermission,
}

impl VoiceOutputPlan {
    pub fn from_checked_response(
        response_text: impl Into<String>,
        post_check_passed: bool,
        profile: VoiceOutputProfile,
    ) -> Self {
        let text = response_text.into();
        let permission = if text.trim().is_empty() {
            SpeechPermission::EmptyText
        } else if post_check_passed {
            SpeechPermission::AllowedCheckedResponse
        } else {
            SpeechPermission::BlockedByPostCheck
        };

        Self {
            text,
            profile,
            permission,
        }
    }

    pub fn may_speak(&self) -> bool {
        self.permission == SpeechPermission::AllowedCheckedResponse
            && self.profile.backend != VoiceBackend::TextOnly
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VoiceInputPolicy {
    pub activation_mode: VoiceActivationMode,
    pub bounded_capture_seconds: u32,
    pub transcript_must_enter_context_gate: bool,
}

impl VoiceInputPolicy {
    pub fn one_shot_default() -> Self {
        Self {
            activation_mode: VoiceActivationMode::OneShotVoice,
            bounded_capture_seconds: 10,
            transcript_must_enter_context_gate: true,
        }
    }

    pub fn push_to_talk_default() -> Self {
        Self {
            activation_mode: VoiceActivationMode::PushToTalk,
            bounded_capture_seconds: 30,
            transcript_must_enter_context_gate: true,
        }
    }

    pub fn future_wake_word_disabled() -> Self {
        Self {
            activation_mode: VoiceActivationMode::FutureWakeWordDisabledByDefault,
            bounded_capture_seconds: 10,
            transcript_must_enter_context_gate: true,
        }
    }

    pub fn is_safe_for_v0_1_default(&self) -> bool {
        self.activation_mode.is_v0_1_default_allowed()
            && self.bounded_capture_seconds > 0
            && self.transcript_must_enter_context_gate
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum VoiceListenState {
    Idle,
    Armed,
    Recording,
    ProcessingTranscript,
    Speaking,
    Stopped,
}

impl VoiceListenState {
    pub fn microphone_is_active(&self) -> bool {
        matches!(self, Self::Recording)
    }

    pub fn visible_status_required(&self) -> bool {
        !matches!(self, Self::Idle)
    }

    pub fn label(&self) -> &'static str {
        match self {
            Self::Idle => "Voice idle",
            Self::Armed => "Voice armed",
            Self::Recording => "Recording",
            Self::ProcessingTranscript => "Processing transcript",
            Self::Speaking => "Speaking",
            Self::Stopped => "Stopped",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VoiceStatusSnapshot {
    pub activation_mode: VoiceActivationMode,
    pub listen_state: VoiceListenState,
    pub label: String,
    pub microphone_active: bool,
    pub visible_status_required: bool,
    pub bounded_capture_seconds: u32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PushToTalkStateMachine {
    activation_mode: VoiceActivationMode,
    listen_state: VoiceListenState,
    bounded_capture_seconds: u32,
}

impl PushToTalkStateMachine {
    pub fn new_push_to_talk() -> Self {
        Self {
            activation_mode: VoiceActivationMode::PushToTalk,
            listen_state: VoiceListenState::Idle,
            bounded_capture_seconds: 30,
        }
    }

    pub fn state(&self) -> VoiceListenState {
        self.listen_state
    }

    pub fn arm(&mut self) {
        self.listen_state = VoiceListenState::Armed;
    }

    pub fn start_recording(&mut self) -> Result<(), &'static str> {
        match self.listen_state {
            VoiceListenState::Idle | VoiceListenState::Armed => {
                self.listen_state = VoiceListenState::Recording;
                Ok(())
            }
            VoiceListenState::Recording => Ok(()),
            VoiceListenState::ProcessingTranscript
            | VoiceListenState::Speaking
            | VoiceListenState::Stopped => {
                Err("push-to-talk recording cannot start from current state")
            }
        }
    }

    pub fn stop_recording(&mut self) -> Result<(), &'static str> {
        match self.listen_state {
            VoiceListenState::Recording => {
                self.listen_state = VoiceListenState::ProcessingTranscript;
                Ok(())
            }
            _ => Err("push-to-talk recording is not active"),
        }
    }

    pub fn begin_speaking(&mut self) -> Result<(), &'static str> {
        match self.listen_state {
            VoiceListenState::ProcessingTranscript | VoiceListenState::Idle => {
                self.listen_state = VoiceListenState::Speaking;
                Ok(())
            }
            _ => Err("speech output cannot begin from current state"),
        }
    }

    pub fn finish_speaking(&mut self) {
        self.listen_state = VoiceListenState::Idle;
    }

    pub fn panic_stop(&mut self) {
        self.listen_state = VoiceListenState::Stopped;
    }

    pub fn reset(&mut self) {
        self.listen_state = VoiceListenState::Idle;
    }

    pub fn snapshot(&self) -> VoiceStatusSnapshot {
        VoiceStatusSnapshot {
            activation_mode: self.activation_mode.clone(),
            listen_state: self.listen_state,
            label: self.listen_state.label().to_string(),
            microphone_active: self.listen_state.microphone_is_active(),
            visible_status_required: self.listen_state.visible_status_required(),
            bounded_capture_seconds: self.bounded_capture_seconds,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn iris_default_voice_is_kokoro_af_heart_at_point_95_speed() {
        let profile = VoiceOutputProfile::iris_default();

        assert_eq!(profile.backend, VoiceBackend::KokoroOnnx);
        assert_eq!(profile.kokoro.voice, "af_heart");
        assert!((profile.kokoro.speed - 0.95).abs() < f32::EPSILON);
        assert_eq!(profile.kokoro.wake_signal_ms, 900);
        assert_eq!(profile.kokoro.lead_silence_ms, 300);
        assert_eq!(profile.kokoro.tail_silence_ms, 300);
    }

    #[test]
    fn checked_response_may_speak() {
        let plan = VoiceOutputPlan::from_checked_response(
            "Hello, I am Iris.",
            true,
            VoiceOutputProfile::iris_default(),
        );

        assert_eq!(plan.permission, SpeechPermission::AllowedCheckedResponse);
        assert!(plan.may_speak());
    }

    #[test]
    fn blocked_response_must_not_speak() {
        let plan = VoiceOutputPlan::from_checked_response(
            "I will do that.",
            false,
            VoiceOutputProfile::iris_default(),
        );

        assert_eq!(plan.permission, SpeechPermission::BlockedByPostCheck);
        assert!(!plan.may_speak());
    }

    #[test]
    fn empty_response_must_not_speak() {
        let plan =
            VoiceOutputPlan::from_checked_response("   ", true, VoiceOutputProfile::iris_default());

        assert_eq!(plan.permission, SpeechPermission::EmptyText);
        assert!(!plan.may_speak());
    }

    #[test]
    fn text_only_profile_never_speaks() {
        let plan =
            VoiceOutputPlan::from_checked_response("Hello.", true, VoiceOutputProfile::text_only());

        assert_eq!(plan.permission, SpeechPermission::AllowedCheckedResponse);
        assert!(!plan.may_speak());
    }

    #[test]
    fn one_shot_voice_policy_is_safe_for_current_testing() {
        let policy = VoiceInputPolicy::one_shot_default();

        assert_eq!(policy.activation_mode, VoiceActivationMode::OneShotVoice);
        assert!(policy.is_safe_for_v0_1_default());
    }

    #[test]
    fn push_to_talk_policy_is_safe_for_v0_1() {
        let policy = VoiceInputPolicy::push_to_talk_default();

        assert_eq!(policy.activation_mode, VoiceActivationMode::PushToTalk);
        assert!(policy.is_safe_for_v0_1_default());
    }

    #[test]
    fn future_wake_word_is_documented_but_not_v0_1_default() {
        let policy = VoiceInputPolicy::future_wake_word_disabled();

        assert_eq!(
            policy.activation_mode,
            VoiceActivationMode::FutureWakeWordDisabledByDefault
        );
        assert!(!policy.is_safe_for_v0_1_default());
        assert!(policy.activation_mode.is_live_microphone_mode());
    }

    #[test]
    fn push_to_talk_starts_idle() {
        let ptt = PushToTalkStateMachine::new_push_to_talk();

        assert_eq!(ptt.state(), VoiceListenState::Idle);
        assert!(!ptt.snapshot().microphone_active);
        assert!(!ptt.snapshot().visible_status_required);
    }

    #[test]
    fn push_to_talk_records_with_visible_status() {
        let mut ptt = PushToTalkStateMachine::new_push_to_talk();

        ptt.arm();
        assert_eq!(ptt.state(), VoiceListenState::Armed);
        assert!(ptt.snapshot().visible_status_required);

        ptt.start_recording().expect("recording should start");
        let snapshot = ptt.snapshot();

        assert_eq!(snapshot.listen_state, VoiceListenState::Recording);
        assert!(snapshot.microphone_active);
        assert!(snapshot.visible_status_required);
        assert_eq!(snapshot.bounded_capture_seconds, 30);
    }

    #[test]
    fn push_to_talk_transitions_to_processing_after_stop() {
        let mut ptt = PushToTalkStateMachine::new_push_to_talk();

        ptt.start_recording().expect("recording should start");
        ptt.stop_recording().expect("recording should stop");

        assert_eq!(ptt.state(), VoiceListenState::ProcessingTranscript);
        assert!(!ptt.snapshot().microphone_active);
        assert!(ptt.snapshot().visible_status_required);
    }

    #[test]
    fn push_to_talk_speaking_returns_to_idle() {
        let mut ptt = PushToTalkStateMachine::new_push_to_talk();

        ptt.start_recording().expect("recording should start");
        ptt.stop_recording().expect("recording should stop");
        ptt.begin_speaking().expect("speaking should begin");

        assert_eq!(ptt.state(), VoiceListenState::Speaking);
        assert!(ptt.snapshot().visible_status_required);

        ptt.finish_speaking();

        assert_eq!(ptt.state(), VoiceListenState::Idle);
        assert!(!ptt.snapshot().visible_status_required);
    }

    #[test]
    fn panic_stop_forces_stopped_state() {
        let mut ptt = PushToTalkStateMachine::new_push_to_talk();

        ptt.start_recording().expect("recording should start");
        ptt.panic_stop();

        assert_eq!(ptt.state(), VoiceListenState::Stopped);
        assert!(!ptt.snapshot().microphone_active);
        assert!(ptt.snapshot().visible_status_required);
    }

    #[test]
    fn stopped_state_cannot_start_recording_until_reset() {
        let mut ptt = PushToTalkStateMachine::new_push_to_talk();

        ptt.panic_stop();

        assert!(ptt.start_recording().is_err());

        ptt.reset();
        assert!(ptt.start_recording().is_ok());
        assert_eq!(ptt.state(), VoiceListenState::Recording);
    }
}
