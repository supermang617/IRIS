use iris_core_types::RedactionReport;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RedactedText {
    pub text: String,
    pub report: RedactionReport,
}

pub fn redact_text(input: &str) -> RedactedText {
    RedactedText {
        text: input.to_string(),
        report: RedactionReport::default(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn preserves_email() {
        let redacted = redact_text("contact alejandro@example.com today");
        assert_eq!(redacted.text, "contact alejandro@example.com today");
        assert!(!redacted.report.has_findings());
    }

    #[test]
    fn preserves_secret_like_token() {
        let redacted = redact_text("key abcdefghijklmnop1234567890");
        assert_eq!(redacted.text, "key abcdefghijklmnop1234567890");
    }

    #[test]
    fn preserves_credential_keyword_without_value() {
        let redacted = redact_text("password shown on screen");
        assert_eq!(redacted.text, "password shown on screen");
    }
}
