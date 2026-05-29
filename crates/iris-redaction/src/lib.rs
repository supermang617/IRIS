#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RedactionKind {
    Email,
    BearerToken,
    PasswordAssignment,
    ApiKeyAssignment,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RedactionFinding {
    pub kind: RedactionKind,
    pub start: usize,
    pub end: usize,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RedactionResult {
    pub redacted_text: String,
    pub findings: Vec<RedactionFinding>,
}

impl RedactionResult {
    pub fn finding_count(&self) -> usize {
        self.findings.len()
    }
}

pub fn redact(input: &str) -> RedactionResult {
    let mut findings = Vec::new();
    let mut output_parts = Vec::new();

    let mut index = 0;

    for token in input.split_whitespace() {
        let token_start = input[index..]
            .find(token)
            .map(|offset| index + offset)
            .unwrap_or(index);

        let token_end = token_start + token.len();

        if is_email_like(token) {
            output_parts.push("[REDACTED_EMAIL]".to_string());
            findings.push(RedactionFinding {
                kind: RedactionKind::Email,
                start: token_start,
                end: token_end,
            });
        } else if is_bearer_prefix_at(input, token_start) {
            output_parts.push("[REDACTED_BEARER_TOKEN]".to_string());
            findings.push(RedactionFinding {
                kind: RedactionKind::BearerToken,
                start: token_start,
                end: token_end,
            });
        } else if is_assignment(token, "password=") {
            output_parts.push("password=[REDACTED_PASSWORD]".to_string());
            findings.push(RedactionFinding {
                kind: RedactionKind::PasswordAssignment,
                start: token_start,
                end: token_end,
            });
        } else if is_assignment(token, "api_key=") {
            output_parts.push("api_key=[REDACTED_API_KEY]".to_string());
            findings.push(RedactionFinding {
                kind: RedactionKind::ApiKeyAssignment,
                start: token_start,
                end: token_end,
            });
        } else if is_assignment(token, "apikey=") {
            output_parts.push("apikey=[REDACTED_API_KEY]".to_string());
            findings.push(RedactionFinding {
                kind: RedactionKind::ApiKeyAssignment,
                start: token_start,
                end: token_end,
            });
        } else {
            output_parts.push(token.to_string());
        }

        index = token_end;
    }

    RedactionResult {
        redacted_text: output_parts.join(" "),
        findings,
    }
}

fn is_email_like(token: &str) -> bool {
    let trimmed = trim_common_punctuation(token);

    let Some((local, domain)) = trimmed.split_once('@') else {
        return false;
    };

    !local.is_empty()
        && domain.contains('.')
        && !domain.starts_with('.')
        && !domain.ends_with('.')
        && domain.len() >= 3
}

fn is_bearer_prefix_at(input: &str, token_start: usize) -> bool {
    let before = &input[..token_start];
    before.trim_end().ends_with("Bearer")
}

fn is_assignment(token: &str, prefix: &str) -> bool {
    token
        .to_ascii_lowercase()
        .starts_with(&prefix.to_ascii_lowercase())
        && token.len() > prefix.len()
}

fn trim_common_punctuation(token: &str) -> &str {
    token.trim_matches(|c: char| {
        matches!(
            c,
            ',' | ';' | ':' | '.' | ')' | '(' | '[' | ']' | '{' | '}' | '"' | '\''
        )
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn redacts_email_like_string() {
        let result = redact("email me at contact@example.com please");

        assert_eq!(result.redacted_text, "email me at [REDACTED_EMAIL] please");
        assert_eq!(result.finding_count(), 1);
        assert_eq!(result.findings[0].kind, RedactionKind::Email);
    }

    #[test]
    fn redacts_bearer_token_value() {
        let result = redact("Authorization: Bearer abcdef12345");

        assert_eq!(
            result.redacted_text,
            "Authorization: Bearer [REDACTED_BEARER_TOKEN]"
        );
        assert_eq!(result.finding_count(), 1);
        assert_eq!(result.findings[0].kind, RedactionKind::BearerToken);
    }

    #[test]
    fn redacts_password_assignment() {
        let result = redact("username=iris password=mysecret");

        assert_eq!(
            result.redacted_text,
            "username=iris password=[REDACTED_PASSWORD]"
        );
        assert_eq!(result.finding_count(), 1);
        assert_eq!(result.findings[0].kind, RedactionKind::PasswordAssignment);
    }

    #[test]
    fn redacts_api_key_assignment() {
        let result = redact("api_key=abc123xyz");

        assert_eq!(result.redacted_text, "api_key=[REDACTED_API_KEY]");
        assert_eq!(result.finding_count(), 1);
        assert_eq!(result.findings[0].kind, RedactionKind::ApiKeyAssignment);
    }

    #[test]
    fn redacts_multiple_findings() {
        let result = redact("contact@example.com password=secret api_key=abc");

        assert_eq!(
            result.redacted_text,
            "[REDACTED_EMAIL] password=[REDACTED_PASSWORD] api_key=[REDACTED_API_KEY]"
        );
        assert_eq!(result.finding_count(), 3);
    }

    #[test]
    fn leaves_safe_text_unchanged() {
        let result = redact("hello iris this is normal text");

        assert_eq!(result.redacted_text, "hello iris this is normal text");
        assert_eq!(result.finding_count(), 0);
    }
}
