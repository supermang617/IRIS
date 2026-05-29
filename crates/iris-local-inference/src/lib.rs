#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LocalInferenceBackend {
    Disabled,
    FutureLoopback,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LocalInferenceConfigError {
    EmptyEndpoint,
    CloudEndpointRejected,
    NonLoopbackEndpointRejected,
    MissingPort,
    InvalidPort,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LocalInferenceEndpoint {
    value: String,
}

impl LocalInferenceEndpoint {
    pub fn as_str(&self) -> &str {
        &self.value
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LocalInferenceConfig {
    pub backend: LocalInferenceBackend,
    pub endpoint: Option<LocalInferenceEndpoint>,
}

impl LocalInferenceConfig {
    pub fn disabled() -> Self {
        Self {
            backend: LocalInferenceBackend::Disabled,
            endpoint: None,
        }
    }

    pub fn future_loopback(endpoint: &str) -> Result<Self, LocalInferenceConfigError> {
        let endpoint = endpoint.trim();

        if endpoint.is_empty() {
            return Err(LocalInferenceConfigError::EmptyEndpoint);
        }

        if endpoint.contains("://") {
            return Err(LocalInferenceConfigError::CloudEndpointRejected);
        }

        let Some((host, port)) = endpoint.rsplit_once(':') else {
            return Err(LocalInferenceConfigError::MissingPort);
        };

        if host != "127.0.0.1" && host != "localhost" {
            return Err(LocalInferenceConfigError::NonLoopbackEndpointRejected);
        }

        let Ok(port) = port.parse::<u16>() else {
            return Err(LocalInferenceConfigError::InvalidPort);
        };

        if port == 0 {
            return Err(LocalInferenceConfigError::InvalidPort);
        }

        Ok(Self {
            backend: LocalInferenceBackend::FutureLoopback,
            endpoint: Some(LocalInferenceEndpoint {
                value: endpoint.to_string(),
            }),
        })
    }
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

#[derive(Debug, Clone)]
pub struct LocalInferenceStub {
    config: LocalInferenceConfig,
}

impl LocalInferenceStub {
    pub fn new_disabled() -> Self {
        Self {
            config: LocalInferenceConfig::disabled(),
        }
    }

    pub fn with_config(config: LocalInferenceConfig) -> Self {
        Self { config }
    }

    pub fn config(&self) -> &LocalInferenceConfig {
        &self.config
    }

    pub fn infer(&self, request: LocalInferenceRequest) -> LocalInferenceResponse {
        let _prompt_was_accepted_but_not_sent_anywhere = request.prompt;

        LocalInferenceResponse {
            text: "Local inference disabled in current build.".to_string(),
            backend: LocalInferenceBackend::Disabled,
        }
    }
}

impl Default for LocalInferenceStub {
    fn default() -> Self {
        Self::new_disabled()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn disabled_config_is_valid() {
        let config = LocalInferenceConfig::disabled();

        assert_eq!(config.backend, LocalInferenceBackend::Disabled);
        assert_eq!(config.endpoint, None);
    }

    #[test]
    fn accepts_127_0_0_1_loopback_endpoint() {
        let config = LocalInferenceConfig::future_loopback("127.0.0.1:11434").unwrap();

        assert_eq!(config.backend, LocalInferenceBackend::FutureLoopback);
        assert_eq!(config.endpoint.unwrap().as_str(), "127.0.0.1:11434");
    }

    #[test]
    fn accepts_localhost_loopback_endpoint() {
        let config = LocalInferenceConfig::future_loopback("localhost:1234").unwrap();

        assert_eq!(config.backend, LocalInferenceBackend::FutureLoopback);
        assert_eq!(config.endpoint.unwrap().as_str(), "localhost:1234");
    }

    #[test]
    fn rejects_cloud_endpoint() {
        let err = LocalInferenceConfig::future_loopback("api.example.com:443").unwrap_err();

        assert_eq!(err, LocalInferenceConfigError::NonLoopbackEndpointRejected);
    }

    #[test]
    fn rejects_url_scheme_endpoint() {
        let err = LocalInferenceConfig::future_loopback("https://127.0.0.1:11434").unwrap_err();

        assert_eq!(err, LocalInferenceConfigError::CloudEndpointRejected);
    }

    #[test]
    fn rejects_empty_endpoint() {
        let err = LocalInferenceConfig::future_loopback("").unwrap_err();

        assert_eq!(err, LocalInferenceConfigError::EmptyEndpoint);
    }

    #[test]
    fn rejects_missing_port() {
        let err = LocalInferenceConfig::future_loopback("127.0.0.1").unwrap_err();

        assert_eq!(err, LocalInferenceConfigError::MissingPort);
    }

    #[test]
    fn rejects_zero_port() {
        let err = LocalInferenceConfig::future_loopback("127.0.0.1:0").unwrap_err();

        assert_eq!(err, LocalInferenceConfigError::InvalidPort);
    }

    #[test]
    fn disabled_stub_still_returns_disabled_response() {
        let stub = LocalInferenceStub::new_disabled();
        let response = stub.infer(LocalInferenceRequest::new("hello iris"));

        assert_eq!(response.text, "Local inference disabled in current build.");
        assert_eq!(response.backend, LocalInferenceBackend::Disabled);
    }

    #[test]
    fn future_loopback_config_does_not_change_stub_behavior() {
        let config = LocalInferenceConfig::future_loopback("127.0.0.1:11434").unwrap();
        let stub = LocalInferenceStub::with_config(config);
        let response = stub.infer(LocalInferenceRequest::new("future local prompt"));

        assert_eq!(response.text, "Local inference disabled in current build.");
        assert_eq!(response.backend, LocalInferenceBackend::Disabled);
    }
}
