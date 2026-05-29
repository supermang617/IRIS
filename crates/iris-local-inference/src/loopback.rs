use std::io::{Read, Write};
use std::net::{TcpStream, ToSocketAddrs};
use std::time::Duration;

use crate::{LocalInferenceBackend, LocalInferenceRequest, LocalInferenceResponse};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LoopbackInferenceError {
    EmptyEndpoint,
    EmptyModel,
    EmptyPrompt,
    NonLoopbackEndpointRejected,
    MissingPort,
    InvalidPort,
    ConnectFailed,
    WriteFailed,
    ReadFailed,
    InvalidResponse,
    MissingResponseText,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OllamaLoopbackConfig {
    pub endpoint: String,
    pub model: String,
}

impl OllamaLoopbackConfig {
    pub fn new(
        endpoint: impl Into<String>,
        model: impl Into<String>,
    ) -> Result<Self, LoopbackInferenceError> {
        let endpoint = endpoint.into();
        let model = model.into();

        validate_loopback_endpoint(&endpoint)?;

        if model.trim().is_empty() {
            return Err(LoopbackInferenceError::EmptyModel);
        }

        Ok(Self {
            endpoint: endpoint.trim().to_string(),
            model: model.trim().to_string(),
        })
    }
}

#[derive(Debug, Clone)]
pub struct OllamaLoopbackClient {
    config: OllamaLoopbackConfig,
}

impl OllamaLoopbackClient {
    pub fn new(config: OllamaLoopbackConfig) -> Self {
        Self { config }
    }

    pub fn infer(
        &self,
        request: LocalInferenceRequest,
    ) -> Result<LocalInferenceResponse, LoopbackInferenceError> {
        if request.prompt.trim().is_empty() {
            return Err(LoopbackInferenceError::EmptyPrompt);
        }

        let body = build_ollama_generate_body(&self.config.model, &request.prompt);
        let http_request = build_http_request(&self.config.endpoint, "/api/generate", &body);

        let mut stream = connect_loopback(&self.config.endpoint)?;
        stream
            .set_read_timeout(Some(Duration::from_secs(120)))
            .map_err(|_| LoopbackInferenceError::ConnectFailed)?;
        stream
            .set_write_timeout(Some(Duration::from_secs(30)))
            .map_err(|_| LoopbackInferenceError::ConnectFailed)?;

        stream
            .write_all(http_request.as_bytes())
            .map_err(|_| LoopbackInferenceError::WriteFailed)?;

        let mut response = String::new();
        stream
            .read_to_string(&mut response)
            .map_err(|_| LoopbackInferenceError::ReadFailed)?;

        let text = extract_ollama_response_text(&response)?;

        Ok(LocalInferenceResponse {
            text,
            backend: LocalInferenceBackend::OllamaLoopback,
        })
    }
}

fn connect_loopback(endpoint: &str) -> Result<TcpStream, LoopbackInferenceError> {
    let mut addrs = endpoint
        .to_socket_addrs()
        .map_err(|_| LoopbackInferenceError::InvalidPort)?;

    let Some(addr) = addrs.find(|addr| addr.ip().is_loopback()) else {
        return Err(LoopbackInferenceError::NonLoopbackEndpointRejected);
    };

    TcpStream::connect(addr).map_err(|_| LoopbackInferenceError::ConnectFailed)
}

pub fn validate_loopback_endpoint(endpoint: &str) -> Result<(), LoopbackInferenceError> {
    let endpoint = endpoint.trim();

    if endpoint.is_empty() {
        return Err(LoopbackInferenceError::EmptyEndpoint);
    }

    if endpoint.contains("://") {
        return Err(LoopbackInferenceError::NonLoopbackEndpointRejected);
    }

    let Some((host, port)) = endpoint.rsplit_once(':') else {
        return Err(LoopbackInferenceError::MissingPort);
    };

    if host != "127.0.0.1" && host != "localhost" {
        return Err(LoopbackInferenceError::NonLoopbackEndpointRejected);
    }

    let Ok(port) = port.parse::<u16>() else {
        return Err(LoopbackInferenceError::InvalidPort);
    };

    if port == 0 {
        return Err(LoopbackInferenceError::InvalidPort);
    }

    Ok(())
}

fn build_http_request(endpoint: &str, path: &str, body: &str) -> String {
    let host = endpoint
        .rsplit_once(':')
        .map(|(host, _)| host)
        .unwrap_or(endpoint);

    format!(
        "POST {path} HTTP/1.1\r\nHost: {host}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
        body.as_bytes().len()
    )
}

fn build_ollama_generate_body(model: &str, prompt: &str) -> String {
    format!(
        "{{\"model\":\"{}\",\"prompt\":\"{}\",\"stream\":false}}",
        escape_json(model),
        escape_json(prompt)
    )
}

fn escape_json(input: &str) -> String {
    let mut escaped = String::new();

    for character in input.chars() {
        match character {
            '"' => escaped.push_str("\\\""),
            '\\' => escaped.push_str("\\\\"),
            '\n' => escaped.push_str("\\n"),
            '\r' => escaped.push_str("\\r"),
            '\t' => escaped.push_str("\\t"),
            value => escaped.push(value),
        }
    }

    escaped
}

fn extract_ollama_response_text(http_response: &str) -> Result<String, LoopbackInferenceError> {
    if !http_response.starts_with("HTTP/1.1 200") && !http_response.starts_with("HTTP/1.0 200") {
        return Err(LoopbackInferenceError::InvalidResponse);
    }

    let Some((_, body)) = http_response.split_once("\r\n\r\n") else {
        return Err(LoopbackInferenceError::InvalidResponse);
    };

    let Some(response_start) = body.find("\"response\":\"") else {
        return Err(LoopbackInferenceError::MissingResponseText);
    };

    let value_start = response_start + "\"response\":\"".len();
    let value = &body[value_start..];

    let mut output = String::new();
    let mut escaped = false;

    for character in value.chars() {
        if escaped {
            match character {
                'n' => output.push('\n'),
                'r' => output.push('\r'),
                't' => output.push('\t'),
                '"' => output.push('"'),
                '\\' => output.push('\\'),
                other => output.push(other),
            }
            escaped = false;
            continue;
        }

        if character == '\\' {
            escaped = true;
            continue;
        }

        if character == '"' {
            return Ok(output);
        }

        output.push(character);
    }

    Err(LoopbackInferenceError::MissingResponseText)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_127_0_0_1_endpoint() {
        assert_eq!(validate_loopback_endpoint("127.0.0.1:11434"), Ok(()));
    }

    #[test]
    fn accepts_localhost_endpoint() {
        assert_eq!(validate_loopback_endpoint("localhost:11434"), Ok(()));
    }

    #[test]
    fn rejects_non_loopback_endpoint() {
        assert_eq!(
            validate_loopback_endpoint("api.example.com:443"),
            Err(LoopbackInferenceError::NonLoopbackEndpointRejected)
        );
    }

    #[test]
    fn rejects_url_endpoint() {
        assert_eq!(
            validate_loopback_endpoint("http://127.0.0.1:11434"),
            Err(LoopbackInferenceError::NonLoopbackEndpointRejected)
        );
    }

    #[test]
    fn builds_ollama_generate_body_without_streaming() {
        let body = build_ollama_generate_body("qwen-test", "hello \"iris\"");

        assert!(body.contains("\"model\":\"qwen-test\""));
        assert!(body.contains("\"prompt\":\"hello \\\"iris\\\"\""));
        assert!(body.contains("\"stream\":false"));
    }

    #[test]
    fn extracts_ollama_response_text() {
        let response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{\"response\":\"hello iris\",\"done\":true}";

        assert_eq!(
            extract_ollama_response_text(response),
            Ok("hello iris".to_string())
        );
    }
}
