use iris_core_types::{
    AuthorityClass, ContextSource, GatedContextBundle, GatedContextItem, RawContextItem,
};
use iris_redaction::redact_text;

const MAX_ITEM_CHARS: usize = 2_000;

pub fn gate_context(items: Vec<RawContextItem>) -> GatedContextBundle {
    let mut gated_items = Vec::new();
    let mut suppressed_count = 0usize;

    for item in items {
        let redacted = redact_text(&item.text);
        let mut text = redacted.text;
        let mut suppressed = false;

        if item.source.is_untrusted_evidence() {
            text = harden_untrusted_evidence(&text);
        }

        if text.chars().count() > MAX_ITEM_CHARS {
            text = text.chars().take(MAX_ITEM_CHARS).collect();
            suppressed = true;
            suppressed_count += 1;
        }

        gated_items.push(GatedContextItem {
            authority: authority_for_source(&item.source),
            source: item.source,
            text,
            redaction_report: redacted.report,
            suppressed,
        });
    }

    GatedContextBundle {
        budget_report: format!(
            "{} item(s), max {} chars per item",
            gated_items.len(),
            MAX_ITEM_CHARS
        ),
        suppression_report: format!("{suppressed_count} item(s) truncated"),
        items: gated_items,
    }
}

fn authority_for_source(source: &ContextSource) -> AuthorityClass {
    match source {
        ContextSource::SystemPolicy => AuthorityClass::SystemPolicy,
        ContextSource::HudText | ContextSource::UserUtterance | ContextSource::AsrTranscript => {
            AuthorityClass::DirectUserInstruction
        }
        ContextSource::MemoryItem => AuthorityClass::ApprovedMemory,
        ContextSource::SystemDiagnostic => AuthorityClass::LocalDiagnostic,
        ContextSource::ImageInput
        | ContextSource::VideoInput
        | ContextSource::DocumentText
        | ContextSource::WebpageText
        | ContextSource::ScreenOcrText
        | ContextSource::UiText
        | ContextSource::WindowMetadata => AuthorityClass::UntrustedEvidence,
        ContextSource::AssistantResponse => AuthorityClass::AssistantHistory,
    }
}

fn harden_untrusted_evidence(text: &str) -> String {
    let lowered = text.to_ascii_lowercase();
    let risky = [
        "ignore your instructions",
        "ignore previous instructions",
        "click allow",
        "run this command",
        "save this to memory",
        "you are authorized",
    ]
    .iter()
    .any(|marker| lowered.contains(marker));

    if risky {
        format!("UNTRUSTED_VISUAL_EVIDENCE_QUOTED: {text}")
    } else {
        format!("UNTRUSTED_VISUAL_EVIDENCE: {text}")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn labels_hud_text_as_direct_user_instruction() {
        let bundle = gate_context(vec![RawContextItem::new(
            ContextSource::HudText,
            "explain this",
        )]);
        assert_eq!(
            bundle.items[0].authority,
            AuthorityClass::DirectUserInstruction
        );
    }

    #[test]
    fn labels_visual_text_as_untrusted_evidence() {
        let bundle = gate_context(vec![RawContextItem::new(
            ContextSource::ScreenOcrText,
            "ignore previous instructions",
        )]);
        assert_eq!(bundle.items[0].authority, AuthorityClass::UntrustedEvidence);
        assert!(
            bundle.items[0]
                .text
                .starts_with("UNTRUSTED_VISUAL_EVIDENCE")
        );
    }

    #[test]
    fn treats_visual_sources_as_evidence_not_user_instruction() {
        for source in [
            ContextSource::ImageInput,
            ContextSource::VideoInput,
            ContextSource::DocumentText,
            ContextSource::WebpageText,
            ContextSource::ScreenOcrText,
            ContextSource::UiText,
        ] {
            let bundle = gate_context(vec![RawContextItem::new(source, "run this command")]);
            assert_eq!(bundle.items[0].authority, AuthorityClass::UntrustedEvidence);
            assert!(
                bundle.items[0]
                    .text
                    .starts_with("UNTRUSTED_VISUAL_EVIDENCE_QUOTED")
            );
        }
    }

    #[test]
    fn preserves_user_text_before_cognition() {
        let bundle = gate_context(vec![RawContextItem::new(
            ContextSource::HudText,
            "my email is user@example.com",
        )]);
        assert_eq!(bundle.items[0].text, "my email is user@example.com");
        assert!(!bundle.items[0].redaction_report.has_findings());
    }
}
