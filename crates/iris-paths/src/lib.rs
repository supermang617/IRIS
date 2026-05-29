use std::path::{Component, Path, PathBuf};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum IrisPathError {
    EmptyRelativePath,
    AbsolutePathRejected,
    ParentTraversalRejected,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct IrisRoots {
    root: PathBuf,
}

impl IrisRoots {
    pub fn new(root: impl Into<PathBuf>) -> Self {
        Self { root: root.into() }
    }

    pub fn root(&self) -> &Path {
        &self.root
    }

    pub fn resolve_child(&self, relative_path: impl AsRef<Path>) -> Result<PathBuf, IrisPathError> {
        let relative_path = relative_path.as_ref();

        if relative_path.as_os_str().is_empty() {
            return Err(IrisPathError::EmptyRelativePath);
        }

        if relative_path.is_absolute() {
            return Err(IrisPathError::AbsolutePathRejected);
        }

        for component in relative_path.components() {
            match component {
                Component::ParentDir => return Err(IrisPathError::ParentTraversalRejected),
                Component::Prefix(_) | Component::RootDir => {
                    return Err(IrisPathError::AbsolutePathRejected);
                }
                _ => {}
            }
        }

        Ok(self.root.join(relative_path))
    }

    pub fn config_path(
        &self,
        relative_path: impl AsRef<Path>,
    ) -> Result<ConfigPath, IrisPathError> {
        Ok(ConfigPath(self.resolve_child(relative_path)?))
    }

    pub fn log_path(&self, relative_path: impl AsRef<Path>) -> Result<LogPath, IrisPathError> {
        Ok(LogPath(self.resolve_child(relative_path)?))
    }

    pub fn cache_path(&self, relative_path: impl AsRef<Path>) -> Result<CachePath, IrisPathError> {
        Ok(CachePath(self.resolve_child(relative_path)?))
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ConfigPath(PathBuf);

impl ConfigPath {
    pub fn as_path(&self) -> &Path {
        &self.0
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LogPath(PathBuf);

impl LogPath {
    pub fn as_path(&self) -> &Path {
        &self.0
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CachePath(PathBuf);

impl CachePath {
    pub fn as_path(&self) -> &Path {
        &self.0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_relative_path_inside_root() {
        let roots = IrisRoots::new(PathBuf::from("C:/IrisData"));
        let path = roots.config_path("config/settings.toml").unwrap();

        assert_eq!(
            path.as_path(),
            Path::new("C:/IrisData").join("config/settings.toml")
        );
    }

    #[test]
    fn rejects_parent_traversal() {
        let roots = IrisRoots::new(PathBuf::from("C:/IrisData"));
        let err = roots.config_path("../outside.toml").unwrap_err();

        assert_eq!(err, IrisPathError::ParentTraversalRejected);
    }

    #[test]
    fn rejects_nested_parent_traversal() {
        let roots = IrisRoots::new(PathBuf::from("C:/IrisData"));
        let err = roots.log_path("logs/../../outside.log").unwrap_err();

        assert_eq!(err, IrisPathError::ParentTraversalRejected);
    }

    #[test]
    fn rejects_absolute_path_outside_root() {
        let roots = IrisRoots::new(PathBuf::from("C:/IrisData"));

        #[cfg(windows)]
        let err = roots
            .cache_path("C:/Windows/System32/file.bin")
            .unwrap_err();

        #[cfg(not(windows))]
        let err = roots.cache_path("/etc/passwd").unwrap_err();

        assert_eq!(err, IrisPathError::AbsolutePathRejected);
    }

    #[test]
    fn typed_wrappers_preserve_paths() {
        let roots = IrisRoots::new(PathBuf::from("C:/IrisData"));

        let config = roots.config_path("config/app.toml").unwrap();
        let log = roots.log_path("logs/app.log").unwrap();
        let cache = roots.cache_path("cache/data.bin").unwrap();

        assert_eq!(config.as_path(), Path::new("C:/IrisData/config/app.toml"));
        assert_eq!(log.as_path(), Path::new("C:/IrisData/logs/app.log"));
        assert_eq!(cache.as_path(), Path::new("C:/IrisData/cache/data.bin"));
    }
}
