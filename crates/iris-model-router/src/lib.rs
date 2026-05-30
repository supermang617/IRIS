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
        "qwen3-vl:4b",
        ModelFamily::Qwen,
        ModelVariant::AbliteratedOrUncensored,
        ModelFormat::GGUF,
        Quantization::Q4KM,
        ModelSource::BartowskiHuggingFace,
        "qwen3-vl:4b",
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
        assert_eq!(routed.manifest.model_id, "qwen3-vl:4b");
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
        assert_eq!(routed.manifest.model_id, "qwen3-vl:4b");
        assert_eq!(routed.manifest.minimum_vram_gb, 4);
    }

    #[test]
    fn routes_no_vram_low_ram_to_edge_selected_model() {
        let profile = HardwareProfile::new(8, 0, "edge");
        let routed = route_model(&profile).unwrap();

        assert_eq!(routed.tier, ModelTier::Edge);
        assert_eq!(routed.manifest.model_id, "qwen3-vl:4b");
        assert_eq!(routed.manifest.minimum_vram_gb, 0);
    }
}
