pub const PROJECT_NAME: &str = "Project Iris";
pub const PROJECT_VERSION: &str = "v0.1";

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Provenance {
    HudText,
    UserUtterance,
    AsrTranscript,
    ScreenOcrText,
    WindowMetadata,
    MemoryItem,
    SystemDiagnostic,
    AssistantResponse,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AuthorityClass {
    SystemPolicy,
    UserInstruction,
    ApprovedMemory,
    LocalDiagnostic,
    UntrustedEvidence,
    AssistantHistory,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ContextSource {
    DirectUserText,
    ScreenOcr,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ContextItem {
    pub source: ContextSource,
    pub provenance: Provenance,
    pub authority: AuthorityClass,
    pub text: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GatedContextBundle {
    pub items: Vec<ContextItem>,
    pub redaction_finding_count: usize,
}

impl GatedContextBundle {
    pub fn new(items: Vec<ContextItem>, redaction_finding_count: usize) -> Self {
        Self {
            items,
            redaction_finding_count,
        }
    }

    pub fn item_count(&self) -> usize {
        self.items.len()
    }
}
