use serde::{Deserialize, Serialize};
use std::{
    fs::{self, OpenOptions},
    io::{BufRead, BufReader, Write},
    process::{Child, ChildStdin, Command, Stdio},
    sync::{Arc, Mutex, OnceLock},
    thread,
    time::{Instant, SystemTime, UNIX_EPOCH},
};

#[cfg(windows)]
use std::os::windows::process::CommandExt;

#[cfg(windows)]
const CREATE_NO_WINDOW: u32 = 0x08000000;

static KOKORO_WORKER: OnceLock<Mutex<Option<KokoroWorker>>> = OnceLock::new();
const MAX_MEMORY_ITEMS: usize = 40;

#[derive(Debug, Clone, Serialize)]
struct HudCommandResponse {
    text: String,
    cancelled: bool,
    model_elapsed_ms: u128,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "lowercase")]
enum ConversationRole {
    User,
    Iris,
}

#[derive(Debug, Clone, Deserialize)]
struct ConversationTurn {
    role: ConversationRole,
    text: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct MemoryItem {
    id: u64,
    text: String,
    created_ms: u128,
    updated_ms: u128,
}

#[derive(Debug, Clone, Serialize)]
struct AsrCommandResponse {
    text: String,
    elapsed_ms: u128,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct TtsCommandResponse {
    wav_bytes: Vec<u8>,
    elapsed_ms: u128,
    voice: String,
}

#[derive(Debug, Clone)]
struct KokoroSettings {
    workspace_root: std::path::PathBuf,
    model_path: std::path::PathBuf,
    voices_path: std::path::PathBuf,
    helper_path: std::path::PathBuf,
    voice: String,
    lang: String,
    speed: f32,
}

struct KokoroWorker {
    child: Child,
    stdin: ChildStdin,
    stdout: BufReader<std::process::ChildStdout>,
}

#[derive(Debug, Deserialize)]
struct KokoroWorkerResponse {
    ok: bool,
    #[serde(default)]
    wav_b64: String,
    #[serde(default)]
    error: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
struct VoiceDiagnosticEvent {
    event: String,
    detail: String,
    mode: String,
    listening: bool,
    thinking: bool,
    #[serde(default)]
    speaking: bool,
    voice_loop: bool,
    wake_word: bool,
    wake_command_armed: bool,
}

#[tauri::command]
fn dashboard_snapshot() -> Result<iris_status::DashboardSnapshot, String> {
    current_dashboard_snapshot()
}

fn current_dashboard_snapshot() -> Result<iris_status::DashboardSnapshot, String> {
    let cwd = std::env::current_dir().map_err(|err| err.to_string())?;
    let manifest_path = iris_config::find_manifest_path(&cwd)?;
    let manifest = iris_config::load_manifest_from_workspace(&cwd)?;
    let hardware = iris_hardware::scan_system();
    let _workspace_root = manifest_path
        .parent()
        .ok_or_else(|| "manifest path has no parent".to_string())?;
    Ok(iris_status::build_dashboard_snapshot(&manifest, &hardware))
}

#[tauri::command]
async fn submit_typed_hud(
    text: String,
    history: Option<Vec<ConversationTurn>>,
) -> HudCommandResponse {
    tauri::async_runtime::spawn_blocking(move || submit_typed_hud_blocking(text, history))
        .await
        .unwrap_or_else(|err| HudCommandResponse {
            text: format!("Local model unavailable: {err}"),
            cancelled: false,
            model_elapsed_ms: 0,
        })
}

#[tauri::command]
fn list_memories() -> Result<Vec<MemoryItem>, String> {
    load_memories()
}

#[tauri::command]
fn add_memory(text: String) -> Result<Vec<MemoryItem>, String> {
    let text = normalize_memory_text(&text)?;
    let mut memories = load_memories()?;
    let now = timestamp_ms()?;
    let id = memories.iter().map(|memory| memory.id).max().unwrap_or(0) + 1;
    memories.push(MemoryItem {
        id,
        text,
        created_ms: now,
        updated_ms: now,
    });
    trim_memory_cap(&mut memories);
    save_memories(&memories)?;
    Ok(memories)
}

#[tauri::command]
fn edit_memory(id: u64, text: String) -> Result<Vec<MemoryItem>, String> {
    let text = normalize_memory_text(&text)?;
    let mut memories = load_memories()?;
    let now = timestamp_ms()?;
    let memory = memories
        .iter_mut()
        .find(|memory| memory.id == id)
        .ok_or_else(|| format!("memory {id} does not exist"))?;
    memory.text = text;
    memory.updated_ms = now;
    save_memories(&memories)?;
    Ok(memories)
}

#[tauri::command]
fn delete_memory(id: u64) -> Result<Vec<MemoryItem>, String> {
    let mut memories = load_memories()?;
    let original_len = memories.len();
    memories.retain(|memory| memory.id != id);
    if memories.len() == original_len {
        return Err(format!("memory {id} does not exist"));
    }
    save_memories(&memories)?;
    Ok(memories)
}

fn submit_typed_hud_blocking(
    text: String,
    history: Option<Vec<ConversationTurn>>,
) -> HudCommandResponse {
    let started = Instant::now();
    let history = history.unwrap_or_default();
    let response = match model_response(&text, &history) {
        Ok(response) => response,
        Err(error) => iris_core_types::AssistantResponse::text_only(format!(
            "Local model unavailable: {error}"
        )),
    };
    HudCommandResponse {
        text: response.text,
        cancelled: response.cancelled,
        model_elapsed_ms: started.elapsed().as_millis(),
    }
}

#[tauri::command]
async fn native_asr_listen_once() -> Result<AsrCommandResponse, String> {
    tauri::async_runtime::spawn_blocking(|| {
        native_asr_listen_for(
            6_500,
            CaptureEndpoint::Speech {
                min_ms: 800,
                trailing_silence_ms: 650,
            },
        )
    })
    .await
    .map_err(|err| err.to_string())?
}

#[tauri::command]
async fn native_asr_listen_interrupt() -> Result<AsrCommandResponse, String> {
    tauri::async_runtime::spawn_blocking(|| native_asr_listen_for(1_500, CaptureEndpoint::Fixed))
        .await
        .map_err(|err| err.to_string())?
}

fn native_asr_listen_for(
    duration_ms: u64,
    endpoint: CaptureEndpoint,
) -> Result<AsrCommandResponse, String> {
    let started = Instant::now();
    let audio = record_microphone_mono_16khz(duration_ms, endpoint)?;
    let text = transcribe_local_whisper(&audio)?;
    Ok(AsrCommandResponse {
        text,
        elapsed_ms: started.elapsed().as_millis(),
    })
}

#[tauri::command]
async fn kokoro_tts_wav(text: String) -> Result<TtsCommandResponse, String> {
    tauri::async_runtime::spawn_blocking(move || kokoro_tts_wav_blocking(text))
        .await
        .map_err(|err| err.to_string())?
}

#[tauri::command]
async fn warm_kokoro_tts() -> Result<(), String> {
    tauri::async_runtime::spawn_blocking(|| {
        let settings = kokoro_settings()?;
        let slot = KOKORO_WORKER.get_or_init(|| Mutex::new(None));
        let mut guard = slot.lock().map_err(|err| err.to_string())?;
        if guard.is_none() {
            *guard = Some(start_kokoro_worker(&settings)?);
        }
        Ok(())
    })
    .await
    .map_err(|err| err.to_string())?
}

fn kokoro_tts_wav_blocking(text: String) -> Result<TtsCommandResponse, String> {
    let started = Instant::now();
    let text = text.trim();
    if text.is_empty() {
        return Err("cannot synthesize empty speech".to_string());
    }
    if text.chars().count() > 4_000 {
        return Err("speech text is too long for one local Kokoro turn".to_string());
    }

    let settings = kokoro_settings()?;
    let wav_bytes = synthesize_with_warm_kokoro(&settings, text)
        .or_else(|_| synthesize_with_one_shot_kokoro(&settings, text))?;
    Ok(TtsCommandResponse {
        wav_bytes,
        elapsed_ms: started.elapsed().as_millis(),
        voice: settings.voice,
    })
}

fn kokoro_settings() -> Result<KokoroSettings, String> {
    let workspace_root = workspace_root()?;
    let manifest = iris_config::load_manifest_from_workspace(&workspace_root)?;
    let tts = manifest.tts_policy;
    let model_path = workspace_root.join(&tts.model_path);
    let voices_path = workspace_root.join(&tts.voices_path);
    let helper_path = workspace_root.join(&tts.helper_path);
    if !model_path.exists() {
        return Err(format!("missing Kokoro model: {}", model_path.display()));
    }
    if !voices_path.exists() {
        return Err(format!("missing Kokoro voices: {}", voices_path.display()));
    }
    if !helper_path.exists() {
        return Err(format!("missing Kokoro helper: {}", helper_path.display()));
    }

    Ok(KokoroSettings {
        workspace_root,
        model_path,
        voices_path,
        helper_path,
        voice: tts.voice,
        lang: tts.lang,
        speed: tts.speed,
    })
}

fn synthesize_with_warm_kokoro(settings: &KokoroSettings, text: &str) -> Result<Vec<u8>, String> {
    let slot = KOKORO_WORKER.get_or_init(|| Mutex::new(None));
    let mut guard = slot.lock().map_err(|err| err.to_string())?;
    if guard.is_none() {
        *guard = Some(start_kokoro_worker(settings)?);
    }

    let result = match guard.as_mut() {
        Some(worker) => worker.synthesize(text),
        None => Err("Kokoro worker did not start".to_string()),
    };
    if result.is_err() {
        *guard = None;
    }
    result
}

fn start_kokoro_worker(settings: &KokoroSettings) -> Result<KokoroWorker, String> {
    let python = std::env::var("IRIS_PYTHON").unwrap_or_else(|_| "python".to_string());
    let mut command = Command::new(python);
    #[cfg(windows)]
    command.creation_flags(CREATE_NO_WINDOW);
    let mut child = command
        .arg(&settings.helper_path)
        .arg("--model")
        .arg(&settings.model_path)
        .arg("--voices")
        .arg(&settings.voices_path)
        .arg("--voice")
        .arg(&settings.voice)
        .arg("--lang")
        .arg(&settings.lang)
        .arg("--speed")
        .arg(settings.speed.to_string())
        .arg("--server")
        .current_dir(&settings.workspace_root)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|err| format!("failed to start warm Kokoro helper: {err}"))?;

    let stdin = child
        .stdin
        .take()
        .ok_or_else(|| "failed to open warm Kokoro stdin".to_string())?;
    let stdout = child
        .stdout
        .take()
        .ok_or_else(|| "failed to open warm Kokoro stdout".to_string())?;

    Ok(KokoroWorker {
        child,
        stdin,
        stdout: BufReader::new(stdout),
    })
}

impl KokoroWorker {
    fn synthesize(&mut self, text: &str) -> Result<Vec<u8>, String> {
        if let Ok(Some(status)) = self.child.try_wait() {
            return Err(format!("warm Kokoro helper exited: {status}"));
        }
        let request = serde_json::json!({
            "id": timestamp_ms()?,
            "text": text,
        });
        writeln!(self.stdin, "{request}")
            .map_err(|err| format!("failed to send text to warm Kokoro: {err}"))?;
        self.stdin
            .flush()
            .map_err(|err| format!("failed to flush warm Kokoro stdin: {err}"))?;

        let mut line = String::new();
        self.stdout
            .read_line(&mut line)
            .map_err(|err| format!("failed to read warm Kokoro response: {err}"))?;
        if line.trim().is_empty() {
            return Err("warm Kokoro returned no response".to_string());
        }
        let response = serde_json::from_str::<KokoroWorkerResponse>(&line)
            .map_err(|err| format!("invalid warm Kokoro response: {err}"))?;
        if !response.ok {
            return Err(format!("warm Kokoro failed: {}", response.error));
        }
        base64_decode(&response.wav_b64)
    }
}

fn synthesize_with_one_shot_kokoro(
    settings: &KokoroSettings,
    text: &str,
) -> Result<Vec<u8>, String> {
    let tmp_dir = settings.workspace_root.join("tmp/tts");
    fs::create_dir_all(&tmp_dir).map_err(|err| err.to_string())?;
    let output_path = tmp_dir.join(format!("iris-{}.wav", timestamp_ms()?));
    let python = std::env::var("IRIS_PYTHON").unwrap_or_else(|_| "python".to_string());
    let mut command = Command::new(python);
    #[cfg(windows)]
    command.creation_flags(CREATE_NO_WINDOW);
    let mut child = command
        .arg(&settings.helper_path)
        .arg("--model")
        .arg(&settings.model_path)
        .arg("--voices")
        .arg(&settings.voices_path)
        .arg("--voice")
        .arg(&settings.voice)
        .arg("--lang")
        .arg(&settings.lang)
        .arg("--speed")
        .arg(settings.speed.to_string())
        .arg("--output")
        .arg(&output_path)
        .current_dir(&settings.workspace_root)
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|err| format!("failed to start Kokoro helper: {err}"))?;

    child
        .stdin
        .as_mut()
        .ok_or_else(|| "failed to open Kokoro helper stdin".to_string())?
        .write_all(text.as_bytes())
        .map_err(|err| format!("failed to send text to Kokoro helper: {err}"))?;
    drop(child.stdin.take());

    let output = child
        .wait_with_output()
        .map_err(|err| format!("failed to wait for Kokoro helper: {err}"))?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        let _ = fs::remove_file(&output_path);
        return Err(format!("Kokoro helper failed: {}", stderr.trim()));
    }

    let wav_bytes = fs::read(&output_path)
        .map_err(|err| format!("failed to read Kokoro wav {}: {err}", output_path.display()))?;
    let _ = fs::remove_file(&output_path);
    Ok(wav_bytes)
}

fn base64_decode(text: &str) -> Result<Vec<u8>, String> {
    fn value(byte: u8) -> Option<u8> {
        match byte {
            b'A'..=b'Z' => Some(byte - b'A'),
            b'a'..=b'z' => Some(byte - b'a' + 26),
            b'0'..=b'9' => Some(byte - b'0' + 52),
            b'+' => Some(62),
            b'/' => Some(63),
            _ => None,
        }
    }

    let cleaned = text
        .bytes()
        .filter(|byte| !byte.is_ascii_whitespace())
        .collect::<Vec<_>>();
    if cleaned.len() % 4 != 0 {
        return Err("invalid base64 length".to_string());
    }
    let mut output = Vec::with_capacity(cleaned.len() / 4 * 3);
    for chunk in cleaned.chunks(4) {
        let a = value(chunk[0]).ok_or_else(|| "invalid base64 data".to_string())?;
        let b = value(chunk[1]).ok_or_else(|| "invalid base64 data".to_string())?;
        let c = if chunk[2] == b'=' {
            0
        } else {
            value(chunk[2]).ok_or_else(|| "invalid base64 data".to_string())?
        };
        let d = if chunk[3] == b'=' {
            0
        } else {
            value(chunk[3]).ok_or_else(|| "invalid base64 data".to_string())?
        };
        let n = ((a as u32) << 18) | ((b as u32) << 12) | ((c as u32) << 6) | d as u32;
        output.push(((n >> 16) & 0xff) as u8);
        if chunk[2] != b'=' {
            output.push(((n >> 8) & 0xff) as u8);
        }
        if chunk[3] != b'=' {
            output.push((n & 0xff) as u8);
        }
    }
    Ok(output)
}

#[allow(dead_code)]
fn _old_signature_anchor() {
    let _ = (
        6_500,
        CaptureEndpoint::Speech {
            min_ms: 800,
            trailing_silence_ms: 650,
        },
    );
}

#[tauri::command]
fn log_voice_diagnostic(event: VoiceDiagnosticEvent) -> Result<(), String> {
    let workspace_root = workspace_root()?;
    let diagnostics_dir = workspace_root.join("diagnostics");
    fs::create_dir_all(&diagnostics_dir).map_err(|err| err.to_string())?;
    let log_path = diagnostics_dir.join("voice-events.jsonl");
    let timestamp_ms = timestamp_ms()?;
    let line = format!(
        "{{\"timestamp_ms\":{},\"event\":\"{}\",\"detail\":\"{}\",\"mode\":\"{}\",\"listening\":{},\"thinking\":{},\"speaking\":{},\"voice_loop\":{},\"wake_word\":{},\"wake_command_armed\":{}}}\n",
        timestamp_ms,
        json_safe(&event.event),
        json_safe(&event.detail),
        json_safe(&event.mode),
        event.listening,
        event.thinking,
        event.speaking,
        event.voice_loop,
        event.wake_word,
        event.wake_command_armed
    );
    let mut file = OpenOptions::new()
        .create(true)
        .append(true)
        .open(log_path)
        .map_err(|err| err.to_string())?;
    file.write_all(line.as_bytes())
        .map_err(|err| err.to_string())
}

fn timestamp_ms() -> Result<u128, String> {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|err| err.to_string())
        .map(|duration| duration.as_millis())
}

fn json_safe(value: &str) -> String {
    value
        .chars()
        .take(500)
        .flat_map(|character| character.escape_default())
        .collect()
}

fn memory_file_path() -> Result<std::path::PathBuf, String> {
    Ok(workspace_root()?.join(".iris-data/memories.json"))
}

fn load_memories() -> Result<Vec<MemoryItem>, String> {
    let path = memory_file_path()?;
    if !path.exists() {
        return Ok(Vec::new());
    }
    let bytes = fs::read(&path)
        .map_err(|err| format!("failed to read memories {}: {err}", path.display()))?;
    if bytes.is_empty() {
        return Ok(Vec::new());
    }
    let mut memories = serde_json::from_slice::<Vec<MemoryItem>>(&bytes)
        .map_err(|err| format!("failed to parse memories {}: {err}", path.display()))?;
    trim_memory_cap(&mut memories);
    Ok(memories)
}

fn save_memories(memories: &[MemoryItem]) -> Result<(), String> {
    let path = memory_file_path()?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|err| err.to_string())?;
    }
    let json = serde_json::to_vec_pretty(memories).map_err(|err| err.to_string())?;
    fs::write(&path, json)
        .map_err(|err| format!("failed to write memories {}: {err}", path.display()))
}

fn normalize_memory_text(text: &str) -> Result<String, String> {
    let clean = text.split_whitespace().collect::<Vec<_>>().join(" ");
    if clean.is_empty() {
        return Err("memory text cannot be empty".to_string());
    }
    if clean.chars().count() > 240 {
        return Err("memory text must be 240 characters or less".to_string());
    }
    Ok(clean)
}

fn trim_memory_cap(memories: &mut Vec<MemoryItem>) {
    memories.sort_by_key(|memory| memory.created_ms);
    if memories.len() > MAX_MEMORY_ITEMS {
        let excess = memories.len() - MAX_MEMORY_ITEMS;
        memories.drain(0..excess);
    }
}

fn workspace_root() -> Result<std::path::PathBuf, String> {
    let cwd = std::env::current_dir().map_err(|err| err.to_string())?;
    let manifest_path = iris_config::find_manifest_path(&cwd).or_else(|_| {
        let exe = std::env::current_exe().map_err(|err| err.to_string())?;
        iris_config::find_manifest_path(exe)
    })?;
    manifest_path
        .parent()
        .map(std::path::Path::to_path_buf)
        .ok_or_else(|| "manifest path has no parent".to_string())
}

fn model_response(
    text: &str,
    history: &[ConversationTurn],
) -> Result<iris_core_types::AssistantResponse, String> {
    let cwd = std::env::current_dir().map_err(|err| err.to_string())?;
    let manifest = iris_config::load_manifest_from_workspace(&cwd)?;
    let settings = iris_ollama::OllamaSettings::from_manifest(&manifest)?;
    let client = iris_ollama::OllamaClient::new(settings)?;
    let gated_context = iris_ui::gate_typed_text(text);
    let ollama_history = history
        .iter()
        .map(|turn| iris_ollama::ConversationTurn {
            role: match turn.role {
                ConversationRole::User => iris_ollama::ConversationRole::User,
                ConversationRole::Iris => iris_ollama::ConversationRole::Iris,
            },
            text: turn.text.clone(),
        })
        .collect::<Vec<_>>();
    let memories = load_memories()?
        .into_iter()
        .map(|memory| memory.text)
        .collect::<Vec<_>>();
    Ok(client.respond_with_history_and_memories(&gated_context, &ollama_history, &memories))
}

#[derive(Debug, Clone, Copy)]
enum CaptureEndpoint {
    Fixed,
    Speech {
        min_ms: u64,
        trailing_silence_ms: u64,
    },
}

fn record_microphone_mono_16khz(
    duration_ms: u64,
    endpoint: CaptureEndpoint,
) -> Result<Vec<f32>, String> {
    use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};

    let host = cpal::default_host();
    let device = host
        .default_input_device()
        .ok_or_else(|| "no default microphone input device found".to_string())?;
    let supported_config = device
        .default_input_config()
        .map_err(|err| format!("failed to read microphone config: {err}"))?;
    let sample_rate = supported_config.sample_rate().0;
    let channels = usize::from(supported_config.channels());
    let config = supported_config.config();
    let captured = Arc::new(Mutex::new(Vec::<f32>::new()));
    let captured_for_stream = Arc::clone(&captured);
    let error_state = Arc::new(Mutex::new(None::<String>));
    let error_for_stream = Arc::clone(&error_state);
    let err_fn = move |err: cpal::StreamError| {
        if let Ok(mut slot) = error_for_stream.lock() {
            *slot = Some(err.to_string());
        }
    };

    let stream = match supported_config.sample_format() {
        cpal::SampleFormat::F32 => device.build_input_stream(
            &config,
            move |data: &[f32], _| push_mono_samples(data, channels, &captured_for_stream),
            err_fn,
            None,
        ),
        cpal::SampleFormat::I16 => device.build_input_stream(
            &config,
            move |data: &[i16], _| {
                let converted: Vec<f32> = data
                    .iter()
                    .map(|sample| *sample as f32 / i16::MAX as f32)
                    .collect();
                push_mono_samples(&converted, channels, &captured_for_stream);
            },
            err_fn,
            None,
        ),
        cpal::SampleFormat::U16 => device.build_input_stream(
            &config,
            move |data: &[u16], _| {
                let converted: Vec<f32> = data
                    .iter()
                    .map(|sample| (*sample as f32 / u16::MAX as f32) * 2.0 - 1.0)
                    .collect();
                push_mono_samples(&converted, channels, &captured_for_stream);
            },
            err_fn,
            None,
        ),
        other => return Err(format!("unsupported microphone sample format: {other:?}")),
    }
    .map_err(|err| format!("failed to open microphone stream: {err}"))?;

    stream
        .play()
        .map_err(|err| format!("failed to start microphone stream: {err}"))?;
    wait_for_capture_endpoint(&captured, sample_rate, duration_ms, endpoint);
    drop(stream);

    if let Some(error) = error_state.lock().map_err(|err| err.to_string())?.clone() {
        return Err(format!("microphone stream error: {error}"));
    }

    let source = captured.lock().map_err(|err| err.to_string())?.clone();
    if source.is_empty() {
        return Err("microphone produced no audio samples".to_string());
    }
    let resampled = resample_linear(&source, sample_rate, 16_000);
    Ok(pad_audio_with_silence(&resampled, 16_000, 250))
}

fn wait_for_capture_endpoint(
    captured: &Arc<Mutex<Vec<f32>>>,
    sample_rate: u32,
    max_ms: u64,
    endpoint: CaptureEndpoint,
) {
    match endpoint {
        CaptureEndpoint::Fixed => {
            thread::sleep(std::time::Duration::from_millis(max_ms));
        }
        CaptureEndpoint::Speech {
            min_ms,
            trailing_silence_ms,
        } => wait_for_speech_endpoint(captured, sample_rate, max_ms, min_ms, trailing_silence_ms),
    }
}

fn wait_for_speech_endpoint(
    captured: &Arc<Mutex<Vec<f32>>>,
    sample_rate: u32,
    max_ms: u64,
    min_ms: u64,
    trailing_silence_ms: u64,
) {
    let started = Instant::now();
    let mut speech_started = false;
    let mut quiet_since: Option<Instant> = None;

    while started.elapsed().as_millis() < u128::from(max_ms) {
        thread::sleep(std::time::Duration::from_millis(80));

        let snapshot = match captured.lock() {
            Ok(samples) => samples.clone(),
            Err(_) => break,
        };
        let captured_ms = samples_to_ms(snapshot.len(), sample_rate);
        let recent_rms = recent_rms(&snapshot, sample_rate, 180);

        if recent_rms >= 0.012 {
            speech_started = true;
            quiet_since = None;
            continue;
        }

        if !speech_started || captured_ms < min_ms {
            continue;
        }

        let quiet_start = quiet_since.get_or_insert_with(Instant::now);
        if quiet_start.elapsed().as_millis() >= u128::from(trailing_silence_ms) {
            break;
        }
    }
}

fn samples_to_ms(sample_count: usize, sample_rate: u32) -> u64 {
    if sample_rate == 0 {
        return 0;
    }
    ((sample_count as u128 * 1_000) / u128::from(sample_rate)) as u64
}

fn recent_rms(samples: &[f32], sample_rate: u32, window_ms: u64) -> f32 {
    if samples.is_empty() || sample_rate == 0 {
        return 0.0;
    }
    let window_len = ((u128::from(sample_rate) * u128::from(window_ms)) / 1_000) as usize;
    let start = samples.len().saturating_sub(window_len.max(1));
    rms(&samples[start..])
}

fn rms(samples: &[f32]) -> f32 {
    if samples.is_empty() {
        return 0.0;
    }
    let sum = samples
        .iter()
        .map(|sample| {
            let clamped = sample.clamp(-1.0, 1.0);
            clamped * clamped
        })
        .sum::<f32>();
    (sum / samples.len() as f32).sqrt()
}

fn pad_audio_with_silence(audio: &[f32], sample_rate: u32, padding_ms: u64) -> Vec<f32> {
    if audio.is_empty() || sample_rate == 0 || padding_ms == 0 {
        return audio.to_vec();
    }
    let padding_len = ((u128::from(sample_rate) * u128::from(padding_ms)) / 1_000) as usize;
    let mut padded = Vec::with_capacity(audio.len() + padding_len * 2);
    padded.resize(padding_len, 0.0);
    padded.extend_from_slice(audio);
    padded.resize(padded.len() + padding_len, 0.0);
    padded
}

fn push_mono_samples(samples: &[f32], channels: usize, captured: &Arc<Mutex<Vec<f32>>>) {
    if channels == 0 {
        return;
    }
    if let Ok(mut output) = captured.lock() {
        for frame in samples.chunks(channels) {
            let sum: f32 = frame.iter().copied().sum();
            output.push(sum / channels as f32);
        }
    }
}

fn resample_linear(input: &[f32], source_rate: u32, target_rate: u32) -> Vec<f32> {
    if input.is_empty() || source_rate == 0 || source_rate == target_rate {
        return input.to_vec();
    }

    let output_len =
        (input.len() as f64 * target_rate as f64 / source_rate as f64).round() as usize;
    let mut output = Vec::with_capacity(output_len);
    let ratio = source_rate as f64 / target_rate as f64;
    for index in 0..output_len {
        let source_position = index as f64 * ratio;
        let left = source_position.floor() as usize;
        let right = (left + 1).min(input.len() - 1);
        let fraction = (source_position - left as f64) as f32;
        output.push(input[left] * (1.0 - fraction) + input[right] * fraction);
    }
    output
}

fn transcribe_local_whisper(audio: &[f32]) -> Result<String, String> {
    use whisper_rs::{FullParams, SamplingStrategy, WhisperContext, WhisperContextParameters};

    let model_path = workspace_root()?.join("models/whisper/ggml-tiny.en.bin");
    if !model_path.exists() {
        return Err(format!("missing local ASR model: {}", model_path.display()));
    }

    let context = WhisperContext::new_with_params(
        model_path
            .to_str()
            .ok_or_else(|| "ASR model path is not valid UTF-8".to_string())?,
        WhisperContextParameters::default(),
    )
    .map_err(|err| format!("failed to load Whisper model: {err}"))?;
    let mut state = context
        .create_state()
        .map_err(|err| format!("failed to create Whisper state: {err}"))?;
    let mut params = FullParams::new(SamplingStrategy::Greedy { best_of: 0 });
    params.set_n_threads(4);
    params.set_language(Some("en"));
    params.set_translate(false);
    params.set_print_special(false);
    params.set_print_progress(false);
    params.set_print_realtime(false);
    params.set_print_timestamps(false);
    params.set_suppress_blank(true);

    state
        .full(params, audio)
        .map_err(|err| format!("Whisper transcription failed: {err}"))?;
    let text = state
        .as_iter()
        .map(|segment| segment.to_string())
        .collect::<Vec<_>>()
        .join(" ")
        .trim()
        .to_string();
    Ok(text)
}

pub fn run() {
    tauri::Builder::<tauri_runtime_wry::Wry<tauri::EventLoopMessage>>::default()
        .invoke_handler(tauri::generate_handler![
            add_memory,
            dashboard_snapshot,
            delete_memory,
            edit_memory,
            kokoro_tts_wav,
            list_memories,
            log_voice_diagnostic,
            native_asr_listen_interrupt,
            native_asr_listen_once,
            submit_typed_hud,
            warm_kokoro_tts
        ])
        .run(tauri::generate_context!())
        .expect("failed to run Project Iris Tauri shell");
}
