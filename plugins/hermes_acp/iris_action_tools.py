from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import threading
import time
import uuid
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable


IRIS_ACTION_TOOLSETS = ("file", "terminal")
IRIS_ACTION_TOOLS = (
    "read_file",
    "write_file",
    "patch",
    "search_files",
    "terminal",
    "process",
)
SENSITIVE_PATH_PARTS = {
    ".aws",
    ".azure",
    ".git",
    ".gnupg",
    ".ssh",
    "credentials",
    "id_ed25519",
    "id_rsa",
}
SENSITIVE_FILE_NAMES = {
    ".env",
    ".env.local",
    ".env.production",
    "credentials.json",
}
MAX_PROCESS_OUTPUT_CHARS = 100_000
POWERSHELL_DESCRIPTION = (
    "Execute native Windows PowerShell 7 commands in the selected Iris workspace. "
    "Use read_file, search_files, write_file, and patch for file operations. "
    "Write PowerShell, not Bash: use Get-ChildItem instead of ls flags, "
    "Select-String instead of grep, and Select-Object instead of head or tail. "
    "Foreground commands return output and exit status. Set background=true for "
    "long-running work, then use process to poll, wait, inspect logs, send input, "
    "or stop it. Destructive or otherwise high-risk commands require Iris approval."
)
PROCESS_DESCRIPTION = (
    "Manage native PowerShell background processes started by terminal. "
    "Supported actions: list, poll, log, wait, kill, write, submit, and close."
)
BASHISM_REPAIRS = (
    (
        re.compile(r"\bls\s+-[A-Za-z]*a[A-Za-z]*\b", re.IGNORECASE),
        "Use `Get-ChildItem -Force` instead of `ls -la` or other Bash ls flags.",
    ),
    (
        re.compile(r"(^|[\s|;])grep(\s|$)", re.IGNORECASE),
        "Use `Select-String` instead of `grep`.",
    ),
    (
        re.compile(r"(^|[\s|;])head(\s|$)", re.IGNORECASE),
        "Use `Select-Object -First <count>` instead of `head`.",
    ),
    (
        re.compile(r"(^|[\s|;])tail(\s|$)", re.IGNORECASE),
        "Use `Select-Object -Last <count>` instead of `tail`.",
    ),
    (
        re.compile(r"&&|\|\|"),
        "Use PowerShell control flow or separate commands instead of Bash `&&` or `||`.",
    ),
)


@dataclass
class _NativeProcess:
    session_id: str
    task_id: str
    command: str
    cwd: str
    process: subprocess.Popen[str]
    started_at: float
    notify_on_complete: bool
    output: str = ""
    poll_offset: int = 0
    lock: threading.Lock = field(default_factory=threading.Lock)
    reader: threading.Thread | None = None


_native_processes: dict[str, _NativeProcess] = {}
_native_processes_lock = threading.Lock()


def register_iris_action_guards() -> tuple[str, ...]:
    import model_tools  # noqa: F401
    from tools.registry import registry

    _configure_file_tool_bash()
    for name in IRIS_ACTION_TOOLS:
        entry = registry.get_entry(name)
        if entry is None or getattr(entry.handler, "_iris_guarded", False):
            continue
        if name == "terminal":
            guarded = _native_terminal_handler
            description = POWERSHELL_DESCRIPTION
            schema = json.loads(json.dumps(entry.schema))
            schema["description"] = description
        elif name == "process":
            guarded = _native_process_handler
            description = PROCESS_DESCRIPTION
            schema = json.loads(json.dumps(entry.schema))
            schema["description"] = description
        else:
            guarded = _guard_handler(name, entry.handler)
            description = entry.description
            schema = entry.schema
        guarded._iris_guarded = True
        registry.register(
            name=entry.name,
            toolset=entry.toolset,
            schema=schema,
            handler=guarded,
            check_fn=entry.check_fn,
            requires_env=entry.requires_env,
            is_async=entry.is_async,
            description=description,
            emoji=entry.emoji,
            max_result_size_chars=entry.max_result_size_chars,
            dynamic_schema_overrides=entry.dynamic_schema_overrides,
        )

    registered = set(registry.get_all_tool_names())
    missing = [name for name in IRIS_ACTION_TOOLS if name not in registered]
    if missing:
        raise RuntimeError(f"Hermes action tools are unavailable: {', '.join(missing)}")
    return IRIS_ACTION_TOOLS


def _guard_handler(name: str, handler: Callable[..., str]) -> Callable[..., str]:
    def guarded(args: dict[str, Any], **kwargs: Any) -> str:
        workspace = _workspace_for_task(kwargs.get("task_id"))
        normalized_args = _normalize_path_args(name, args, workspace)
        for target in _paths_for_tool(name, normalized_args):
            risk = _path_risk(target, workspace)
            if risk and not _approve_once(
                f"{name}: {target}",
                risk,
            ):
                return json.dumps(
                    {"error": f"{risk} approval denied; no file operation was performed."}
                )
        return handler(normalized_args, **kwargs)

    return guarded


def _normalize_path_args(
    name: str,
    args: dict[str, Any],
    workspace: Path,
) -> dict[str, Any]:
    normalized = dict(args)
    if name in {"read_file", "write_file", "search_files"}:
        default_path = "." if name == "search_files" else ""
        raw = str(normalized.get("path") or default_path).strip()
        if raw:
            normalized["path"] = _upstream_file_path(
                _resolve_workspace_path(raw, workspace)
            )
    elif name == "patch" and normalized.get("mode", "replace") == "replace":
        raw = str(normalized.get("path") or "").strip()
        if raw:
            normalized["path"] = _upstream_file_path(
                _resolve_workspace_path(raw, workspace)
            )
    return normalized


def _paths_for_tool(name: str, args: dict[str, Any]) -> list[str]:
    if name in {"read_file", "write_file", "search_files"}:
        return [str(args.get("path") or ".")]
    if name != "patch":
        return []
    if args.get("mode", "replace") == "replace":
        return [str(args.get("path") or "")]
    paths: list[str] = []
    for line in str(args.get("patch") or "").splitlines():
        for prefix in (
            "*** Add File: ",
            "*** Update File: ",
            "*** Delete File: ",
            "*** Move to: ",
        ):
            if line.startswith(prefix):
                paths.append(line[len(prefix) :].strip())
                break
    return paths


def _resolve_workspace_path(raw_path: str, workspace: Path) -> Path:
    normalized = raw_path.strip()
    if (
        os.name == "nt"
        and len(normalized) >= 3
        and normalized[0] == "/"
        and normalized[1].isalpha()
        and normalized[2] == "/"
    ):
        normalized = f"{normalized[1]}:{normalized[2:]}"
    candidate = Path(normalized).expanduser()
    if not candidate.is_absolute():
        candidate = workspace / candidate
    return candidate.resolve(strict=False)


def _upstream_file_path(path: Path) -> str:
    return path.as_posix() if os.name == "nt" else str(path)


def _configure_file_tool_bash() -> None:
    if os.name != "nt":
        return
    configured = os.environ.get("HERMES_GIT_BASH_PATH", "").strip()
    candidates = [
        Path(configured) if configured else None,
        Path(os.environ.get("ProgramFiles", r"C:\Program Files"))
        / "Git"
        / "bin"
        / "bash.exe",
        Path(os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)"))
        / "Git"
        / "bin"
        / "bash.exe",
        Path(os.environ.get("LOCALAPPDATA", ""))
        / "Programs"
        / "Git"
        / "bin"
        / "bash.exe",
    ]
    for candidate in candidates:
        if candidate is not None and candidate.is_file():
            os.environ["HERMES_GIT_BASH_PATH"] = str(candidate)
            return
    raise RuntimeError(
        "Hermes file tools require Git for Windows Bash, but bash.exe was not found."
    )


def _workspace_for_task(task_id: Any) -> Path:
    from tools import terminal_tool

    selected = os.environ.get("IRIS_AGENTIC_WORKSPACE", "").strip()
    if selected:
        return Path(selected).expanduser().resolve(strict=False)
    raw = terminal_tool._task_env_overrides.get(str(task_id or ""), {}).get("cwd")
    return Path(str(raw or Path.cwd())).expanduser().resolve(strict=False)


def _path_risk(raw_path: str, workspace: Path) -> str | None:
    resolved = _resolve_workspace_path(raw_path, workspace)
    lowered_parts = {part.lower() for part in resolved.parts}
    if resolved.name.lower() in SENSITIVE_FILE_NAMES or lowered_parts & SENSITIVE_PATH_PARTS:
        return "sensitive files"
    try:
        resolved.relative_to(workspace)
    except ValueError:
        return "scope expansion"
    return None


def _approve_once(summary: str, description: str) -> bool:
    from tools import terminal_tool

    callback = terminal_tool._get_approval_callback()
    if callback is None:
        return False
    decision = callback(summary, description, allow_permanent=False)
    return decision == "once"


def _native_terminal_handler(args: dict[str, Any], **kwargs: Any) -> str:
    from tools import terminal_tool

    command = args.get("command")
    if not isinstance(command, str) or not command.strip():
        return _json_result(error="command must be a non-empty string")
    if args.get("pty"):
        return _json_result(
            error="PTY mode is not available in the Iris native PowerShell adapter."
        )

    task_id = str(kwargs.get("task_id") or "")
    workspace = _workspace_for_task(task_id)
    workdir_raw = str(args.get("workdir") or "").strip()
    workdir = _resolve_workspace_path(workdir_raw, workspace) if workdir_raw else workspace
    risk = _path_risk(str(workdir), workspace)
    if risk and not _approve_once(f"terminal workdir: {workdir}", risk):
        return _json_result(error=f"{risk} approval denied; command was not run.")
    if not workdir.is_dir():
        return _json_result(error=f"working directory does not exist: {workdir}")

    approval = terminal_tool._check_all_guards(command, "local")
    if not approval.get("approved"):
        return _approval_denied_result(command, approval)
    compatibility_error = _powershell_compatibility_error(command)
    if compatibility_error:
        return _json_result(error=compatibility_error)

    try:
        timeout = _coerce_timeout(args.get("timeout"), default=180)
    except (TypeError, ValueError):
        return _json_result(error="timeout must be a positive whole number")
    if not args.get("background") and timeout > 600:
        return _json_result(
            error="foreground timeout cannot exceed 600 seconds; use background=true"
        )

    process = _start_powershell(command, workdir)
    if args.get("background"):
        session = _track_background_process(
            process=process,
            command=command,
            cwd=workdir,
            task_id=task_id,
            notify_on_complete=bool(args.get("notify_on_complete")),
        )
        return json.dumps(
            {
                "output": "Background PowerShell process started",
                "session_id": session.session_id,
                "pid": process.pid,
                "exit_code": 0,
                "error": None,
            },
            ensure_ascii=False,
        )

    try:
        output, _ = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        _kill_process_tree(process)
        output, _ = process.communicate()
        return _json_result(
            output=output,
            exit_code=-1,
            error=f"PowerShell command timed out after {timeout} seconds",
        )
    output = _trim_output(output)
    return json.dumps(
        {
            "output": output,
            "exit_code": process.returncode,
            "error": None,
            "status": "completed" if process.returncode == 0 else "failed",
        },
        ensure_ascii=False,
    )


def _native_process_handler(args: dict[str, Any], **kwargs: Any) -> str:
    action = str(args.get("action") or "").strip().lower()
    task_id = str(kwargs.get("task_id") or "")
    if action == "list":
        with _native_processes_lock:
            sessions = [
                _process_summary(session)
                for session in _native_processes.values()
                if session.task_id == task_id
            ]
        return json.dumps({"processes": sessions}, ensure_ascii=False)

    session_id = str(args.get("session_id") or "").strip()
    session = _get_process(session_id, task_id)
    if session is None:
        return json.dumps(
            {"status": "not_found", "error": f"No process with ID {session_id}"},
            ensure_ascii=False,
        )

    if action == "poll":
        with session.lock:
            output = session.output[session.poll_offset :]
            session.poll_offset = len(session.output)
        return json.dumps(
            {**_process_summary(session), "output": output},
            ensure_ascii=False,
        )
    if action == "log":
        with session.lock:
            lines = session.output.splitlines()
        offset = args.get("offset")
        limit = args.get("limit")
        start = int(offset) if offset is not None else max(0, len(lines) - 200)
        count = int(limit) if limit is not None else 200
        return json.dumps(
            {
                **_process_summary(session),
                "output": "\n".join(lines[start : start + max(1, count)]),
                "offset": start,
                "total_lines": len(lines),
            },
            ensure_ascii=False,
        )
    if action == "wait":
        try:
            timeout = _coerce_timeout(args.get("timeout"), default=60)
        except (TypeError, ValueError):
            return _json_result(error="timeout must be a positive whole number")
        try:
            session.process.wait(timeout=max(1, timeout))
        except subprocess.TimeoutExpired:
            return json.dumps(
                {
                    **_process_summary(session),
                    "timeout_note": f"Waited {timeout}s, process still running",
                },
                ensure_ascii=False,
            )
        _finalize_process(session)
        return json.dumps(_process_summary(session), ensure_ascii=False)
    if action == "kill":
        _kill_process_tree(session.process)
        _finalize_process(session)
        return json.dumps(_process_summary(session), ensure_ascii=False)
    if action in {"write", "submit"}:
        if session.process.poll() is not None or session.process.stdin is None:
            return json.dumps(
                {"status": "already_exited", "error": "Process stdin is unavailable"},
                ensure_ascii=False,
            )
        data = str(args.get("data") or "")
        if action == "submit":
            data += os.linesep
        session.process.stdin.write(data)
        session.process.stdin.flush()
        return json.dumps(
            {"status": "ok", "bytes_written": len(data)},
            ensure_ascii=False,
        )
    if action == "close":
        if session.process.stdin is not None:
            session.process.stdin.close()
        return json.dumps({"status": "ok"}, ensure_ascii=False)
    return json.dumps(
        {"status": "error", "error": f"Unsupported process action: {action}"},
        ensure_ascii=False,
    )


def _powershell_executable() -> str:
    modern = shutil.which("pwsh.exe") or shutil.which("pwsh")
    if modern:
        return modern
    system_root = Path(os.environ.get("SystemRoot", r"C:\Windows"))
    candidate = system_root / "System32" / "WindowsPowerShell" / "v1.0" / "powershell.exe"
    return str(candidate) if candidate.is_file() else "powershell.exe"


def _start_powershell(command: str, cwd: Path) -> subprocess.Popen[str]:
    from tools.environments.local import _sanitize_subprocess_env

    prefix = (
        "[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false); "
        "[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false); "
        "$OutputEncoding = [Console]::OutputEncoding; "
    )
    creationflags = getattr(subprocess, "CREATE_NO_WINDOW", 0)
    return subprocess.Popen(
        [
            _powershell_executable(),
            "-NoLogo",
            "-NoProfile",
            "-NonInteractive",
            "-ExecutionPolicy",
            "Bypass",
            "-Command",
            prefix + command,
        ],
        cwd=str(cwd),
        env=_sanitize_subprocess_env(os.environ),
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
        creationflags=creationflags,
    )


def _track_background_process(
    *,
    process: subprocess.Popen[str],
    command: str,
    cwd: Path,
    task_id: str,
    notify_on_complete: bool,
) -> _NativeProcess:
    session = _NativeProcess(
        session_id=f"proc_{uuid.uuid4().hex[:12]}",
        task_id=task_id,
        command=command,
        cwd=str(cwd),
        process=process,
        started_at=time.time(),
        notify_on_complete=notify_on_complete,
    )
    with _native_processes_lock:
        _native_processes[session.session_id] = session

    def collect_output() -> None:
        if process.stdout is None:
            return
        with process.stdout:
            while True:
                chunk = process.stdout.read(4096)
                if not chunk:
                    break
                with session.lock:
                    session.output = _trim_output(session.output + chunk)

    session.reader = threading.Thread(
        target=collect_output,
        name=f"iris-hermes-{session.session_id}",
        daemon=True,
    )
    session.reader.start()
    return session


def _get_process(session_id: str, task_id: str) -> _NativeProcess | None:
    with _native_processes_lock:
        session = _native_processes.get(session_id)
    if session is None or session.task_id != task_id:
        return None
    return session


def _process_summary(session: _NativeProcess) -> dict[str, Any]:
    exit_code = session.process.poll()
    if exit_code is not None:
        _finalize_process(session)
    return {
        "session_id": session.session_id,
        "pid": session.process.pid,
        "command": session.command,
        "cwd": session.cwd,
        "status": "running" if exit_code is None else "exited",
        "exit_code": exit_code,
        "runtime_seconds": round(time.time() - session.started_at, 3),
        "notify_on_complete": session.notify_on_complete,
    }


def _kill_process_tree(process: subprocess.Popen[str]) -> None:
    if process.poll() is not None:
        return
    if os.name == "nt":
        subprocess.run(
            ["taskkill.exe", "/PID", str(process.pid), "/T", "/F"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
    else:
        process.terminate()
    try:
        process.wait(timeout=2)
    except subprocess.TimeoutExpired:
        process.kill()


def _finalize_process(session: _NativeProcess) -> None:
    if session.reader is not None and session.reader is not threading.current_thread():
        session.reader.join(timeout=1)
    if session.process.stdin is not None and not session.process.stdin.closed:
        session.process.stdin.close()


def _approval_denied_result(command: str, approval: dict[str, Any]) -> str:
    if approval.get("status") == "pending_approval":
        return json.dumps(
            {
                "output": "",
                "exit_code": -1,
                "error": "",
                "status": "pending_approval",
                "approval_pending": True,
                "command": approval.get("command", command),
                "description": approval.get("description", "command flagged"),
                "pattern_key": approval.get("pattern_key", ""),
            },
            ensure_ascii=False,
        )
    message = approval.get("message") or (
        f"Command denied: {approval.get('description', 'command flagged')}"
    )
    if "denied" in str(message).lower():
        return json.dumps(
            {
                "output": (
                    "The user denied this action. No command was run. "
                    "Stop this workflow and report the denial without trying alternatives."
                ),
                "exit_code": 0,
                "error": None,
                "status": "denied",
            },
            ensure_ascii=False,
        )
    return _json_result(error=str(message))


def _trim_output(output: str) -> str:
    if len(output) <= MAX_PROCESS_OUTPUT_CHARS:
        return output
    return "[earlier output truncated]\n" + output[-MAX_PROCESS_OUTPUT_CHARS:]


def _coerce_timeout(value: Any, *, default: int) -> int:
    if value is None:
        return default
    numeric = float(value)
    if not numeric.is_integer() or numeric < 1:
        raise ValueError("timeout is not a positive whole number")
    return int(numeric)


def _powershell_compatibility_error(command: str) -> str | None:
    for pattern, repair in BASHISM_REPAIRS:
        if pattern.search(command):
            return (
                "Iris terminal runs native Windows PowerShell, not Bash. "
                f"{repair} No command was run."
            )
    return None


def _json_result(
    *,
    output: str = "",
    exit_code: int = -1,
    error: str | None = None,
) -> str:
    return json.dumps(
        {
            "output": _trim_output(output),
            "exit_code": exit_code,
            "error": error,
            "status": "error" if error else "completed",
        },
        ensure_ascii=False,
    )
