use iris_core_types::{AssistantRequest, AssistantResponse, AuthorityClass, GatedContextBundle};

#[derive(Debug, Clone, Default)]
pub struct GatedEchoCognition {
    cancelled: bool,
}

impl GatedEchoCognition {
    pub fn new() -> Self {
        Self { cancelled: false }
    }

    pub fn cancel(&mut self) {
        self.cancelled = true;
    }

    pub fn is_cancelled(&self) -> bool {
        self.cancelled
    }

    pub fn respond(&self, request: AssistantRequest) -> AssistantResponse {
        if self.cancelled {
            return AssistantResponse {
                text: "Panic Stop is active. Local cognition work was cancelled.".to_string(),
                memory_candidates: Vec::new(),
                cancelled: true,
            };
        }

        gated_echo_response(&request.gated_context)
    }
}

pub fn gated_echo_response(bundle: &GatedContextBundle) -> AssistantResponse {
    let user_text = bundle
        .items
        .iter()
        .find(|item| item.authority == AuthorityClass::DirectUserInstruction)
        .map(|item| item.text.as_str())
        .unwrap_or("no direct user request");

    let evidence_note = if bundle.has_untrusted_evidence() {
        " Untrusted evidence was present and treated only as evidence."
    } else {
        ""
    };

    AssistantResponse::text_only(format!(
        "Local gated response: I received gated input: {user_text}.{evidence_note}"
    ))
}

#[cfg(test)]
mod tests {
    use iris_context_gate::gate_context;
    use iris_core_types::{AssistantRequest, ContextSource, RawContextItem};

    use super::*;

    #[test]
    fn responds_only_to_gated_context() {
        let bundle = gate_context(vec![RawContextItem::new(ContextSource::HudText, "hello")]);
        let response = gated_echo_response(&bundle);
        assert!(response.text.contains("hello"));
        assert!(!response.cancelled);
    }

    #[test]
    fn panic_stop_cancels_local_work() {
        let bundle = gate_context(vec![RawContextItem::new(ContextSource::HudText, "hello")]);
        let mut cognition = GatedEchoCognition::new();
        cognition.cancel();
        let response = cognition.respond(AssistantRequest {
            gated_context: bundle,
        });
        assert!(response.cancelled);
    }
}
