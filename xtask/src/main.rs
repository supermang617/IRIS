use std::env;
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Debug)]
struct Finding {
    path: PathBuf,
    needle: String,
}

fn main() {
    let root = env::current_dir().expect("failed to read current directory");
    let findings = audit_repo(&root);

    if findings.is_empty() {
        println!("Project Iris xtask audit passed.");
        return;
    }

    eprintln!("Project Iris xtask audit failed.");
    eprintln!("Forbidden runtime/API string findings: {}", findings.len());

    for finding in findings {
        eprintln!("{} :: {}", finding.path.display(), finding.needle);
    }

    std::process::exit(1);
}

fn audit_repo(root: &Path) -> Vec<Finding> {
    let mut findings = Vec::new();
    scan_dir(root, root, &mut findings);
    findings
}

fn scan_dir(root: &Path, dir: &Path, findings: &mut Vec<Finding>) {
    let Ok(entries) = fs::read_dir(dir) else {
        return;
    };

    for entry in entries.flatten() {
        let path = entry.path();

        if should_skip_path(root, &path) {
            continue;
        }

        if path.is_dir() {
            scan_dir(root, &path, findings);
        } else if should_scan_file(&path) {
            scan_file(&path, findings);
        }
    }
}

fn should_skip_path(root: &Path, path: &Path) -> bool {
    let relative = path.strip_prefix(root).unwrap_or(path);

    if relative == Path::new("AGENTS.md") {
        return true;
    }

    if relative == Path::new("xtask").join("src").join("main.rs") {
        return true;
    }

    relative.components().any(|component| {
        let text = component.as_os_str().to_string_lossy();
        matches!(text.as_ref(), ".git" | "target" | ".vs" | ".codex")
    })
}

fn should_scan_file(path: &Path) -> bool {
    matches!(
        path.extension().and_then(|ext| ext.to_str()),
        Some("rs" | "toml")
    )
}

fn scan_file(path: &Path, findings: &mut Vec<Finding>) {
    let Ok(content) = fs::read_to_string(path) else {
        return;
    };

    for needle in forbidden_needles() {
        if content.contains(&needle) {
            findings.push(Finding {
                path: path.to_path_buf(),
                needle,
            });
        }
    }
}

fn forbidden_needles() -> Vec<String> {
    vec![
        make(&["std::process", "::Command"]),
        make(&["Command", "::new"]),
        make(&["clip", "board"]),
        make(&["Send", "Input"]),
        make(&["mouse", "_event"]),
        make(&["keybd", "_event"]),
        make(&["req", "west"]),
        make(&["hy", "per"]),
        make(&["tokio", "::net"]),
        make(&["std", "::net"]),
        make(&["tauri", "_plugin", "_shell"]),
        make(&["power", "shell"]),
        make(&["cmd", ".exe"]),
    ]
}

fn make(parts: &[&str]) -> String {
    parts.join("")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn forbidden_needles_include_process_command() {
        assert!(
            forbidden_needles()
                .iter()
                .any(|needle| needle == "std::process::Command")
        );
    }

    #[test]
    fn scans_rust_and_toml() {
        assert!(should_scan_file(Path::new("src/main.rs")));
        assert!(should_scan_file(Path::new("Cargo.toml")));
        assert!(!should_scan_file(Path::new("README.md")));
        assert!(!should_scan_file(Path::new("image.png")));
    }

    #[test]
    fn skips_agent_instruction_file_and_self() {
        let root = Path::new("C:/Projects/IRIS");

        assert!(should_skip_path(
            root,
            Path::new("C:/Projects/IRIS/AGENTS.md")
        ));
        assert!(should_skip_path(
            root,
            Path::new("C:/Projects/IRIS/xtask/src/main.rs")
        ));
    }
}
