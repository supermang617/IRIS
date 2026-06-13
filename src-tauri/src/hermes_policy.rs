use serde::{Deserialize, Serialize};
use std::{
    path::Path,
    sync::{
        Mutex, OnceLock,
        atomic::{AtomicBool, Ordering},
    },
};

pub const AGENTIC_INACTIVITY_TIMEOUT_MS: u128 = 30 * 60 * 1_000;

static HERMES_POLICY: OnceLock<Mutex<HermesPolicyState>> = OnceLock::new();
static AGENTIC_RUNTIME_AVAILABLE: AtomicBool = AtomicBool::new(false);

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum HermesMode {
    Off,
    Safe,
    Agentic,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RiskClass {
    Ordinary,
    DestructiveGit,
    InstallOrAdmin,
    Credentials,
    ConsequentialBrowserSubmission,
    ExecutableDownload,
    Payment,
    SensitiveFiles,
    ScopeExpansion,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AgenticSession {
    pub session_id: String,
    pub workspace_path: String,
    pub created_ms: u128,
    pub last_activity_ms: u128,
    pub expires_at_ms: u128,
    pub inactivity_timeout_ms: u128,
    pub workspace_boundary: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ApprovalRequest {
    pub request_id: String,
    pub risk_class: RiskClass,
    pub summary: String,
    pub requires_separate_confirmation: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BrowserPreview {
    pub url: String,
    pub screenshot_path: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case", tag = "type", content = "payload")]
pub enum HermesEvent {
    Text(String),
    Thinking(bool),
    ToolActivity(String),
    ApprovalRequest(ApprovalRequest),
    BrowserPreview(BrowserPreview),
    Completion(String),
    Error(String),
    Expired,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HermesPolicySnapshot {
    pub mode: HermesMode,
    pub startup_default: HermesMode,
    pub panic_stop_active: bool,
    pub agentic_runtime_available: bool,
    pub agentic_session: Option<AgenticSession>,
}

#[derive(Debug, Clone)]
struct HermesPolicyState {
    mode: HermesMode,
    panic_stop_active: bool,
    agentic_session: Option<AgenticSession>,
    session_sequence: u64,
}

impl Default for HermesPolicyState {
    fn default() -> Self {
        Self {
            mode: HermesMode::Safe,
            panic_stop_active: false,
            agentic_session: None,
            session_sequence: 0,
        }
    }
}

pub fn snapshot(now_ms: u128) -> Result<HermesPolicySnapshot, String> {
    with_state(now_ms, |state| Ok(state.snapshot()))
}

pub fn set_agentic_runtime_available(available: bool) {
    AGENTIC_RUNTIME_AVAILABLE.store(available, Ordering::Relaxed);
}

pub fn set_mode(mode: HermesMode, now_ms: u128) -> Result<HermesPolicySnapshot, String> {
    with_state(now_ms, |state| {
        state.set_mode(mode)?;
        Ok(state.snapshot())
    })
}

pub fn create_agentic_session(
    workspace_path: &Path,
    now_ms: u128,
) -> Result<HermesPolicySnapshot, String> {
    if !workspace_path.is_absolute() {
        return Err("Agentic workspace path must be absolute".to_string());
    }
    if !workspace_path.is_dir() {
        return Err(format!(
            "Agentic workspace does not exist or is not a directory: {}",
            workspace_path.display()
        ));
    }
    let canonical = workspace_path.canonicalize().map_err(|err| {
        format!(
            "failed to resolve Agentic workspace {}: {err}",
            workspace_path.display()
        )
    })?;
    with_state(now_ms, |state| {
        state.create_agentic_session(&canonical, now_ms)?;
        Ok(state.snapshot())
    })
}

pub fn record_agentic_activity(now_ms: u128) -> Result<HermesPolicySnapshot, String> {
    with_state(now_ms, |state| {
        state.record_agentic_activity(now_ms)?;
        Ok(state.snapshot())
    })
}

pub fn end_agentic_session(now_ms: u128) -> Result<HermesPolicySnapshot, String> {
    with_state(now_ms, |state| {
        state.end_agentic_session();
        Ok(state.snapshot())
    })
}

pub fn activate_panic_stop(now_ms: u128) -> Result<HermesPolicySnapshot, String> {
    with_state(now_ms, |state| {
        state.activate_panic_stop();
        Ok(state.snapshot())
    })
}

pub fn clear_panic_stop(now_ms: u128) -> Result<HermesPolicySnapshot, String> {
    with_state(now_ms, |state| {
        state.clear_panic_stop();
        Ok(state.snapshot())
    })
}

fn with_state<T>(
    now_ms: u128,
    operation: impl FnOnce(&mut HermesPolicyState) -> Result<T, String>,
) -> Result<T, String> {
    let state = HERMES_POLICY.get_or_init(|| Mutex::new(HermesPolicyState::default()));
    let mut guard = state
        .lock()
        .map_err(|_| "Hermes policy state is unavailable".to_string())?;
    guard.expire_if_idle(now_ms);
    operation(&mut guard)
}

impl HermesPolicyState {
    fn set_mode(&mut self, mode: HermesMode) -> Result<(), String> {
        if self.panic_stop_active && mode != HermesMode::Off {
            return Err("Panic Stop is active; Hermes must remain Off".to_string());
        }
        match mode {
            HermesMode::Off => {
                self.mode = HermesMode::Off;
                self.agentic_session = None;
            }
            HermesMode::Safe => {
                self.mode = HermesMode::Safe;
                self.agentic_session = None;
            }
            HermesMode::Agentic => {
                if self.agentic_session.is_none() {
                    return Err(
                        "Agentic mode requires a new approved workspace session".to_string()
                    );
                }
                self.mode = HermesMode::Agentic;
            }
        }
        Ok(())
    }

    fn create_agentic_session(
        &mut self,
        workspace_path: &Path,
        now_ms: u128,
    ) -> Result<(), String> {
        if self.panic_stop_active {
            return Err("Panic Stop is active; Agentic session creation is blocked".to_string());
        }
        if self.agentic_session.is_some() {
            return Err("An Agentic Hermes session is already active".to_string());
        }
        self.session_sequence += 1;
        self.agentic_session = Some(AgenticSession {
            session_id: format!(
                "iris-agentic-{now_ms}-{}-{}",
                std::process::id(),
                self.session_sequence
            ),
            workspace_path: workspace_path.to_string_lossy().to_string(),
            created_ms: now_ms,
            last_activity_ms: now_ms,
            expires_at_ms: now_ms + AGENTIC_INACTIVITY_TIMEOUT_MS,
            inactivity_timeout_ms: AGENTIC_INACTIVITY_TIMEOUT_MS,
            workspace_boundary: "advisory_unrestricted_powershell".to_string(),
        });
        self.mode = HermesMode::Agentic;
        Ok(())
    }

    fn record_agentic_activity(&mut self, now_ms: u128) -> Result<(), String> {
        if self.mode != HermesMode::Agentic {
            return Err("Hermes is not in Agentic mode".to_string());
        }
        let session = self
            .agentic_session
            .as_mut()
            .ok_or_else(|| "Agentic session is unavailable".to_string())?;
        session.last_activity_ms = now_ms;
        session.expires_at_ms = now_ms + AGENTIC_INACTIVITY_TIMEOUT_MS;
        Ok(())
    }

    fn end_agentic_session(&mut self) {
        self.agentic_session = None;
        self.mode = if self.panic_stop_active {
            HermesMode::Off
        } else {
            HermesMode::Safe
        };
    }

    fn activate_panic_stop(&mut self) {
        self.panic_stop_active = true;
        self.agentic_session = None;
        self.mode = HermesMode::Off;
    }

    fn clear_panic_stop(&mut self) {
        self.panic_stop_active = false;
        self.agentic_session = None;
        self.mode = HermesMode::Safe;
    }

    fn expire_if_idle(&mut self, now_ms: u128) {
        if self.mode == HermesMode::Agentic
            && self
                .agentic_session
                .as_ref()
                .is_some_and(|session| now_ms >= session.expires_at_ms)
        {
            self.agentic_session = None;
            self.mode = HermesMode::Safe;
        }
    }

    fn snapshot(&self) -> HermesPolicySnapshot {
        HermesPolicySnapshot {
            mode: self.mode,
            startup_default: HermesMode::Safe,
            panic_stop_active: self.panic_stop_active,
            agentic_runtime_available: AGENTIC_RUNTIME_AVAILABLE.load(Ordering::Relaxed),
            agentic_session: self.agentic_session.clone(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_workspace() -> std::path::PathBuf {
        std::env::temp_dir()
    }

    fn isolated_state() -> HermesPolicyState {
        HermesPolicyState::default()
    }

    #[test]
    fn startup_default_is_safe_without_session() {
        let state = isolated_state();
        assert_eq!(state.mode, HermesMode::Safe);
        assert!(state.agentic_session.is_none());
        assert!(!state.panic_stop_active);
    }

    #[test]
    fn independent_process_state_always_starts_safe() {
        let first = isolated_state();
        let second = isolated_state();

        assert_eq!(first.mode, HermesMode::Safe);
        assert_eq!(second.mode, HermesMode::Safe);
        assert!(first.agentic_session.is_none());
        assert!(second.agentic_session.is_none());
    }

    #[test]
    fn agentic_mode_requires_session() {
        let mut state = isolated_state();
        let result = state.set_mode(HermesMode::Agentic);
        assert!(result.is_err());
        assert_eq!(state.mode, HermesMode::Safe);
    }

    #[test]
    fn session_creation_rejects_duplicates_and_refreshes_activity() {
        let mut state = isolated_state();
        state
            .create_agentic_session(&test_workspace(), 100)
            .expect("first Agentic session");
        assert_eq!(state.mode, HermesMode::Agentic);
        assert!(
            state
                .create_agentic_session(&test_workspace(), 200)
                .is_err()
        );

        state
            .record_agentic_activity(300)
            .expect("refresh Agentic session");
        let session = state.agentic_session.expect("active session");
        assert_eq!(session.last_activity_ms, 300);
        assert_eq!(session.expires_at_ms, 300 + AGENTIC_INACTIVITY_TIMEOUT_MS);
    }

    #[test]
    fn session_expires_back_to_safe() {
        let mut state = isolated_state();
        state.mode = HermesMode::Agentic;
        state.agentic_session = Some(AgenticSession {
            session_id: "test".to_string(),
            workspace_path: test_workspace().to_string_lossy().to_string(),
            created_ms: 1,
            last_activity_ms: 1,
            expires_at_ms: 10,
            inactivity_timeout_ms: AGENTIC_INACTIVITY_TIMEOUT_MS,
            workspace_boundary: "advisory_unrestricted_powershell".to_string(),
        });

        state.expire_if_idle(10);

        assert_eq!(state.mode, HermesMode::Safe);
        assert!(state.agentic_session.is_none());
    }

    #[test]
    fn panic_stop_forces_off_and_clear_returns_safe() {
        let mut state = isolated_state();
        state
            .create_agentic_session(&test_workspace(), 100)
            .expect("Agentic session");
        state.activate_panic_stop();
        assert_eq!(state.mode, HermesMode::Off);
        assert!(state.panic_stop_active);
        assert!(state.agentic_session.is_none());
        assert!(state.set_mode(HermesMode::Safe).is_err());

        state.clear_panic_stop();
        assert_eq!(state.mode, HermesMode::Safe);
        assert!(!state.panic_stop_active);
        assert!(state.agentic_session.is_none());
    }

    #[test]
    fn mode_change_ends_agentic_session() {
        let mut state = isolated_state();
        state
            .create_agentic_session(&test_workspace(), 100)
            .expect("Agentic session");

        state.set_mode(HermesMode::Safe).expect("Safe mode");

        assert_eq!(state.mode, HermesMode::Safe);
        assert!(state.agentic_session.is_none());
    }
}
