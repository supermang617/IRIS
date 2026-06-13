use iris_cognition::GatedEchoCognition;
use iris_context_gate::gate_context;
use iris_core_types::{
    AssistantRequest, AssistantResponse, ContextSource, GatedContextBundle, RawContextItem,
};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HudInput {
    pub text: String,
}

impl HudInput {
    pub fn typed(text: impl Into<String>) -> Self {
        Self { text: text.into() }
    }
}

#[derive(Debug, Default)]
pub struct LocalHud {
    cognition: GatedEchoCognition,
}

impl LocalHud {
    pub fn new() -> Self {
        Self {
            cognition: GatedEchoCognition::new(),
        }
    }

    pub fn submit_text(&self, input: HudInput) -> AssistantResponse {
        let gated_context = gate_typed_text(input.text);
        self.cognition.respond(AssistantRequest { gated_context })
    }

    pub fn panic_stop(&mut self) {
        self.cognition.cancel();
    }

    pub fn reset_after_panic_stop(&mut self) {
        self.cognition = GatedEchoCognition::new();
    }

    pub fn is_panic_stopped(&self) -> bool {
        self.cognition.is_cancelled()
    }
}

pub fn gate_typed_text(text: impl Into<String>) -> GatedContextBundle {
    gate_context(vec![RawContextItem::new(ContextSource::HudText, text)])
}

pub fn safety_status_lines() -> Vec<&'static str> {
    vec![
        iris_policy::SYSTEM_CONTROL,
        iris_policy::EXECUTOR,
        iris_policy::INPUT_SIMULATION,
        iris_policy::CLIPBOARD_ACCESS,
        iris_policy::RUNTIME_NETWORK,
        iris_policy::PLUGINS,
        iris_policy::SCREEN_CONTENT_AUTHORITY,
        iris_policy::FILESYSTEM_SCOPE,
    ]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn typed_hud_input_gets_local_response() {
        let hud = LocalHud::new();
        let response = hud.submit_text(HudInput::typed("what can you do?"));
        assert!(response.text.contains("what can you do?"));
    }

    #[test]
    fn panic_stop_blocks_local_response_until_reset() {
        let mut hud = LocalHud::new();
        hud.panic_stop();
        assert!(hud.is_panic_stopped());

        let stopped = hud.submit_text(HudInput::typed("hello"));
        assert!(stopped.cancelled);
        assert!(stopped.text.contains("Panic Stop"));

        hud.reset_after_panic_stop();
        let resumed = hud.submit_text(HudInput::typed("hello"));
        assert!(!resumed.cancelled);
        assert!(resumed.text.contains("hello"));
    }

    #[test]
    fn safety_status_describes_safe_and_agentic_boundaries() {
        let lines = safety_status_lines();
        assert!(
            lines
                .iter()
                .any(|line| line.contains("Safe mode unsupported"))
        );
        assert!(lines.contains(&"Executor: Agentic Session only"));
    }
}
