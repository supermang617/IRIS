#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ModelFamily {
    Qwen,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ModelVariant {
    AbliteratedOrUncensored,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ModelFormat {
    GGUF,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Quantization {
    Q4KM,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ModelSource {
    BartowskiHuggingFace,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ModelManifestError {
    EmptyModelId,
    EmptyFilename,
    EmptySha256,
    ZeroMinimumRam,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ModelManifest {
    pub model_id: String,
    pub family: ModelFamily,
    pub variant: ModelVariant,
    pub format: ModelFormat,
    pub quantization: Quantization,
    pub source: ModelSource,
    pub filename: String,
    pub sha256: String,
    pub minimum_ram_gb: u32,
    pub minimum_vram_gb: u32,
}

impl ModelManifest {
    pub fn new_verified_metadata(
        model_id: impl Into<String>,
        family: ModelFamily,
        variant: ModelVariant,
        format: ModelFormat,
        quantization: Quantization,
        source: ModelSource,
        filename: impl Into<String>,
        sha256: impl Into<String>,
        minimum_ram_gb: u32,
        minimum_vram_gb: u32,
    ) -> Result<Self, ModelManifestError> {
        let model_id = model_id.into();
        let filename = filename.into();
        let sha256 = sha256.into();

        if model_id.trim().is_empty() {
            return Err(ModelManifestError::EmptyModelId);
        }

        if filename.trim().is_empty() {
            return Err(ModelManifestError::EmptyFilename);
        }

        if sha256.trim().is_empty() {
            return Err(ModelManifestError::EmptySha256);
        }

        if minimum_ram_gb == 0 {
            return Err(ModelManifestError::ZeroMinimumRam);
        }

        Ok(Self {
            model_id,
            family,
            variant,
            format,
            quantization,
            source,
            filename,
            sha256,
            minimum_ram_gb,
            minimum_vram_gb,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn valid_manifest() -> Result<ModelManifest, ModelManifestError> {
        ModelManifest::new_verified_metadata(
            "qwen-ab-literated-placeholder",
            ModelFamily::Qwen,
            ModelVariant::AbliteratedOrUncensored,
            ModelFormat::GGUF,
            Quantization::Q4KM,
            ModelSource::BartowskiHuggingFace,
            "placeholder-model.Q4_K_M.gguf",
            "placeholder-sha256-must-be-replaced-before-use",
            8,
            4,
        )
    }

    #[test]
    fn valid_manifest_is_accepted() {
        let manifest = valid_manifest().unwrap();

        assert_eq!(manifest.family, ModelFamily::Qwen);
        assert_eq!(manifest.variant, ModelVariant::AbliteratedOrUncensored);
        assert_eq!(manifest.format, ModelFormat::GGUF);
        assert_eq!(manifest.quantization, Quantization::Q4KM);
        assert_eq!(manifest.source, ModelSource::BartowskiHuggingFace);
        assert_eq!(manifest.minimum_ram_gb, 8);
        assert_eq!(manifest.minimum_vram_gb, 4);
    }

    #[test]
    fn rejects_empty_model_id() {
        let err = ModelManifest::new_verified_metadata(
            "",
            ModelFamily::Qwen,
            ModelVariant::AbliteratedOrUncensored,
            ModelFormat::GGUF,
            Quantization::Q4KM,
            ModelSource::BartowskiHuggingFace,
            "placeholder.gguf",
            "placeholder-sha256",
            8,
            4,
        )
        .unwrap_err();

        assert_eq!(err, ModelManifestError::EmptyModelId);
    }

    #[test]
    fn rejects_empty_filename() {
        let err = ModelManifest::new_verified_metadata(
            "qwen-placeholder",
            ModelFamily::Qwen,
            ModelVariant::AbliteratedOrUncensored,
            ModelFormat::GGUF,
            Quantization::Q4KM,
            ModelSource::BartowskiHuggingFace,
            "",
            "placeholder-sha256",
            8,
            4,
        )
        .unwrap_err();

        assert_eq!(err, ModelManifestError::EmptyFilename);
    }

    #[test]
    fn rejects_empty_sha256() {
        let err = ModelManifest::new_verified_metadata(
            "qwen-placeholder",
            ModelFamily::Qwen,
            ModelVariant::AbliteratedOrUncensored,
            ModelFormat::GGUF,
            Quantization::Q4KM,
            ModelSource::BartowskiHuggingFace,
            "placeholder.gguf",
            "",
            8,
            4,
        )
        .unwrap_err();

        assert_eq!(err, ModelManifestError::EmptySha256);
    }

    #[test]
    fn rejects_zero_minimum_ram() {
        let err = ModelManifest::new_verified_metadata(
            "qwen-placeholder",
            ModelFamily::Qwen,
            ModelVariant::AbliteratedOrUncensored,
            ModelFormat::GGUF,
            Quantization::Q4KM,
            ModelSource::BartowskiHuggingFace,
            "placeholder.gguf",
            "placeholder-sha256",
            0,
            4,
        )
        .unwrap_err();

        assert_eq!(err, ModelManifestError::ZeroMinimumRam);
    }
}
