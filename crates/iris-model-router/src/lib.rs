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
    if profile.dedicated_vram_gb >= 16 {
        return Ok(RoutedModel {
            tier: ModelTier::HighEndDesktop,
            manifest: placeholder_manifest(
                "qwen-ab-literated-14b-placeholder",
                "placeholder-qwen-14b-abliterated.Q4_K_M.gguf",
                24,
                16,
            )?,
        });
    }

    if profile.dedicated_vram_gb >= 8 {
        return Ok(RoutedModel {
            tier: ModelTier::StandardDesktop,
            manifest: placeholder_manifest(
                "qwen-ab-literated-8b-placeholder",
                "placeholder-qwen-8b-abliterated.Q4_K_M.gguf",
                16,
                8,
            )?,
        });
    }

    if profile.dedicated_vram_gb >= 4 || profile.total_ram_gb >= 12 {
        return Ok(RoutedModel {
            tier: ModelTier::Lightweight,
            manifest: placeholder_manifest(
                "qwen-ab-literated-4b-placeholder",
                "placeholder-qwen-4b-abliterated.Q4_K_M.gguf",
                8,
                4,
            )?,
        });
    }

    Ok(RoutedModel {
        tier: ModelTier::Edge,
        manifest: placeholder_manifest(
            "qwen-ab-literated-edge-placeholder",
            "placeholder-qwen-0_5b-to-1_5b-abliterated.Q4_K_M.gguf",
            4,
            0,
        )?,
    })
}

fn placeholder_manifest(
    model_id: &str,
    filename: &str,
    minimum_ram_gb: u32,
    minimum_vram_gb: u32,
) -> Result<ModelManifest, ModelManifestError> {
    ModelManifest::new_verified_metadata(
        model_id,
        ModelFamily::Qwen,
        ModelVariant::AbliteratedOrUncensored,
        ModelFormat::GGUF,
        Quantization::Q4KM,
        ModelSource::BartowskiHuggingFace,
        filename,
        "placeholder-sha256-must-be-replaced-before-use",
        minimum_ram_gb,
        minimum_vram_gb,
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn routes_rtx_4060_class_to_standard_desktop() {
        let profile = HardwareProfile::windows_rtx_4060_class();
        let routed = route_model(&profile).unwrap();

        assert_eq!(routed.tier, ModelTier::StandardDesktop);
        assert_eq!(routed.manifest.family, ModelFamily::Qwen);
        assert_eq!(
            routed.manifest.variant,
            ModelVariant::AbliteratedOrUncensored
        );
        assert_eq!(routed.manifest.format, ModelFormat::GGUF);
        assert_eq!(routed.manifest.quantization, Quantization::Q4KM);
        assert_eq!(routed.manifest.minimum_vram_gb, 8);
    }

    #[test]
    fn routes_high_vram_to_high_end_desktop() {
        let profile = HardwareProfile::new(64, 16, "high-end");
        let routed = route_model(&profile).unwrap();

        assert_eq!(routed.tier, ModelTier::HighEndDesktop);
        assert_eq!(routed.manifest.minimum_vram_gb, 16);
    }

    #[test]
    fn routes_four_gb_vram_to_lightweight() {
        let profile = HardwareProfile::new(16, 4, "low-end-gpu");
        let routed = route_model(&profile).unwrap();

        assert_eq!(routed.tier, ModelTier::Lightweight);
        assert_eq!(routed.manifest.minimum_vram_gb, 4);
    }

    #[test]
    fn routes_no_vram_low_ram_to_edge() {
        let profile = HardwareProfile::new(8, 0, "edge");
        let routed = route_model(&profile).unwrap();

        assert_eq!(routed.tier, ModelTier::Edge);
        assert_eq!(routed.manifest.minimum_vram_gb, 0);
    }

    #[test]
    fn routes_no_vram_but_enough_ram_to_lightweight() {
        let profile = HardwareProfile::new(16, 0, "ram-only");
        let routed = route_model(&profile).unwrap();

        assert_eq!(routed.tier, ModelTier::Lightweight);
    }
}
