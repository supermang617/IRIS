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

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum VoiceSessionState {
    Idle,
    Armed,
    Listening,
    Transcribing,
    Thinking,
    Speaking,
    Stopped,
}

impl VoiceSessionState {
    pub fn is_visible_active_state(&self) -> bool {
        matches!(
            self,
            Self::Armed | Self::Listening | Self::Transcribing | Self::Thinking | Self::Speaking
        )
    }

    pub fn accepts_audio_capture(&self) -> bool {
        matches!(self, Self::Listening)
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum VoiceStopReason {
    Completed,
    PanicStop,
    Timeout,
    UserCancelled,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VoiceSessionSnapshot {
    pub state: VoiceSessionState,
    pub activation_mode: VoiceActivationMode,
    pub visible_to_user: bool,
    pub bounded_capture_seconds: u32,
    pub transcript_must_enter_context_gate: bool,
    pub stop_reason: Option<VoiceStopReason>,
}

impl VoiceSessionSnapshot {
    pub fn idle() -> Self {
        Self {
            state: VoiceSessionState::Idle,
            activation_mode: VoiceActivationMode::TypedPrompt,
            visible_to_user: false,
            bounded_capture_seconds: 0,
            transcript_must_enter_context_gate: true,
            stop_reason: None,
        }
    }

    pub fn from_policy(policy: VoiceInputPolicy) -> Self {
        Self {
            state: VoiceSessionState::Armed,
            activation_mode: policy.activation_mode,
            visible_to_user: true,
            bounded_capture_seconds: policy.bounded_capture_seconds,
            transcript_must_enter_context_gate: policy.transcript_must_enter_context_gate,
            stop_reason: None,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VoiceSessionController {
    snapshot: VoiceSessionSnapshot,
}

impl Default for VoiceSessionController {
    fn default() -> Self {
        Self::new_idle()
    }
}

impl VoiceSessionController {
    pub fn new_idle() -> Self {
        Self {
            snapshot: VoiceSessionSnapshot::idle(),
        }
    }

    pub fn snapshot(&self) -> &VoiceSessionSnapshot {
        &self.snapshot
    }

    pub fn arm(&mut self, policy: VoiceInputPolicy) {
        self.snapshot = VoiceSessionSnapshot::from_policy(policy);
    }

    pub fn start_listening(&mut self) {
        if self.snapshot.state == VoiceSessionState::Armed {
            self.snapshot.state = VoiceSessionState::Listening;
            self.snapshot.visible_to_user = true;
        }
    }

    pub fn start_transcribing(&mut self) {
        if self.snapshot.state == VoiceSessionState::Listening {
            self.snapshot.state = VoiceSessionState::Transcribing;
            self.snapshot.visible_to_user = true;
        }
    }

    pub fn start_thinking(&mut self) {
        if matches!(
            self.snapshot.state,
            VoiceSessionState::Transcribing | VoiceSessionState::Armed
        ) {
            self.snapshot.state = VoiceSessionState::Thinking;
            self.snapshot.visible_to_user = true;
        }
    }

    pub fn start_speaking(&mut self) {
        if self.snapshot.state == VoiceSessionState::Thinking {
            self.snapshot.state = VoiceSessionState::Speaking;
            self.snapshot.visible_to_user = true;
        }
    }

    pub fn complete(&mut self) {
        self.snapshot.state = VoiceSessionState::Idle;
        self.snapshot.visible_to_user = false;
        self.snapshot.stop_reason = Some(VoiceStopReason::Completed);
    }

    pub fn stop(&mut self, reason: VoiceStopReason) {
        self.snapshot.state = VoiceSessionState::Stopped;
        self.snapshot.visible_to_user = true;
        self.snapshot.stop_reason = Some(reason);
    }

    pub fn reset_idle(&mut self) {
        self.snapshot = VoiceSessionSnapshot::idle();
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
        assert_eq!(profile.kokoro.speed, 0.95);
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
    fn voice_session_starts_idle_and_invisible() {
        let controller = VoiceSessionController::new_idle();
        let snapshot = controller.snapshot();

        assert_eq!(snapshot.state, VoiceSessionState::Idle);
        assert!(!snapshot.visible_to_user);
        assert!(!snapshot.state.is_visible_active_state());
        assert!(!snapshot.state.accepts_audio_capture());
    }

    #[test]
    fn one_shot_voice_session_has_visible_bounded_capture() {
        let mut controller = VoiceSessionController::new_idle();

        controller.arm(VoiceInputPolicy::one_shot_default());
        controller.start_listening();

        let snapshot = controller.snapshot();

        assert_eq!(snapshot.activation_mode, VoiceActivationMode::OneShotVoice);
        assert_eq!(snapshot.state, VoiceSessionState::Listening);
        assert!(snapshot.visible_to_user);
        assert_eq!(snapshot.bounded_capture_seconds, 10);
        assert!(snapshot.transcript_must_enter_context_gate);
        assert!(snapshot.state.accepts_audio_capture());
    }

    #[test]
    fn push_to_talk_session_has_visible_bounded_capture() {
        let mut controller = VoiceSessionController::new_idle();

        controller.arm(VoiceInputPolicy::push_to_talk_default());
        controller.start_listening();

        let snapshot = controller.snapshot();

        assert_eq!(snapshot.activation_mode, VoiceActivationMode::PushToTalk);
        assert_eq!(snapshot.state, VoiceSessionState::Listening);
        assert!(snapshot.visible_to_user);
        assert_eq!(snapshot.bounded_capture_seconds, 30);
        assert!(snapshot.transcript_must_enter_context_gate);
    }

    #[test]
    fn session_progresses_to_speaking_then_idle() {
        let mut controller = VoiceSessionController::new_idle();

        controller.arm(VoiceInputPolicy::one_shot_default());
        controller.start_listening();
        controller.start_transcribing();
        controller.start_thinking();
        controller.start_speaking();

        assert_eq!(controller.snapshot().state, VoiceSessionState::Speaking);
        assert!(controller.snapshot().visible_to_user);

        controller.complete();

        assert_eq!(controller.snapshot().state, VoiceSessionState::Idle);
        assert!(!controller.snapshot().visible_to_user);
        assert_eq!(
            controller.snapshot().stop_reason,
            Some(VoiceStopReason::Completed)
        );
    }

    #[test]
    fn panic_stop_sets_stopped_visible_state() {
        let mut controller = VoiceSessionController::new_idle();

        controller.arm(VoiceInputPolicy::one_shot_default());
        controller.start_listening();
        controller.stop(VoiceStopReason::PanicStop);

        assert_eq!(controller.snapshot().state, VoiceSessionState::Stopped);
        assert!(controller.snapshot().visible_to_user);
        assert_eq!(
            controller.snapshot().stop_reason,
            Some(VoiceStopReason::PanicStop)
        );
        assert!(!controller.snapshot().state.accepts_audio_capture());
    }

    #[test]
    fn reset_returns_to_idle_after_stop() {
        let mut controller = VoiceSessionController::new_idle();

        controller.arm(VoiceInputPolicy::one_shot_default());
        controller.start_listening();
        controller.stop(VoiceStopReason::UserCancelled);
        controller.reset_idle();

        assert_eq!(controller.snapshot(), &VoiceSessionSnapshot::idle());
    }
}
