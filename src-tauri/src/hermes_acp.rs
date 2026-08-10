use crate::hermes_policy::{ApprovalRequest, BrowserPreview, HermesEvent, RiskClass};
use serde::Serialize;
use serde_json::{Value, json};
use std::{
    collections::{HashMap, VecDeque},
    fs::{self, OpenOptions},
    io::{BufRead, BufReader, Write},
    path::{Path, PathBuf},
    process::{Child, ChildStdin, Command, Stdio},
    sync::{
        Arc, Mutex, OnceLock,
        atomic::{AtomicU64, Ordering},
        mpsc,
    },
    thread,
    time::{Duration, SystemTime, UNIX_EPOCH},
};

#[cfg(windows)]
use std::os::windows::{io::AsRawHandle, process::CommandExt};
#[cfg(windows)]
use windows::Win32::{
    Foundation::{CloseHandle, HANDLE},
    System::JobObjects::{
        AssignProcessToJobObject, CreateJobObjectW, JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE,
        JOBOBJECT_EXTENDED_LIMIT_INFORMATION, JobObjectExtendedLimitInformation,
        SetInformationJobObject, TerminateJobObject,
    },
};

#[cfg(windows)]
const CREATE_NO_WINDOW: u32 = 0x08000000;
const ACP_REQUEST_TIMEOUT: Duration = Duration::from_secs(240);
const MAX_CONSECUTIVE_MALFORMED_ACP_LINES: usize = 3;
const MAX_ACP_LINE_BYTES: usize = 1_048_576;
const MAX_ACP_TASK_EVENT_BYTES: usize = 8 * 1024 * 1024;
const MAX_ACP_TASK_EVENTS: usize = 4_096;
const MAX_HERMES_STDERR_LINE_BYTES: usize = 16 * 1024;
pub(crate) const MAX_HERMES_STDERR_BYTES: u64 = 512 * 1024;
const HERMES_AGENT_VERSION: &str = "0.18.0";
const ACP_PACKAGE_VERSION: &str = "0.9.0";
const PYJWT_VERSION: &str = "2.13.0";
const KOKORO_ONNX_VERSION: &str = "0.5.0";
const SOUNDFILE_VERSION: &str = "0.14.0";
const HERMES_WHEEL_SHA256: &str =
    "bf75c02d59f7c464cd0d85026fb7ee2e6bb15f003beccab3442b572f1ae1fd37";

static ACP_BRIDGE: OnceLock<Mutex<Option<Arc<HermesAcpBridge>>>> = OnceLock::new();
static HERMES_PYTHON: OnceLock<Option<PythonLaunch>> = OnceLock::new();
static VOICE_PYTHON: OnceLock<Option<PythonLaunch>> = OnceLock::new();
static MEMORY_BROKER_ACCESS: OnceLock<MemoryBrokerAccess> = OnceLock::new();
#[cfg(test)]
static TEST_MEMORY_BROKER_ACCESS: OnceLock<Mutex<Option<MemoryBrokerAccess>>> = OnceLock::new();

#[derive(Clone)]
struct MemoryBrokerAccess {
    url: Arc<str>,
    bearer_token: Arc<str>,
}

type AcpResponse = Result<Value, String>;
type PendingRequestMap = HashMap<u64, mpsc::Sender<AcpResponse>>;
type SharedPendingRequests = Arc<Mutex<PendingRequestMap>>;
type SharedPendingApproval = Arc<Mutex<Option<PendingAcpApproval>>>;
type AcpEventSink = Arc<Mutex<BoundedAcpEvents>>;
type SharedAcpEventSink = Arc<Mutex<Option<AcpEventSink>>>;

pub fn configure_memory_broker(url: &str, bearer_token: &str) -> Result<(), String> {
    let access = validated_memory_broker_access(url, bearer_token)?;
    if let Err(candidate) = MEMORY_BROKER_ACCESS.set(access) {
        let existing = MEMORY_BROKER_ACCESS
            .get()
            .ok_or_else(|| "Hermes memory broker credential state is unavailable".to_string())?;
        if existing.url.as_ref() != candidate.url.as_ref()
            || existing.bearer_token.as_ref() != candidate.bearer_token.as_ref()
        {
            return Err("Hermes memory broker credential is already configured".to_string());
        }
    }
    Ok(())
}

fn validated_memory_broker_access(
    url: &str,
    bearer_token: &str,
) -> Result<MemoryBrokerAccess, String> {
    let port = url
        .strip_prefix("http://127.0.0.1:")
        .and_then(|value| value.parse::<u16>().ok())
        .filter(|port| *port != 0)
        .ok_or_else(|| "Hermes memory broker endpoint must be ephemeral loopback".to_string())?;
    if url != format!("http://127.0.0.1:{port}") {
        return Err("Hermes memory broker endpoint must be ephemeral loopback".to_string());
    }
    if bearer_token.len() != 64 || !bearer_token.as_bytes().iter().all(u8::is_ascii_hexdigit) {
        return Err("Hermes memory broker credential is invalid".to_string());
    }
    Ok(MemoryBrokerAccess {
        url: Arc::from(url),
        bearer_token: Arc::from(bearer_token),
    })
}

fn configured_memory_broker_access() -> Option<MemoryBrokerAccess> {
    #[cfg(test)]
    if let Some(access) = TEST_MEMORY_BROKER_ACCESS
        .get_or_init(|| Mutex::new(None))
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .clone()
    {
        return Some(access);
    }
    MEMORY_BROKER_ACCESS.get().cloned()
}

#[cfg(test)]
fn configure_test_memory_broker(url: &str, bearer_token: &str) -> Result<(), String> {
    let access = validated_memory_broker_access(url, bearer_token)?;
    *TEST_MEMORY_BROKER_ACCESS
        .get_or_init(|| Mutex::new(None))
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner()) = Some(access);
    Ok(())
}

#[cfg(test)]
fn clear_test_memory_broker() {
    *TEST_MEMORY_BROKER_ACCESS
        .get_or_init(|| Mutex::new(None))
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner()) = None;
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HermesAcpRuntimeStatus {
    pub installed: bool,
    pub running: bool,
    pub initialized: bool,
    pub version: &'static str,
    pub wheel_sha256: &'static str,
    pub launcher_path: String,
    pub python_path: String,
    pub stderr_log_path: String,
    pub exposed_tools: Vec<&'static str>,
    pub memory_tools_enabled: bool,
    pub action_tools_enabled: bool,
    pub browser_tools_enabled: bool,
    pub durable_memory_enabled: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct PythonLaunch {
    executable: PathBuf,
    prefix_args: Vec<String>,
}

impl PythonLaunch {
    fn display(&self) -> String {
        std::iter::once(self.executable.to_string_lossy().to_string())
            .chain(self.prefix_args.iter().cloned())
            .collect::<Vec<_>>()
            .join(" ")
    }
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HermesAcpTaskResult {
    pub text: String,
    pub events: Vec<HermesEvent>,
    pub provenance: Vec<HermesProvenance>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HermesProvenance {
    pub authority: String,
    pub source: String,
    pub memory_id: Option<u64>,
    pub staging_id: Option<u64>,
    pub evidence: Option<String>,
}

struct HermesAcpBridge {
    child: Arc<Mutex<Child>>,
    stdin: Arc<Mutex<ChildStdin>>,
    pending: SharedPendingRequests,
    pending_approval: SharedPendingApproval,
    event_sink: SharedAcpEventSink,
    next_request_id: AtomicU64,
    session: Arc<Mutex<Option<AcpSession>>>,
    browser_command_output_dir: PathBuf,
    #[cfg(windows)]
    job: WindowsJob,
}

#[derive(Default)]
struct BoundedAcpEvents {
    values: VecDeque<Value>,
    total_bytes: usize,
}

impl BoundedAcpEvents {
    fn push(&mut self, value: Value) {
        let Ok(bytes) = serde_json::to_vec(&value).map(|bytes| bytes.len()) else {
            return;
        };
        if bytes > MAX_ACP_TASK_EVENT_BYTES {
            return;
        }
        while self.values.len() >= MAX_ACP_TASK_EVENTS
            || self.total_bytes.saturating_add(bytes) > MAX_ACP_TASK_EVENT_BYTES
        {
            let Some(removed) = self.values.pop_front() else {
                break;
            };
            self.total_bytes = self
                .total_bytes
                .saturating_sub(serde_json::to_vec(&removed).map_or(0, |bytes| bytes.len()));
        }
        self.total_bytes = self.total_bytes.saturating_add(bytes);
        self.values.push_back(value);
    }

    fn snapshot(&self) -> Vec<Value> {
        self.values.iter().cloned().collect()
    }
}

struct AcpEventRegistration {
    registry: SharedAcpEventSink,
    sink: AcpEventSink,
}

impl Drop for AcpEventRegistration {
    fn drop(&mut self) {
        if let Ok(mut current) = self.registry.lock()
            && current
                .as_ref()
                .is_some_and(|active| Arc::ptr_eq(active, &self.sink))
        {
            *current = None;
        }
    }
}

#[derive(Debug, Clone)]
struct AcpSession {
    id: String,
    workspace_path: String,
}

#[derive(Debug, Clone)]
struct PendingAcpApproval {
    rpc_id: Value,
    request: ApprovalRequest,
    allow_once_option: Option<String>,
}

#[cfg(windows)]
struct WindowsJob {
    handle: HANDLE,
}

#[cfg(windows)]
unsafe impl Send for WindowsJob {}
#[cfg(windows)]
unsafe impl Sync for WindowsJob {}

#[cfg(windows)]
impl WindowsJob {
    fn create_and_assign(child: &Child) -> Result<Self, String> {
        let handle = unsafe { CreateJobObjectW(None, None) }.map_err(|err| err.to_string())?;
        let mut limits = JOBOBJECT_EXTENDED_LIMIT_INFORMATION::default();
        limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
        unsafe {
            SetInformationJobObject(
                handle,
                JobObjectExtendedLimitInformation,
                std::ptr::addr_of!(limits).cast(),
                std::mem::size_of::<JOBOBJECT_EXTENDED_LIMIT_INFORMATION>() as u32,
            )
            .map_err(|err| err.to_string())?;
            AssignProcessToJobObject(handle, HANDLE(child.as_raw_handle()))
                .map_err(|err| err.to_string())?;
        }
        Ok(Self { handle })
    }

    fn terminate(&self) {
        let _ = unsafe { TerminateJobObject(self.handle, 1) };
    }
}

#[cfg(windows)]
impl Drop for WindowsJob {
    fn drop(&mut self) {
        self.terminate();
        let _ = unsafe { CloseHandle(self.handle) };
    }
}

pub fn runtime_status(resource_root: &Path, state_root: &Path) -> HermesAcpRuntimeStatus {
    let paths = RuntimePaths::new(resource_root, state_root);
    let python = hermes_python(&paths);
    let browser_exe = resource_root
        .join(".iris-runtime/browser/node_modules/agent-browser/bin/agent-browser-win32-x64.exe");
    let browser_tools_enabled =
        browser_exe.is_file() && browser_executable(resource_root).is_some();
    let running = ACP_BRIDGE
        .get()
        .and_then(|state| state.lock().ok())
        .and_then(|guard| guard.as_ref().cloned())
        .is_some_and(|bridge| bridge.is_running());
    HermesAcpRuntimeStatus {
        installed: python.is_some()
            && paths.site_packages.is_dir()
            && paths.launcher.is_file()
            && browser_tools_enabled,
        running,
        initialized: running,
        version: HERMES_AGENT_VERSION,
        wheel_sha256: HERMES_WHEEL_SHA256,
        launcher_path: paths.launcher.to_string_lossy().to_string(),
        python_path: python.map_or_else(String::new, |python| python.display()),
        stderr_log_path: paths.stderr_log.to_string_lossy().to_string(),
        exposed_tools: vec![
            "iris_query_memory",
            "iris_propose_memory",
            "read_file",
            "write_file",
            "patch",
            "search_files",
            "terminal",
            "process",
            "browser_open",
            "browser_snapshot",
            "browser_click",
            "browser_fill",
            "browser_press",
            "browser_screenshot",
            "browser_get_url",
            "browser_upload",
            "browser_download",
            "browser_close",
        ],
        memory_tools_enabled: true,
        action_tools_enabled: true,
        browser_tools_enabled,
        durable_memory_enabled: false,
    }
}

fn browser_executable(resource_root: &Path) -> Option<PathBuf> {
    let configured = std::env::var_os("IRIS_BROWSER_EXECUTABLE_PATH").map(PathBuf::from);
    let mut candidates = Vec::new();
    for (variable, relative) in [
        ("ProgramFiles", "Google/Chrome/Application/chrome.exe"),
        ("ProgramFiles(x86)", "Google/Chrome/Application/chrome.exe"),
        ("LOCALAPPDATA", "Google/Chrome/Application/chrome.exe"),
    ] {
        if let Some(root) = std::env::var_os(variable).filter(|value| !value.is_empty()) {
            candidates.push(PathBuf::from(root).join(relative));
        }
    }
    // Source checkouts may retain the pinned development browser. Production
    // packages intentionally omit it and use the WinGet-managed system Chrome.
    candidates.push(
        resource_root.join(".iris-runtime/browser/browsers/chrome-149.0.7827.115/chrome.exe"),
    );
    select_browser_executable(configured, candidates)
}

fn select_browser_executable(
    configured: Option<PathBuf>,
    candidates: impl IntoIterator<Item = PathBuf>,
) -> Option<PathBuf> {
    if let Some(configured) = configured {
        return (configured.is_absolute() && configured.is_file()).then_some(configured);
    }
    candidates.into_iter().find(|candidate| candidate.is_file())
}

pub fn submit_task(
    resource_root: &Path,
    state_root: &Path,
    workspace_path: &str,
    model: &str,
    text: &str,
) -> Result<HermesAcpTaskResult, String> {
    let clean = text.trim();
    if clean.is_empty() {
        return Err("Agentic Hermes task cannot be empty".to_string());
    }
    let bridge = ensure_bridge(resource_root, state_root, model)?;
    let session_id = bridge.ensure_session(workspace_path)?;
    let event_sink = Arc::new(Mutex::new(BoundedAcpEvents::default()));
    let event_registration = register_acp_event_sink(&bridge.event_sink, event_sink.clone())?;
    let first_response = bridge.request(
        "session/prompt",
        json!({
            "sessionId": session_id,
            "prompt": [{"type": "text", "text": clean}]
        }),
    );
    let initial_events = acp_event_snapshot(&event_sink)?;
    let mut text = assistant_text_from_notifications(&initial_events);
    let response = if first_response.is_ok() && is_empty_agent_text(&text) {
        bridge.request(
            "session/prompt",
            json!({
                "sessionId": session_id,
                "prompt": [{
                    "type": "text",
                    "text": "Your previous final response was empty. Do not rerun the tool. Reply now with a concise, non-empty answer using the successful tool result already in this conversation."
                }]
            }),
        )
    } else {
        first_response
    };
    response?;
    drop(event_registration);
    let raw_events = acp_event_snapshot(&event_sink)?;
    let mut events = Vec::new();
    let mut thinking_emitted = false;
    for event in raw_events.iter().filter_map(event_from_notification) {
        if matches!(event, HermesEvent::Text(_)) {
            continue;
        }
        if matches!(event, HermesEvent::Thinking(true)) {
            if thinking_emitted {
                continue;
            }
            thinking_emitted = true;
        }
        events.push(event);
    }
    events.extend(
        browser_previews_from_notifications(&raw_events)
            .into_iter()
            .map(HermesEvent::BrowserPreview),
    );
    text = assistant_text_from_notifications(&raw_events);
    let provenance = provenance_from_notifications(&raw_events);
    append_action_audit(state_root, &session_id, &raw_events)?;
    reject_repeated_tool_failures(&raw_events)?;
    if is_empty_agent_text(&text) {
        text = fallback_text_from_successful_tool(&raw_events)
            .ok_or_else(|| "Hermes ACP returned no assistant text".to_string())?;
    }
    if !text.is_empty() {
        events.push(HermesEvent::Text(text.clone()));
    }
    events.push(HermesEvent::Thinking(false));
    events.push(HermesEvent::Completion(text.clone()));
    Ok(HermesAcpTaskResult {
        text,
        events,
        provenance,
    })
}

fn register_acp_event_sink(
    registry: &SharedAcpEventSink,
    sink: AcpEventSink,
) -> Result<AcpEventRegistration, String> {
    let mut current = registry
        .lock()
        .map_err(|_| "Hermes ACP event state is unavailable".to_string())?;
    if current.is_some() {
        return Err("Hermes ACP already has an active task".to_string());
    }
    *current = Some(sink.clone());
    drop(current);
    Ok(AcpEventRegistration {
        registry: registry.clone(),
        sink,
    })
}

fn acp_event_snapshot(sink: &AcpEventSink) -> Result<Vec<Value>, String> {
    sink.lock()
        .map_err(|_| "Hermes ACP event buffer is unavailable".to_string())
        .map(|events| events.snapshot())
}

fn push_acp_event(sink: &AcpEventSink, value: Value) {
    if let Ok(mut events) = sink.lock() {
        events.push(value);
    }
}

fn assistant_text_from_notifications(notifications: &[Value]) -> String {
    let chunks = notifications
        .iter()
        .filter_map(agent_message_text)
        .collect::<Vec<_>>();
    assistant_text_from_chunks(&chunks)
}

fn assistant_text_from_chunks(chunks: &[String]) -> String {
    let mut output = String::new();
    for chunk in chunks
        .iter()
        .map(|chunk| chunk.as_str())
        .filter(|chunk| !chunk.is_empty())
    {
        if output.is_empty() {
            output.push_str(chunk);
        } else if chunk.starts_with(&output) {
            output.clear();
            output.push_str(chunk);
        } else if output.ends_with(chunk) || is_retry_fragment(&output, chunk) {
            continue;
        } else {
            let overlap = suffix_prefix_overlap_len(&output, chunk);
            output.push_str(&chunk[overlap..]);
        }
    }
    output.trim().to_string()
}

fn is_retry_fragment(output: &str, chunk: &str) -> bool {
    if output.chars().count() < 4 || chunk.chars().count() > 2 {
        return false;
    }
    let Some(first) = output.chars().next() else {
        return false;
    };
    chunk.chars().all(|character| character == first)
}

fn suffix_prefix_overlap_len(left: &str, right: &str) -> usize {
    let left_chars = left.chars().collect::<Vec<_>>();
    let right_chars = right.chars().collect::<Vec<_>>();
    let max = left_chars.len().min(right_chars.len());
    let mut best = 0;
    for width in 1..=max {
        if left_chars[left_chars.len() - width..] == right_chars[..width] {
            best = width;
        }
    }
    if best == 0 {
        return 0;
    }
    right
        .char_indices()
        .nth(best)
        .map(|(index, _)| index)
        .unwrap_or(right.len())
}

fn is_empty_agent_text(text: &str) -> bool {
    let trimmed = text.trim();
    let unfenced = if trimmed.starts_with("```") {
        trimmed
            .lines()
            .skip(1)
            .filter(|line| line.trim() != "```")
            .collect::<Vec<_>>()
            .join("\n")
    } else {
        trimmed.to_string()
    };
    let normalized = unfenced.trim().to_ascii_lowercase();
    normalized.is_empty()
        || matches!(
            normalized.as_str(),
            "(empty)" | "empty" | "(no content)" | "no content"
        )
}

fn fallback_text_from_successful_tool(notifications: &[Value]) -> Option<String> {
    notifications.iter().rev().find_map(|notification| {
        let update = notification.get("params")?.get("update")?;
        if update.get("sessionUpdate").and_then(Value::as_str) != Some("tool_call_update")
            || update.get("status").and_then(Value::as_str) != Some("completed")
        {
            return None;
        }
        let detail = tool_event_detail(update);
        (!detail.trim().is_empty()).then(|| {
            format!(
                "Hermes completed the requested tool action.\n{}",
                redact_and_truncate(&detail, 1_500)
            )
        })
    })
}

pub fn stop() {
    let Some(state) = ACP_BRIDGE.get() else {
        return;
    };
    let bridge = state.lock().ok().and_then(|mut guard| guard.take());
    if let Some(bridge) = bridge {
        bridge.terminate();
    }
}

pub fn pending_approval() -> Option<ApprovalRequest> {
    let bridge = ACP_BRIDGE
        .get()
        .and_then(|state| state.lock().ok())
        .and_then(|guard| guard.as_ref().cloned())?;
    bridge
        .pending_approval
        .lock()
        .ok()
        .and_then(|pending| pending.as_ref().map(|item| item.request.clone()))
}

pub fn respond_to_approval(request_id: &str, approved: bool) -> Result<(), String> {
    let bridge = ACP_BRIDGE
        .get()
        .and_then(|state| state.lock().ok())
        .and_then(|guard| guard.as_ref().cloned())
        .ok_or_else(|| "Hermes ACP is not running".to_string())?;
    let pending = {
        let mut guard = bridge
            .pending_approval
            .lock()
            .map_err(|_| "Hermes approval state is unavailable".to_string())?;
        let current = guard
            .as_ref()
            .ok_or_else(|| "No Hermes approval is pending".to_string())?;
        if current.request.request_id != request_id {
            return Err("Hermes approval request is no longer current".to_string());
        }
        guard.take().expect("pending approval checked above")
    };
    let outcome = if approved {
        let option_id = pending
            .allow_once_option
            .ok_or_else(|| "Hermes did not offer a one-action approval option".to_string())?;
        json!({"outcome": "selected", "optionId": option_id})
    } else {
        json!({"outcome": "cancelled"})
    };
    write_json_line(
        &bridge.stdin,
        &json!({
            "jsonrpc": "2.0",
            "id": pending.rpc_id,
            "result": {"outcome": outcome}
        }),
    )
}

fn ensure_bridge(
    resource_root: &Path,
    state_root: &Path,
    model: &str,
) -> Result<Arc<HermesAcpBridge>, String> {
    let state = ACP_BRIDGE.get_or_init(|| Mutex::new(None));
    let mut guard = state
        .lock()
        .map_err(|_| "Hermes ACP bridge state is unavailable".to_string())?;
    if let Some(bridge) = guard.as_ref().filter(|bridge| bridge.is_running()) {
        return Ok(bridge.clone());
    }
    let bridge = Arc::new(HermesAcpBridge::start(resource_root, state_root, model)?);
    bridge.initialize()?;
    *guard = Some(bridge.clone());
    Ok(bridge)
}

impl HermesAcpBridge {
    fn start(resource_root: &Path, state_root: &Path, model: &str) -> Result<Self, String> {
        let paths = RuntimePaths::new(resource_root, state_root);
        for (label, path) in [
            ("Hermes ACP packages", &paths.site_packages),
            ("Iris Hermes ACP launcher", &paths.launcher),
        ] {
            if !path.exists() {
                return Err(format!("{label} is missing: {}", path.display()));
            }
        }
        let python = hermes_python(&paths).ok_or_else(|| {
            "Hermes ACP requires Python 3.13. Install or upgrade Python 3.13, then restart Iris."
                .to_string()
        })?;
        if let Some(parent) = paths.stderr_log.parent() {
            fs::create_dir_all(parent).map_err(|err| err.to_string())?;
        }
        rotate_diagnostic_log(&paths.stderr_log, MAX_HERMES_STDERR_BYTES)?;
        let mut command = python_command_for_script(&python, &paths.launcher, &paths.site_packages);
        command
            .current_dir(resource_root)
            .env("HERMES_HOME", &paths.home)
            .env("IRIS_RESOURCE_ROOT", resource_root)
            .env("IRIS_DATA_ROOT", state_root)
            .env(
                "IRIS_BROWSER_COMMAND_OUTPUT_DIR",
                &paths.browser_command_output,
            )
            .env("IRIS_HERMES_MODEL", model)
            .env("IRIS_HERMES_OLLAMA_BASE_URL", "http://127.0.0.1:11434/v1")
            .env("HERMES_DISABLE_LAZY_INSTALLS", "1")
            .env("PYTHONUTF8", "1")
            .env("PYTHONDONTWRITEBYTECODE", "1")
            .env_remove("OPENAI_API_KEY")
            .env_remove("OPENROUTER_API_KEY")
            .env_remove("ANTHROPIC_API_KEY")
            .env_remove("NOUS_API_KEY")
            .env_remove("IRIS_HERMES_BROKER_URL")
            .env_remove("IRIS_HERMES_BROKER_TOKEN")
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        if let Some(access) = configured_memory_broker_access() {
            command
                .env("IRIS_HERMES_BROKER_URL", access.url.as_ref())
                .env("IRIS_HERMES_BROKER_TOKEN", access.bearer_token.as_ref());
        }
        #[cfg(windows)]
        command.creation_flags(CREATE_NO_WINDOW);
        let mut child = command
            .spawn()
            .map_err(|err| format!("failed to start Hermes ACP: {err}"))?;
        let stdin = Arc::new(Mutex::new(
            child
                .stdin
                .take()
                .ok_or_else(|| "Hermes ACP stdin is unavailable".to_string())?,
        ));
        let stdout = child
            .stdout
            .take()
            .ok_or_else(|| "Hermes ACP stdout is unavailable".to_string())?;
        let stderr = child
            .stderr
            .take()
            .ok_or_else(|| "Hermes ACP stderr is unavailable".to_string())?;
        start_bounded_stderr_reader(stderr, paths.stderr_log.clone());
        #[cfg(windows)]
        let job = WindowsJob::create_and_assign(&child)?;
        let child = Arc::new(Mutex::new(child));
        let pending = Arc::new(Mutex::new(HashMap::new()));
        let pending_approval = Arc::new(Mutex::new(None));
        let event_sink = Arc::new(Mutex::new(None));
        let session = Arc::new(Mutex::new(None));
        start_reader(
            stdout,
            stdin.clone(),
            pending.clone(),
            pending_approval.clone(),
            event_sink.clone(),
            session.clone(),
        );
        Ok(Self {
            child,
            stdin,
            pending,
            pending_approval,
            event_sink,
            next_request_id: AtomicU64::new(1),
            session,
            browser_command_output_dir: paths.browser_command_output,
            #[cfg(windows)]
            job,
        })
    }

    fn initialize(&self) -> Result<(), String> {
        self.request(
            "initialize",
            json!({
                "protocolVersion": 1,
                "clientCapabilities": {
                    "auth": {"terminal": false},
                    "fs": {"readTextFile": false, "writeTextFile": false},
                    "terminal": false
                },
                "clientInfo": {
                    "name": "iris",
                    "title": "Iris",
                    "version": env!("CARGO_PKG_VERSION")
                }
            }),
        )
        .map(|_| ())
    }

    fn ensure_session(&self, workspace_path: &str) -> Result<String, String> {
        let mut session = self
            .session
            .lock()
            .map_err(|_| "Hermes ACP session state is unavailable".to_string())?;
        if let Some(existing) = session
            .as_ref()
            .filter(|existing| existing.workspace_path == workspace_path)
        {
            return Ok(existing.id.clone());
        }
        let response = self.request(
            "session/new",
            json!({"cwd": workspace_path, "mcpServers": []}),
        )?;
        let session_id = response
            .get("sessionId")
            .and_then(Value::as_str)
            .ok_or_else(|| "Hermes ACP session/new returned no sessionId".to_string())?
            .to_string();
        self.request(
            "session/set_mode",
            json!({"sessionId": session_id, "modeId": "accept_edits"}),
        )?;
        *session = Some(AcpSession {
            id: session_id.clone(),
            workspace_path: workspace_path.to_string(),
        });
        Ok(session_id)
    }

    fn request(&self, method: &str, params: Value) -> Result<Value, String> {
        let id = self.next_request_id.fetch_add(1, Ordering::Relaxed);
        let (tx, rx) = mpsc::channel();
        self.pending
            .lock()
            .map_err(|_| "Hermes ACP pending request state is unavailable".to_string())?
            .insert(id, tx);
        let request = json!({
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params
        });
        if let Err(error) = write_json_line(&self.stdin, &request) {
            if let Ok(mut pending) = self.pending.lock() {
                pending.remove(&id);
            }
            return Err(error);
        }
        let response = match rx.recv_timeout(ACP_REQUEST_TIMEOUT) {
            Ok(response) => response,
            Err(error) => {
                if let Ok(mut pending) = self.pending.lock() {
                    pending.remove(&id);
                }
                return Err(match error {
                    mpsc::RecvTimeoutError::Timeout => {
                        format!("Hermes ACP request timed out: {method}")
                    }
                    mpsc::RecvTimeoutError::Disconnected => {
                        format!("Hermes ACP response channel closed: {method}")
                    }
                });
            }
        }?;
        response
            .get("result")
            .cloned()
            .ok_or_else(|| format!("Hermes ACP response missing result: {method}"))
    }

    fn is_running(&self) -> bool {
        self.child
            .lock()
            .ok()
            .is_some_and(|mut child| matches!(child.try_wait(), Ok(None)))
    }

    fn terminate(&self) {
        if let Ok(mut pending) = self.pending_approval.lock() {
            *pending = None;
        }
        #[cfg(windows)]
        self.job.terminate();
        if let Ok(mut child) = self.child.lock() {
            let _ = child.kill();
            let _ = child.wait();
        }
        if let Ok(entries) = fs::read_dir(&self.browser_command_output_dir) {
            for entry in entries.flatten() {
                if entry.file_type().is_ok_and(|kind| kind.is_file()) {
                    let _ = fs::remove_file(entry.path());
                }
            }
        }
    }
}

struct RuntimePaths {
    site_packages: PathBuf,
    launcher: PathBuf,
    home: PathBuf,
    stderr_log: PathBuf,
    browser_command_output: PathBuf,
}

impl RuntimePaths {
    fn new(resource_root: &Path, state_root: &Path) -> Self {
        let venv = resource_root.join(".iris-runtime/hermes/.venv");
        Self {
            site_packages: venv.join("Lib/site-packages"),
            launcher: resource_root.join("plugins/hermes_acp/iris_acp.py"),
            home: state_root.join(".iris-data/hermes-home"),
            stderr_log: state_root.join("diagnostics/hermes-acp-stderr.log"),
            browser_command_output: state_root.join(".iris-data/hermes-browser/command-output"),
        }
    }
}

fn hermes_python(paths: &RuntimePaths) -> Option<PythonLaunch> {
    HERMES_PYTHON
        .get_or_init(|| discover_python313(&paths.site_packages))
        .clone()
}

fn discover_python313(site_packages: &Path) -> Option<PythonLaunch> {
    python313_candidates()
        .into_iter()
        .filter(|candidate| !is_packaged_venv_python(candidate, site_packages))
        .find(|candidate| python313_supports_hermes(candidate, site_packages))
}

fn is_packaged_venv_python(candidate: &PythonLaunch, site_packages: &Path) -> bool {
    let Some(venv_root) = site_packages.parent().and_then(Path::parent) else {
        return false;
    };
    let packaged = venv_root.join("Scripts/python.exe");
    normalized_path_text(&candidate.executable)
        .eq_ignore_ascii_case(&normalized_path_text(&packaged))
}

fn normalized_path_text(path: &Path) -> String {
    path.to_string_lossy().replace('\\', "/")
}

fn python313_candidates() -> Vec<PythonLaunch> {
    let mut candidates = Vec::new();
    if let Some(configured) = std::env::var_os("IRIS_PYTHON")
        && !configured.is_empty()
    {
        push_python_candidate(
            &mut candidates,
            PythonLaunch {
                executable: PathBuf::from(configured),
                prefix_args: Vec::new(),
            },
        );
    }
    if let Some(local_app_data) = std::env::var_os("LOCALAPPDATA") {
        let local_app_data = PathBuf::from(local_app_data);
        push_python_path(
            &mut candidates,
            local_app_data.join("Programs/Python/Python313/python.exe"),
        );
        push_uv_python_candidates(&mut candidates, &local_app_data.join("uv/python"));
    }
    if let Some(app_data) = std::env::var_os("APPDATA") {
        push_uv_python_candidates(&mut candidates, &PathBuf::from(app_data).join("uv/python"));
    }
    if let Some(program_files) = std::env::var_os("ProgramFiles") {
        push_python_path(
            &mut candidates,
            PathBuf::from(program_files).join("Python313/python.exe"),
        );
    }
    push_python_candidate(
        &mut candidates,
        PythonLaunch {
            executable: PathBuf::from("py"),
            prefix_args: vec!["-3.13".to_string()],
        },
    );
    for executable in ["python3.13", "python"] {
        push_python_path(&mut candidates, PathBuf::from(executable));
    }
    candidates
}

fn push_uv_python_candidates(candidates: &mut Vec<PythonLaunch>, root: &Path) {
    let Ok(entries) = fs::read_dir(root) else {
        return;
    };
    let mut executables = entries
        .flatten()
        .filter(|entry| {
            entry
                .file_name()
                .to_string_lossy()
                .starts_with("cpython-3.13")
        })
        .map(|entry| entry.path().join("python.exe"))
        .collect::<Vec<_>>();
    executables.sort();
    for executable in executables {
        push_python_path(candidates, executable);
    }
}

fn push_python_path(candidates: &mut Vec<PythonLaunch>, executable: PathBuf) {
    push_python_candidate(
        candidates,
        PythonLaunch {
            executable,
            prefix_args: Vec::new(),
        },
    );
}

fn push_python_candidate(candidates: &mut Vec<PythonLaunch>, candidate: PythonLaunch) {
    if !candidates.iter().any(|existing| existing == &candidate) {
        candidates.push(candidate);
    }
}

fn python313_supports_hermes(candidate: &PythonLaunch, site_packages: &Path) -> bool {
    let version_probe = format!(
        "import importlib.metadata as m,pathlib,sys; import acp,acp_adapter,jwt; site=pathlib.Path({:?}).resolve(); modules=(acp,acp_adapter,jwt); origins=[pathlib.Path(module.__file__).resolve() for module in modules]; ok=sys.version_info[:2] == (3, 13) and m.version('hermes-agent') == {HERMES_AGENT_VERSION:?} and m.version('agent-client-protocol') == {ACP_PACKAGE_VERSION:?} and m.version('PyJWT') == {PYJWT_VERSION:?} and all(site == origin or site in origin.parents for origin in origins); raise SystemExit(0 if ok else 1)",
        site_packages.to_string_lossy()
    );
    let mut command = Command::new(&candidate.executable);
    command
        .args(&candidate.prefix_args)
        .args(["-S", "-c", &version_probe])
        .env("PYTHONPATH", site_packages)
        .env("PYTHONNOUSERSITE", "1")
        .env("PYTHONDONTWRITEBYTECODE", "1")
        .env_remove("PYTHONHOME")
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    #[cfg(windows)]
    command.creation_flags(CREATE_NO_WINDOW);
    command.status().is_ok_and(|status| status.success())
}

fn discover_voice_python313(site_packages: &Path) -> Option<PythonLaunch> {
    python313_candidates()
        .into_iter()
        .filter(|candidate| !is_packaged_venv_python(candidate, site_packages))
        .find(|candidate| python313_supports_voice(candidate, site_packages))
}

fn python313_supports_voice(candidate: &PythonLaunch, site_packages: &Path) -> bool {
    let version_probe = format!(
        "import importlib.metadata as m,pathlib,sys; import kokoro_onnx,numpy,onnxruntime,soundfile; site=pathlib.Path({:?}).resolve(); modules=(kokoro_onnx,numpy,onnxruntime,soundfile); origins=[pathlib.Path(module.__file__).resolve() for module in modules]; ok=sys.version_info[:2] == (3, 13) and m.version('kokoro-onnx') == {KOKORO_ONNX_VERSION:?} and m.version('soundfile') == {SOUNDFILE_VERSION:?} and all(site == origin or site in origin.parents for origin in origins); raise SystemExit(0 if ok else 1)",
        site_packages.to_string_lossy()
    );
    let mut command = Command::new(&candidate.executable);
    command
        .args(&candidate.prefix_args)
        .args(["-S", "-c", &version_probe])
        .env("PYTHONPATH", site_packages)
        .env("PYTHONNOUSERSITE", "1")
        .env("PYTHONDONTWRITEBYTECODE", "1")
        .env_remove("PYTHONHOME")
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    #[cfg(windows)]
    command.creation_flags(CREATE_NO_WINDOW);
    command.status().is_ok_and(|status| status.success())
}

fn python_command_for_script(
    python: &PythonLaunch,
    script: &Path,
    site_packages: &Path,
) -> Command {
    let mut command = Command::new(&python.executable);
    command
        .args(&python.prefix_args)
        .arg("-S")
        .arg(script)
        .env("PYTHONPATH", site_packages)
        .env("PYTHONNOUSERSITE", "1")
        .env_remove("PYTHONHOME");
    command
}

pub(crate) fn python313_command_for_script(
    resource_root: &Path,
    script: &Path,
) -> Result<Command, String> {
    let site_packages = resource_root.join(".iris-runtime/hermes/.venv/Lib/site-packages");
    if !site_packages.is_dir() {
        return Err(format!(
            "Hermes Python packages are missing: {}",
            site_packages.display()
        ));
    }
    let python = HERMES_PYTHON
        .get_or_init(|| discover_python313(&site_packages))
        .as_ref()
        .ok_or_else(|| {
            "Iris requires Python 3.13. Install or upgrade Python 3.13, then restart Iris."
                .to_string()
        })?;
    Ok(python_command_for_script(python, script, &site_packages))
}

pub(crate) fn python313_voice_command_for_script(
    resource_root: &Path,
    script: &Path,
) -> Result<Command, String> {
    let site_packages = resource_root.join(".iris-runtime/voice/Lib/site-packages");
    if !site_packages.is_dir() {
        return Err(format!(
            "Iris voice Python packages are missing: {}",
            site_packages.display()
        ));
    }
    let python = VOICE_PYTHON
        .get_or_init(|| discover_voice_python313(&site_packages))
        .as_ref()
        .ok_or_else(|| {
            "Iris voice requires exact Python 3.13 with its pinned kokoro-onnx 0.5.0 and soundfile 0.14.0 layer. Repair or upgrade Iris, then restart it."
                .to_string()
        })?;
    Ok(python_command_for_script(python, script, &site_packages))
}

fn start_reader(
    stdout: impl std::io::Read + Send + 'static,
    stdin: Arc<Mutex<ChildStdin>>,
    pending: SharedPendingRequests,
    pending_approval: SharedPendingApproval,
    event_sink: SharedAcpEventSink,
    session: Arc<Mutex<Option<AcpSession>>>,
) {
    thread::spawn(move || {
        let mut malformed_lines = 0;
        let mut stdout = BufReader::new(stdout);
        while let Ok(Some(line)) = read_bounded_line(&mut stdout, MAX_ACP_LINE_BYTES) {
            let Ok(value) = parse_acp_frame(line) else {
                malformed_lines += 1;
                if malformed_lines >= MAX_CONSECUTIVE_MALFORMED_ACP_LINES {
                    break;
                }
                continue;
            };
            malformed_lines = 0;
            if value.get("method").and_then(Value::as_str) == Some("session/request_permission")
                && value.get("id").is_some()
            {
                let workspace = session
                    .lock()
                    .ok()
                    .and_then(|session| session.as_ref().map(|item| item.workspace_path.clone()));
                let approval = approval_from_request(&value, workspace.as_deref());
                if approval.request.risk_class == RiskClass::Ordinary {
                    let outcome = approval.allow_once_option.as_ref().map_or_else(
                        || json!({"outcome": "cancelled"}),
                        |option_id| {
                            json!({
                                "outcome": "selected",
                                "optionId": option_id
                            })
                        },
                    );
                    let response = json!({
                        "jsonrpc": "2.0",
                        "id": approval.rpc_id,
                        "result": {"outcome": outcome}
                    });
                    let _ = write_json_line(&stdin, &response);
                    continue;
                }
                let mut stored = false;
                if let Ok(mut current) = pending_approval.lock()
                    && current.is_none()
                {
                    *current = Some(approval.clone());
                    stored = true;
                }
                if stored {
                    if let Some(sink) = event_sink
                        .lock()
                        .ok()
                        .and_then(|sink| sink.as_ref().cloned())
                    {
                        push_acp_event(
                            &sink,
                            json!({
                                "method": "iris/approval_request",
                                "params": {"approval": approval.request}
                            }),
                        );
                    }
                } else {
                    let response = json!({
                        "jsonrpc": "2.0",
                        "id": value.get("id").cloned().unwrap_or(Value::Null),
                        "result": {"outcome": {"outcome": "cancelled"}}
                    });
                    let _ = write_json_line(&stdin, &response);
                }
                continue;
            }
            if value.get("method").is_some() && value.get("id").is_some() {
                let response = json!({
                    "jsonrpc": "2.0",
                    "id": value.get("id").cloned().unwrap_or(Value::Null),
                    "error": {
                        "code": -32601,
                        "message": "Iris ACP client does not expose client-side tools"
                    }
                });
                let _ = write_json_line(&stdin, &response);
                continue;
            }
            if let Some(id) = value.get("id").and_then(Value::as_u64) {
                let sender = pending.lock().ok().and_then(|mut map| map.remove(&id));
                if let Some(sender) = sender {
                    let result = if let Some(error) = value.get("error") {
                        Err(format!("Hermes ACP error: {error}"))
                    } else {
                        Ok(value)
                    };
                    let _ = sender.send(result);
                }
                continue;
            }
            if value.get("method").and_then(Value::as_str) == Some("session/update")
                && let Some(sink) = event_sink
                    .lock()
                    .ok()
                    .and_then(|sink| sink.as_ref().cloned())
            {
                push_acp_event(&sink, value);
            }
        }
        fail_pending_requests(&pending, "Hermes ACP stream closed or became malformed");
    });
}

pub(crate) fn start_bounded_stderr_reader(
    stderr: impl std::io::Read + Send + 'static,
    path: PathBuf,
) {
    thread::spawn(move || {
        let _ = write_bounded_stderr(BufReader::new(stderr), &path, MAX_HERMES_STDERR_BYTES);
    });
}

#[derive(Debug, PartialEq, Eq)]
struct BoundedLine {
    bytes: Vec<u8>,
    oversized: bool,
}

fn read_bounded_line(
    reader: &mut impl BufRead,
    max_bytes: usize,
) -> std::io::Result<Option<BoundedLine>> {
    let mut bytes = Vec::with_capacity(max_bytes.min(8 * 1024));
    let mut content_bytes = 0_usize;
    let mut last_byte = None;
    let mut saw_input = false;

    loop {
        let available = reader.fill_buf()?;
        if available.is_empty() {
            if !saw_input {
                return Ok(None);
            }
            return Ok(Some(finish_bounded_line(
                bytes,
                content_bytes,
                last_byte,
                max_bytes,
            )));
        }

        saw_input = true;
        let newline = available.iter().position(|byte| *byte == b'\n');
        let content_len = newline.unwrap_or(available.len());
        if content_len > 0 {
            last_byte = Some(available[content_len - 1]);
            content_bytes = content_bytes.saturating_add(content_len);
        }
        let remaining = max_bytes.saturating_sub(bytes.len());
        let retained = content_len.min(remaining);
        bytes.extend_from_slice(&available[..retained]);
        let consumed = newline.map_or(content_len, |position| position + 1);
        reader.consume(consumed);

        if newline.is_some() {
            return Ok(Some(finish_bounded_line(
                bytes,
                content_bytes,
                last_byte,
                max_bytes,
            )));
        }
    }
}

fn finish_bounded_line(
    mut bytes: Vec<u8>,
    content_bytes: usize,
    last_byte: Option<u8>,
    max_bytes: usize,
) -> BoundedLine {
    let has_line_ending_carriage_return = last_byte == Some(b'\r');
    let logical_bytes = content_bytes.saturating_sub(usize::from(has_line_ending_carriage_return));
    let oversized = logical_bytes > max_bytes;
    if has_line_ending_carriage_return && bytes.last() == Some(&b'\r') {
        bytes.pop();
    }
    BoundedLine { bytes, oversized }
}

fn parse_acp_frame(frame: BoundedLine) -> Result<Value, String> {
    if frame.oversized {
        return Err("Hermes ACP response exceeded the line-size limit".to_string());
    }
    let line = String::from_utf8(frame.bytes)
        .map_err(|_| "Hermes ACP returned a non-UTF-8 response".to_string())?;
    parse_acp_line(&line)
}

fn write_bounded_stderr(reader: impl BufRead, path: &Path, max_bytes: u64) -> Result<(), String> {
    let mut reader = reader;
    let mut written = path.metadata().map(|metadata| metadata.len()).unwrap_or(0);
    let mut output = OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)
        .map_err(|err| format!("failed to open Hermes ACP diagnostics: {err}"))?;
    while let Some(line) = read_bounded_line(&mut reader, MAX_HERMES_STDERR_LINE_BYTES)
        .map_err(|err| format!("failed to read Hermes ACP diagnostics: {err}"))?
    {
        let decoded = String::from_utf8_lossy(&line.bytes);
        let mut clean = redact_and_truncate(&decoded, 2_000);
        if line.oversized {
            clean.push_str(" [stderr line truncated]");
        }
        let remaining = max_bytes.saturating_sub(written);
        if remaining == 0 {
            continue;
        }
        let max_line_bytes = remaining.saturating_sub(1) as usize;
        let mut take = clean.len().min(max_line_bytes);
        while take > 0 && !clean.is_char_boundary(take) {
            take -= 1;
        }
        let bytes = &clean.as_bytes()[..take];
        output
            .write_all(bytes)
            .and_then(|_| output.write_all(b"\n"))
            .map_err(|err| format!("failed to write Hermes ACP diagnostics: {err}"))?;
        written = written
            .saturating_add(bytes.len() as u64 + 1)
            .min(max_bytes);
    }
    output
        .flush()
        .map_err(|err| format!("failed to flush Hermes ACP diagnostics: {err}"))
}

pub(crate) fn rotate_diagnostic_log(path: &Path, max_bytes: u64) -> Result<(), String> {
    if path.metadata().map(|metadata| metadata.len()).unwrap_or(0) < max_bytes {
        return Ok(());
    }
    let backup = path.with_extension("log.previous");
    if backup.exists() {
        fs::remove_file(&backup)
            .map_err(|err| format!("failed to replace Hermes diagnostics backup: {err}"))?;
    }
    fs::rename(path, backup)
        .map_err(|err| format!("failed to rotate Hermes ACP diagnostics: {err}"))
}

fn parse_acp_line(line: &str) -> Result<Value, String> {
    if line.len() > MAX_ACP_LINE_BYTES {
        return Err("Hermes ACP response exceeded the line-size limit".to_string());
    }
    let value = serde_json::from_str::<Value>(line)
        .map_err(|error| format!("Hermes ACP returned malformed JSON: {error}"))?;
    if !value.is_object() {
        return Err("Hermes ACP response must be a JSON object".to_string());
    }
    Ok(value)
}

fn fail_pending_requests(pending: &SharedPendingRequests, message: &str) {
    if let Ok(mut pending) = pending.lock() {
        for (_, sender) in pending.drain() {
            let _ = sender.send(Err(message.to_string()));
        }
    }
}

fn approval_from_request(value: &Value, workspace: Option<&str>) -> PendingAcpApproval {
    let rpc_id = value.get("id").cloned().unwrap_or(Value::Null);
    let params = value.get("params").cloned().unwrap_or(Value::Null);
    let tool_call = params.get("toolCall").cloned().unwrap_or(Value::Null);
    let raw_summary = approval_summary(&tool_call);
    let risk_class = classify_risk(&format!("{raw_summary}\n{tool_call}"), workspace);
    let summary = redact_and_truncate(&raw_summary, 1_200);
    let allow_once_option = params
        .get("options")
        .and_then(Value::as_array)
        .and_then(|options| {
            options.iter().find_map(|option| {
                (option.get("optionId").and_then(Value::as_str) == Some("allow_once"))
                    .then(|| "allow_once".to_string())
            })
        });
    let request_id = match &rpc_id {
        Value::String(value) => value.clone(),
        other => other.to_string(),
    };
    PendingAcpApproval {
        rpc_id,
        request: ApprovalRequest {
            request_id,
            risk_class,
            summary,
            requires_separate_confirmation: risk_class != RiskClass::Ordinary,
        },
        allow_once_option,
    }
}

fn approval_summary(tool_call: &Value) -> String {
    let title = tool_call
        .get("title")
        .and_then(Value::as_str)
        .unwrap_or("Hermes requested permission");
    let raw_input = tool_call.get("rawInput").cloned().unwrap_or(Value::Null);
    let detail = raw_input
        .get("command")
        .or_else(|| raw_input.get("path"))
        .or_else(|| raw_input.get("arguments").and_then(|args| args.get("path")))
        .and_then(Value::as_str);
    detail.map_or_else(|| title.to_string(), |detail| format!("{title}\n{detail}"))
}

fn classify_risk(summary: &str, workspace: Option<&str>) -> RiskClass {
    let lower = summary.to_ascii_lowercase();
    if lower.contains("payment browser") || lower.starts_with("payment:") {
        return RiskClass::Payment;
    }
    if lower.contains("consequential browser submission") {
        return RiskClass::ConsequentialBrowserSubmission;
    }
    if lower.contains("executable download") {
        return RiskClass::ExecutableDownload;
    }
    if [
        "git reset --hard",
        "git clean -",
        "git push --force",
        "git push -f",
        "git rebase",
        "git checkout --",
        "git branch -d",
    ]
    .iter()
    .any(|pattern| lower.contains(pattern))
    {
        return RiskClass::DestructiveGit;
    }
    if [
        "winget install",
        "choco install",
        "scoop install",
        "pip install",
        "uv pip install",
        "npm install",
        "cargo install",
        "msiexec",
        "runas",
        "-verb runas",
        "set-executionpolicy",
    ]
    .iter()
    .any(|pattern| lower.contains(pattern))
    {
        return RiskClass::InstallOrAdmin;
    }
    if [
        ".env",
        ".ssh",
        "id_rsa",
        "id_ed25519",
        "credential",
        "password",
        "api key",
        "secret",
        "token",
    ]
    .iter()
    .any(|pattern| lower.contains(pattern))
    {
        return RiskClass::Credentials;
    }
    if ["invoke-webrequest", "curl ", "wget "]
        .iter()
        .any(|pattern| lower.contains(pattern))
        && [".exe", ".msi", ".msix", ".bat", ".cmd", ".ps1"]
            .iter()
            .any(|extension| lower.contains(extension))
    {
        return RiskClass::ExecutableDownload;
    }
    if lower.contains("sensitive files") {
        return RiskClass::SensitiveFiles;
    }
    if lower.contains("scope expansion")
        || workspace.is_some_and(|workspace| {
            let normalized_workspace = workspace.replace('/', "\\").to_ascii_lowercase();
            lower.contains(":\\") && !lower.contains(&normalized_workspace)
        })
    {
        return RiskClass::ScopeExpansion;
    }
    RiskClass::Ordinary
}

fn write_json_line(stdin: &Arc<Mutex<ChildStdin>>, value: &Value) -> Result<(), String> {
    let mut stdin = stdin
        .lock()
        .map_err(|_| "Hermes ACP stdin is unavailable".to_string())?;
    serde_json::to_writer(&mut *stdin, value).map_err(|err| err.to_string())?;
    stdin.write_all(b"\n").map_err(|err| err.to_string())?;
    stdin.flush().map_err(|err| err.to_string())
}

fn event_from_notification(notification: &Value) -> Option<HermesEvent> {
    if notification.get("method").and_then(Value::as_str) == Some("iris/approval_request") {
        return serde_json::from_value(notification.get("params")?.get("approval")?.clone())
            .ok()
            .map(HermesEvent::ApprovalRequest);
    }
    let update = notification.get("params")?.get("update")?;
    match update.get("sessionUpdate")?.as_str()? {
        "agent_message_chunk" => agent_message_text(notification).map(HermesEvent::Text),
        "agent_thought_chunk" => Some(HermesEvent::Thinking(true)),
        "tool_call" | "tool_call_update" => {
            let title = update
                .get("title")
                .and_then(Value::as_str)
                .unwrap_or("Hermes tool activity");
            let status = update
                .get("status")
                .and_then(Value::as_str)
                .unwrap_or("in_progress");
            let detail = tool_event_detail(update);
            Some(HermesEvent::ToolActivity(if detail.is_empty() {
                format!("{title}: {status}")
            } else {
                format!("{title}: {status}\n{detail}")
            }))
        }
        _ => None,
    }
}

fn tool_event_detail(update: &Value) -> String {
    let mut text = Vec::new();
    collect_text_blocks(update.get("content").unwrap_or(&Value::Null), &mut text);
    redact_and_truncate(&text.join("\n"), 1_500)
}

fn collect_text_blocks(value: &Value, found: &mut Vec<String>) {
    match value {
        Value::Array(values) => {
            for value in values {
                collect_text_blocks(value, found);
            }
        }
        Value::Object(map) => {
            if map.get("type").and_then(Value::as_str) == Some("text")
                && let Some(text) = map.get("text").and_then(Value::as_str)
            {
                found.push(text.to_string());
            }
            for value in map.values() {
                collect_text_blocks(value, found);
            }
        }
        _ => {}
    }
}

fn append_action_audit(
    state_root: &Path,
    session_id: &str,
    notifications: &[Value],
) -> Result<(), String> {
    let path = state_root.join("diagnostics/hermes-actions.jsonl");
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|err| err.to_string())?;
    }
    if path.metadata().map(|meta| meta.len()).unwrap_or(0) > 2 * 1024 * 1024 {
        let archive = path.with_extension("jsonl.1");
        let _ = fs::remove_file(&archive);
        fs::rename(&path, archive).map_err(|err| err.to_string())?;
    }
    let mut output = OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)
        .map_err(|err| err.to_string())?;
    for notification in notifications {
        let Some(update) = notification
            .get("params")
            .and_then(|params| params.get("update"))
        else {
            continue;
        };
        if !matches!(
            update.get("sessionUpdate").and_then(Value::as_str),
            Some("tool_call") | Some("tool_call_update")
        ) {
            continue;
        }
        let title = update
            .get("title")
            .and_then(Value::as_str)
            .unwrap_or("Hermes tool activity");
        let status = update
            .get("status")
            .and_then(Value::as_str)
            .unwrap_or("in_progress");
        let detail = tool_event_detail(update);
        let record = json!({
            "timestampMs": unix_timestamp_ms(),
            "sessionId": session_id,
            "title": redact_and_truncate(title, 300),
            "status": status,
            "detail": detail,
        });
        serde_json::to_writer(&mut output, &record).map_err(|err| err.to_string())?;
        output.write_all(b"\n").map_err(|err| err.to_string())?;
    }
    output.flush().map_err(|err| err.to_string())
}

fn reject_repeated_tool_failures(notifications: &[Value]) -> Result<(), String> {
    let mut last_title = String::new();
    let mut repeated = 0_u8;
    for notification in notifications {
        let Some(update) = notification
            .get("params")
            .and_then(|params| params.get("update"))
        else {
            continue;
        };
        if update.get("sessionUpdate").and_then(Value::as_str) != Some("tool_call_update")
            || update.get("status").and_then(Value::as_str) != Some("failed")
        {
            continue;
        }
        let title = update
            .get("title")
            .and_then(Value::as_str)
            .unwrap_or("Hermes tool");
        if title == last_title {
            repeated += 1;
        } else {
            last_title = title.to_string();
            repeated = 1;
        }
        if repeated >= 3 {
            return Err(format!(
                "Hermes stopped after three repeated failures from {}",
                redact_and_truncate(title, 160)
            ));
        }
    }
    Ok(())
}

fn unix_timestamp_ms() -> u128 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis()
}

fn redact_and_truncate(input: &str, limit: usize) -> String {
    let mut output = input
        .lines()
        .map(|line| {
            let lower = line.to_ascii_lowercase();
            if [
                "password",
                "secret",
                "api key",
                "token=",
                "authorization:",
                "iris_hermes_broker_",
            ]
            .iter()
            .any(|marker| lower.contains(marker))
            {
                "[redacted sensitive detail]".to_string()
            } else {
                line.to_string()
            }
        })
        .collect::<Vec<_>>()
        .join("\n");
    if let Some(profile) = std::env::var_os("USERPROFILE") {
        let profile = profile.to_string_lossy();
        if !profile.is_empty() {
            output = output.replace(profile.as_ref(), "%USERPROFILE%");
            output = output.replace(&profile.replace('\\', "/"), "%USERPROFILE%");
        }
    }
    if output.len() > limit {
        let mut truncate_at = limit;
        while truncate_at > 0 && !output.is_char_boundary(truncate_at) {
            truncate_at -= 1;
        }
        output.truncate(truncate_at);
        output.push_str("...");
    }
    output
}

fn agent_message_text(notification: &Value) -> Option<String> {
    let update = notification.get("params")?.get("update")?;
    if update.get("sessionUpdate")?.as_str()? != "agent_message_chunk" {
        return None;
    }
    update
        .get("content")?
        .get("text")?
        .as_str()
        .map(str::to_string)
}

fn provenance_from_notifications(notifications: &[Value]) -> Vec<HermesProvenance> {
    let mut found = Vec::new();
    for notification in notifications {
        collect_provenance(notification, &mut found);
    }
    found.sort_by(|left, right| {
        left.source
            .cmp(&right.source)
            .then(left.memory_id.cmp(&right.memory_id))
            .then(left.staging_id.cmp(&right.staging_id))
    });
    found.dedup();
    found
}

fn browser_previews_from_notifications(notifications: &[Value]) -> Vec<BrowserPreview> {
    let mut found = Vec::new();
    for notification in notifications {
        collect_browser_previews(notification, &mut found);
    }
    let mut merged: Vec<BrowserPreview> = Vec::new();
    for preview in found {
        let existing = merged.iter_mut().find(|item| {
            (!preview.url.is_empty() && item.url == preview.url)
                || (preview.url.is_empty()
                    && item.url.is_empty()
                    && item.screenshot_path == preview.screenshot_path)
        });
        if let Some(existing) = existing {
            if existing.screenshot_path.is_none() {
                existing.screenshot_path = preview.screenshot_path;
            }
        } else {
            merged.push(preview);
        }
    }
    merged
}

fn collect_browser_previews(value: &Value, found: &mut Vec<BrowserPreview>) {
    match value {
        Value::Array(values) => {
            for value in values {
                collect_browser_previews(value, found);
            }
        }
        Value::Object(map) => {
            if let Some(preview) = map.get("browserPreview").and_then(Value::as_object) {
                let url = preview
                    .get("url")
                    .and_then(Value::as_str)
                    .unwrap_or("")
                    .trim()
                    .to_string();
                let screenshot_path = preview
                    .get("screenshotPath")
                    .or_else(|| preview.get("screenshot_path"))
                    .and_then(Value::as_str)
                    .map(str::trim)
                    .filter(|path| !path.is_empty())
                    .map(str::to_string);
                if !url.is_empty() || screenshot_path.is_some() {
                    found.push(BrowserPreview {
                        url,
                        screenshot_path,
                    });
                }
            }
            for value in map.values() {
                collect_browser_previews(value, found);
            }
        }
        Value::String(text) => {
            let clean = text.trim();
            if (clean.starts_with('{') || clean.starts_with('['))
                && let Ok(parsed) = serde_json::from_str::<Value>(clean)
            {
                collect_browser_previews(&parsed, found);
            }
            for line in text.lines().map(str::trim) {
                if line.starts_with('{')
                    && line.ends_with('}')
                    && let Ok(parsed) = serde_json::from_str::<Value>(line)
                {
                    collect_browser_previews(&parsed, found);
                }
            }
            if let Some(marker) = text.find("IRIS_BROWSER_PREVIEW:") {
                let payload = text[marker + "IRIS_BROWSER_PREVIEW:".len()..]
                    .lines()
                    .next()
                    .unwrap_or("")
                    .trim();
                if let Ok(parsed) = serde_json::from_str::<Value>(payload) {
                    collect_browser_previews(&json!({"browserPreview": parsed}), found);
                }
            }
        }
        _ => {}
    }
}

fn collect_provenance(value: &Value, found: &mut Vec<HermesProvenance>) {
    match value {
        Value::Array(values) => {
            for value in values {
                collect_provenance(value, found);
            }
        }
        Value::Object(map) => {
            if let Some(provenance) = map.get("provenance").and_then(Value::as_object) {
                let source = provenance
                    .get("source")
                    .and_then(Value::as_str)
                    .unwrap_or("iris")
                    .to_string();
                let authority = provenance
                    .get("authority")
                    .and_then(Value::as_str)
                    .unwrap_or("untrusted_evidence")
                    .to_string();
                let memory_id = provenance
                    .get("memoryId")
                    .or_else(|| provenance.get("memory_id"))
                    .and_then(Value::as_u64);
                let staging_id = provenance
                    .get("stagingId")
                    .or_else(|| provenance.get("staging_id"))
                    .and_then(Value::as_u64)
                    .or_else(|| map.get("staging_id").and_then(Value::as_u64));
                let evidence = provenance
                    .get("evidence")
                    .and_then(Value::as_str)
                    .map(str::to_string);
                found.push(HermesProvenance {
                    authority,
                    source,
                    memory_id,
                    staging_id,
                    evidence,
                });
            }
            for value in map.values() {
                collect_provenance(value, found);
            }
        }
        Value::String(text) => {
            let clean = text.trim();
            if (clean.starts_with('{') || clean.starts_with('['))
                && let Ok(parsed) = serde_json::from_str::<Value>(clean)
            {
                collect_provenance(&parsed, found);
            }
            if let Some(marker) = text.find("IRIS_PROVENANCE:") {
                let payload = text[marker + "IRIS_PROVENANCE:".len()..]
                    .lines()
                    .next()
                    .unwrap_or("")
                    .trim();
                if let Ok(parsed) = serde_json::from_str::<Value>(payload) {
                    collect_provenance(&parsed, found);
                }
            }
        }
        _ => {}
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Read;
    use std::sync::atomic::AtomicBool;

    // Hermes ACP owns one supervised process and session, so live tests must not
    // compete for that singleton even when the Rust test runner is parallel.
    static LIVE_ACP_TEST_LOCK: Mutex<()> = Mutex::new(());

    #[test]
    fn browser_executable_selection_honors_valid_absolute_override() {
        let current_exe = std::env::current_exe().expect("current test executable");
        assert_eq!(
            select_browser_executable(
                Some(current_exe.clone()),
                [PathBuf::from("C:/missing/browser.exe")],
            ),
            Some(current_exe),
        );
        assert_eq!(
            select_browser_executable(
                Some(PathBuf::from("relative/browser.exe")),
                [std::env::current_exe().expect("current test executable")],
            ),
            None,
        );
    }

    #[test]
    fn browser_executable_selection_uses_first_existing_system_candidate() {
        let current_exe = std::env::current_exe().expect("current test executable");
        assert_eq!(
            select_browser_executable(
                None,
                [PathBuf::from("C:/missing/browser.exe"), current_exe.clone(),],
            ),
            Some(current_exe),
        );
    }

    struct BridgeCleanup;

    impl Drop for BridgeCleanup {
        fn drop(&mut self) {
            stop();
            clear_test_memory_broker();
        }
    }

    struct FakeMemoryBroker {
        stop: Arc<AtomicBool>,
        thread: Option<thread::JoinHandle<()>>,
        requests: Arc<Mutex<Vec<String>>>,
        address: std::net::SocketAddr,
        bearer_token: String,
    }

    impl FakeMemoryBroker {
        fn start() -> Self {
            let listener =
                std::net::TcpListener::bind("127.0.0.1:0").expect("bind fake Iris memory broker");
            let address = listener.local_addr().expect("fake broker address");
            let bearer_token = "ab".repeat(32);
            listener
                .set_nonblocking(true)
                .expect("nonblocking fake broker");
            let stop = Arc::new(AtomicBool::new(false));
            let requests = Arc::new(Mutex::new(Vec::new()));
            let thread_stop = stop.clone();
            let thread_requests = requests.clone();
            let thread_bearer_token = bearer_token.clone();
            let handle = thread::spawn(move || {
                while !thread_stop.load(Ordering::Relaxed) {
                    match listener.accept() {
                        Ok((mut stream, _)) => {
                            let _ = stream.set_nonblocking(false);
                            let _ = stream.set_read_timeout(Some(Duration::from_secs(2)));
                            let mut bytes = Vec::with_capacity(16_384);
                            let mut expected = None;
                            loop {
                                let mut chunk = [0_u8; 4096];
                                let count =
                                    std::io::Read::read(&mut stream, &mut chunk).unwrap_or(0);
                                if count == 0 {
                                    break;
                                }
                                bytes.extend_from_slice(&chunk[..count]);
                                if expected.is_none()
                                    && let Some(header_end) =
                                        bytes.windows(4).position(|part| part == b"\r\n\r\n")
                                {
                                    let headers =
                                        String::from_utf8_lossy(&bytes[..header_end]).to_string();
                                    let content_length = headers
                                        .lines()
                                        .find_map(|line| {
                                            let (name, value) = line.split_once(':')?;
                                            name.eq_ignore_ascii_case("content-length")
                                                .then(|| value.trim().parse::<usize>().ok())
                                                .flatten()
                                        })
                                        .unwrap_or(0);
                                    expected = Some(header_end + 4 + content_length);
                                }
                                if expected.is_some_and(|length| bytes.len() >= length) {
                                    break;
                                }
                            }
                            let request = String::from_utf8_lossy(&bytes).to_string();
                            let authenticated = request.lines().skip(1).any(|line| {
                                line.strip_prefix("Authorization: Bearer ")
                                    .is_some_and(|value| value == thread_bearer_token)
                            });
                            let path = request
                                .lines()
                                .next()
                                .and_then(|line| line.split_whitespace().nth(1))
                                .unwrap_or("/")
                                .to_string();
                            if let Ok(mut observed) = thread_requests.lock() {
                                observed.push(path.clone());
                            }
                            let body = if !authenticated {
                                json!({"ok": false, "error": "authentication failed"})
                            } else {
                                match path.as_str() {
                                    "/memory/search" => json!({
                                        "ok": true,
                                        "readOnly": true,
                                        "results": [{
                                            "id": 7,
                                            "text": "Alejandro is 45",
                                            "score": 1.0,
                                            "source": "iris_active_memory",
                                            "provenance": {
                                                "authority": "user_approved",
                                                "source": "iris_active_memory",
                                                "memoryId": 7
                                            }
                                        }]
                                    }),
                                    "/memory/propose" => json!({
                                        "ok": true,
                                        "verdict": "staged",
                                        "staging_id": 9,
                                        "reason": "proposal written to staging only"
                                    }),
                                    "/memory/status" => json!({
                                        "ok": true,
                                        "loopbackOnly": true,
                                        "authenticated": true,
                                        "stagingItems": 0,
                                        "pendingStagingItems": 0,
                                        "decidedStagingItems": 0
                                    }),
                                    _ => json!({"ok": false, "error": "unexpected route"}),
                                }
                            }
                            .to_string();
                            let response_status = if authenticated {
                                "200 OK"
                            } else {
                                "401 Unauthorized"
                            };
                            let response = format!(
                                "HTTP/1.1 {response_status}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                                body.len(),
                                body
                            );
                            let _ = std::io::Write::write_all(&mut stream, response.as_bytes());
                            let _ = std::io::Write::flush(&mut stream);
                        }
                        Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                            thread::sleep(Duration::from_millis(10));
                        }
                        Err(_) => {
                            thread::sleep(Duration::from_millis(10));
                        }
                    }
                }
            });
            Self {
                stop,
                thread: Some(handle),
                requests,
                address,
                bearer_token,
            }
        }

        fn url(&self) -> String {
            format!("http://{}", self.address)
        }
    }

    impl Drop for FakeMemoryBroker {
        fn drop(&mut self) {
            self.stop.store(true, Ordering::Relaxed);
            let _ = std::net::TcpStream::connect(self.address);
            if let Some(handle) = self.thread.take() {
                let _ = handle.join();
            }
        }
    }

    #[test]
    fn rejects_malformed_or_oversized_acp_lines() {
        assert!(parse_acp_line("not-json").is_err());
        assert!(parse_acp_line("[]").is_err());
        assert!(parse_acp_line(&"x".repeat(MAX_ACP_LINE_BYTES + 1)).is_err());
        assert_eq!(
            parse_acp_line(r#"{"jsonrpc":"2.0","id":1}"#).expect("valid ACP object")["id"],
            1
        );
    }

    #[test]
    fn bounded_acp_reader_drains_oversized_newline_free_frame() {
        let streamed_bytes = MAX_ACP_LINE_BYTES + 3 * 1024 * 1024;
        let source = std::io::repeat(b'x')
            .take(streamed_bytes as u64)
            .chain(std::io::Cursor::new(
                b"\n{\"jsonrpc\":\"2.0\",\"id\":7}\r\n",
            ));
        let mut reader = BufReader::with_capacity(257, source);

        let oversized = read_bounded_line(&mut reader, MAX_ACP_LINE_BYTES)
            .expect("read oversized frame")
            .expect("oversized frame");
        assert!(oversized.oversized);
        assert_eq!(oversized.bytes.len(), MAX_ACP_LINE_BYTES);
        assert_eq!(
            parse_acp_frame(oversized).expect_err("reject oversized ACP frame"),
            "Hermes ACP response exceeded the line-size limit"
        );

        let valid = read_bounded_line(&mut reader, MAX_ACP_LINE_BYTES)
            .expect("read following frame")
            .expect("following frame");
        assert!(!valid.oversized);
        assert_eq!(
            parse_acp_line(std::str::from_utf8(&valid.bytes).expect("utf-8 ACP frame"))
                .expect("valid ACP frame")["id"],
            7
        );
        assert!(
            read_bounded_line(&mut reader, MAX_ACP_LINE_BYTES)
                .expect("read EOF")
                .is_none()
        );

        let mut exact_crlf = BufReader::with_capacity(2, std::io::Cursor::new(b"1234\r\n"));
        let exact = read_bounded_line(&mut exact_crlf, 4)
            .expect("read exact CRLF frame")
            .expect("exact CRLF frame");
        assert!(!exact.oversized);
        assert_eq!(exact.bytes, b"1234");
    }

    #[test]
    fn failing_pending_requests_unblocks_every_waiter() {
        let pending: SharedPendingRequests = Arc::new(Mutex::new(HashMap::new()));
        let (first_tx, first_rx) = mpsc::channel();
        let (second_tx, second_rx) = mpsc::channel();
        pending
            .lock()
            .expect("pending requests")
            .insert(1, first_tx);
        pending
            .lock()
            .expect("pending requests")
            .insert(2, second_tx);

        fail_pending_requests(&pending, "ACP stream failed");

        assert_eq!(
            first_rx.recv().expect("first response"),
            Err("ACP stream failed".to_string())
        );
        assert_eq!(
            second_rx.recv().expect("second response"),
            Err("ACP stream failed".to_string())
        );
        assert!(pending.lock().expect("pending requests").is_empty());
    }

    #[test]
    fn acp_task_events_are_bounded_and_keep_the_latest_evidence() {
        let mut events = BoundedAcpEvents::default();
        for index in 0..(MAX_ACP_TASK_EVENTS + 32) {
            events.push(json!({"index": index, "text": "x".repeat(2_048)}));
        }

        assert!(events.values.len() <= MAX_ACP_TASK_EVENTS);
        assert!(events.total_bytes <= MAX_ACP_TASK_EVENT_BYTES);
        assert_eq!(
            events
                .values
                .back()
                .and_then(|value| value.get("index"))
                .and_then(Value::as_u64),
            Some((MAX_ACP_TASK_EVENTS + 31) as u64)
        );
    }

    #[test]
    fn acp_event_registration_rejects_concurrent_tasks_and_clears_on_drop() {
        let registry: SharedAcpEventSink = Arc::new(Mutex::new(None));
        let first_sink = Arc::new(Mutex::new(BoundedAcpEvents::default()));
        let first = register_acp_event_sink(&registry, first_sink).expect("first registration");
        let concurrent_error = match register_acp_event_sink(
            &registry,
            Arc::new(Mutex::new(BoundedAcpEvents::default())),
        ) {
            Ok(_) => panic!("concurrent registration must fail"),
            Err(error) => error,
        };
        assert!(concurrent_error.contains("active task"));

        drop(first);
        assert!(registry.lock().expect("event registry").is_none());
        register_acp_event_sink(&registry, Arc::new(Mutex::new(BoundedAcpEvents::default())))
            .expect("registration after drop");
    }

    #[test]
    fn extracts_agent_message_chunks() {
        let notification = json!({
            "method": "session/update",
            "params": {
                "update": {
                    "sessionUpdate": "agent_message_chunk",
                    "content": {"type": "text", "text": "hello"}
                }
            }
        });

        assert_eq!(agent_message_text(&notification).as_deref(), Some("hello"));
        assert_eq!(
            event_from_notification(&notification),
            Some(HermesEvent::Text("hello".to_string()))
        );
    }

    #[test]
    fn reconstructs_final_text_from_cumulative_chunks() {
        let chunks = vec![
            "I".to_string(),
            "IR".to_string(),
            "IRIS".to_string(),
            "IRIS_ROUNDTRIP_OK".to_string(),
        ];

        assert_eq!(
            assistant_text_from_chunks(&chunks),
            "IRIS_ROUNDTRIP_OK".to_string()
        );
    }

    #[test]
    fn reconstructs_final_text_from_incremental_chunks() {
        let chunks = vec![
            "The result is ".to_string(),
            "IRIS_ACTION".to_string(),
            "_OK".to_string(),
        ];

        assert_eq!(
            assistant_text_from_chunks(&chunks),
            "The result is IRIS_ACTION_OK".to_string()
        );
    }

    #[test]
    fn ignores_tiny_retry_fragments_after_complete_text() {
        let chunks = vec![
            "IRIS_ROUNDTRIP_OK".to_string(),
            "I".to_string(),
            "I".to_string(),
        ];

        assert_eq!(
            assistant_text_from_chunks(&chunks),
            "IRIS_ROUNDTRIP_OK".to_string()
        );
    }

    #[test]
    fn recognizes_empty_agent_placeholders() {
        assert!(is_empty_agent_text(""));
        assert!(is_empty_agent_text("```text\n(empty)\n```"));
        assert!(is_empty_agent_text("(no content)"));
        assert!(!is_empty_agent_text("IRIS_ACTION_OK"));
    }

    #[test]
    fn falls_back_only_to_completed_tool_output() {
        let notifications = vec![
            json!({
                "method": "session/update",
                "params": {"update": {
                    "sessionUpdate": "tool_call_update",
                    "status": "failed",
                    "content": [{"type": "text", "text": "failed result"}]
                }}
            }),
            json!({
                "method": "session/update",
                "params": {"update": {
                    "sessionUpdate": "tool_call_update",
                    "status": "completed",
                    "content": [{"type": "text", "text": "IRIS_ACTION_OK"}]
                }}
            }),
        ];

        assert_eq!(
            fallback_text_from_successful_tool(&notifications).as_deref(),
            Some("Hermes completed the requested tool action.\nIRIS_ACTION_OK")
        );
    }

    #[test]
    fn extracts_structured_memory_provenance_from_tool_output() {
        let notifications = vec![json!({
            "method": "session/update",
            "params": {
                "update": {
                    "sessionUpdate": "tool_call_update",
                    "content": [{
                        "type": "content",
                        "content": {
                            "type": "text",
                            "text": "{\"results\":[{\"provenance\":{\"authority\":\"user_approved\",\"source\":\"iris_active_memory\",\"memoryId\":7}}]}"
                        }
                    }]
                }
            }
        })];

        assert_eq!(
            provenance_from_notifications(&notifications),
            vec![HermesProvenance {
                authority: "user_approved".to_string(),
                source: "iris_active_memory".to_string(),
                memory_id: Some(7),
                staging_id: None,
                evidence: None,
            }]
        );
    }

    #[test]
    fn extracts_provenance_marker_from_formatted_acp_tool_output() {
        let notifications = vec![json!({
            "method": "session/update",
            "params": {
                "update": {
                    "sessionUpdate": "tool_call_update",
                    "content": [{
                        "type": "content",
                        "content": {
                            "type": "text",
                            "text": "iris_query_memory result\n\nIRIS_PROVENANCE:{\"items\":[{\"provenance\":{\"authority\":\"user_approved\",\"source\":\"iris_active_memory\",\"memoryId\":7}}]}"
                        }
                    }]
                }
            }
        })];

        assert_eq!(
            provenance_from_notifications(&notifications),
            vec![HermesProvenance {
                authority: "user_approved".to_string(),
                source: "iris_active_memory".to_string(),
                memory_id: Some(7),
                staging_id: None,
                evidence: None,
            }]
        );
    }

    #[test]
    fn extracts_browser_preview_marker_from_tool_output() {
        let notifications = vec![json!({
            "method": "session/update",
            "params": {
                "update": {
                    "sessionUpdate": "tool_call_update",
                    "content": [{
                        "type": "text",
                        "text": "IRIS_BROWSER_PREVIEW:{\"url\":\"https://example.com\",\"screenshotPath\":\"C:\\\\Projects\\\\IRIS\\\\diagnostics\\\\browser\\\\shot.png\"}"
                    }]
                }
            }
        })];

        assert_eq!(
            browser_previews_from_notifications(&notifications),
            vec![BrowserPreview {
                url: "https://example.com".to_string(),
                screenshot_path: Some(
                    "C:\\Projects\\IRIS\\diagnostics\\browser\\shot.png".to_string()
                ),
            }]
        );
    }

    #[test]
    fn extracts_browser_preview_from_untrusted_tool_wrapper() {
        let notifications = vec![json!({
            "method": "session/update",
            "params": {
                "update": {
                    "sessionUpdate": "tool_call_update",
                    "content": [{
                        "type": "text",
                        "text": "<untrusted_tool_result>\n{\"success\":true,\"browserPreview\":{\"url\":\"https://example.com/\",\"screenshotPath\":\"C:\\\\Projects\\\\IRIS\\\\diagnostics\\\\browser\\\\shot.png\"},\"content\":\"IRIS_BROWSER_PREVIEW:{\\\"url\\\":\\\"https://example.com/\\\"}\"}\n</untrusted_tool_result>"
                    }]
                }
            }
        })];

        assert_eq!(
            browser_previews_from_notifications(&notifications),
            vec![BrowserPreview {
                url: "https://example.com/".to_string(),
                screenshot_path: Some(
                    "C:\\Projects\\IRIS\\diagnostics\\browser\\shot.png".to_string()
                ),
            }]
        );
    }

    #[test]
    fn classifies_permanent_confirmation_risks() {
        assert_eq!(
            classify_risk("run git reset --hard HEAD", Some("C:\\work")),
            RiskClass::DestructiveGit
        );
        assert_eq!(
            classify_risk("run winget install Example.Tool", Some("C:\\work")),
            RiskClass::InstallOrAdmin
        );
        assert_eq!(
            classify_risk("read C:\\work\\.env", Some("C:\\work")),
            RiskClass::Credentials
        );
        assert_eq!(
            classify_risk("payment browser click: Buy now", Some("C:\\work")),
            RiskClass::Payment
        );
        assert_eq!(
            classify_risk(
                "consequential browser submission: Submit order",
                Some("C:\\work")
            ),
            RiskClass::ConsequentialBrowserSubmission
        );
        assert_eq!(
            classify_risk("executable download: setup.exe", Some("C:\\work")),
            RiskClass::ExecutableDownload
        );
        assert_eq!(
            classify_risk(
                "scope expansion\nterminal workdir: C:\\other",
                Some("C:\\work")
            ),
            RiskClass::ScopeExpansion
        );
    }

    #[test]
    fn ordinary_workspace_edits_use_session_approval() {
        let request = json!({
            "id": 17,
            "params": {
                "toolCall": {
                    "title": "write: result.txt",
                    "rawInput": {
                        "tool": "write_file",
                        "arguments": {
                            "path": "C:\\work\\result.txt"
                        }
                    }
                },
                "options": [{
                    "optionId": "allow_once"
                }]
            }
        });

        let approval = approval_from_request(&request, Some("C:\\work"));
        assert_eq!(approval.request.risk_class, RiskClass::Ordinary);
        assert!(!approval.request.requires_separate_confirmation);
        assert_eq!(approval.allow_once_option.as_deref(), Some("allow_once"));
    }

    #[test]
    fn ordinary_browser_research_uses_session_approval() {
        let request = json!({
            "id": 18,
            "params": {
                "toolCall": {
                    "title": "browser_open: Brave Search",
                    "rawInput": {
                        "tool": "browser_open",
                        "arguments": {
                            "url": "https://search.brave.com/search?q=ollama"
                        }
                    }
                },
                "options": [{
                    "optionId": "allow_once"
                }]
            }
        });

        let approval = approval_from_request(&request, Some("C:\\work"));
        assert_eq!(approval.request.risk_class, RiskClass::Ordinary);
        assert!(!approval.request.requires_separate_confirmation);
        assert_eq!(approval.allow_once_option.as_deref(), Some("allow_once"));
    }

    #[test]
    fn action_audit_redacts_sensitive_values() {
        assert_eq!(
            redact_and_truncate("command\nAuthorization: Bearer private", 500),
            "command\n[redacted sensitive detail]"
        );
    }

    #[test]
    fn diagnostic_truncation_is_utf8_boundary_safe_and_redacted() {
        const LIMIT: usize = 2_000;
        let redacted_prefix = "[redacted sensitive detail]\n";
        let filler = "x".repeat(LIMIT - 1 - redacted_prefix.len());
        let input = format!("Authorization: Bearer private\n{filler}🦀");

        let output = redact_and_truncate(&input, LIMIT);

        assert!(output.starts_with(redacted_prefix));
        assert!(!output.contains("private"));
        assert!(!output.contains('🦀'));
        assert!(output.ends_with("..."));
        assert!(output.len() <= LIMIT + "...".len());
    }

    #[test]
    fn hermes_stderr_is_redacted_and_bounded() {
        let root = std::env::temp_dir().join(format!(
            "iris-hermes-stderr-{}-{}",
            std::process::id(),
            unix_timestamp_ms()
        ));
        fs::create_dir_all(&root).expect("diagnostics root");
        let path = root.join("hermes-acp-stderr.log");
        let input = std::io::Cursor::new(
            b"ordinary diagnostic\nAuthorization: Bearer private\nIRIS_HERMES_BROKER_URL=http://127.0.0.1:43123\nmore output\n",
        );

        write_bounded_stderr(input, &path, 64).expect("bounded log");
        let output = fs::read_to_string(&path).expect("diagnostic output");
        assert!(output.contains("ordinary diagnostic"));
        assert!(output.contains("[redacted sensitive detail]"));
        assert!(!output.contains("private"));
        assert!(!output.contains("43123"));
        assert!(path.metadata().expect("metadata").len() <= 64);
        fs::remove_dir_all(root).expect("remove diagnostics root");
    }

    #[test]
    fn hermes_stderr_streams_oversized_newline_free_output_with_fixed_retention() {
        let root = std::env::temp_dir().join(format!(
            "iris-hermes-stderr-oversized-{}-{}",
            std::process::id(),
            unix_timestamp_ms()
        ));
        fs::create_dir_all(&root).expect("diagnostics root");
        let path = root.join("hermes-acp-stderr.log");
        let input = std::io::Cursor::new(b"Authorization: Bearer never-write-this ")
            .chain(std::io::repeat(b'x').take(4 * 1024 * 1024));

        write_bounded_stderr(BufReader::with_capacity(127, input), &path, 128)
            .expect("bounded oversized log");
        let output = fs::read_to_string(&path).expect("diagnostic output");
        assert!(output.contains("[redacted sensitive detail]"));
        assert!(output.contains("[stderr line truncated]"));
        assert!(!output.contains("never-write-this"));
        assert!(path.metadata().expect("metadata").len() <= 128);
        fs::remove_dir_all(root).expect("remove diagnostics root");
    }

    #[test]
    fn runtime_paths_split_immutable_resources_from_writable_state() {
        let resources = Path::new("C:/Program Files/Iris");
        let state = Path::new("C:/Users/Iris/AppData/Local/Iris");
        let paths = RuntimePaths::new(resources, state);

        assert!(paths.site_packages.starts_with(resources));
        assert!(paths.launcher.starts_with(resources));
        assert!(paths.home.starts_with(state));
        assert!(paths.stderr_log.starts_with(state));
        assert!(paths.browser_command_output.starts_with(state));
        assert!(!paths.home.starts_with(resources));
        assert!(!paths.browser_command_output.starts_with(resources));
    }

    #[test]
    fn hermes_python_launch_uses_external_313_with_iris_owned_packages() {
        let resources = Path::new("C:/Program Files/Iris");
        let state = Path::new("C:/Users/Iris/AppData/Local/Iris");
        let paths = RuntimePaths::new(resources, state);
        let python = PythonLaunch {
            executable: PathBuf::from("C:/Python313/python.exe"),
            prefix_args: Vec::new(),
        };
        let command = python_command_for_script(&python, &paths.launcher, &paths.site_packages);
        let args = command
            .get_args()
            .map(|arg| arg.to_string_lossy().to_string())
            .collect::<Vec<_>>();
        let env = command
            .get_envs()
            .map(|(key, value)| {
                (
                    key.to_string_lossy().to_string(),
                    value.map(|value| value.to_string_lossy().to_string()),
                )
            })
            .collect::<HashMap<_, _>>();

        let expected_site_packages = paths.site_packages.to_string_lossy().to_string();
        assert_eq!(command.get_program(), python.executable.as_os_str());
        assert_eq!(
            args,
            [
                "-S".to_string(),
                paths.launcher.to_string_lossy().to_string()
            ]
        );
        assert_eq!(
            env.get("PYTHONPATH").and_then(|value| value.as_deref()),
            Some(expected_site_packages.as_str())
        );
        assert_eq!(
            env.get("PYTHONNOUSERSITE")
                .and_then(|value| value.as_deref()),
            Some("1")
        );
        assert_eq!(env.get("PYTHONHOME"), Some(&None));
        assert!(
            args.iter()
                .all(|arg| !arg.contains(".venv/Scripts/python.exe"))
        );
        assert!(!is_packaged_venv_python(&python, &paths.site_packages));
        assert!(is_packaged_venv_python(
            &PythonLaunch {
                executable: resources.join(".iris-runtime/hermes/.venv/Scripts/python.exe"),
                prefix_args: Vec::new(),
            },
            &paths.site_packages,
        ));
    }

    #[test]
    fn image_provider_uses_the_same_relocatable_python_launch() {
        let resources = Path::new("C:/Program Files/Iris");
        let state = Path::new("C:/Users/Iris/AppData/Local/Iris");
        let paths = RuntimePaths::new(resources, state);
        let script = resources.join("tools/iris_image_provider.py");
        let python = PythonLaunch {
            executable: PathBuf::from("C:/Python313/python.exe"),
            prefix_args: Vec::new(),
        };
        let command = python_command_for_script(&python, &script, &paths.site_packages);
        let args = command
            .get_args()
            .map(|arg| arg.to_string_lossy().to_string())
            .collect::<Vec<_>>();

        assert_eq!(command.get_program(), python.executable.as_os_str());
        assert_eq!(
            args,
            ["-S".to_string(), script.to_string_lossy().to_string()]
        );
        assert!(
            args.iter()
                .all(|arg| !arg.contains(".venv/Scripts/python.exe"))
        );
    }

    #[test]
    fn voice_python_launch_uses_only_the_iris_owned_voice_layer() {
        let resources = Path::new("C:/Program Files/Iris");
        let script = resources.join("tools/kokoro_tts.py");
        let voice_site_packages = resources.join(".iris-runtime/voice/Lib/site-packages");
        let python = PythonLaunch {
            executable: PathBuf::from("C:/Python313/python.exe"),
            prefix_args: Vec::new(),
        };
        let command = python_command_for_script(&python, &script, &voice_site_packages);
        let env = command
            .get_envs()
            .map(|(key, value)| {
                (
                    key.to_string_lossy().to_string(),
                    value.map(|value| value.to_string_lossy().to_string()),
                )
            })
            .collect::<HashMap<_, _>>();
        let expected = voice_site_packages.to_string_lossy().to_string();

        assert_eq!(
            env.get("PYTHONPATH").and_then(|value| value.as_deref()),
            Some(expected.as_str()),
        );
        assert!(!expected.contains(".iris-runtime/hermes"));
        assert_eq!(
            env.get("PYTHONNOUSERSITE")
                .and_then(|value| value.as_deref()),
            Some("1")
        );
    }

    #[test]
    fn read_only_venv_config_is_ignored_and_never_rewritten() {
        let root = std::env::temp_dir().join(format!(
            "iris-hermes-venv-config-test-{}",
            std::process::id()
        ));
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(&root).expect("test root");
        let config = root.join("pyvenv.cfg");
        let original = "home = C:\\build-machine\\Python313\nversion_info = 3.13.14\n";
        fs::write(&config, original).expect("venv config");
        let mut permissions = fs::metadata(&config)
            .expect("config metadata")
            .permissions();
        permissions.set_readonly(true);
        fs::set_permissions(&config, permissions).expect("read-only config");

        let resources = root.join("resources");
        let state = root.join("state");
        let paths = RuntimePaths::new(&resources, &state);
        let python = PythonLaunch {
            executable: PathBuf::from("C:/Python313/python.exe"),
            prefix_args: Vec::new(),
        };
        let _command = python_command_for_script(&python, &paths.launcher, &paths.site_packages);
        assert_eq!(
            fs::read_to_string(&config).expect("unchanged config"),
            original
        );

        #[allow(clippy::permissions_set_readonly_false)]
        {
            let mut permissions = fs::metadata(&config)
                .expect("config metadata")
                .permissions();
            permissions.set_readonly(false);
            fs::set_permissions(&config, permissions).expect("restore config permissions");
        }
        fs::remove_dir_all(root).expect("remove venv config test");
    }

    #[test]
    #[ignore = "requires the provisioned Hermes ACP runtime, browser runtime, and live local Ollama"]
    fn live_hermes_acp_browser_research_returns_preview() {
        let _serial = LIVE_ACP_TEST_LOCK
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        let _cleanup = BridgeCleanup;
        let root = Path::new(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .expect("workspace root");
        let status = runtime_status(root, root);
        assert!(status.installed, "{status:?}");
        assert!(status.browser_tools_enabled, "{status:?}");
        let manifest = iris_config::load_manifest_from_workspace(root).expect("manifest");
        let result = submit_task(
            root,
            root,
            root.to_string_lossy().as_ref(),
            &manifest.model_policy.model_id,
            "Call browser_open with https://example.com now. Do not call any other tool. Then reply with the page title from the tool result.",
        )
        .expect("live Hermes browser task");

        assert!(
            result.events.iter().any(
                |event| matches!(event, HermesEvent::BrowserPreview(preview) if preview.url.starts_with("https://example.com"))
            ),
            "{:?}",
            result.events
        );
        assert!(
            result.text.to_ascii_lowercase().contains("example"),
            "{}",
            result.text
        );
    }

    #[test]
    #[ignore = "requires the provisioned Hermes ACP runtime and live local Ollama"]
    fn live_hermes_acp_round_trip() {
        let _serial = LIVE_ACP_TEST_LOCK
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        let _cleanup = BridgeCleanup;
        let root = Path::new(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .expect("workspace root");
        let manifest: Value = serde_json::from_str(
            &fs::read_to_string(root.join("manifest.json")).expect("manifest.json"),
        )
        .expect("valid manifest.json");
        let model = manifest["model_policy"]["model_id"]
            .as_str()
            .expect("model id");

        let result = submit_task(
            root,
            root,
            root.to_str().expect("UTF-8 workspace path"),
            model,
            "Reply with exactly IRIS_ROUNDTRIP_OK and no other text.",
        )
        .expect("live Hermes ACP round trip");

        assert!(
            result
                .text
                .chars()
                .filter(|character| character.is_ascii_alphanumeric())
                .collect::<String>()
                .eq_ignore_ascii_case("IRISROUNDTRIPOK"),
            "unexpected ACP response: {}",
            result.text
        );
        assert!(
            result
                .events
                .iter()
                .any(|event| matches!(event, HermesEvent::Completion(_)))
        );
    }

    #[test]
    #[ignore = "requires the provisioned Hermes ACP runtime and live local Ollama"]
    fn live_hermes_acp_uses_iris_rag_and_staging_tools() {
        let _serial = LIVE_ACP_TEST_LOCK
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        let _cleanup = BridgeCleanup;
        let broker = FakeMemoryBroker::start();
        configure_test_memory_broker(&broker.url(), &broker.bearer_token)
            .expect("configure authenticated fake broker");
        let root = Path::new(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .expect("workspace root");
        let manifest: Value = serde_json::from_str(
            &fs::read_to_string(root.join("manifest.json")).expect("manifest.json"),
        )
        .expect("valid manifest.json");
        let model = manifest["model_policy"]["model_id"]
            .as_str()
            .expect("model id");
        let workspace = root.to_str().expect("UTF-8 workspace path");

        let query = submit_task(
            root,
            root,
            workspace,
            model,
            "You must call iris_query_memory with query `age` and limit 5. Then answer Alejandro's age in one sentence and cite memory ID 7.",
        )
        .expect("Hermes Iris RAG query");
        assert!(
            query.text.contains("45"),
            "unexpected RAG response: {}",
            query.text
        );
        assert!(query.provenance.iter().any(|item| {
            item.authority == "user_approved"
                && item.source == "iris_active_memory"
                && item.memory_id == Some(7)
        }));

        stop();
        let proposal = submit_task(
            root,
            root,
            workspace,
            model,
            "Call iris_propose_memory now. Set text to exactly `Alejandro prefers concise status reports`, source to exactly `user_statement`, and evidence to exactly `Direct user statement`. Do not answer until the tool returns. Then report that the proposal still requires user approval.",
        )
        .expect("Hermes Iris staged memory proposal");
        assert!(proposal.provenance.iter().any(|item| {
            item.authority == "untrusted_proposal"
                && item.source == "user_statement"
                && item.staging_id == Some(9)
        }));

        let observed = broker.requests.lock().expect("fake broker requests");
        assert!(observed.iter().any(|path| path == "/memory/search"));
        assert!(observed.iter().any(|path| path == "/memory/propose"));
    }

    #[test]
    #[ignore = "requires the provisioned Hermes ACP runtime and live local Ollama"]
    fn live_hermes_acp_file_shell_and_denied_destructive_git() {
        let _serial = LIVE_ACP_TEST_LOCK
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        let _cleanup = BridgeCleanup;
        let root = Path::new(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .expect("workspace root");
        let manifest: Value = serde_json::from_str(
            &fs::read_to_string(root.join("manifest.json")).expect("manifest.json"),
        )
        .expect("valid manifest.json");
        let model = manifest["model_policy"]["model_id"]
            .as_str()
            .expect("model id");
        let workspace =
            std::env::temp_dir().join(format!("iris-hermes-action-test-{}", std::process::id()));
        let _ = fs::remove_dir_all(&workspace);
        fs::create_dir_all(&workspace).expect("temporary action workspace");
        fs::write(workspace.join("seed.txt"), "IRIS_ACTION_OK").expect("write action test seed");
        let workspace_text = workspace.to_string_lossy().to_string();

        let read_prompt = "Call read_file on path `seed.txt` in the approved workspace now. Reply with exactly the file content.";
        let read = submit_task(root, root, &workspace_text, model, read_prompt)
            .expect("Hermes read_file task");
        assert!(read.text.contains("IRIS_ACTION_OK"), "{}", read.text);

        stop();
        let write = submit_task(
            root,
            root,
            &workspace_text,
            model,
            "Call write_file now with path result.txt and content exactly IRIS_WRITE_OK. Then report completion.",
        )
        .expect("Hermes write_file task");
        assert!(
            write
                .events
                .iter()
                .any(|event| matches!(event, HermesEvent::ToolActivity(activity) if activity.contains("result.txt")))
        );
        assert_eq!(
            fs::read_to_string(workspace.join("result.txt")).expect("written result"),
            "IRIS_WRITE_OK"
        );

        stop();
        let shell = submit_task(
            root,
            root,
            &workspace_text,
            model,
            "Call terminal with native PowerShell command `Write-Output 'IRIS_SHELL_OK'`. Reply with exactly its output.",
        )
        .expect("Hermes terminal task");
        assert!(shell.text.contains("IRIS_SHELL_OK"), "{}", shell.text);

        stop();
        let result = thread::scope(|scope| {
            let workspace_text = workspace_text.clone();
            let task = scope.spawn(move || {
                submit_task(
                    root,
                    root,
                    &workspace_text,
                    model,
                    "Call terminal with command `git reset --hard HEAD` now. Do not substitute another command.",
                )
            });
            let approval = (0..240)
                .find_map(|_| {
                    let approval = pending_approval();
                    if approval.is_none() {
                        thread::sleep(Duration::from_millis(250));
                    }
                    approval
                })
                .expect("destructive Git approval request");
            assert_eq!(approval.risk_class, RiskClass::DestructiveGit);
            respond_to_approval(&approval.request_id, false).expect("deny destructive Git");
            task.join().expect("Hermes destructive Git task thread")
        });
        assert!(
            result.is_ok(),
            "Hermes should report a denied action safely"
        );

        stop();
        fs::remove_dir_all(&workspace).expect("remove temporary action workspace");
    }
}
