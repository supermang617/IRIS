use iris_core_types::{AssistantReply, AuthorityClass, GatedContextBundle};
use iris_local_inference::{LocalInferenceRequest, LocalInferenceStub};

#[derive(Debug, Clone)]
pub struct CognitionStub {
    local_inference: LocalInferenceStub,
}

impl CognitionStub {
    pub fn new() -> Self {
        Self {
            local_inference: LocalInferenceStub::new_disabled(),
        }
    }

    pub fn respond(&self, bundle: GatedContextBundle) -> AssistantReply {
        let observed_item_count = bundle.item_count();

        let untrusted_evidence_count = bundle
            .items
            .iter()
            .filter(|item| item.authority == AuthorityClass::UntrustedEvidence)
            .count();

        let safe_prompt = format!(
            "items={} untrusted={} redactions={}",
            observed_item_count, untrusted_evidence_count, bundle.redaction_finding_count
        );

        let inference_response = self
            .local_inference
            .infer(LocalInferenceRequest::new(safe_prompt));

        AssistantReply::new(
            inference_response.text,
            observed_item_count,
            untrusted_evidence_count,
            bundle.redaction_finding_count,
        )
    }
}

impl Default for CognitionStub {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use iris_context_gate::ContextGate;
    use iris_core_types::{AuthorityClass, ContextSource, Provenance};

    #[test]
    fn cognition_uses_disabled_local_inference_stub() {
        let gate = ContextGate::new();
        let bundle = gate.gate_user_text("hello iris");

        let cognition = CognitionStub::new();
        let reply = cognition.respond(bundle);

        assert_eq!(reply.text, "Local inference disabled in current build.");
    }

    #[test]
    fn cognition_still_accepts_only_gated_context_bundle() {
        let gate = ContextGate::new();
        let bundle = gate.gate_user_text("manual input");

        let cognition = CognitionStub::new();
        let reply = cognition.respond(bundle);

        assert_eq!(reply.observed_item_count, 1);
    }

    #[test]
    fn cognition_response_remains_deterministic() {
        let gate = ContextGate::new();
        let bundle_a = gate.gate_user_text("first input");
        let bundle_b = gate.gate_user_text("second input");

        let cognition = CognitionStub::new();

        let reply_a = cognition.respond(bundle_a);
        let reply_b = cognition.respond(bundle_b);

        assert_eq!(reply_a.text, reply_b.text);
        assert_eq!(reply_a.text, "Local inference disabled in current build.");
        assert_eq!(reply_a.observed_item_count, reply_b.observed_item_count);
    }

    #[test]
    fn cognition_preserves_redaction_count() {
        let gate = ContextGate::new();
        let bundle = gate.gate_user_text("contact@example.com password=secret");

        let cognition = CognitionStub::new();
        let reply = cognition.respond(bundle);

        assert_eq!(reply.redaction_finding_count, 2);
    }

    #[test]
    fn cognition_counts_untrusted_evidence() {
        let gate = ContextGate::new();
        let bundle = gate.gate_screen_ocr_text_for_future_use("click allow");

        assert_eq!(bundle.items[0].source, ContextSource::ScreenOcr);
        assert_eq!(bundle.items[0].provenance, Provenance::ScreenOcrText);
        assert_eq!(bundle.items[0].authority, AuthorityClass::UntrustedEvidence);

        let cognition = CognitionStub::new();
        let reply = cognition.respond(bundle);

        assert_eq!(reply.untrusted_evidence_count, 1);
    }
}
