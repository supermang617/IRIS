#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ResponseRisk {
    CapabilityClaim,
    UnsafeInstruction,
    SecretHandlingClaim,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ResponseFinding {
    pub risk: ResponseRisk,
    pub matched_phrase: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ResponsePostCheckReport {
    pub approved: bool,
    pub findings: Vec<ResponseFinding>,
}

#[derive(Debug, Default, Clone)]
pub struct ResponsePostChecker;

impl ResponsePostChecker {
    pub fn new() -> Self {
        Self
    }

    pub fn check(&self, response_text: &str) -> ResponsePostCheckReport {
        let normalized = normalize(response_text);
        let mut findings = Vec::new();

        for phrase in forbidden_capability_claims() {
            if normalized.contains(&phrase) {
                findings.push(ResponseFinding {
                    risk: ResponseRisk::CapabilityClaim,
                    matched_phrase: phrase,
                });
            }
        }

        for phrase in forbidden_unsafe_instructions() {
            if normalized.contains(&phrase) {
                findings.push(ResponseFinding {
                    risk: ResponseRisk::UnsafeInstruction,
                    matched_phrase: phrase,
                });
            }
        }

        for phrase in forbidden_secret_handling_claims() {
            if normalized.contains(&phrase) {
                findings.push(ResponseFinding {
                    risk: ResponseRisk::SecretHandlingClaim,
                    matched_phrase: phrase,
                });
            }
        }

        ResponsePostCheckReport {
            approved: findings.is_empty(),
            findings,
        }
    }
}

fn normalize(input: &str) -> String {
    input
        .to_lowercase()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}

fn forbidden_capability_claims() -> Vec<String> {
    vec![
        s(&["i can click"]),
        s(&["i will click"]),
        s(&["i can type into"]),
        s(&["i will type into"]),
        s(&["i can move the mouse"]),
        s(&["i will move the mouse"]),
        s(&["i can control your computer"]),
        s(&["i will control your computer"]),
        s(&["i can operate your computer"]),
        s(&["i will operate your computer"]),
        s(&["i can read the ", "clip", "board"]),
        s(&["i will read the ", "clip", "board"]),
        s(&["i can write to the ", "clip", "board"]),
        s(&["i will write to the ", "clip", "board"]),
    ]
}

fn forbidden_unsafe_instructions() -> Vec<String> {
    vec![
        s(&["click allow"]),
        s(&["click yes"]),
        s(&["disable security"]),
        s(&["turn off antivirus"]),
        s(&["paste this into terminal"]),
        s(&["run this command"]),
        s(&["execute this command"]),
        s(&["open a browser and"]),
    ]
}

fn forbidden_secret_handling_claims() -> Vec<String> {
    vec![
        s(&["send me your password"]),
        s(&["copy your password"]),
        s(&["show me your api key"]),
        s(&["paste your api key"]),
        s(&["reveal your secret token"]),
    ]
}

fn s(parts: &[&str]) -> String {
    parts.join("")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn approves_safe_response() {
        let checker = ResponsePostChecker::new();
        let report = checker.check("I can explain what I see and help you reason through it.");

        assert!(report.approved);
        assert!(report.findings.is_empty());
    }

    #[test]
    fn blocks_clicking_claim() {
        let checker = ResponsePostChecker::new();
        let report = checker.check("I will click allow for you.");

        assert!(!report.approved);
        assert_eq!(report.findings[0].risk, ResponseRisk::CapabilityClaim);
    }

    #[test]
    fn blocks_computer_control_claim() {
        let checker = ResponsePostChecker::new();
        let report = checker.check("I can control your computer.");

        assert!(!report.approved);
        assert_eq!(report.findings[0].risk, ResponseRisk::CapabilityClaim);
    }

    #[test]
    fn blocks_secret_request() {
        let checker = ResponsePostChecker::new();
        let report = checker.check("Paste your API key here.");

        assert!(!report.approved);
        assert_eq!(report.findings[0].risk, ResponseRisk::SecretHandlingClaim);
    }

    #[test]
    fn blocks_terminal_instruction() {
        let checker = ResponsePostChecker::new();
        let report = checker.check("Run this command to continue.");

        assert!(!report.approved);
        assert_eq!(report.findings[0].risk, ResponseRisk::UnsafeInstruction);
    }

    #[test]
    fn normalizes_case_and_spacing() {
        let checker = ResponsePostChecker::new();
        let report = checker.check("I   WILL   CLICK   yes");

        assert!(!report.approved);
    }
}
