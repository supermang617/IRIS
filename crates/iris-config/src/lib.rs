use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};

pub const MANIFEST_FILE_NAME: &str = "manifest.json";
pub const IRIS_MODEL_ID: &str = "huihui_ai/gemma-4-abliterated:e2b";
pub const IRIS_VISION_MODEL_ID: &str = "qwen3.5:4b";
pub const OLLAMA_MODEL_LOCK_RELATIVE_PATH: &str = "profiles/iris_ollama_model.lock.json";
pub const OLLAMA_VISION_MODEL_LOCK_RELATIVE_PATH: &str =
    "profiles/iris_ollama_vision_model.lock.json";
const EMBEDDED_OLLAMA_MODEL_LOCK: &str =
    include_str!("../../../profiles/iris_ollama_model.lock.json");
const EMBEDDED_OLLAMA_VISION_MODEL_LOCK: &str =
    include_str!("../../../profiles/iris_ollama_vision_model.lock.json");

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct OllamaModelLock {
    pub schema_version: u32,
    pub provider: String,
    pub model_id: String,
    pub manifest_digest: String,
    pub model_layer_digest: String,
    pub total_bytes: u64,
    pub family: String,
    pub parameter_size: String,
    pub quantization_level: String,
    pub required_capabilities: Vec<String>,
    pub general_vision_verified: bool,
}

#[derive(Debug, Clone, Deserialize, PartialEq)]
pub struct ProjectManifest {
    pub project: ProjectSection,
    pub model_policy: ModelPolicy,
    pub vision_model_policy: VisionModelPolicy,
    pub resource_policy: ResourcePolicy,
    pub dynamic_context_policy: DynamicContextPolicy,
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
    pub runtime_loads_model: bool,
    pub provider: String,
    pub model_id: String,
    pub model_display_name: String,
    pub parameter_size: String,
    pub num_ctx_ceiling: u32,
    /// Compatibility fallback for an automatic Ollama placement failure.
    pub num_gpu_layers: u32,
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
pub struct VisionModelPolicy {
    pub provider: String,
    pub model_id: String,
    pub model_display_name: String,
    pub parameter_size: String,
    pub num_ctx_ceiling: u32,
    pub num_gpu_layers: u32,
    pub architecture: String,
    pub image_input_capable: bool,
    pub general_vision_verified: bool,
}

#[derive(Debug, Clone, Deserialize, PartialEq)]
pub struct ResourcePolicy {
    pub reserved_system_memory_ratio: f64,
    pub scan_inputs: Vec<String>,
}

#[derive(Debug, Clone, Deserialize, PartialEq)]
pub struct DynamicContextPolicy {
    pub enabled_by_default: bool,
    pub storage_path: String,
    pub stores_raw_text: bool,
    pub half_life_days: u32,
    pub max_observations: u32,
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

    pub fn validate_v0_1_policy(&self) -> Result<(), String> {
        require(
            self.project.target_platform == "windows",
            "Iris target platform must be windows",
        )?;
        require(
            !self.model_policy.runtime_loads_model,
            "Iris runtime must not eagerly load a model from manifest policy",
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
            !self.model_policy.single_model_only,
            "Iris must declare its separately locked visual model",
        )?;
        require(
            !self.model_policy.fallback_models_allowed,
            "Iris must not define fallback models",
        )?;
        require(
            !self.model_policy.unified_model,
            "manifest must not claim one unified model when visual inference is separate",
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
            self.model_policy.separate_vision_model,
            "manifest must declare the separately locked vision model",
        )?;
        require(
            self.model_policy.num_ctx_ceiling == 8192,
            "manifest num_ctx ceiling must be exactly 8192",
        )?;
        require(
            self.model_policy.num_gpu_layers == 1,
            "Gemma 4 safe Ollama GPU fallback must remain one layer on this Windows target",
        )?;
        require(
            self.model_policy.architecture == "gemma4",
            "manifest must select the locked Gemma 4 architecture",
        )?;
        require(
            self.vision_model_policy.provider == "ollama_local",
            "Iris vision must use the local Ollama provider",
        )?;
        require(
            self.vision_model_policy.model_id == IRIS_VISION_MODEL_ID,
            "Iris vision model must be qwen3.5:4b",
        )?;
        require(
            self.vision_model_policy.parameter_size == "4.7B"
                && self.vision_model_policy.architecture == "qwen35",
            "Iris vision model metadata differs from the audited Qwen target",
        )?;
        require(
            self.vision_model_policy.num_ctx_ceiling == 2048
                && self.vision_model_policy.num_gpu_layers == 1,
            "Iris vision model runtime bounds differ from the audited profile",
        )?;
        require(
            self.vision_model_policy.image_input_capable
                && self.vision_model_policy.general_vision_verified,
            "Iris vision model must declare verified local image input",
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
            self.dynamic_context_policy.enabled_by_default,
            "dynamic system context must be enabled by default",
        )?;
        require(
            self.dynamic_context_policy.storage_path == ".iris-data/dynamic_context.json",
            "dynamic system context must stay inside the Iris-owned data root",
        )?;
        require(
            !self.dynamic_context_policy.stores_raw_text,
            "dynamic system context must not store raw user text",
        )?;
        require(
            self.dynamic_context_policy.half_life_days == 30,
            "dynamic system context half-life must be 30 days",
        )?;
        require(
            self.dynamic_context_policy.max_observations == 64,
            "dynamic system context observation cap must be 64",
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
            self.safety_invariant.system_control == "agentic_session_approved_tool_actions_only"
                && self.safety_invariant.executor == "no_arbitrary_shell_process",
            "system control must be limited to approved tool actions without arbitrary shell/process execution",
        )?;
        locked_ollama_model()?.validate_against_manifest(self)?;
        locked_ollama_vision_model()?.validate_against_vision_policy(&self.vision_model_policy)?;
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

impl OllamaModelLock {
    pub fn from_json_str(input: &str) -> Result<Self, String> {
        serde_json::from_str(input).map_err(|err| format!("invalid Iris Ollama model lock: {err}"))
    }

    pub fn validate_against_manifest(&self, manifest: &ProjectManifest) -> Result<(), String> {
        require(
            self.schema_version == 1,
            "unsupported Ollama model lock schema",
        )?;
        require(
            self.provider == "ollama_local" && self.provider == manifest.model_policy.provider,
            "Ollama model lock provider differs from manifest policy",
        )?;
        require(
            self.model_id == IRIS_MODEL_ID && self.model_id == manifest.model_policy.model_id,
            "Ollama model lock identity differs from manifest policy",
        )?;
        require(
            is_lower_sha256(&self.manifest_digest),
            "Ollama model manifest digest must be lowercase SHA256",
        )?;
        require(
            self.model_layer_digest
                .strip_prefix("sha256:")
                .is_some_and(is_lower_sha256),
            "Ollama model-layer digest must be sha256-prefixed lowercase SHA256",
        )?;
        require(
            self.total_bytes > 0,
            "Ollama model byte count must be positive",
        )?;
        require(
            self.family == manifest.model_policy.architecture,
            "Ollama model family differs from manifest architecture",
        )?;
        require(
            self.parameter_size == manifest.model_policy.parameter_size,
            "Ollama model parameter size differs from manifest policy",
        )?;
        require(
            !self.quantization_level.trim().is_empty(),
            "Ollama model quantization must not be empty",
        )?;
        require(
            !self.required_capabilities.is_empty()
                && self
                    .required_capabilities
                    .iter()
                    .all(|capability| !capability.trim().is_empty()),
            "Ollama model lock must declare required capabilities",
        )?;
        let mut unique = self.required_capabilities.clone();
        unique.sort();
        unique.dedup();
        require(
            unique.len() == self.required_capabilities.len(),
            "Ollama model lock capabilities must be unique",
        )?;
        for capability in ["completion", "vision", "audio", "tools", "thinking"] {
            require(
                self.required_capabilities
                    .iter()
                    .any(|required| required == capability),
                "Ollama model lock is missing a required Iris capability",
            )?;
        }
        Ok(())
    }

    pub fn validate_against_vision_policy(&self, policy: &VisionModelPolicy) -> Result<(), String> {
        self.validate_common()?;
        require(
            self.provider == policy.provider,
            "vision model lock provider differs from manifest policy",
        )?;
        require(
            self.model_id == IRIS_VISION_MODEL_ID && self.model_id == policy.model_id,
            "vision model lock identity differs from manifest policy",
        )?;
        require(
            self.family == policy.architecture && self.parameter_size == policy.parameter_size,
            "vision model lock metadata differs from manifest policy",
        )?;
        for capability in ["completion", "vision", "tools", "thinking"] {
            require(
                self.required_capabilities
                    .iter()
                    .any(|required| required == capability),
                "vision model lock is missing a required Iris capability",
            )?;
        }
        require(
            self.general_vision_verified && policy.general_vision_verified,
            "vision model lock must be release-verified for general vision",
        )?;
        Ok(())
    }

    fn validate_common(&self) -> Result<(), String> {
        require(
            self.schema_version == 1,
            "unsupported Ollama model lock schema",
        )?;
        require(
            self.provider == "ollama_local",
            "unsupported Ollama model provider",
        )?;
        require(
            is_lower_sha256(&self.manifest_digest),
            "Ollama model manifest digest must be lowercase SHA256",
        )?;
        require(
            self.model_layer_digest
                .strip_prefix("sha256:")
                .is_some_and(is_lower_sha256),
            "Ollama model-layer digest must be sha256-prefixed lowercase SHA256",
        )?;
        require(
            self.total_bytes > 0,
            "Ollama model byte count must be positive",
        )?;
        require(
            !self.quantization_level.trim().is_empty(),
            "Ollama model quantization must not be empty",
        )?;
        require(
            !self.required_capabilities.is_empty()
                && self
                    .required_capabilities
                    .iter()
                    .all(|capability| !capability.trim().is_empty()),
            "Ollama model lock must declare required capabilities",
        )?;
        let mut unique = self.required_capabilities.clone();
        unique.sort();
        unique.dedup();
        require(
            unique.len() == self.required_capabilities.len(),
            "Ollama model lock capabilities must be unique",
        )
    }
}

pub fn locked_ollama_model() -> Result<OllamaModelLock, String> {
    OllamaModelLock::from_json_str(EMBEDDED_OLLAMA_MODEL_LOCK)
}

pub fn locked_ollama_vision_model() -> Result<OllamaModelLock, String> {
    OllamaModelLock::from_json_str(EMBEDDED_OLLAMA_VISION_MODEL_LOCK)
}

pub fn load_manifest_from_workspace(start: impl AsRef<Path>) -> Result<ProjectManifest, String> {
    let manifest_path = find_manifest_path(start)?;
    let input = std::fs::read_to_string(&manifest_path)
        .map_err(|err| format!("{}: {err}", manifest_path.display()))?;
    let manifest = ProjectManifest::from_json_str(&input)?;
    manifest.validate_v0_1_policy()?;
    let workspace_root = manifest_path
        .parent()
        .ok_or_else(|| "Iris manifest path has no parent".to_string())?;
    let lock_path = workspace_root.join(OLLAMA_MODEL_LOCK_RELATIVE_PATH);
    let lock_input = std::fs::read_to_string(&lock_path)
        .map_err(|err| format!("{}: {err}", lock_path.display()))?;
    let disk_lock = OllamaModelLock::from_json_str(&lock_input)?;
    disk_lock.validate_against_manifest(&manifest)?;
    require(
        disk_lock == locked_ollama_model()?,
        "packaged Ollama model lock differs from the lock embedded in Iris",
    )?;
    let vision_lock_path = workspace_root.join(OLLAMA_VISION_MODEL_LOCK_RELATIVE_PATH);
    let vision_lock_input = std::fs::read_to_string(&vision_lock_path)
        .map_err(|err| format!("{}: {err}", vision_lock_path.display()))?;
    let disk_vision_lock = OllamaModelLock::from_json_str(&vision_lock_input)?;
    disk_vision_lock.validate_against_vision_policy(&manifest.vision_model_policy)?;
    require(
        disk_vision_lock == locked_ollama_vision_model()?,
        "packaged Ollama vision model lock differs from the lock embedded in Iris",
    )?;
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

fn is_lower_sha256(value: &str) -> bool {
    value.len() == 64
        && value
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
}

#[cfg(test)]
mod tests {
    use super::*;

    const VALID_MANIFEST: &str = include_str!("../../../manifest.json");

    #[test]
    fn validates_v0_1_manifest_policy() {
        let manifest = ProjectManifest::from_json_str(VALID_MANIFEST).unwrap();
        manifest.validate_v0_1_policy().unwrap();
    }

    #[test]
    fn configured_model_is_exact_ollama_gemma4_target() {
        let manifest = ProjectManifest::from_json_str(VALID_MANIFEST).unwrap();
        let selection = manifest.configured_model();

        assert_eq!(selection.id, IRIS_MODEL_ID);
        assert_eq!(selection.provider, "ollama_local");
        assert_eq!(selection.parameter_size, "5.1B");
        assert_eq!(selection.effective_num_ctx_ceiling, 8192);
        assert_eq!(manifest.model_policy.num_gpu_layers, 1);
        assert!(manifest.model_policy.vision_capable);
        assert!(manifest.model_policy.image_input_capable);
        assert!(
            !manifest
                .model_policy
                .enabled_runtime_capabilities
                .contains(&"vision".to_string())
        );
    }

    #[test]
    fn ollama_model_locks_are_exact_and_visual_route_is_verified() {
        let manifest = ProjectManifest::from_json_str(VALID_MANIFEST).unwrap();
        let lock = locked_ollama_model().unwrap();

        lock.validate_against_manifest(&manifest).unwrap();
        assert_eq!(
            lock.manifest_digest,
            "7c4fbc4573d646fa7a2bcd940cd682a57c5717fcd1b48fd96ea45b1ef24d499f"
        );
        assert_eq!(
            lock.model_layer_digest,
            "sha256:fd456de3e24d0a03164a636029339fbda0f4c5b1ae11616423006bbff6f2e81d"
        );
        assert_eq!(lock.total_bytes, 7_162_405_953);
        assert_eq!(lock.quantization_level, "Q4_K_M");
        assert!(!lock.general_vision_verified);

        let vision_lock = locked_ollama_vision_model().unwrap();
        vision_lock
            .validate_against_vision_policy(&manifest.vision_model_policy)
            .unwrap();
        assert_eq!(vision_lock.model_id, IRIS_VISION_MODEL_ID);
        assert_eq!(
            vision_lock.manifest_digest,
            "2a654d98e6fba55d452b7043684e9b57a947e393bbffa62485a7aac05ee4eefd"
        );
        assert_eq!(
            vision_lock.model_layer_digest,
            "sha256:81fb60c7daa80fc1123380b98970b320ae233409f0f71a72ed7b9b0d62f40490"
        );
        assert_eq!(vision_lock.total_bytes, 3_389_983_735);
        assert_eq!(vision_lock.family, "qwen35");
        assert_eq!(vision_lock.parameter_size, "4.7B");
        assert_eq!(vision_lock.quantization_level, "Q4_K_M");
        assert!(vision_lock.general_vision_verified);
    }

    #[test]
    fn ollama_model_lock_rejects_identity_and_capability_drift() {
        let manifest = ProjectManifest::from_json_str(VALID_MANIFEST).unwrap();
        let mut lock = locked_ollama_model().unwrap();
        lock.manifest_digest = "0".repeat(63);
        assert!(lock.validate_against_manifest(&manifest).is_err());

        let mut lock = locked_ollama_model().unwrap();
        lock.required_capabilities
            .retain(|capability| capability != "vision");
        assert!(lock.validate_against_manifest(&manifest).is_err());
    }

    #[test]
    fn rejects_fallback_models() {
        let input = VALID_MANIFEST.replace(
            "\"fallback_models_allowed\": false",
            "\"fallback_models_allowed\": true",
        );
        let manifest = ProjectManifest::from_json_str(&input).unwrap();
        assert!(manifest.validate_v0_1_policy().is_err());
    }

    #[test]
    fn rejects_disabling_the_separate_verified_visual_route() {
        let input = VALID_MANIFEST.replace(
            "\"separate_vision_model\": true",
            "\"separate_vision_model\": false",
        );
        let manifest = ProjectManifest::from_json_str(&input).unwrap();
        assert!(manifest.validate_v0_1_policy().is_err());
    }

    #[test]
    fn rejects_runtime_network_enabled() {
        let input = VALID_MANIFEST.replace(
            "\"runtime_external_network\": \"disabled\"",
            "\"runtime_external_network\": \"enabled\"",
        );
        let manifest = ProjectManifest::from_json_str(&input).unwrap();
        assert!(manifest.validate_v0_1_policy().is_err());
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

    #[test]
    fn dynamic_context_policy_is_local_bounded_and_text_free() {
        let manifest = ProjectManifest::from_json_str(VALID_MANIFEST).unwrap();
        let policy = &manifest.dynamic_context_policy;

        assert!(policy.enabled_by_default);
        assert_eq!(policy.storage_path, ".iris-data/dynamic_context.json");
        assert!(!policy.stores_raw_text);
        assert_eq!(policy.half_life_days, 30);
        assert_eq!(policy.max_observations, 64);
    }
}
