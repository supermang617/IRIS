use iris_config::{ModelSelection, ProjectManifest};
use iris_hardware::HardwareSnapshot;
use serde::Serialize;

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct DashboardSnapshot {
    pub project_name: String,
    pub project_version: String,
    pub runtime_posture: String,
    pub core_invariant: &'static str,
    pub platform: String,
    pub model: ModelStatus,
    pub num_ctx_ceiling: u32,
    pub hardware: HardwareStatus,
    pub safety: SafetyStatus,
    pub hermes: HermesStatus,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct ModelStatus {
    pub id: String,
    pub provider: String,
    pub display_name: String,
    pub parameter_size: String,
    pub fallback_models_allowed: bool,
    pub runtime_external_network: String,
    pub loopback_only: bool,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct HardwareStatus {
    pub total_ram_gb: f64,
    pub available_ram_gb: f64,
    pub usable_after_reserve_gb: f64,
    pub cpu_cores: usize,
    pub gpu_vram_gb: Option<f64>,
    pub reserved_memory_ratio: f64,
    pub basis: String,
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
pub struct SafetyStatus {
    pub system_control: &'static str,
    pub executor: &'static str,
    pub input_simulation: &'static str,
    pub clipboard_access: &'static str,
    pub runtime_network: &'static str,
    pub plugins: &'static str,
    pub screen_content_authority: &'static str,
    pub filesystem_scope: &'static str,
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
pub struct HermesStatus {
    pub enabled_by_default: bool,
    pub sidecar_enabled_by_default: bool,
    pub lifecycle_owner: &'static str,
    pub transport: &'static str,
    pub broker_url: &'static str,
    pub external_network: bool,
    pub approved_tools: Vec<&'static str>,
    pub acting_tools: Vec<&'static str>,
    pub parallel_inference_streams: u32,
    pub status: &'static str,
}

pub fn build_dashboard_snapshot(
    manifest: &ProjectManifest,
    hardware: &HardwareSnapshot,
) -> DashboardSnapshot {
    let model = manifest.configured_model();
    snapshot_from_parts(manifest, hardware, model)
}

fn snapshot_from_parts(
    manifest: &ProjectManifest,
    hardware: &HardwareSnapshot,
    model: ModelSelection,
) -> DashboardSnapshot {
    let num_ctx_ceiling = model.effective_num_ctx_ceiling;
    DashboardSnapshot {
        project_name: manifest.project.name.clone(),
        project_version: manifest.project.version.clone(),
        runtime_posture: manifest.project.runtime_posture.clone(),
        core_invariant: iris_policy::CORE_PRODUCT_INVARIANT,
        platform: hardware.platform.as_str().to_string(),
        model: model_status(manifest, model),
        num_ctx_ceiling,
        hardware: HardwareStatus {
            total_ram_gb: rounded_gb(hardware.total_ram_gb()),
            available_ram_gb: rounded_gb(hardware.available_ram_gb()),
            usable_after_reserve_gb: rounded_gb(hardware.usable_memory_gb()),
            cpu_cores: hardware.cpu_cores,
            gpu_vram_gb: hardware
                .gpu_vram_bytes
                .map(|bytes| rounded_gb(bytes as f64 / 1024.0 / 1024.0 / 1024.0)),
            reserved_memory_ratio: hardware.reserved_memory_ratio,
            basis: hardware.basis(),
        },
        safety: SafetyStatus {
            system_control: iris_policy::SYSTEM_CONTROL,
            executor: iris_policy::EXECUTOR,
            input_simulation: iris_policy::INPUT_SIMULATION,
            clipboard_access: iris_policy::CLIPBOARD_ACCESS,
            runtime_network: iris_policy::RUNTIME_NETWORK,
            plugins: iris_policy::PLUGINS,
            screen_content_authority: iris_policy::SCREEN_CONTENT_AUTHORITY,
            filesystem_scope: iris_policy::FILESYSTEM_SCOPE,
        },
        hermes: HermesStatus {
            enabled_by_default: true,
            sidecar_enabled_by_default: true,
            lifecycle_owner: "iris",
            transport: "stdin_stdout_json",
            broker_url: "http://127.0.0.1:48731",
            external_network: true,
            approved_tools: vec![
                "iris_query_memory",
                "iris_propose_memory",
                "iris_web_research",
            ],
            acting_tools: Vec::new(),
            parallel_inference_streams: 1,
            status: "enabled_sandboxed_research_rag_helper_no_computer_control",
        },
    }
}

fn model_status(manifest: &ProjectManifest, selection: ModelSelection) -> ModelStatus {
    ModelStatus {
        id: selection.id,
        provider: selection.provider,
        display_name: selection.display_name,
        parameter_size: selection.parameter_size,
        fallback_models_allowed: manifest.model_policy.fallback_models_allowed,
        runtime_external_network: manifest.ipc_policy.runtime_external_network.clone(),
        loopback_only: manifest.ipc_policy.loopback_only,
    }
}

fn rounded_gb(value: f64) -> f64 {
    (value * 10.0).round() / 10.0
}

#[cfg(test)]
mod tests {
    use super::*;
    use iris_hardware::{DEFAULT_RESERVED_MEMORY_RATIO, HardwareSnapshot, PlatformTarget};

    const MANIFEST: &str = include_str!("../../../manifest.json");

    fn gb(value: u64) -> u64 {
        value * 1024 * 1024 * 1024
    }

    #[test]
    fn dashboard_snapshot_uses_single_windows_model() {
        let manifest = ProjectManifest::from_json_str(MANIFEST).unwrap();
        let hardware = HardwareSnapshot {
            platform: PlatformTarget::Windows,
            total_ram_bytes: gb(64),
            available_ram_bytes: gb(56),
            cpu_cores: 16,
            gpu_vram_bytes: None,
            reserved_memory_ratio: DEFAULT_RESERVED_MEMORY_RATIO,
        };
        let snapshot = build_dashboard_snapshot(&manifest, &hardware);

        assert_eq!(snapshot.project_name, "Project Iris");
        assert_eq!(snapshot.platform, "windows");
        assert_eq!(snapshot.model.id, iris_config::IRIS_MODEL_ID);
        assert_eq!(snapshot.model.provider, "ollama_local");
        assert!(!snapshot.model.fallback_models_allowed);
        assert_eq!(snapshot.num_ctx_ceiling, 8192);
        assert_eq!(snapshot.safety.runtime_network, "Runtime Network: Disabled");
        assert!(snapshot.hermes.enabled_by_default);
        assert!(snapshot.hermes.sidecar_enabled_by_default);
        assert_eq!(snapshot.hermes.lifecycle_owner, "iris");
        assert_eq!(snapshot.hermes.broker_url, "http://127.0.0.1:48731");
        assert_eq!(
            snapshot.hermes.approved_tools,
            vec![
                "iris_query_memory",
                "iris_propose_memory",
                "iris_web_research"
            ]
        );
        assert!(snapshot.hermes.acting_tools.is_empty());
        assert_eq!(snapshot.hermes.parallel_inference_streams, 1);
        assert_eq!(
            snapshot.hermes.status,
            "enabled_sandboxed_research_rag_helper_no_computer_control"
        );
    }
}
