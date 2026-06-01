use serde::Deserialize;
use std::path::{Path, PathBuf};

pub const MANIFEST_FILE_NAME: &str = "manifest.json";
pub const IRIS_MODEL_ID: &str = "huihui_ai/gemma-4-abliterated:e2b";

#[derive(Debug, Clone, Deserialize, PartialEq)]
pub struct ProjectManifest {
    pub project: ProjectSection,
    pub model_policy: ModelPolicy,
    pub resource_policy: ResourcePolicy,
    pub tts_policy: TtsPolicy,
    pub ipc_policy: IpcPolicy,
    pub safety_invariant: SafetyInvariant,
}

#[derive(Debug, Clone, Deserialize, PartialEq)]
pub struct ProjectSection {
    pub name: String,
    pub version: String,
    pub runtime_posture: String,
    pub target_platform: String,
}

#[derive(Debug, Clone, Deserialize, PartialEq)]
pub struct ModelPolicy {
    pub phase0_loads_model: bool,
    pub provider: String,
    pub model_id: String,
    pub model_display_name: String,
    pub parameter_size: String,
    pub num_ctx_ceiling: u32,
    pub architecture: String,
    pub single_model_only: bool,
    pub fallback_models_allowed: bool,
    pub unified_model: bool,
    pub vision_capable: bool,
    pub image_input_capable: bool,
    pub audio_capable: bool,
    pub tool_capable: bool,
    pub thinking_capable: bool,
    pub enabled_runtime_capabilities: Vec<String>,
    pub separate_vision_model: bool,
    pub rejected_architectures: Vec<String>,
}

#[derive(Debug, Clone, Deserialize, PartialEq)]
pub struct ResourcePolicy {
    pub reserved_system_memory_ratio: f64,
    pub scan_inputs: Vec<String>,
}

#[derive(Debug, Clone, Deserialize, PartialEq)]
pub struct TtsPolicy {
    pub provider: String,
    pub voice: String,
    pub lang: String,
    pub speed: f32,
    pub model_path: String,
    pub voices_path: String,
    pub helper_path: String,
}

#[derive(Debug, Clone, Deserialize, PartialEq)]
pub struct IpcPolicy {
    pub runtime_external_network: String,
    pub loopback_only: bool,
    pub allowed_hosts: Vec<String>,
}

#[derive(Debug, Clone, Deserialize, PartialEq)]
pub struct SafetyInvariant {
    pub system_control: String,
    pub executor: String,
    pub input_simulation: String,
    pub clipboard_access: String,
    pub runtime_network: String,
    pub plugins: String,
    pub screen_content_authority: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ModelSelection {
    pub id: String,
    pub provider: String,
    pub display_name: String,
    pub parameter_size: String,
    pub effective_num_ctx_ceiling: u32,
}

impl ProjectManifest {
    pub fn from_json_str(input: &str) -> Result<Self, String> {
        serde_json::from_str(input).map_err(|err| format!("invalid Iris manifest JSON: {err}"))
    }

    pub fn validate_phase0_policy(&self) -> Result<(), String> {
        require(
            self.project.target_platform == "windows",
            "Iris prototype target platform must be windows",
        )?;
        require(
            !self.model_policy.phase0_loads_model,
            "Phase 0 must not load a model",
        )?;
        require(
            self.model_policy.provider == "ollama_local",
            "Iris must use the local Ollama provider",
        )?;
        require(
            self.model_policy.model_id == IRIS_MODEL_ID,
            "Iris model must be huihui_ai/gemma-4-abliterated:e2b",
        )?;
        require(
            self.model_policy.single_model_only,
            "Iris must be configured as a single-model program",
        )?;
        require(
            !self.model_policy.fallback_models_allowed,
            "Iris must not define fallback models",
        )?;
        require(
            self.model_policy.unified_model,
            "manifest must declare one unified model",
        )?;
        require(
            self.model_policy.vision_capable,
            "manifest must declare the configured model as vision-capable",
        )?;
        require(
            self.model_policy.image_input_capable,
            "manifest must declare image input capability for the configured model",
        )?;
        require(
            self.model_policy
                .enabled_runtime_capabilities
                .iter()
                .any(|capability| capability == "completion"),
            "manifest must enable completion capability",
        )?;
        require(
            self.model_policy
                .enabled_runtime_capabilities
                .iter()
                .any(|capability| capability == "vision"),
            "manifest must enable vision capability",
        )?;
        require(
            !self.model_policy.separate_vision_model,
            "manifest must reject a separate vision model",
        )?;
        require(
            self.model_policy.num_ctx_ceiling == 8192,
            "manifest num_ctx ceiling must be exactly 8192",
        )?;
        require(
            self.model_policy.architecture == "gemma4",
            "manifest must select the locked Gemma 4 architecture",
        )?;
        require(
            self.model_policy
                .rejected_architectures
                .iter()
                .any(|architecture| architecture == "moe"),
            "manifest must reject MoE architectures",
        )?;
        require(
            self.model_policy
                .rejected_architectures
                .iter()
                .any(|architecture| architecture == "omni"),
            "manifest must reject Omni architectures",
        )?;
        require(
            self.resource_policy.reserved_system_memory_ratio >= 0.30
                && self.resource_policy.reserved_system_memory_ratio <= 0.40,
            "reserved system memory ratio must stay between 30% and 40%",
        )?;
        require(
            self.tts_policy.provider == "kokoro_onnx_python",
            "Iris TTS provider must be Kokoro ONNX",
        )?;
        require(
            self.tts_policy.voice == "af_heart",
            "Iris TTS voice must be af_heart",
        )?;
        require(
            self.tts_policy.lang == "en-us",
            "Iris TTS language must be en-us",
        )?;
        require(
            self.tts_policy.speed > 0.5 && self.tts_policy.speed <= 1.5,
            "Iris TTS speed must stay in a safe local range",
        )?;
        require(
            self.ipc_policy.runtime_external_network == "disabled",
            "runtime external network must be disabled",
        )?;
        require(self.ipc_policy.loopback_only, "IPC must be loopback-only")?;
        require(
            self.ipc_policy
                .allowed_hosts
                .iter()
                .any(|host| host == "127.0.0.1")
                && self
                    .ipc_policy
                    .allowed_hosts
                    .iter()
                    .any(|host| host == "localhost"),
            "IPC allowed hosts must include localhost loopback",
        )?;
        require(
            self.safety_invariant.system_control == "unsupported",
            "system control must be unsupported",
        )?;
        Ok(())
    }

    pub fn configured_model(&self) -> ModelSelection {
        ModelSelection {
            id: self.model_policy.model_id.clone(),
            provider: self.model_policy.provider.clone(),
            display_name: self.model_policy.model_display_name.clone(),
            parameter_size: self.model_policy.parameter_size.clone(),
            effective_num_ctx_ceiling: self.model_policy.num_ctx_ceiling,
        }
    }
}

pub fn load_manifest_from_workspace(start: impl AsRef<Path>) -> Result<ProjectManifest, String> {
    let manifest_path = find_manifest_path(start)?;
    let input = std::fs::read_to_string(&manifest_path)
        .map_err(|err| format!("{}: {err}", manifest_path.display()))?;
    let manifest = ProjectManifest::from_json_str(&input)?;
    manifest.validate_phase0_policy()?;
    Ok(manifest)
}

pub fn find_manifest_path(start: impl AsRef<Path>) -> Result<PathBuf, String> {
    let mut current = start.as_ref().to_path_buf();
    if current.is_file() {
        current.pop();
    }

    loop {
        let candidate = current.join(MANIFEST_FILE_NAME);
        if candidate.exists() {
            return Ok(candidate);
        }
        if !current.pop() {
            return Err(format!(
                "could not find {MANIFEST_FILE_NAME} from {}",
                start.as_ref().display()
            ));
        }
    }
}

fn require(condition: bool, message: &str) -> Result<(), String> {
    if condition {
        Ok(())
    } else {
        Err(message.to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const VALID_MANIFEST: &str = include_str!("../../../manifest.json");

    #[test]
    fn validates_phase0_manifest_policy() {
        let manifest = ProjectManifest::from_json_str(VALID_MANIFEST).unwrap();
        manifest.validate_phase0_policy().unwrap();
    }

    #[test]
    fn configured_model_is_exact_ollama_gemma4_target() {
        let manifest = ProjectManifest::from_json_str(VALID_MANIFEST).unwrap();
        let selection = manifest.configured_model();

        assert_eq!(selection.id, IRIS_MODEL_ID);
        assert_eq!(selection.provider, "ollama_local");
        assert_eq!(selection.parameter_size, "5.1B");
        assert_eq!(selection.effective_num_ctx_ceiling, 8192);
        assert!(manifest.model_policy.vision_capable);
        assert!(manifest.model_policy.image_input_capable);
        assert!(
            manifest
                .model_policy
                .enabled_runtime_capabilities
                .contains(&"vision".to_string())
        );
    }

    #[test]
    fn rejects_fallback_models() {
        let input = VALID_MANIFEST.replace(
            "\"fallback_models_allowed\": false",
            "\"fallback_models_allowed\": true",
        );
        let manifest = ProjectManifest::from_json_str(&input).unwrap();
        assert!(manifest.validate_phase0_policy().is_err());
    }

    #[test]
    fn rejects_runtime_network_enabled() {
        let input = VALID_MANIFEST.replace(
            "\"runtime_external_network\": \"disabled\"",
            "\"runtime_external_network\": \"enabled\"",
        );
        let manifest = ProjectManifest::from_json_str(&input).unwrap();
        assert!(manifest.validate_phase0_policy().is_err());
    }

    #[test]
    fn configured_tts_voice_is_af_heart() {
        let manifest = ProjectManifest::from_json_str(VALID_MANIFEST).unwrap();

        assert_eq!(manifest.tts_policy.provider, "kokoro_onnx_python");
        assert_eq!(manifest.tts_policy.voice, "af_heart");
        assert_eq!(
            manifest.tts_policy.model_path,
            "models/kokoro/kokoro-v1.0.onnx"
        );
    }
}
