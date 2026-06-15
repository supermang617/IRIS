use crate::hermes_policy::{ApprovalRequest, BrowserPreview, HermesEvent, RiskClass};
use serde::Serialize;
use serde_json::{Value, json};
use std::{
    collections::HashMap,
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
const HERMES_AGENT_VERSION: &str = "0.16.0";
const HERMES_WHEEL_SHA256: &str =
    "accb5a4a4827b41b3d162d2eb0b5f6db585d942ee23a3678ef21fc94d21c34a2";

static ACP_BRIDGE: OnceLock<Mutex<Option<Arc<HermesAcpBridge>>>> = OnceLock::new();

type AcpResponse = Result<Value, String>;
type PendingRequestMap = HashMap<u64, mpsc::Sender<AcpResponse>>;
type SharedPendingRequests = Arc<Mutex<PendingRequestMap>>;
type SharedPendingApproval = Arc<Mutex<Option<PendingAcpApproval>>>;

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
    event_sender: Arc<Mutex<Option<mpsc::Sender<Value>>>>,
    next_request_id: AtomicU64,
    session: Arc<Mutex<Option<AcpSession>>>,
    browser_command_output_dir: PathBuf,
    #[cfg(windows)]
    job: WindowsJob,
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

pub fn runtime_status(workspace_root: &Path) -> HermesAcpRuntimeStatus {
    let paths = RuntimePaths::new(workspace_root);
    let browser_exe = workspace_root
        .join(".iris-runtime/browser/node_modules/agent-browser/bin/agent-browser-win32-x64.exe");
    let chrome_exe =
        workspace_root.join(".iris-runtime/browser/browsers/chrome-149.0.7827.115/chrome.exe");
    let browser_tools_enabled = browser_exe.is_file() && chrome_exe.is_file();
    let running = ACP_BRIDGE
        .get()
        .and_then(|state| state.lock().ok())
        .and_then(|guard| guard.as_ref().cloned())
        .is_some_and(|bridge| bridge.is_running());
    HermesAcpRuntimeStatus {
        installed: paths.python.exists() && paths.launcher.exists() && browser_tools_enabled,
        running,
        initialized: running,
        version: HERMES_AGENT_VERSION,
        wheel_sha256: HERMES_WHEEL_SHA256,
        launcher_path: paths.launcher.to_string_lossy().to_string(),
        python_path: paths.python.to_string_lossy().to_string(),
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

pub fn submit_task(
    workspace_root: &Path,
    workspace_path: &str,
    model: &str,
    text: &str,
) -> Result<HermesAcpTaskResult, String> {
    let clean = text.trim();
    if clean.is_empty() {
        return Err("Agentic Hermes task cannot be empty".to_string());
    }
    let bridge = ensure_bridge(workspace_root, model)?;
    let session_id = bridge.ensure_session(workspace_path)?;
    let (event_tx, event_rx) = mpsc::channel();
    {
        let mut sender = bridge
            .event_sender
            .lock()
            .map_err(|_| "Hermes ACP event state is unavailable".to_string())?;
        *sender = Some(event_tx);
    }
    let first_response = bridge.request(
        "session/prompt",
        json!({
            "sessionId": session_id,
            "prompt": [{"type": "text", "text": clean}]
        }),
    );
    let mut raw_events = event_rx.try_iter().collect::<Vec<_>>();
    let mut text = assistant_text_from_notifications(&raw_events);
    let response = if first_response.is_ok() && is_empty_agent_text(&text) {
        let recovery = bridge.request(
            "session/prompt",
            json!({
                "sessionId": session_id,
                "prompt": [{
                    "type": "text",
                    "text": "Your previous final response was empty. Do not rerun the tool. Reply now with a concise, non-empty answer using the successful tool result already in this conversation."
                }]
            }),
        );
        raw_events.extend(event_rx.try_iter());
        recovery
    } else {
        first_response
    };
    if let Ok(mut sender) = bridge.event_sender.lock() {
        *sender = None;
    }
    response?;

    raw_events.extend(event_rx.try_iter());
    let mut events = Vec::new();
    let mut thinking_emitted = false;
    for event in raw_events.iter().filter_map(event_from_notification) {
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
    append_action_audit(workspace_root, &session_id, &raw_events)?;
    reject_repeated_tool_failures(&raw_events)?;
    if is_empty_agent_text(&text) {
        text = fallback_text_from_successful_tool(&raw_events)
            .ok_or_else(|| "Hermes ACP returned no assistant text".to_string())?;
    }
    events.push(HermesEvent::Thinking(false));
    events.push(HermesEvent::Completion(text.clone()));
    Ok(HermesAcpTaskResult {
        text,
        events,
        provenance,
    })
}

fn assistant_text_from_notifications(notifications: &[Value]) -> String {
    notifications
        .iter()
        .filter_map(agent_message_text)
        .collect::<Vec<_>>()
        .join("")
        .trim()
        .to_string()
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

fn ensure_bridge(workspace_root: &Path, model: &str) -> Result<Arc<HermesAcpBridge>, String> {
    let state = ACP_BRIDGE.get_or_init(|| Mutex::new(None));
    let mut guard = state
        .lock()
        .map_err(|_| "Hermes ACP bridge state is unavailable".to_string())?;
    if let Some(bridge) = guard.as_ref().filter(|bridge| bridge.is_running()) {
        return Ok(bridge.clone());
    }
    let bridge = Arc::new(HermesAcpBridge::start(workspace_root, model)?);
    bridge.initialize()?;
    *guard = Some(bridge.clone());
    Ok(bridge)
}

impl HermesAcpBridge {
    fn start(workspace_root: &Path, model: &str) -> Result<Self, String> {
        let paths = RuntimePaths::new(workspace_root);
        for (label, path) in [
            ("Hermes ACP Python", &paths.python),
            ("Iris Hermes ACP launcher", &paths.launcher),
        ] {
            if !path.exists() {
                return Err(format!("{label} is missing: {}", path.display()));
            }
        }
        if let Some(parent) = paths.stderr_log.parent() {
            fs::create_dir_all(parent).map_err(|err| err.to_string())?;
        }
        let stderr = OpenOptions::new()
            .create(true)
            .append(true)
            .open(&paths.stderr_log)
            .map_err(|err| format!("failed to open Hermes ACP diagnostics: {err}"))?;
        let mut command = Command::new(&paths.python);
        command
            .arg(&paths.launcher)
            .current_dir(workspace_root)
            .env("HERMES_HOME", &paths.home)
            .env("IRIS_HERMES_MODEL", model)
            .env("IRIS_HERMES_OLLAMA_BASE_URL", "http://127.0.0.1:11434/v1")
            .env("HERMES_DISABLE_LAZY_INSTALLS", "1")
            .env("PYTHONUTF8", "1")
            .env_remove("OPENAI_API_KEY")
            .env_remove("OPENROUTER_API_KEY")
            .env_remove("ANTHROPIC_API_KEY")
            .env_remove("NOUS_API_KEY")
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::from(stderr));
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
        #[cfg(windows)]
        let job = WindowsJob::create_and_assign(&child)?;
        let child = Arc::new(Mutex::new(child));
        let pending = Arc::new(Mutex::new(HashMap::new()));
        let pending_approval = Arc::new(Mutex::new(None));
        let event_sender = Arc::new(Mutex::new(None));
        let session = Arc::new(Mutex::new(None));
        start_reader(
            stdout,
            stdin.clone(),
            pending.clone(),
            pending_approval.clone(),
            event_sender.clone(),
            session.clone(),
        );
        Ok(Self {
            child,
            stdin,
            pending,
            pending_approval,
            event_sender,
            next_request_id: AtomicU64::new(1),
            session,
            browser_command_output_dir: workspace_root.join(".iris-runtime/browser/command-output"),
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
        rx.recv_timeout(ACP_REQUEST_TIMEOUT)
            .map_err(|_| format!("Hermes ACP request timed out: {method}"))??
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
    python: PathBuf,
    launcher: PathBuf,
    home: PathBuf,
    stderr_log: PathBuf,
}

impl RuntimePaths {
    fn new(workspace_root: &Path) -> Self {
        let runtime = workspace_root.join(".iris-runtime/hermes");
        Self {
            python: runtime.join(".venv/Scripts/python.exe"),
            launcher: workspace_root.join("plugins/hermes_acp/iris_acp.py"),
            home: workspace_root.join(".iris-data/hermes-home"),
            stderr_log: workspace_root.join("diagnostics/hermes-acp-stderr.log"),
        }
    }
}

fn start_reader(
    stdout: impl std::io::Read + Send + 'static,
    stdin: Arc<Mutex<ChildStdin>>,
    pending: SharedPendingRequests,
    pending_approval: SharedPendingApproval,
    event_sender: Arc<Mutex<Option<mpsc::Sender<Value>>>>,
    session: Arc<Mutex<Option<AcpSession>>>,
) {
    thread::spawn(move || {
        let mut malformed_lines = 0;
        for line in BufReader::new(stdout).lines() {
            let Ok(line) = line else {
                break;
            };
            let Ok(value) = parse_acp_line(&line) else {
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
                    if let Some(sender) = event_sender
                        .lock()
                        .ok()
                        .and_then(|sender| sender.as_ref().cloned())
                    {
                        let _ = sender.send(json!({
                            "method": "iris/approval_request",
                            "params": {"approval": approval.request}
                        }));
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
                && let Some(sender) = event_sender
                    .lock()
                    .ok()
                    .and_then(|sender| sender.as_ref().cloned())
            {
                let _ = sender.send(value);
            }
        }
        fail_pending_requests(&pending, "Hermes ACP stream closed or became malformed");
    });
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
    workspace_root: &Path,
    session_id: &str,
    notifications: &[Value],
) -> Result<(), String> {
    let path = workspace_root.join("diagnostics/hermes-actions.jsonl");
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
            if ["password", "secret", "api key", "token=", "authorization:"]
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
    if output.len() > limit {
        output.truncate(limit);
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
    use std::sync::atomic::AtomicBool;

    // Hermes ACP owns one supervised process and session, so live tests must not
    // compete for that singleton even when the Rust test runner is parallel.
    static LIVE_ACP_TEST_LOCK: Mutex<()> = Mutex::new(());

    struct BridgeCleanup;

    impl Drop for BridgeCleanup {
        fn drop(&mut self) {
            stop();
        }
    }

    struct FakeMemoryBroker {
        stop: Arc<AtomicBool>,
        thread: Option<thread::JoinHandle<()>>,
        requests: Arc<Mutex<Vec<String>>>,
    }

    impl FakeMemoryBroker {
        fn start() -> Self {
            let listener = std::net::TcpListener::bind("127.0.0.1:48731")
                .expect("bind fake Iris memory broker");
            listener
                .set_nonblocking(true)
                .expect("nonblocking fake broker");
            let stop = Arc::new(AtomicBool::new(false));
            let requests = Arc::new(Mutex::new(Vec::new()));
            let thread_stop = stop.clone();
            let thread_requests = requests.clone();
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
                            let path = request
                                .lines()
                                .next()
                                .and_then(|line| line.split_whitespace().nth(1))
                                .unwrap_or("/")
                                .to_string();
                            if let Ok(mut observed) = thread_requests.lock() {
                                observed.push(path.clone());
                            }
                            let body = match path.as_str() {
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
                                    "loopbackOnly": true
                                }),
                                _ => json!({"ok": false, "error": "unexpected route"}),
                            }
                            .to_string();
                            let response = format!(
                                "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
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
            }
        }
    }

    impl Drop for FakeMemoryBroker {
        fn drop(&mut self) {
            self.stop.store(true, Ordering::Relaxed);
            let _ = std::net::TcpStream::connect("127.0.0.1:48731");
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
    fn action_audit_redacts_sensitive_values() {
        assert_eq!(
            redact_and_truncate("command\nAuthorization: Bearer private", 500),
            "command\n[redacted sensitive detail]"
        );
    }

    #[test]
    fn runtime_paths_stay_inside_workspace() {
        let root = Path::new("C:/Projects/IRIS");
        let paths = RuntimePaths::new(root);

        assert!(paths.python.starts_with(root));
        assert!(paths.launcher.starts_with(root));
        assert!(paths.home.starts_with(root));
        assert!(paths.stderr_log.starts_with(root));
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
        let status = runtime_status(root);
        assert!(status.installed, "{status:?}");
        assert!(status.browser_tools_enabled, "{status:?}");
        let manifest = iris_config::load_manifest_from_workspace(root).expect("manifest");
        let result = submit_task(
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

        let seed_path = workspace
            .join("seed.txt")
            .to_string_lossy()
            .replace('\\', "/");
        let read_prompt =
            format!("Call read_file on `{seed_path}` now. Reply with exactly the file content.");
        let read =
            submit_task(root, &workspace_text, model, &read_prompt).expect("Hermes read_file task");
        assert!(read.text.contains("IRIS_ACTION_OK"), "{}", read.text);

        stop();
        let write = submit_task(
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
