pub const PROJECT_NAME: &str = "Project Iris";
pub const PROJECT_VERSION: &str = "v0.1.2";

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ContextSource {
    SystemPolicy,
    HudText,
    UserUtterance,
    AsrTranscript,
    ImageInput,
    VideoInput,
    DocumentText,
    WebpageText,
    ScreenOcrText,
    UiText,
    WindowMetadata,
    MemoryItem,
    SystemDiagnostic,
    AssistantResponse,
}

impl ContextSource {
    pub fn is_user_authoritative(&self) -> bool {
        matches!(
            self,
            Self::HudText | Self::UserUtterance | Self::AsrTranscript
        )
    }

    pub fn is_untrusted_evidence(&self) -> bool {
        matches!(
            self,
            Self::ImageInput
                | Self::VideoInput
                | Self::DocumentText
                | Self::WebpageText
                | Self::ScreenOcrText
                | Self::UiText
                | Self::WindowMetadata
        )
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AuthorityClass {
    SystemPolicy,
    DirectUserInstruction,
    ApprovedMemory,
    LocalDiagnostic,
    UntrustedEvidence,
    AssistantHistory,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RedactionKind {
    SecretLike,
    Email,
    PhoneNumber,
    AuthCode,
    CredentialKeyword,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RedactionFinding {
    pub kind: RedactionKind,
    pub start: usize,
    pub end: usize,
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct RedactionReport {
    pub findings: Vec<RedactionFinding>,
}

impl RedactionReport {
    pub fn has_findings(&self) -> bool {
        !self.findings.is_empty()
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RawContextItem {
    pub source: ContextSource,
    pub text: String,
}

impl RawContextItem {
    pub fn new(source: ContextSource, text: impl Into<String>) -> Self {
        Self {
            source,
            text: text.into(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GatedContextItem {
    pub source: ContextSource,
    pub authority: AuthorityClass,
    pub text: String,
    pub redaction_report: RedactionReport,
    pub suppressed: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct GatedContextBundle {
    pub items: Vec<GatedContextItem>,
    pub budget_report: String,
    pub suppression_report: String,
}

impl GatedContextBundle {
    pub fn has_untrusted_evidence(&self) -> bool {
        self.items
            .iter()
            .any(|item| item.authority == AuthorityClass::UntrustedEvidence)
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AssistantRequest {
    pub gated_context: GatedContextBundle,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AssistantResponse {
    pub text: String,
    pub memory_candidates: Vec<MemoryCandidate>,
    pub cancelled: bool,
}

impl AssistantResponse {
    pub fn text_only(text: impl Into<String>) -> Self {
        Self {
            text: text.into(),
            memory_candidates: Vec::new(),
            cancelled: false,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MemoryCandidate {
    pub proposed_text: String,
    pub source: ContextSource,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DiagnosticEvent {
    pub code: String,
    pub redacted_message: String,
}
