import {
  MAX_DOCUMENT_CHARS as maxDocumentChars,
  MAX_VISION_IMAGE_BYTES as maxVisionImageBytes,
  classifyAttachmentFile,
  normalizeDocumentText,
  promptWithDocument,
  validateDocumentSize,
  validateImageSize
} from "./attachment-state.js";
import { classifyVoiceTranscript } from "./voice-state.js";

const invoke = window.__TAURI__?.core?.invoke;

const elements = {
  attachmentLabel: document.querySelector("#attachment-label"),
  attachmentPreview: document.querySelector("#attachment-preview"),
  attachmentRemove: document.querySelector("#attachment-remove"),
  attachmentStrip: document.querySelector("#attachment-strip"),
  hudForm: document.querySelector("#hud-form"),
  hudInput: document.querySelector("#hud-input"),
  hudOutput: document.querySelector("#hud-output"),
  memoryAddButton: document.querySelector("#memory-add-button"),
  memoryAddInput: document.querySelector("#memory-add-input"),
  memoryButton: document.querySelector("#memory-button"),
  memoryList: document.querySelector("#memory-list"),
  memoryPanel: document.querySelector("#memory-panel"),
  visionButton: document.querySelector("#vision-button"),
  visionFileInput: document.querySelector("#vision-file-input"),
  voiceButton: document.querySelector("#voice-button"),
  sendButton: document.querySelector("#send-button"),
  voiceCapability: document.querySelector("#voice-capability"),
  voiceStatus: document.querySelector("#voice-status")
};

let listening = false;
let speakReplies = true;
let voiceLoop = false;
let wakeWord = true;
let wakeCommandArmed = false;
let thinking = false;
let speaking = false;
let speechRunId = 0;
let interruptionListening = false;
let activeAudio = null;
let activeSpeechResolve = null;
let activeListenMode = "idle";
let stopListeningRequested = false;
let pendingVoiceLatency = null;
let selectedVisionImage = null;
let selectedDocument = null;
let memoryPanelOpen = false;
let cameraCaptureInProgress = false;
const conversationHistory = [];
const maxHistoryTurns = 12;
const cameraSnapshotWidth = 640;
const cameraSnapshotHeight = 480;

class VoiceLatencyTrace {
  constructor() {
    this.turnStartedAt = performance.now();
    this.speechCaptureMs = null;
    this.sttMs = null;
    this.llmFirstTokenMs = null;
    this.llmFullResponseMs = null;
    this.ttsFirstAudioMs = null;
    this.ttsFullMs = null;
    this.timeToFirstSpokenWordMs = null;
    this.totalTurnTimeMs = null;
  }

  applyAsr(result) {
    this.speechCaptureMs = optionalTiming(result.captureElapsedMs ?? result.capture_elapsed_ms);
    this.sttMs = optionalTiming(result.sttElapsedMs ?? result.stt_elapsed_ms);
    const asrElapsed = (this.speechCaptureMs || 0) + (this.sttMs || 0);
    if (asrElapsed > 0) {
      this.turnStartedAt -= asrElapsed;
    }
  }

  finishTotal() {
    this.totalTurnTimeMs = Math.round(performance.now() - this.turnStartedAt);
  }

  toReportPayload() {
    return {
      speechCaptureMs: this.speechCaptureMs,
      sttMs: this.sttMs,
      llmFirstTokenMs: this.llmFirstTokenMs,
      llmFullResponseMs: this.llmFullResponseMs,
      ttsFirstAudioMs: this.ttsFirstAudioMs,
      ttsFullMs: this.ttsFullMs,
      timeToFirstSpokenWordMs: this.timeToFirstSpokenWordMs,
      totalTurnTimeMs: this.totalTurnTimeMs
    };
  }
}

function optionalTiming(value) {
  return Number.isFinite(Number(value)) ? Math.round(Number(value)) : null;
}

async function call(command, args = {}) {
  if (!invoke) {
    throw new Error("Tauri command bridge is unavailable.");
  }
  return invoke(command, args);
}

function logVoice(event, detail = "") {
  if (!invoke) {
    return;
  }

  invoke("log_voice_diagnostic", {
    event: {
      event,
      detail: String(detail).slice(0, 500),
      mode: activeListenMode,
      listening,
      thinking,
      speaking,
      voiceLoop,
      wakeWord,
      wakeCommandArmed
    }
  }).catch((error) => {
    console.error("Iris voice diagnostics failed", error);
  });
}

function formatGb(value) {
  return `${Number(value).toFixed(1)} GB`;
}

function isUsableTranscript(transcript) {
  const normalized = String(transcript || "").trim().toLowerCase();
  if (!normalized) {
    return false;
  }
  const blocked = new Set([
    "[blank_audio]",
    "[music]",
    "[music playing]",
    "(music)",
    "(upbeat music)",
    "[silence]",
    "(silence)"
  ]);
  if (blocked.has(normalized)) {
    return false;
  }
  return !normalized.includes("music playing");
}

function rememberTurn(role, text) {
  const clean = String(text || "").trim();
  if (!clean) {
    return;
  }
  conversationHistory.push({ role, text: clean });
  while (conversationHistory.length > maxHistoryTurns) {
    conversationHistory.shift();
  }
}

async function refreshDashboard() {
  try {
    const snapshot = await call("dashboard_snapshot");
    logVoice(
      "system_snapshot",
      `model=${snapshot.model.parameter_size}; ram=${formatGb(snapshot.hardware.total_ram_gb)}; free=${formatGb(snapshot.hardware.available_ram_gb)}; usable=${formatGb(snapshot.hardware.usable_after_reserve_gb)}; cpu=${snapshot.hardware.cpu_cores}`
    );
  } catch (error) {
    logVoice("system_snapshot_failed", String(error));
  }
}

async function warmVoice() {
  try {
    logVoice("kokoro_warm_start");
    await call("warm_kokoro_tts");
    logVoice("kokoro_warm_ready");
  } catch (error) {
    logVoice("kokoro_warm_error", String(error));
  }
}

async function warmModel() {
  try {
    logVoice("ollama_warm_start");
    await call("warm_ollama_model");
    logVoice("ollama_warm_ready");
  } catch (error) {
    logVoice("ollama_warm_error", String(error));
  }
}

async function submitMessage(text, source = "typed") {
  if (thinking || speaking) {
    return;
  }
  const latencyTrace = new VoiceLatencyTrace();
  if (pendingVoiceLatency) {
    latencyTrace.applyAsr(pendingVoiceLatency);
    pendingVoiceLatency = null;
  }
  try {
    if (await handleMemoryCommand(text)) {
      elements.hudInput.value = "";
      restartListeningIfReady();
      return;
    }
  } catch (error) {
    elements.hudOutput.textContent = String(error);
    restartListeningIfReady();
    return;
  }

  if (selectedVisionImage) {
    await submitImageMessage(text, latencyTrace);
    return;
  }

  const originalText = text;
  let documentAttached = false;
  if (selectedDocument) {
    const document = selectedDocument;
    selectedDocument = null;
    documentAttached = true;
    renderAttachmentSelection();
    text = promptWithDocument(text, document);
  }

  const turnStarted = performance.now();
  thinking = true;
  logVoice("submit_start", source);
  setInputsDisabled(true);
  elements.hudOutput.textContent = documentAttached
    ? `${originalText}\n\nDocument attached. Thinking locally...`
    : `${text}\n\nThinking locally...`;
  try {
    const history = conversationHistory.slice();
    const response = await call("submit_typed_hud", { text, history });
    latencyTrace.llmFullResponseMs = optionalTiming(response.model_elapsed_ms);
    elements.hudOutput.textContent = response.text;
    rememberTurn("user", documentAttached ? `[document] ${originalText}` : originalText);
    rememberTurn("iris", response.text);
    logVoice(
      "turn_complete",
      `${source}; model_ms=${response.model_elapsed_ms}; total_ms=${Math.round(performance.now() - turnStarted)}`
    );
    thinking = false;
    setInputsDisabled(false);
    await speak(response.text, latencyTrace);
  } catch (error) {
    elements.hudOutput.textContent = String(error);
    logVoice(
      "turn_error",
      `${source}; total_ms=${Math.round(performance.now() - turnStarted)}; ${String(error)}`
    );
  } finally {
    latencyTrace.finishTotal();
    await logVoiceLatencyReport(latencyTrace);
    thinking = false;
    setInputsDisabled(false);
    logVoice("submit_end", source);
    restartListeningIfReady();
  }
}

async function submitImageMessage(prompt, latencyTrace) {
  const image = selectedVisionImage;
  clearAttachment();

  const turnStarted = performance.now();
  thinking = true;
  logVoice("image_probe_start", `bytes=${image.bytes.length}`);
  setInputsDisabled(true);
  elements.hudOutput.textContent = `Image selected.\n\nThinking locally...`;
  try {
    const response = await call("submit_image_probe", {
      imageName: image.name,
      imageBytes: image.bytes,
      prompt
    });
    latencyTrace.llmFullResponseMs = optionalTiming(response.model_elapsed_ms);
    elements.hudOutput.textContent = response.text;
    rememberTurn("user", `[image] ${prompt}`);
    rememberTurn("iris", response.text);
    logVoice(
      "image_probe_complete",
      `model_ms=${response.model_elapsed_ms}; total_ms=${Math.round(performance.now() - turnStarted)}`
    );
    thinking = false;
    setInputsDisabled(false);
    await speak(response.text, latencyTrace);
  } catch (error) {
    elements.hudOutput.textContent = String(error);
    logVoice(
      "image_probe_error",
      `total_ms=${Math.round(performance.now() - turnStarted)}; ${String(error)}`
    );
  } finally {
    latencyTrace.finishTotal();
    await logVoiceLatencyReport(latencyTrace);
    thinking = false;
    setInputsDisabled(false);
    logVoice("submit_end", "image-probe");
    restartListeningIfReady();
  }
}

async function logVoiceLatencyReport(trace) {
  if (!invoke) {
    return;
  }
  try {
    await call("log_voice_latency_report", { trace: trace.toReportPayload() });
  } catch (error) {
    logVoice("voice_latency_report_error", String(error));
  }
}

async function handleMemoryCommand(text) {
  const clean = String(text || "").trim();
  const addMatch = clean.match(/^(?:remember|memory\s+add)\s*[:,-]?\s+(.+)$/i);
  if (addMatch) {
    const memories = await call("add_memory", { text: addMatch[1] });
    elements.hudOutput.textContent = `Memory added.\n\n${formatMemories(memories)}`;
    return true;
  }

  if (/^memory\s+list$/i.test(clean)) {
    const memories = await call("list_memories");
    elements.hudOutput.textContent = formatMemories(memories);
    return true;
  }

  const deleteMatch = clean.match(/^memory\s+(?:delete|remove)\s+(\d+)$/i);
  if (deleteMatch) {
    const memories = await call("delete_memory", { id: Number(deleteMatch[1]) });
    elements.hudOutput.textContent = `Memory deleted.\n\n${formatMemories(memories)}`;
    return true;
  }

  const editMatch = clean.match(/^memory\s+edit\s+(\d+)\s*[:,-]\s*(.+)$/i);
  if (editMatch) {
    const memories = await call("edit_memory", {
      id: Number(editMatch[1]),
      text: editMatch[2]
    });
    elements.hudOutput.textContent = `Memory updated.\n\n${formatMemories(memories)}`;
    return true;
  }

  if (/^memory\s+help$/i.test(clean)) {
    elements.hudOutput.textContent =
      "Memory commands:\nremember: <text>\nmemory list\nmemory edit <number>: <text>\nmemory delete <number>\n\nIris stores up to 40 short memories.";
    return true;
  }

  return false;
}

function formatMemories(memories) {
  if (!Array.isArray(memories) || memories.length === 0) {
    return "No memories saved.";
  }
  return memories.map((memory) => `${memory.id}. ${memory.text}`).join("\n");
}

async function toggleMemoryPanel() {
  memoryPanelOpen = !memoryPanelOpen;
  elements.memoryPanel.hidden = !memoryPanelOpen;
  elements.memoryButton.classList.toggle("listening", memoryPanelOpen);
  elements.memoryButton.setAttribute("aria-pressed", memoryPanelOpen ? "true" : "false");
  if (memoryPanelOpen) {
    await refreshMemoryPanel();
  }
}

async function refreshMemoryPanel() {
  const memories = await call("list_memories");
  renderMemoryPanel(memories);
}

function renderMemoryPanel(memories) {
  elements.memoryList.innerHTML = "";
  if (!Array.isArray(memories) || memories.length === 0) {
    const empty = document.createElement("div");
    empty.className = "memory-empty";
    empty.textContent = "No memories saved.";
    elements.memoryList.append(empty);
    return;
  }

  for (const memory of memories) {
    const row = document.createElement("div");
    row.className = "memory-row";

    const input = document.createElement("input");
    input.maxLength = 240;
    input.value = memory.text;
    input.setAttribute("aria-label", `Edit memory ${memory.id}`);

    const save = document.createElement("button");
    save.className = "memory-action";
    save.type = "button";
    save.title = "Save memory";
    save.setAttribute("aria-label", `Save memory ${memory.id}`);
    save.textContent = "+";
    save.addEventListener("click", async () => {
      await editMemoryFromPanel(memory.id, input.value);
    });

    const remove = document.createElement("button");
    remove.className = "memory-action";
    remove.type = "button";
    remove.title = "Delete memory";
    remove.setAttribute("aria-label", `Delete memory ${memory.id}`);
    remove.textContent = "-";
    remove.addEventListener("click", async () => {
      await deleteMemoryFromPanel(memory.id);
    });

    row.append(input, save, remove);
    elements.memoryList.append(row);
  }
}

async function addMemoryFromPanel() {
  const text = elements.memoryAddInput.value.trim();
  if (!text) {
    elements.hudOutput.textContent = "Type a memory first.";
    return;
  }
  try {
    const memories = await call("add_memory", { text });
    elements.memoryAddInput.value = "";
    renderMemoryPanel(memories);
    elements.hudOutput.textContent = "Memory added.";
  } catch (error) {
    elements.hudOutput.textContent = String(error);
  }
}

async function editMemoryFromPanel(id, text) {
  const clean = String(text || "").trim();
  if (!clean) {
    elements.hudOutput.textContent = "Memory cannot be empty.";
    return;
  }
  try {
    const memories = await call("edit_memory", { id, text: clean });
    renderMemoryPanel(memories);
    elements.hudOutput.textContent = "Memory saved.";
  } catch (error) {
    elements.hudOutput.textContent = String(error);
  }
}

async function deleteMemoryFromPanel(id) {
  try {
    const memories = await call("delete_memory", { id });
    renderMemoryPanel(memories);
    elements.hudOutput.textContent = "Memory deleted.";
  } catch (error) {
    elements.hudOutput.textContent = String(error);
  }
}

function cancelSpeech() {
  speechRunId += 1;
  speaking = false;
  if (activeAudio) {
    activeAudio.pause();
    activeAudio.src = "";
    activeAudio = null;
  }
  if (activeSpeechResolve) {
    const resolve = activeSpeechResolve;
    activeSpeechResolve = null;
    resolve();
  }
}

async function speak(text, latencyTrace = null) {
  if (!speakReplies) {
    return Promise.resolve();
  }

  return new Promise((resolve) => {
    const runId = ++speechRunId;
    speaking = true;
    activeSpeechResolve = resolve;
    let resolved = false;
    const resolveOnce = () => {
      if (resolved) {
        return;
      }
      resolved = true;
      if (speechRunId === runId) {
        speaking = false;
      }
      if (activeSpeechResolve === resolve) {
        activeSpeechResolve = null;
      }
      logVoice("speech_finished", `run=${runId}`);
      resolve();
    };

    const ttsStartedAt = performance.now();
    logVoice("kokoro_tts_start", `run=${runId}`);
    call("kokoro_tts_wav", { text })
      .then((response) => {
        if (speechRunId !== runId) {
          resolveOnce();
          return;
        }
        const bytes = new Uint8Array(response.wavBytes);
        const blob = new Blob([bytes], { type: "audio/wav" });
        const url = URL.createObjectURL(blob);
        const audio = new Audio(url);
        activeAudio = audio;
        if (latencyTrace) {
          latencyTrace.ttsFullMs = optionalTiming(response.elapsedMs);
        }
        logVoice("speech_started", `run=${runId}; voice=${response.voice}; tts_ms=${response.elapsedMs}`);
        monitorSpeechInterruption(runId);
        audio.onplaying = () => {
          if (latencyTrace && latencyTrace.ttsFirstAudioMs === null) {
            latencyTrace.ttsFirstAudioMs = Math.round(performance.now() - ttsStartedAt);
            latencyTrace.timeToFirstSpokenWordMs = Math.round(
              performance.now() - latencyTrace.turnStartedAt
            );
          }
        };
        audio.onended = () => {
          URL.revokeObjectURL(url);
          if (activeAudio === audio) {
            activeAudio = null;
          }
          resolveOnce();
        };
        audio.onerror = () => {
          URL.revokeObjectURL(url);
          if (activeAudio === audio) {
            activeAudio = null;
          }
          resolveOnce();
        };
        audio.play().catch((error) => {
          logVoice("speech_playback_error", String(error));
          URL.revokeObjectURL(url);
          if (activeAudio === audio) {
            activeAudio = null;
          }
          resolveOnce();
        });
      })
      .catch((error) => {
        logVoice("kokoro_tts_error", String(error));
        resolveOnce();
      });
  });
}

async function monitorSpeechInterruption(runId) {
  if (interruptionListening || !invoke) {
    return;
  }

  interruptionListening = true;
  try {
    while (speaking && speechRunId === runId) {
      logVoice("speech_interruption_listen_start", `run=${runId}`);
      const result = await call("native_asr_listen_interrupt");
      const transcript = String(result.text || "").trim();
      logVoice("speech_interruption_result", `${result.elapsed_ms}ms; ${transcript}`);
      if (!isUsableTranscript(transcript)) {
        continue;
      }
      const decision = classifyVoiceTranscript(transcript, {
        voiceLoop,
        wakeWord,
        wakeCommandArmed,
        interruptionOnly: true
      });
      logVoice("speech_interruption_decision", `${decision.action}:${decision.source}:${decision.prompt}`);
      if (decision.action === "interrupt" && speaking && speechRunId === runId) {
        logVoice("speech_interruption_detected", transcript);
        cancelSpeech();
        wakeCommandArmed = false;
        voiceLoop = true;
        elements.hudOutput.textContent = "Stopped.";
        elements.voiceStatus.textContent = "Interrupted. Listening.";
        restartListeningIfReady(250);
        return;
      }
    }
  } catch (error) {
    logVoice("speech_interruption_error", String(error));
  } finally {
    interruptionListening = false;
  }
}

function setInputsDisabled(disabled) {
  elements.hudInput.disabled = disabled;
  elements.sendButton.disabled = disabled;
  elements.attachmentRemove.disabled = disabled;
  elements.voiceButton.disabled = false;
  elements.visionButton.disabled = disabled;
  elements.memoryButton.disabled = disabled;
  elements.memoryAddButton.disabled = disabled;
  elements.memoryAddInput.disabled = disabled;
}

function setListening(nextListening) {
  listening = nextListening;
  elements.voiceButton.classList.toggle("listening", listening);
  elements.voiceButton.setAttribute(
    "aria-label",
    listening && activeListenMode === "push" ? "Stop listening" : "Push to talk"
  );
  elements.voiceButton.setAttribute(
    "title",
    listening && activeListenMode === "push" ? "Stop listening" : "Push to talk"
  );
}

function renderVoiceCapability() {
  elements.voiceCapability.textContent = "Native ASR / Kokoro af_heart";
}

function restartListeningIfReady(delayMs = 650) {
  if ((!voiceLoop && !wakeWord) || thinking || speaking || listening || stopListeningRequested) {
    return;
  }

  window.setTimeout(() => {
    if ((!voiceLoop && !wakeWord) || thinking || speaking || listening || stopListeningRequested) {
      return;
    }
    listenOnce(wakeWord ? "wake" : "loop");
  }, delayMs);
}

async function listenOnce(mode) {
  if (listening || thinking || speaking) {
    return;
  }

  activeListenMode = mode;
  setListening(true);
  logVoice("native_asr_start_requested");
  elements.voiceStatus.textContent = mode === "push" ? "Listening..." : "Listening for Iris.";
  try {
    const result = await call("native_asr_listen_once");
    const transcript = String(result.text || "").trim();
    logVoice("native_asr_result", `${result.elapsed_ms}ms; ${transcript}`);
    pendingVoiceLatency = {
      captureElapsedMs: result.captureElapsedMs ?? result.capture_elapsed_ms,
      sttElapsedMs: result.sttElapsedMs ?? result.stt_elapsed_ms
    };
    if (!isUsableTranscript(transcript)) {
      pendingVoiceLatency = null;
      elements.voiceStatus.textContent = "No speech transcript captured.";
      return;
    }
    elements.hudOutput.textContent = transcript;
    handleVoiceTranscript(transcript);
  } catch (error) {
    elements.hudOutput.textContent = String(error);
    logVoice("native_asr_error", String(error));
  } finally {
    setListening(false);
    if (mode !== "push") {
      restartListeningIfReady(650);
    }
  }
}

function handleVoiceTranscript(transcript) {
  const decision = classifyVoiceTranscript(transcript, {
    voiceLoop,
    wakeWord,
    wakeCommandArmed,
    interruptionOnly: false
  });
  elements.voiceStatus.textContent = decision.status;
  logVoice("voice_decision", `${decision.action}:${decision.source}:${decision.prompt}`);

  if (decision.action === "interrupt") {
    pendingVoiceLatency = null;
    cancelSpeech();
    wakeCommandArmed = false;
    voiceLoop = false;
    elements.hudOutput.textContent = "Stopped.";
    restartListeningIfReady(250);
    return;
  }

  if (decision.action === "submit") {
    wakeCommandArmed = false;
    voiceLoop = false;
    submitMessage(decision.prompt, decision.source);
    return;
  }

  if (decision.action === "arm-wake-followup") {
    pendingVoiceLatency = null;
    wakeCommandArmed = true;
    voiceLoop = false;
    elements.hudOutput.textContent = "Listening.";
    elements.voiceStatus.textContent = "Listening.";
    restartListeningIfReady(100);
    return;
  }

  if (decision.action === "wait-for-wake") {
    if (voiceLoop) {
      submitMessage(transcript, "voice-session");
      return;
    }
    pendingVoiceLatency = null;
    wakeCommandArmed = false;
  }
}

elements.hudForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  const text = elements.hudInput.value.trim();
  if (!text) {
    return;
  }

  submitMessage(text, "typed");
});

elements.voiceButton.addEventListener("click", () => {
  if (listening && activeListenMode === "push") {
    stopListeningRequested = true;
    return;
  }

  stopListeningRequested = false;
  listenOnce("push");
});

elements.memoryButton.addEventListener("click", () => {
  toggleMemoryPanel().catch((error) => {
    elements.hudOutput.textContent = String(error);
  });
});

elements.memoryAddButton.addEventListener("click", () => {
  addMemoryFromPanel();
});

elements.memoryAddInput.addEventListener("keydown", (event) => {
  if (event.key === "Enter") {
    event.preventDefault();
    addMemoryFromPanel();
  }
});

elements.attachmentRemove.addEventListener("click", () => {
  clearAttachment();
});

elements.visionButton.addEventListener("click", () => {
  if (thinking || speaking || cameraCaptureInProgress) {
    return;
  }
  captureCameraSnapshot().catch((error) => {
    elements.hudOutput.textContent = String(error);
  });
});

elements.visionFileInput.addEventListener("change", async () => {
  const file = elements.visionFileInput.files?.[0];
  elements.visionFileInput.value = "";
  if (!file) {
    return;
  }
  try {
    await attachFile(file);
  } catch (error) {
    clearAttachment();
    elements.hudOutput.textContent = String(error);
  }
});

elements.hudInput.addEventListener("paste", (event) => {
  const file = firstClipboardFile(event.clipboardData);
  if (!file) {
    return;
  }
  event.preventDefault();
  attachFile(file).catch((error) => {
    clearAttachment();
    elements.hudOutput.textContent = String(error);
  });
});

elements.hudForm.addEventListener("dragover", (event) => {
  if (!event.dataTransfer?.files?.length) {
    return;
  }
  event.preventDefault();
  elements.hudForm.classList.add("drop-active");
});

elements.hudForm.addEventListener("dragleave", () => {
  elements.hudForm.classList.remove("drop-active");
});

elements.hudForm.addEventListener("drop", (event) => {
  elements.hudForm.classList.remove("drop-active");
  const file = event.dataTransfer?.files?.[0];
  if (!file) {
    return;
  }
  event.preventDefault();
  attachFile(file).catch((error) => {
    clearAttachment();
    elements.hudOutput.textContent = String(error);
  });
});

function firstClipboardFile(clipboardData) {
  if (!clipboardData) {
    return null;
  }
  for (const item of clipboardData.items || []) {
    if (item.kind === "file") {
      const file = item.getAsFile();
      if (file) {
        return file;
      }
    }
  }
  return clipboardData.files?.[0] || null;
}

async function attachFile(file) {
  switch (classifyAttachmentFile(file)) {
    case "image":
      setImageAttachment(await readVisionImage(file), "Image attached. Type what you want Iris to inspect.");
      return;
    case "video":
      setImageAttachment(
        await snapshotFromVideoFile(file),
        "Video frame attached. Type what you want Iris to inspect."
      );
      return;
    case "document":
      setDocumentAttachment(await readDocumentAttachment(file));
      return;
    default:
      throw new Error("Attach an image, a supported video, or a plain text document.");
  }
}

async function readVisionImage(file) {
  if (classifyAttachmentFile(file) !== "image") {
    throw new Error("Vision input supports png, jpg, jpeg, and webp images.");
  }
  validateImageSize(file);
  const buffer = await file.arrayBuffer();
  const previewUrl = URL.createObjectURL(file);
  return {
    name: file.name || "selected-image",
    bytes: Array.from(new Uint8Array(buffer)),
    previewUrl,
    kindLabel: "Image"
  };
}

async function readDocumentAttachment(file) {
  validateDocumentSize(file);
  const raw = await file.text();
  const normalized = normalizeDocumentText(raw);
  return {
    name: file.name || "document.txt",
    text: normalized.text,
    truncated: normalized.truncated
  };
}

async function captureCameraSnapshot() {
  if (!navigator.mediaDevices?.getUserMedia) {
    throw new Error("Camera input is unavailable in this Iris window.");
  }

  cameraCaptureInProgress = true;
  elements.visionButton.disabled = true;
  elements.hudOutput.textContent = "Camera starting.";
  let stream = null;
  try {
    stream = await navigator.mediaDevices.getUserMedia({
      audio: false,
      video: {
        width: { ideal: cameraSnapshotWidth, max: cameraSnapshotWidth },
        height: { ideal: cameraSnapshotHeight, max: cameraSnapshotHeight },
        frameRate: { ideal: 5, max: 10 }
      }
    });
    setImageAttachment(
      await snapshotFromStream(stream),
      "Camera snapshot attached. Type what you want Iris to inspect."
    );
  } finally {
    if (stream) {
      for (const track of stream.getTracks()) {
        track.stop();
      }
    }
    cameraCaptureInProgress = false;
    elements.visionButton.disabled = false;
  }
}

async function snapshotFromStream(stream) {
  const video = document.createElement("video");
  video.muted = true;
  video.playsInline = true;
  video.srcObject = stream;
  await video.play();
  await waitForVideoFrame(video);

  const width = Math.min(video.videoWidth || cameraSnapshotWidth, cameraSnapshotWidth);
  const height = Math.min(video.videoHeight || cameraSnapshotHeight, cameraSnapshotHeight);
  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;
  const context = canvas.getContext("2d");
  if (!context) {
    throw new Error("Camera snapshot failed.");
  }
  context.drawImage(video, 0, 0, width, height);
  const blob = await new Promise((resolve) => canvas.toBlob(resolve, "image/jpeg", 0.72));
  if (!blob) {
    throw new Error("Camera snapshot failed.");
  }
  if (blob.size > maxVisionImageBytes) {
    throw new Error("Camera snapshot is too large.");
  }
  const buffer = await blob.arrayBuffer();
  return {
    name: "camera-snapshot.jpg",
    bytes: Array.from(new Uint8Array(buffer)),
    previewUrl: URL.createObjectURL(blob),
    kindLabel: "Camera"
  };
}

async function snapshotFromVideoFile(file) {
  if (file.size <= 0) {
    throw new Error("Video attachment needs a non-empty file.");
  }
  const video = document.createElement("video");
  video.muted = true;
  video.playsInline = true;
  video.preload = "metadata";
  const sourceUrl = URL.createObjectURL(file);
  video.src = sourceUrl;
  video.load();
  try {
    await waitForVideoFrame(video, "Video frame timed out.");
    const width = Math.min(video.videoWidth || cameraSnapshotWidth, cameraSnapshotWidth);
    const height = Math.min(video.videoHeight || cameraSnapshotHeight, cameraSnapshotHeight);
    const canvas = document.createElement("canvas");
    canvas.width = width;
    canvas.height = height;
    const context = canvas.getContext("2d");
    if (!context) {
      throw new Error("Video frame capture failed.");
    }
    context.drawImage(video, 0, 0, width, height);
    const blob = await new Promise((resolve) => canvas.toBlob(resolve, "image/jpeg", 0.72));
    if (!blob) {
      throw new Error("Video frame capture failed.");
    }
    if (blob.size > maxVisionImageBytes) {
      throw new Error("Video frame is too large.");
    }
    const buffer = await blob.arrayBuffer();
    return {
      name: `${(file.name || "video").replace(/\.[^.]+$/, "")}-frame.jpg`,
      bytes: Array.from(new Uint8Array(buffer)),
      previewUrl: URL.createObjectURL(blob),
      kindLabel: "Video frame"
    };
  } finally {
    URL.revokeObjectURL(sourceUrl);
  }
}

function waitForVideoFrame(video, timeoutMessage = "Camera snapshot timed out.") {
  if (video.videoWidth > 0 && video.videoHeight > 0) {
    return Promise.resolve();
  }
  return new Promise((resolve, reject) => {
    const timeout = window.setTimeout(() => reject(new Error(timeoutMessage)), 5000);
    video.onloadeddata = () => {
      window.clearTimeout(timeout);
      resolve();
    };
    video.onerror = () => {
      window.clearTimeout(timeout);
      reject(new Error(timeoutMessage));
    };
  });
}

function setImageAttachment(image, statusText) {
  clearAttachment();
  selectedVisionImage = image;
  elements.hudOutput.textContent = statusText;
  renderAttachmentSelection();
}

function setDocumentAttachment(document) {
  clearAttachment();
  selectedDocument = document;
  elements.hudOutput.textContent = document.truncated
    ? `Document attached. First ${maxDocumentChars} characters will be used.`
    : "Document attached. Type what you want Iris to do with it.";
  renderAttachmentSelection();
}

function clearAttachment() {
  if (selectedVisionImage?.previewUrl) {
    URL.revokeObjectURL(selectedVisionImage.previewUrl);
  }
  selectedVisionImage = null;
  selectedDocument = null;
  renderAttachmentSelection();
}

function renderAttachmentSelection() {
  const hasImage = Boolean(selectedVisionImage);
  const hasDocument = Boolean(selectedDocument);
  const hasAttachment = hasImage || hasDocument;
  elements.visionButton.classList.toggle("listening", hasImage);
  elements.visionButton.setAttribute("aria-pressed", hasImage ? "true" : "false");
  elements.visionButton.setAttribute(
    "title",
    hasImage ? "Visual attachment ready for next prompt" : "Camera snapshot"
  );
  elements.visionButton.setAttribute(
    "aria-label",
    hasImage ? "Visual attachment ready for next prompt" : "Camera snapshot"
  );
  elements.attachmentStrip.hidden = !hasAttachment;
  elements.attachmentPreview.innerHTML = "";
  elements.attachmentLabel.textContent = "";
  if (hasImage) {
    const preview = document.createElement("img");
    preview.alt = "";
    preview.src = selectedVisionImage.previewUrl;
    elements.attachmentPreview.append(preview);
    elements.attachmentLabel.textContent = `${selectedVisionImage.kindLabel || "Image"}: ${selectedVisionImage.name}`;
    return;
  }
  if (hasDocument) {
    elements.attachmentPreview.textContent = "TXT";
    elements.attachmentLabel.textContent = selectedDocument.truncated
      ? `Document: ${selectedDocument.name} (first ${maxDocumentChars} chars)`
      : `Document: ${selectedDocument.name}`;
  }
}

renderVoiceCapability();
renderAttachmentSelection();
logVoice("app_started");
refreshDashboard();
warmVoice();
warmModel();
restartListeningIfReady(500);
