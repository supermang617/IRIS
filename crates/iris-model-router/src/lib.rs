use iris_model_manifest::{
    ModelFamily, ModelFormat, ModelManifest, ModelManifestError, ModelSource, ModelVariant,
    Quantization,
};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HardwareProfile {
    pub total_ram_gb: u32,
    pub dedicated_vram_gb: u32,
    pub os_label: String,
}

impl HardwareProfile {
    pub fn new(total_ram_gb: u32, dedicated_vram_gb: u32, os_label: impl Into<String>) -> Self {
        Self {
            total_ram_gb,
            dedicated_vram_gb,
            os_label: os_label.into(),
        }
    }

    pub fn windows_rtx_4060_class() -> Self {
        Self::new(64, 8, "windows-rtx-4060-class")
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ModelTier {
    Edge,
    Lightweight,
    StandardDesktop,
    HighEndDesktop,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ModelRoutingError {
    Manifest(ModelManifestError),
}

impl From<ModelManifestError> for ModelRoutingError {
    fn from(value: ModelManifestError) -> Self {
        Self::Manifest(value)
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RoutedModel {
    pub tier: ModelTier,
    pub manifest: ModelManifest,
}

pub fn route_model(profile: &HardwareProfile) -> Result<RoutedModel, ModelRoutingError> {
    if profile.dedicated_vram_gb >= 8 {
        return Ok(RoutedModel {
            tier: ModelTier::StandardDesktop,
            manifest: selected_qwen_vl_manifest(8, 8)?,
        });
    }

    if profile.dedicated_vram_gb >= 4 || profile.total_ram_gb >= 12 {
        return Ok(RoutedModel {
            tier: ModelTier::Lightweight,
            manifest: selected_qwen_vl_manifest(8, 4)?,
        });
    }

    Ok(RoutedModel {
        tier: ModelTier::Edge,
        manifest: selected_qwen_vl_manifest(8, 0)?,
    })
}

fn selected_qwen_vl_manifest(
    minimum_ram_gb: u32,
    minimum_vram_gb: u32,
) -> Result<ModelManifest, ModelManifestError> {
    ModelManifest::new_verified_metadata(
        "huihui_ai/qwen3.5-abliterated:9b:9b",
        ModelFamily::Qwen,
        ModelVariant::AbliteratedOrUncensored,
        ModelFormat::GGUF,
        Quantization::Q4KM,
        ModelSource::BartowskiHuggingFace,
        "huihui_ai/qwen3.5-abliterated:9b:9b",
        "ollama-managed-model-digest",
        minimum_ram_gb,
        minimum_vram_gb,
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn routes_rtx_4060_class_to_selected_qwen_vl_model() {
        let profile = HardwareProfile::windows_rtx_4060_class();
        let routed = route_model(&profile).unwrap();

        assert_eq!(routed.tier, ModelTier::StandardDesktop);
        assert_eq!(
            routed.manifest.model_id,
            "huihui_ai/qwen3.5-abliterated:9b:9b"
        );
        assert_eq!(routed.manifest.family, ModelFamily::Qwen);
        assert_eq!(
            routed.manifest.variant,
            ModelVariant::AbliteratedOrUncensored
        );
        assert_eq!(routed.manifest.format, ModelFormat::GGUF);
        assert_eq!(routed.manifest.minimum_vram_gb, 8);
    }

    #[test]
    fn routes_four_gb_vram_to_lightweight_selected_model() {
        let profile = HardwareProfile::new(16, 4, "low-end-gpu");
        let routed = route_model(&profile).unwrap();

        assert_eq!(routed.tier, ModelTier::Lightweight);
        assert_eq!(
            routed.manifest.model_id,
            "huihui_ai/qwen3.5-abliterated:9b:9b"
        );
        assert_eq!(routed.manifest.minimum_vram_gb, 4);
    }

    #[test]
    fn routes_no_vram_low_ram_to_edge_selected_model() {
        let profile = HardwareProfile::new(8, 0, "edge");
        let routed = route_model(&profile).unwrap();

        assert_eq!(routed.tier, ModelTier::Edge);
        assert_eq!(
            routed.manifest.model_id,
            "huihui_ai/qwen3.5-abliterated:9b:9b"
        );
        assert_eq!(routed.manifest.minimum_vram_gb, 0);
    }
}

//
// IRIS_BOUNDED_OLLAMA_CHAT_ROUTER_BEGIN
pub fn bounded_local_chat_for_hud(input: &str) -> Result<String, String> {
    use std::{
        io::{Read, Write},
        net as iris_loopback_socket,
        time::Duration,
    };

    let model = selected_local_model_id_for_hud();
    let num_ctx = selected_local_model_num_ctx_for_hud();
    let num_predict = selected_local_model_num_predict_for_hud();

    let system = "You are Iris. Reply only with the final answer. Do not show reasoning, thinking, analysis, drafts, bullets, or explanations. Do not censor profanity with asterisks. Keep the reply concise.";
    let body = format!(
        "{{\"model\":\"{}\",\"messages\":[{{\"role\":\"system\",\"content\":\"{}\"}},{{\"role\":\"user\",\"content\":\"{}\"}}],\"stream\":false,\"think\":false,\"options\":{{\"num_ctx\":{},\"num_predict\":{},\"temperature\":0.2,\"top_p\":0.8,\"repeat_penalty\":1.1}}}}",
        json_escape_for_hud(&model),
        json_escape_for_hud(system),
        json_escape_for_hud(input),
        num_ctx,
        num_predict
    );

    let mut stream = iris_loopback_socket::TcpStream::connect("127.0.0.1:11434")
        .map_err(|_| "ReadFailed".to_string())?;

    stream
        .set_read_timeout(Some(Duration::from_secs(75)))
        .map_err(|_| "ReadFailed".to_string())?;

    stream
        .set_write_timeout(Some(Duration::from_secs(10)))
        .map_err(|_| "ReadFailed".to_string())?;

    let request = format!(
        "POST /api/chat HTTP/1.1\r\nHost: 127.0.0.1:11434\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
        body.as_bytes().len(),
        body
    );

    stream
        .write_all(request.as_bytes())
        .map_err(|_| "ReadFailed".to_string())?;

    let mut raw = String::new();

    stream
        .read_to_string(&mut raw)
        .map_err(|_| "ReadFailed".to_string())?;

    if !(raw.starts_with("HTTP/1.1 200") || raw.starts_with("HTTP/1.0 200")) {
        return Err("InvalidResponse".to_string());
    }

    let body = http_body_for_hud(&raw)?;

    let text = extract_json_string_field_for_hud(body, "content")
        .or_else(|| extract_json_string_field_for_hud(body, "response"))
        .ok_or_else(|| "InvalidResponse".to_string())?;

    let cleaned = strip_thinking_for_hud(&text);

    if cleaned.trim().is_empty() {
        return Err("InvalidResponse".to_string());
    }

    Ok(cleaned)
}

fn selected_local_model_id_for_hud() -> String {
    std::env::var("IRIS_MODEL_ID")
        .or_else(|_| std::env::var("IRIS_OLLAMA_MODEL"))
        .or_else(|_| std::env::var("IRIS_LOCAL_MODEL"))
        .unwrap_or_else(|_| "huihui_ai/qwen3.5-abliterated:9b:9b".to_string())
}

fn selected_local_model_num_ctx_for_hud() -> usize {
    std::env::var("IRIS_MODEL_NUM_CTX")
        .ok()
        .and_then(|value| value.parse::<usize>().ok())
        .unwrap_or(8192)
}

fn selected_local_model_num_predict_for_hud() -> usize {
    std::env::var("IRIS_MODEL_NUM_PREDICT")
        .ok()
        .and_then(|value| value.parse::<usize>().ok())
        .unwrap_or(160)
}

fn json_escape_for_hud(value: &str) -> String {
    let mut out = String::with_capacity(value.len() + 16);

    for ch in value.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if c.is_control() => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }

    out
}

fn http_body_for_hud(raw: &str) -> Result<&str, String> {
    let separator = "\r\n\r\n";
    let index = raw
        .find(separator)
        .ok_or_else(|| "InvalidResponse".to_string())?;

    Ok(&raw[index + separator.len()..])
}

fn extract_json_string_field_for_hud(body: &str, field: &str) -> Option<String> {
    let key = format!("\"{}\"", field);
    let key_index = body.find(&key)?;
    let after_key = &body[key_index + key.len()..];
    let colon_index = after_key.find(':')?;
    let after_colon = after_key[colon_index + 1..].trim_start();

    if !after_colon.starts_with('"') {
        return None;
    }

    let mut out = String::new();
    let mut escape = false;

    for ch in after_colon[1..].chars() {
        if escape {
            match ch {
                '"' => out.push('"'),
                '\\' => out.push('\\'),
                '/' => out.push('/'),
                'n' => out.push('\n'),
                'r' => out.push('\r'),
                't' => out.push('\t'),
                'b' => out.push('\u{0008}'),
                'f' => out.push('\u{000c}'),
                other => out.push(other),
            }

            escape = false;
            continue;
        }

        if ch == '\\' {
            escape = true;
            continue;
        }

        if ch == '"' {
            return Some(out);
        }

        out.push(ch);
    }

    None
}

fn strip_thinking_for_hud(text: &str) -> String {
    let mut cleaned = text.trim().to_string();

    loop {
        let lower = cleaned.to_lowercase();
        let Some(start) = lower.find("<think>") else {
            break;
        };

        let Some(relative_end) = lower[start..].find("</think>") else {
            cleaned = cleaned[..start].trim().to_string();
            break;
        };

        let end = start + relative_end + "</think>".len();
        cleaned.replace_range(start..end, "");
        cleaned = cleaned.trim().to_string();
    }

    cleaned
}
// IRIS_BOUNDED_OLLAMA_CHAT_ROUTER_END
