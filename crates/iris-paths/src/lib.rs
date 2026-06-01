use std::fmt;
use std::fs;
use std::path::{Component, Path, PathBuf};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum IrisPathArea {
    Config,
    Logs,
    Cache,
    Memory,
    Models,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OwnedPath {
    area: IrisPathArea,
    path: PathBuf,
}

impl OwnedPath {
    pub fn path(&self) -> &Path {
        &self.path
    }

    pub fn area(&self) -> &IrisPathArea {
        &self.area
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PathError {
    AbsolutePathRejected,
    TraversalRejected,
    Io(String),
    EscapeRejected,
}

impl fmt::Display for PathError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::AbsolutePathRejected => write!(f, "absolute paths are not accepted"),
            Self::TraversalRejected => write!(f, "path traversal is not accepted"),
            Self::Io(message) => write!(f, "{message}"),
            Self::EscapeRejected => write!(f, "path escapes the Iris-owned root"),
        }
    }
}

#[derive(Debug, Clone)]
pub struct IrisRoots {
    root: PathBuf,
}

impl IrisRoots {
    pub fn new(root: impl Into<PathBuf>) -> Result<Self, PathError> {
        let root = root.into();
        fs::create_dir_all(&root).map_err(|err| PathError::Io(err.to_string()))?;
        let root = root
            .canonicalize()
            .map_err(|err| PathError::Io(err.to_string()))?;
        Ok(Self { root })
    }

    pub fn root(&self) -> &Path {
        &self.root
    }

    pub fn area_root(&self, area: &IrisPathArea) -> PathBuf {
        let name = match area {
            IrisPathArea::Config => "config",
            IrisPathArea::Logs => "logs",
            IrisPathArea::Cache => "cache",
            IrisPathArea::Memory => "memory",
            IrisPathArea::Models => "models",
        };
        self.root.join(name)
    }

    pub fn resolve_owned(
        &self,
        area: IrisPathArea,
        relative: impl AsRef<Path>,
    ) -> Result<OwnedPath, PathError> {
        let relative = relative.as_ref();
        if relative.is_absolute() {
            return Err(PathError::AbsolutePathRejected);
        }
        reject_traversal(relative)?;

        let area_root = self.area_root(&area);
        fs::create_dir_all(&area_root).map_err(|err| PathError::Io(err.to_string()))?;
        let candidate = area_root.join(relative);
        if !candidate.starts_with(&self.root) {
            return Err(PathError::EscapeRejected);
        }
        Ok(OwnedPath {
            area,
            path: candidate,
        })
    }
}

fn reject_traversal(path: &Path) -> Result<(), PathError> {
    for component in path.components() {
        match component {
            Component::ParentDir | Component::RootDir | Component::Prefix(_) => {
                return Err(PathError::TraversalRejected);
            }
            Component::CurDir | Component::Normal(_) => {}
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_root(name: &str) -> PathBuf {
        let mut root = std::env::temp_dir();
        root.push(format!(
            "iris_paths_{name}_{}",
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .expect("clock works")
                .as_nanos()
        ));
        root
    }

    #[test]
    fn resolves_owned_child_path() {
        let roots = IrisRoots::new(test_root("child")).expect("roots");
        let path = roots
            .resolve_owned(IrisPathArea::Config, "settings.json")
            .expect("owned path");
        assert!(path.path().starts_with(roots.root()));
        assert_eq!(path.area(), &IrisPathArea::Config);
    }

    #[test]
    fn rejects_parent_traversal() {
        let roots = IrisRoots::new(test_root("traversal")).expect("roots");
        let err = roots
            .resolve_owned(IrisPathArea::Logs, "../outside.log")
            .expect_err("traversal must fail");
        assert_eq!(err, PathError::TraversalRejected);
    }

    #[test]
    fn rejects_absolute_paths() {
        let roots = IrisRoots::new(test_root("absolute")).expect("roots");
        let err = roots
            .resolve_owned(IrisPathArea::Cache, roots.root().join("file.txt"))
            .expect_err("absolute path must fail");
        assert_eq!(err, PathError::AbsolutePathRejected);
    }
}
