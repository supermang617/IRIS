use iris_model_manifest::ModelManifest;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ModelStoreError {
    EmptyRoot,
    EmptyFilename,
    AbsoluteFilenameRejected,
    ParentTraversalRejected,
    BackslashRejected,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ModelStoreRoot {
    root: String,
}

impl ModelStoreRoot {
    pub fn new(root: impl Into<String>) -> Result<Self, ModelStoreError> {
        let root = root.into();

        if root.trim().is_empty() {
            return Err(ModelStoreError::EmptyRoot);
        }

        Ok(Self { root })
    }

    pub fn iris_user_models() -> Self {
        Self {
            root: "~/.iris/models".to_string(),
        }
    }

    pub fn as_str(&self) -> &str {
        &self.root
    }

    pub fn model_path_for_manifest(
        &self,
        manifest: &ModelManifest,
    ) -> Result<ModelStorePath, ModelStoreError> {
        self.model_path_for_filename(&manifest.filename)
    }

    pub fn model_path_for_filename(
        &self,
        filename: &str,
    ) -> Result<ModelStorePath, ModelStoreError> {
        validate_model_filename(filename)?;

        Ok(ModelStorePath {
            value: format!("{}/{}", self.root.trim_end_matches('/'), filename),
        })
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ModelStorePath {
    value: String,
}

impl ModelStorePath {
    pub fn as_str(&self) -> &str {
        &self.value
    }
}

pub fn validate_model_filename(filename: &str) -> Result<(), ModelStoreError> {
    if filename.trim().is_empty() {
        return Err(ModelStoreError::EmptyFilename);
    }

    if filename.starts_with('/') {
        return Err(ModelStoreError::AbsoluteFilenameRejected);
    }

    if filename.contains('\\') {
        return Err(ModelStoreError::BackslashRejected);
    }

    if filename
        .split('/')
        .any(|part| part == ".." || part.trim().is_empty())
    {
        return Err(ModelStoreError::ParentTraversalRejected);
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use iris_model_manifest::{
        ModelFamily, ModelFormat, ModelManifest, ModelSource, ModelVariant, Quantization,
    };

    fn test_manifest(filename: &str) -> ModelManifest {
        ModelManifest::new_verified_metadata(
            "qwen-placeholder",
            ModelFamily::Qwen,
            ModelVariant::AbliteratedOrUncensored,
            ModelFormat::GGUF,
            Quantization::Q4KM,
            ModelSource::BartowskiHuggingFace,
            filename,
            "placeholder-sha256",
            16,
            8,
        )
        .unwrap()
    }

    #[test]
    fn accepts_safe_model_filename() {
        assert_eq!(validate_model_filename("qwen-model.Q4_K_M.gguf"), Ok(()));
    }

    #[test]
    fn rejects_empty_filename() {
        assert_eq!(
            validate_model_filename(""),
            Err(ModelStoreError::EmptyFilename)
        );
    }

    #[test]
    fn rejects_absolute_filename() {
        assert_eq!(
            validate_model_filename("/tmp/model.gguf"),
            Err(ModelStoreError::AbsoluteFilenameRejected)
        );
    }

    #[test]
    fn rejects_parent_traversal() {
        assert_eq!(
            validate_model_filename("../model.gguf"),
            Err(ModelStoreError::ParentTraversalRejected)
        );
    }

    #[test]
    fn rejects_backslashes() {
        assert_eq!(
            validate_model_filename("folder\\model.gguf"),
            Err(ModelStoreError::BackslashRejected)
        );
    }

    #[test]
    fn builds_default_model_path() {
        let root = ModelStoreRoot::iris_user_models();
        let manifest = test_manifest("qwen-placeholder.Q4_K_M.gguf");
        let path = root.model_path_for_manifest(&manifest).unwrap();

        assert_eq!(path.as_str(), "~/.iris/models/qwen-placeholder.Q4_K_M.gguf");
    }

    #[test]
    fn custom_root_builds_model_path() {
        let root = ModelStoreRoot::new("C:/Users/test/.iris/models").unwrap();
        let path = root.model_path_for_filename("model.gguf").unwrap();

        assert_eq!(path.as_str(), "C:/Users/test/.iris/models/model.gguf");
    }
}
