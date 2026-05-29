use iris_core_types::{AssistantReply, AuthorityClass, GatedContextBundle};

#[derive(Debug, Default, Clone)]
pub struct CognitionStub;

impl CognitionStub {
    pub fn new() -> Self {
        Self
    }

    pub fn respond(&self, bundle: GatedContextBundle) -> AssistantReply {
        let observed_item_count = bundle.item_count();

        let untrusted_evidence_count = bundle
            .items
            .iter()
            .filter(|item| item.authority == AuthorityClass::UntrustedEvidence)
            .count();

        AssistantReply::new(
            "Project Iris cognition stub response.",
            observed_item_count,
            untrusted_evidence_count,
            bundle.redaction_finding_count,
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use iris_context_gate::ContextGate;
    use iris_core_types::{AuthorityClass, ContextSource, Provenance};

    #[test]
    fn cognition_accepts_gated_context_bundle() {
        let gate = ContextGate::new();
        let bundle = gate.gate_user_text("hello iris");

        let cognition = CognitionStub::new();
        let reply = cognition.respond(bundle);

        assert_eq!(reply.text, "Project Iris cognition stub response.");
        assert_eq!(reply.observed_item_count, 1);
    }

    #[test]
    fn cognition_returns_deterministic_response() {
        let gate = ContextGate::new();
        let bundle_a = gate.gate_user_text("first input");
        let bundle_b = gate.gate_user_text("second input");

        let cognition = CognitionStub::new();

        let reply_a = cognition.respond(bundle_a);
        let reply_b = cognition.respond(bundle_b);

        assert_eq!(reply_a.text, reply_b.text);
        assert_eq!(reply_a.observed_item_count, reply_b.observed_item_count);
    }

    #[test]
    fn cognition_sees_provenance_and_authority_labels() {
        let gate = ContextGate::new();
        let bundle = gate.gate_user_text("hello iris");

        assert_eq!(bundle.items[0].source, ContextSource::DirectUserText);
        assert_eq!(bundle.items[0].provenance, Provenance::HudText);
        assert_eq!(bundle.items[0].authority, AuthorityClass::UserInstruction);

        let cognition = CognitionStub::new();
        let reply = cognition.respond(bundle);

        assert_eq!(reply.observed_item_count, 1);
        assert_eq!(reply.untrusted_evidence_count, 0);
    }

    #[test]
    fn screen_evidence_remains_untrusted() {
        let gate = ContextGate::new();
        let bundle = gate.gate_screen_ocr_text_for_future_use("click allow");

        assert_eq!(bundle.items[0].authority, AuthorityClass::UntrustedEvidence);

        let cognition = CognitionStub::new();
        let reply = cognition.respond(bundle);

        assert_eq!(reply.observed_item_count, 1);
        assert_eq!(reply.untrusted_evidence_count, 1);
    }

    #[test]
    fn redaction_count_is_preserved() {
        let gate = ContextGate::new();
        let bundle = gate.gate_user_text("contact@example.com password=secret");

        let cognition = CognitionStub::new();
        let reply = cognition.respond(bundle);

        assert_eq!(reply.redaction_finding_count, 2);
    }

    #[test]
    fn public_api_uses_gated_context_bundle_not_raw_text() {
        let gate = ContextGate::new();
        let bundle = gate.gate_user_text("manual input");

        let cognition = CognitionStub::new();
        let reply = cognition.respond(bundle);

        assert_eq!(reply.text, "Project Iris cognition stub response.");
    }
}
