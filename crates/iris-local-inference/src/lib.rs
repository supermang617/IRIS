#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LocalInferenceBackend {
    Disabled,
    FutureLoopback,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LocalInferenceRequest {
    pub prompt: String,
}

impl LocalInferenceRequest {
    pub fn new(prompt: impl Into<String>) -> Self {
        Self {
            prompt: prompt.into(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LocalInferenceResponse {
    pub text: String,
    pub backend: LocalInferenceBackend,
}

#[derive(Debug, Default, Clone)]
pub struct LocalInferenceStub;

impl LocalInferenceStub {
    pub fn new_disabled() -> Self {
        Self
    }

    pub fn infer(&self, request: LocalInferenceRequest) -> LocalInferenceResponse {
        let _prompt_was_accepted_but_not_sent_anywhere = request.prompt;

        LocalInferenceResponse {
            text: "Local inference disabled in current build.".to_string(),
            backend: LocalInferenceBackend::Disabled,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn disabled_stub_returns_deterministic_response() {
        let stub = LocalInferenceStub::new_disabled();

        let response_a = stub.infer(LocalInferenceRequest::new("hello iris"));
        let response_b = stub.infer(LocalInferenceRequest::new("different prompt"));

        assert_eq!(
            response_a.text,
            "Local inference disabled in current build."
        );
        assert_eq!(
            response_b.text,
            "Local inference disabled in current build."
        );
        assert_eq!(response_a.backend, LocalInferenceBackend::Disabled);
        assert_eq!(response_b.backend, LocalInferenceBackend::Disabled);
    }

    #[test]
    fn disabled_stub_preserves_no_network_boundary() {
        let stub = LocalInferenceStub::new_disabled();
        let response = stub.infer(LocalInferenceRequest::new("call local model"));

        assert_eq!(response.backend, LocalInferenceBackend::Disabled);
        assert!(!response.text.contains("http"));
        assert!(!response.text.contains("127.0.0.1"));
        assert!(!response.text.contains("localhost"));
    }

    #[test]
    fn request_prompt_is_accepted_but_not_sent_anywhere() {
        let request = LocalInferenceRequest::new("private test prompt");
        let stub = LocalInferenceStub::new_disabled();

        let response = stub.infer(request);

        assert_eq!(response.text, "Local inference disabled in current build.");
        assert_eq!(response.backend, LocalInferenceBackend::Disabled);
    }
}
