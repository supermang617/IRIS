import {
  MAX_DOCUMENT_CHARS as maxDocumentChars,
  MAX_VISION_IMAGE_BYTES as maxVisionImageBytes,
  classifyAttachmentFile,
  normalizeDocumentText,
  promptWithDocument,
  unsupportedAttachmentMessage,
  validateDocumentSize,
  validateImageSize,
  validateVideoSize
} from "./attachment-state.js";
import { requireTrustedBlobUrl } from "./attachment-url.js";
import { latestBrowserPreview } from "./browser-preview.js";
import {
  formatDynamicContextStatus,
  parseDynamicContextCommand
} from "./dynamic-context-state.js";
import {
  clampResponseHeight,
  composerHeightFor,
  responseDefaultHeight,
  responseHeightFromDrag,
  responseHeightFromKeyboard,
  responseMinHeight,
  shouldSubmitComposer
} from "./composer-state.js";
import { formatAgenticHermesPrompt } from "./hermes-agentic-prompt.js";
import { formatHermesMode, parseHermesControlCommand } from "./hermes-mode.js";
import { classifyHermesRoute } from "./hermes-routing.js";
import { shouldClearInputOnSubmit } from "./input-state.js";
import { canSubmitWhilePanicStopped, nextPanicState, panicStatusText } from "./panic-state.js";
import { playWavBytes } from "./speech-output.js";
import { splitSpeechChunks } from "./speech-chunks.js";
import {
  formatHermesMemoryTaskText,
  formatHermesTaskStagedSection,
  formatStagedMemories
} from "./staging-state.js";
import {
  classifyAsrError,
  classifyVoiceTranscript,
  nextVoiceListenMode,
  shouldContinueVoiceSession,
  shouldDisplayVoiceTranscript,
  wakeRestartDelayMs
} from "./voice-state.js";

const invoke = window.__TAURI__?.core?.invoke;
const currentWindow = window.__TAURI__?.window?.getCurrentWindow?.();

const elements = {
  approvalAllow: document.querySelector("#approval-allow"),
  approvalDeny: document.querySelector("#approval-deny"),
  approvalPanel: document.querySelector("#approval-panel"),
  approvalRisk: document.querySelector("#approval-risk"),
  approvalSummary: document.querySelector("#approval-summary"),
  attachmentLabel: document.querySelector("#attachment-label"),
  attachmentPreview: document.querySelector("#attachment-preview"),
  attachmentRemove: document.querySelector("#attachment-remove"),
  attachmentStrip: document.querySelector("#attachment-strip"),
  attachButton: document.querySelector("#attach-button"),
  browserPanel: document.querySelector("#browser-panel"),
  browserPreviewClose: document.querySelector("#browser-preview-close"),
  browserPreviewImage: document.querySelector("#browser-preview-image"),
  browserUrl: document.querySelector("#browser-url"),
  hudForm: document.querySelector("#hud-form"),
  hudInput: document.querySelector("#hud-input"),
  hudOutput: document.querySelector("#hud-output"),
  irisConsole: document.querySelector(".iris-console"),
  memoryAddButton: document.querySelector("#memory-add-button"),
  memoryAddInput: document.querySelector("#memory-add-input"),
  memoryButton: document.querySelector("#memory-button"),
  memoryList: document.querySelector("#memory-list"),
  memoryPanel: document.querySelector("#memory-panel"),
  panicButton: document.querySelector("#panic-button"),
  responsePane: document.querySelector("#response-pane"),
  responseResizeHandle: document.querySelector("#response-resize-handle"),
  screenButton: document.querySelector("#screen-button"),
  visionButton: document.querySelector("#vision-button"),
  visionFileInput: document.querySelector("#vision-file-input"),
  voiceButton: document.querySelector("#voice-button"),
  sendButton: document.querySelector("#send-button"),
  windowDragStrip: document.querySelector("#window-drag-strip"),
  voiceCapability: document.querySelector("#voice-capability"),
  voiceStatus: document.querySelector("#voice-status")
};

let listening = false;
let speakReplies = true;
let voiceLoop = false;
let wakeWord = true;
let wakeCommandArmed = false;
let wakeMissStreak = 0;
let thinking = false;
let speaking = false;
let speechRunId = 0;
let interruptionListening = false;
let activeAudio = null;
let activeSpeechResolve = null;
let activeListenMode = "idle";
let listenGeneration = 0;
let stopListeningRequested = false;
let panicStopActive = false;
let pendingVoiceLatency = null;
let selectedVisionImage = null;
let selectedDocument = null;
let memoryPanelOpen = false;
let cameraCaptureInProgress = false;
let activeApprovalResolver = null;
let browserPreviewRestoreHeight = null;
const conversationHistory = [];
const maxHistoryTurns = 8;
const cameraSnapshotWidth = 640;
const cameraSnapshotHeight = 480;
const defaultCameraPrompt = "Describe what you can see in this camera snapshot. Keep it brief and natural.";
const defaultScreenPrompt = "Describe what is visible underneath the Iris window. Keep it brief and natural.";
const trustedAttachmentObjectUrls = new Set();
const responseHeightStorageKey = "iris.responseHeight";

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
    "(silence)",
    "[inaudible]",
    "(inaudible)",
    "[no speech]",
    "(no speech)",
    "[typing]",
    "(typing)",
    "[keyboard clicking]",
    "(keyboard clicking)"
  ]);
  if (blocked.has(normalized)) {
    return false;
  }
  return (
    !normalized.includes("music playing") &&
    !normalized.includes("keyboard clicking") &&
    !normalized.includes("inaudible")
  );
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

async function warmRuntimeBeforeListening() {
  elements.hudOutput.textContent = "Iris is starting.";
  let runtimeReady = false;
  try {
    const runtime = await call("prepare_local_runtime");
    runtimeReady = Boolean(runtime.ready);
    logVoice(
      "local_runtime_ready",
      `started_ollama=${Boolean(runtime.startedOllama)}; elapsed_ms=${runtime.elapsedMs}`
    );
  } catch (error) {
    logVoice("local_runtime_error", String(error));
    elements.hudOutput.textContent = "Local model service is unavailable.";
  }
  if (runtimeReady) {
    elements.hudOutput.textContent = "Waiting for input.";
    restartListeningIfReady(100);
  }
  await Promise.allSettled([warmVoice(), runtimeReady ? warmModel() : Promise.resolve()]);
  logVoice("runtime_warm_ready");
  if (elements.hudOutput.textContent === "Iris is starting.") {
    elements.hudOutput.textContent = "Waiting for input.";
  }
  restartListeningIfReady(100);
}

async function submitMessage(text, source = "typed") {
  if (!canSubmitWhilePanicStopped(panicStopActive)) {
    elements.hudOutput.textContent = panicStatusText(true);
    return;
  }
  if (thinking || speaking) {
    return;
  }
  await cancelActiveAsr();
  wakeCommandArmed = false;
  voiceLoop = false;
  if (shouldClearInputOnSubmit(text, thinking || speaking)) {
    elements.hudInput.value = "";
    resizeComposerInput();
  }
  const latencyTrace = new VoiceLatencyTrace();
  if (pendingVoiceLatency) {
    latencyTrace.applyAsr(pendingVoiceLatency);
    pendingVoiceLatency = null;
  }
  try {
    if (await handleMemoryCommand(text)) {
      elements.hudInput.value = "";
      resizeComposerInput();
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
    const response = await call("submit_typed_hud", {
      text,
      history,
      styleText: originalText
    });
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
  if (!canSubmitWhilePanicStopped(panicStopActive)) {
    elements.hudOutput.textContent = panicStatusText(true);
    return;
  }
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

async function submitScreenAreaMessage() {
  if (!canSubmitWhilePanicStopped(panicStopActive)) {
    elements.hudOutput.textContent = panicStatusText(true);
    return;
  }
  if (thinking || speaking) {
    return;
  }
  const latencyTrace = new VoiceLatencyTrace();
  const prompt = elements.hudInput.value.trim() || defaultScreenPrompt;
  const turnStarted = performance.now();
  thinking = true;
  logVoice("screen_probe_start", "area-under-iris");
  setInputsDisabled(true);
  elements.hudInput.value = "";
  resizeComposerInput();
  elements.hudOutput.textContent = `Looking under Iris.\n\nThinking locally...`;
  try {
    const response = await call("submit_screen_area_probe", { prompt });
    latencyTrace.llmFullResponseMs = optionalTiming(response.model_elapsed_ms);
    elements.hudOutput.textContent = response.text;
    rememberTurn("user", `[screen] ${prompt}`);
    rememberTurn("iris", response.text);
    logVoice(
      "screen_probe_complete",
      `model_ms=${response.model_elapsed_ms}; total_ms=${Math.round(performance.now() - turnStarted)}`
    );
    thinking = false;
    setInputsDisabled(false);
    await speak(response.text, latencyTrace);
  } catch (error) {
    elements.hudOutput.textContent = String(error);
    logVoice(
      "screen_probe_error",
      `total_ms=${Math.round(performance.now() - turnStarted)}; ${String(error)}`
    );
  } finally {
    latencyTrace.finishTotal();
    await logVoiceLatencyReport(latencyTrace);
    thinking = false;
    setInputsDisabled(false);
    logVoice("submit_end", "screen-probe");
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
  if (!canSubmitWhilePanicStopped(panicStopActive)) {
    elements.hudOutput.textContent = panicStatusText(true);
    return true;
  }
  const clean = String(text || "").trim();
  const dynamicContextCommand = parseDynamicContextCommand(clean);
  if (dynamicContextCommand.action === "status") {
    const status = await call("dynamic_context_status");
    elements.hudOutput.textContent = formatDynamicContextStatus(status);
    return true;
  }
  if (dynamicContextCommand.action === "reset") {
    const status = await call("dynamic_context_reset");
    elements.hudOutput.textContent = `Dynamic context reset.\n\n${formatDynamicContextStatus(status)}`;
    return true;
  }
  if (dynamicContextCommand.action === "set_enabled") {
    const status = await call("dynamic_context_set_enabled", {
      enabled: dynamicContextCommand.enabled
    });
    elements.hudOutput.textContent = formatDynamicContextStatus(status);
    return true;
  }
  const hermesControl = parseHermesControlCommand(clean);
  const hermesRoute = classifyHermesRoute(clean);

  if (hermesControl.action === "status") {
    const status = await call("hermes_status");
    const mode = await call("hermes_mode_status");
    const audit = status.mode === "safe" ? await call("hermes_safety_audit") : null;
    elements.hudOutput.textContent = formatHermesStatus(status, audit);
    elements.hudOutput.textContent += `\n${formatHermesMode(mode)}`;
    return true;
  }

  if (hermesControl.action === "set_mode") {
    const mode = await call("hermes_set_mode", { mode: hermesControl.mode });
    elements.hudOutput.textContent = formatHermesMode(mode);
    return true;
  }

  if (hermesControl.action === "agentic_workspace_required") {
    elements.hudOutput.textContent =
      "Agentic mode requires a workspace. Use: hermes agentic C:\\path\\to\\workspace";
    return true;
  }

  if (hermesControl.action === "create_agentic_session") {
    const mode = await call("hermes_create_agentic_session", {
      workspacePath: hermesControl.workspacePath
    });
    elements.hudOutput.textContent =
      `${formatHermesMode(mode)}\nAgentic Hermes is ready for approved file and PowerShell tasks through Iris. High-risk actions still require one-action confirmation.`;
    return true;
  }

  if (hermesControl.action === "end_agentic_session") {
    const mode = await call("hermes_end_agentic_session");
    elements.hudOutput.textContent = formatHermesMode(mode);
    return true;
  }

  if (/^hermes\s+staging$/i.test(clean)) {
    const staged = await call("hermes_staging_list");
    elements.hudOutput.textContent = formatStagedMemories(staged);
    return true;
  }

  const acceptMatch = clean.match(/^hermes\s+accept\s+(\d+)$/i);
  if (acceptMatch) {
    const staged = await call("hermes_accept_staged_memory", { id: Number(acceptMatch[1]) });
    elements.hudOutput.textContent = `Hermes memory accepted.\n\n${formatStagedMemories(staged)}`;
    await refreshMemoryPanel();
    return true;
  }

  const rejectMatch = clean.match(/^hermes\s+reject\s+(\d+)$/i);
  if (rejectMatch) {
    const staged = await call("hermes_reject_staged_memory", { id: Number(rejectMatch[1]) });
    elements.hudOutput.textContent = `Hermes memory rejected.\n\n${formatStagedMemories(staged)}`;
    return true;
  }

  if (hermesRoute.route !== "none") {
    if (hermesRoute.mode === "image_generation") {
      await runImageGeneration(hermesRoute.text);
      return true;
    }
    await runHermesTask(
      hermesRoute.mode,
      hermesRoute.text,
      hermesRoute.mode === "research",
      hermesRoute.route
    );
    return true;
  }

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
      "Memory and context commands:\nremember: <text>\nmemory list\nmemory edit <number>: <text>\nmemory delete <number>\ndynamic context\ndynamic context on\ndynamic context off\ndynamic context reset\nhermes: <task>\nhermes research: <task>\nhermes code: <task>\nhermes status\nhermes mode off\nhermes mode safe\nhermes agentic C:\\path\\to\\workspace\nhermes session end\nhermes staging\nhermes accept <number>\nhermes reject <number>\n\nIris stores up to 40 short memories. Dynamic context stores only decaying aggregate communication metrics. Online, browser, and research requests can be asked directly through Iris.";
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

async function runHermesTask(mode, text, explicitUserResearchRequest, route = "explicit") {
  const clean = String(text || "").trim();
  if (!clean) {
    elements.hudOutput.textContent = "Type a Hermes task first.";
    return;
  }
  const policy = await call("hermes_mode_status");
  if (policy.mode === "off") {
    elements.hudOutput.textContent = "Hermes is Off. Use `hermes mode safe` or start an Agentic session.";
    return;
  }
  if (policy.mode === "agentic") {
    if (!elements.browserPanel.hidden) {
      await hideBrowserPreview();
    }
    thinking = true;
    setInputsDisabled(true);
    elements.hudOutput.textContent =
      mode === "research"
        ? "Iris is checking current sources."
        : "Iris is working through Agentic Hermes.";
    try {
      const response = await runAgenticTaskWithApprovals(
        formatAgenticHermesPrompt(mode, clean, route)
      );
      elements.hudOutput.textContent = formatAgenticTaskResult(response);
      const preview = latestBrowserPreview(response?.events);
      if (preview) {
        await showBrowserPreview(preview);
      }
    } finally {
      hideAgenticApproval(false);
      thinking = false;
      setInputsDisabled(false);
    }
    return;
  }
  elements.hudOutput.textContent = route === "implicit" ? "Iris is checking current sources." : "Hermes thinking locally.";
  const response = await call("hermes_submit_task", {
    request: {
      mode,
      text: clean,
      explicitUserResearchRequest
    }
  });
  const responseText = formatHermesMemoryTaskText(response.text, response.memoryProposals, clean);
  const staged = formatHermesTaskStagedSection(response.memoryProposals);
  elements.hudOutput.textContent = route === "implicit" ? `Iris found this:\n\n${responseText}${staged}` : `${responseText}${staged}`;
}

async function runImageGeneration(text) {
  const clean = String(text || "").trim();
  if (!clean) {
    elements.hudOutput.textContent = "Type an image request first.";
    return;
  }
  const approved = await showAgenticApproval({
    requestId: `image-generation-${Date.now()}`,
    riskClass: "image_generation",
    summary: `Generate an image with the configured Iris image provider.\n\nPrompt: ${clean}`,
    requiresSeparateConfirmation: true
  });
  if (!approved) {
    elements.hudOutput.textContent = "Image generation canceled.";
    return;
  }
  if (!elements.browserPanel.hidden) {
    await hideBrowserPreview();
  }
  thinking = true;
  setInputsDisabled(true);
  elements.hudOutput.textContent = "Iris is generating the image.";
  try {
    const response = await call("hermes_generate_image", {
      request: {
        prompt: clean,
        approved: true
      }
    });
    elements.hudOutput.textContent = formatImageGenerationResult(response);
    await showGeneratedImagePreview(response);
  } catch (error) {
    elements.hudOutput.textContent = `Image generation failed: ${error}`;
  } finally {
    hideAgenticApproval(false);
    thinking = false;
    setInputsDisabled(false);
  }
}

async function runAgenticTaskWithApprovals(text) {
  let settled = false;
  let taskResult;
  let taskError;
  const task = call("hermes_submit_agentic_task", { text })
    .then(
      (result) => {
        taskResult = result;
      },
      (error) => {
        taskError = error;
      }
    )
    .finally(() => {
      settled = true;
    });
  while (!settled) {
    await new Promise((resolve) => window.setTimeout(resolve, 250));
    if (settled || panicStopActive) {
      continue;
    }
    const approval = await call("hermes_pending_agentic_approval");
    if (!approval || elements.approvalPanel.dataset.requestId === approval.requestId) {
      continue;
    }
    const approved = await showAgenticApproval(approval);
    await call("hermes_respond_agentic_approval", {
      requestId: approval.requestId,
      approved
    });
  }
  await task;
  if (taskError) {
    throw taskError;
  }
  return taskResult;
}

function showAgenticApproval(approval) {
  hideAgenticApproval(false);
  elements.approvalPanel.dataset.requestId = approval.requestId;
  elements.approvalRisk.textContent = formatRiskClass(approval.riskClass);
  elements.approvalSummary.textContent = approval.summary;
  elements.approvalPanel.hidden = false;
  elements.hudOutput.textContent = "Hermes is waiting for your confirmation.";
  return new Promise((resolve) => {
    activeApprovalResolver = resolve;
  });
}

function hideAgenticApproval(decision = false) {
  elements.approvalPanel.hidden = true;
  delete elements.approvalPanel.dataset.requestId;
  if (activeApprovalResolver) {
    const resolve = activeApprovalResolver;
    activeApprovalResolver = null;
    resolve(decision);
  }
}

function formatRiskClass(value) {
  const labels = {
    destructive_git: "Destructive Git action",
    install_or_admin: "Install or administrator action",
    credentials: "Credential or secret access",
    consequential_browser_submission: "Consequential browser submission",
    executable_download: "Executable download",
    image_generation: "Image generation provider",
    payment: "Payment action",
    sensitive_files: "Sensitive file access",
    scope_expansion: "Outside selected workspace",
    ordinary: "Confirmation required"
  };
  return labels[String(value || "")] || "Confirmation required";
}

function formatAgenticTaskResult(response) {
  const activity = (response?.events || [])
    .filter((event) => event?.type === "tool_activity")
    .map((event) => String(event.payload || "").trim())
    .filter(Boolean);
  if (activity.length === 0) {
    return String(response?.text || "");
  }
  return `Tool activity:\n${activity.join("\n\n")}\n\nResult:\n${response.text}`;
}

function formatImageGenerationResult(response) {
  const provenance = response?.provenance || {};
  return [
    String(response?.text || "Image generated."),
    `Saved: ${response?.savedPath || "unknown"}`,
    `Provider: ${provenance.provider || "configured provider"}`,
    `Model: ${provenance.model || "configured model"}`,
    `Size: ${provenance.size || "unknown"}`,
    `Quality: ${provenance.quality || "unknown"}`,
    `Provenance: ${provenance.route || "iris_background_hermes_provider"}`
  ].join("\n");
}

async function showBrowserPreview(preview) {
  elements.browserUrl.textContent = preview.url || "Hermes browser";
  elements.browserPreviewImage.hidden = true;
  elements.browserPreviewImage.removeAttribute("src");
  if (preview.screenshotPath) {
    try {
      elements.browserPreviewImage.src = await call("browser_preview_data_url", {
        screenshotPath: preview.screenshotPath
      });
      elements.browserPreviewImage.hidden = false;
    } catch (error) {
      logVoice("browser_preview_image_error", error);
    }
  }
  elements.browserPanel.hidden = false;
  await resizeForBrowserPreview(true);
}

async function showGeneratedImagePreview(response) {
  elements.browserUrl.textContent = response?.savedPath ? `Generated image: ${response.savedPath}` : "Generated image";
  elements.browserPreviewImage.hidden = true;
  elements.browserPreviewImage.removeAttribute("src");
  if (response?.imageDataUrl) {
    elements.browserPreviewImage.src = response.imageDataUrl;
    elements.browserPreviewImage.hidden = false;
  } else if (response?.savedPath) {
    elements.browserPreviewImage.src = await call("generated_image_data_url", {
      savedPath: response.savedPath
    });
    elements.browserPreviewImage.hidden = false;
  }
  elements.browserPanel.hidden = false;
  await resizeForBrowserPreview(true);
}

async function hideBrowserPreview() {
  elements.browserPanel.hidden = true;
  elements.browserPreviewImage.removeAttribute("src");
  elements.browserPreviewImage.hidden = true;
  elements.browserUrl.textContent = "";
  await resizeForBrowserPreview(false);
}

async function resizeForBrowserPreview(show) {
  const LogicalSize = window.__TAURI__?.dpi?.LogicalSize;
  if (!currentWindow || !LogicalSize) {
    return;
  }
  try {
    const scaleFactor = await currentWindow.scaleFactor();
    const size = await currentWindow.innerSize();
    const width = Math.round(size.width / scaleFactor);
    const height = Math.round(size.height / scaleFactor);
    if (show) {
      if (browserPreviewRestoreHeight === null) {
        browserPreviewRestoreHeight = height;
      }
      await currentWindow.setSize(new LogicalSize(width, Math.max(height, 430)));
    } else if (browserPreviewRestoreHeight !== null) {
      await currentWindow.setSize(new LogicalSize(width, browserPreviewRestoreHeight));
      browserPreviewRestoreHeight = null;
    }
  } catch (error) {
    logVoice("browser_preview_resize_error", error);
  }
}

function formatHermesStatus(status, audit) {
  return [
    `Mode: ${status.mode}`,
    `Hermes enabled: ${Boolean(status.enabled)}`,
    `Sidecar enabled: ${Boolean(status.sidecarEnabled)}`,
    `Broker enabled: ${Boolean(status.brokerEnabled)}`,
    `Running: ${Boolean(status.running)}`,
    `Search enabled: ${Boolean(status.searchEnabled)}`,
    `Tools: ${(status.tools || []).join(", ")}`,
    `Acting tools: ${(status.actingTools || []).length}`,
    `Agentic runtime available: ${Boolean(status.agenticRuntimeAvailable)}`,
    `Safety audit: ${audit ? Boolean(audit.ok) : "not applicable"}`
  ].join("\n");
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
    return;
  }

  const chunks = splitSpeechChunks(text);
  if (chunks.length === 0) {
    return;
  }
  const runId = ++speechRunId;
  speaking = true;
  let totalTtsMs = 0;
  for (let index = 0; index < chunks.length; index += 1) {
    if (speechRunId !== runId || panicStopActive) {
      break;
    }
    totalTtsMs += await playSpeechChunk(chunks[index], runId, latencyTrace, index === 0);
    if (latencyTrace) {
      latencyTrace.ttsFullMs = totalTtsMs;
    }
  }
  if (speechRunId === runId) {
    speaking = false;
  }
  activeSpeechResolve = null;
  logVoice("speech_finished", `run=${runId}; chunks=${chunks.length}`);
}

function playSpeechChunk(text, runId, latencyTrace, firstChunk) {
  return new Promise((resolve) => {
    let resolved = false;
    const resolveOnce = (elapsedMs = 0) => {
      if (resolved) {
        return;
      }
      resolved = true;
      if (activeSpeechResolve === cancelChunk) {
        activeSpeechResolve = null;
      }
      resolve(optionalTiming(elapsedMs) || 0);
    };
    const cancelChunk = () => resolveOnce();
    activeSpeechResolve = cancelChunk;
    const ttsStartedAt = performance.now();
    logVoice("kokoro_tts_start", `run=${runId}; first=${firstChunk}`);
    call("kokoro_tts_wav", { text })
      .then((response) => {
        if (speechRunId !== runId) {
          resolveOnce();
          return;
        }
        const bytes = new Uint8Array(response.wavBytes);
        let speechMarkedPlaying = false;
        const markSpeechPlaying = (method) => {
          if (speechMarkedPlaying || speechRunId !== runId) {
            return;
          }
          speechMarkedPlaying = true;
          logVoice(
            "speech_started",
            `run=${runId}; method=${method}; voice=${response.voice}; tts_ms=${response.elapsedMs}`
          );
          if (latencyTrace && latencyTrace.ttsFirstAudioMs === null) {
            latencyTrace.ttsFirstAudioMs = Math.round(performance.now() - ttsStartedAt);
            latencyTrace.timeToFirstSpokenWordMs = Math.round(
              performance.now() - latencyTrace.turnStartedAt
            );
          }
          if (firstChunk) {
            monitorSpeechInterruption(runId);
          }
        };
        playNativeSpeech(bytes, runId, markSpeechPlaying)
          .catch((nativeError) => {
            logVoice("speech_native_playback_error", `run=${runId}; ${String(nativeError)}`);
            return playWavBytes(bytes, {
              clearActiveHandle: (handle) => {
                if (activeAudio === handle) {
                  activeAudio = null;
                }
              },
              onDiagnostic: (event, message) => {
                logVoice(event, `run=${runId}; ${message}`);
              },
              onPlaying: markSpeechPlaying,
              setActiveHandle: (handle) => {
                activeAudio = handle;
              }
            });
          })
          .then((method) => {
            if (!speechMarkedPlaying && speechRunId === runId) {
              markSpeechPlaying(method);
            }
          })
          .catch((error) => {
            logVoice("speech_playback_error", String(error));
            elements.voiceStatus.textContent =
              "Speech output failed. Check the Windows audio output device and app volume.";
          })
          .finally(() => {
            if (speechRunId === runId && speechMarkedPlaying) {
              logVoice("speech_playback_finished", `run=${runId}`);
            }
            resolveOnce(response.elapsedMs);
          });
      })
      .catch((error) => {
        logVoice("kokoro_tts_error", String(error));
        elements.voiceStatus.textContent = "Speech generation failed. Check diagnostics.";
        resolveOnce();
      });
  });
}

async function playNativeSpeech(bytes, runId, markSpeechPlaying) {
  if (!invoke) {
    throw new Error("native playback is unavailable");
  }
  markSpeechPlaying("native_cpal");
  await call("play_tts_wav", { wavBytes: Array.from(bytes) });
  return "native_cpal";
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
    if (!speaking && speechRunId === runId) {
      restartListeningIfReady(100);
    }
  }
}

function setInputsDisabled(disabled) {
  const gatedDisabled = disabled || panicStopActive;
  elements.hudInput.disabled = gatedDisabled;
  elements.sendButton.disabled = gatedDisabled;
  elements.attachmentRemove.disabled = disabled;
  elements.attachButton.disabled = gatedDisabled;
  elements.voiceButton.disabled = false;
  elements.visionButton.disabled = gatedDisabled;
  elements.screenButton.disabled = gatedDisabled;
  elements.memoryButton.disabled = gatedDisabled;
  elements.memoryAddButton.disabled = gatedDisabled;
  elements.memoryAddInput.disabled = gatedDisabled;
}

function renderPanicStop() {
  elements.panicButton.classList.toggle("active", panicStopActive);
  elements.irisConsole.classList.toggle("panic-active", panicStopActive);
  elements.panicButton.setAttribute("aria-pressed", panicStopActive ? "true" : "false");
  elements.panicButton.setAttribute("title", panicStopActive ? "Resume Iris" : "Pause Iris");
  elements.panicButton.setAttribute("aria-label", panicStopActive ? "Resume Iris" : "Pause Iris");
  setInputsDisabled(thinking || speaking || listening);
}

async function togglePanicStop() {
  const nextActive = nextPanicState(panicStopActive);
  const policy = await call(
    nextActive ? "hermes_panic_stop" : "hermes_clear_panic_stop"
  );
  panicStopActive = Boolean(policy.panicStopActive);
  if (panicStopActive) {
    hideAgenticApproval(false);
    await hideBrowserPreview();
    stopListeningRequested = true;
    voiceLoop = false;
    wakeCommandArmed = false;
    wakeMissStreak = 0;
    pendingVoiceLatency = null;
    setListening(false);
    activeListenMode = "idle";
    if (activeAudio) {
      activeAudio.pause();
      activeAudio = null;
    }
    if (activeSpeechResolve) {
      activeSpeechResolve();
      activeSpeechResolve = null;
    }
    speaking = false;
    elements.voiceStatus.textContent = "Iris paused.";
  } else {
    stopListeningRequested = false;
    wakeMissStreak = 0;
    elements.voiceStatus.textContent = "Wake word armed. Say Iris.";
    restartListeningIfReady(250);
  }
  elements.hudOutput.textContent = panicStatusText(panicStopActive);
  logVoice(panicStopActive ? "panic_stop_active" : "panic_stop_cleared");
  renderPanicStop();
}

elements.approvalAllow.addEventListener("click", () => hideAgenticApproval(true));
elements.approvalDeny.addEventListener("click", () => hideAgenticApproval(false));
elements.browserPreviewClose.addEventListener("click", () => {
  void hideBrowserPreview();
});

function setListening(nextListening) {
  listening = nextListening;
  elements.voiceButton.classList.toggle("listening", listening);
  elements.irisConsole.classList.toggle("listening", listening);
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

function startWindowDrag() {
  currentWindow?.startDragging?.().catch((error) => {
    logVoice("window_drag_error", String(error));
  });
}

function restartListeningIfReady(delayMs = 650) {
  if (panicStopActive || (!voiceLoop && !wakeWord) || thinking || speaking || listening || interruptionListening || stopListeningRequested) {
    return;
  }

  window.setTimeout(() => {
    if (panicStopActive || (!voiceLoop && !wakeWord) || thinking || speaking || listening || interruptionListening || stopListeningRequested) {
      return;
    }
    const mode = nextVoiceListenMode({ wakeCommandArmed, wakeWord, voiceLoop });
    if (mode) {
      listenOnce(mode);
    }
  }, delayMs);
}

async function listenOnce(mode) {
  if (panicStopActive) {
    elements.hudOutput.textContent = panicStatusText(true);
    return;
  }
  if (listening || thinking || speaking) {
    return;
  }

  activeListenMode = mode;
  const generation = listenGeneration;
  let restartDelayMs = 650;
  setListening(true);
  logVoice("native_asr_start_requested");
  elements.voiceStatus.textContent = mode === "push" ? "Listening..." : "Listening for Iris.";
  try {
    const result = await call("native_asr_listen_once", { mode });
    if (generation !== listenGeneration) {
      pendingVoiceLatency = null;
      return;
    }
    if (panicStopActive) {
      pendingVoiceLatency = null;
      return;
    }
    const transcript = String(result.text || "").trim();
    logVoice("native_asr_result", `${result.elapsed_ms}ms; ${transcript}`);
    pendingVoiceLatency = {
      captureElapsedMs: result.captureElapsedMs ?? result.capture_elapsed_ms,
      sttElapsedMs: result.sttElapsedMs ?? result.stt_elapsed_ms
    };
    if (!isUsableTranscript(transcript)) {
      pendingVoiceLatency = null;
      elements.voiceStatus.textContent = "No speech transcript captured.";
      if (mode === "wake") {
        wakeMissStreak += 1;
      }
      restartDelayMs = wakeRestartDelayMs(mode, transcript, "ignore", wakeMissStreak);
      return;
    }
    const decision = handleVoiceTranscript(transcript);
    if (shouldDisplayVoiceTranscript(decision)) {
      elements.hudOutput.textContent = transcript;
    }
    if (mode === "wake" && (decision?.action === "wait-for-wake" || decision?.action === "ignore")) {
      wakeMissStreak += 1;
    } else if (mode !== "wake" || decision?.action === "submit" || decision?.action === "arm-wake-followup") {
      wakeMissStreak = 0;
    }
    restartDelayMs = wakeRestartDelayMs(mode, transcript, decision?.action, wakeMissStreak);
  } catch (error) {
    if (panicStopActive) {
      return;
    }
    const asrError = classifyAsrError(error);
    elements.voiceStatus.textContent = asrError.status;
    if (asrError.severity === "error") {
      elements.hudOutput.textContent = String(error);
    }
    logVoice(asrError.event, String(error));
  } finally {
    setListening(false);
    if (mode !== "push") {
      restartListeningIfReady(restartDelayMs);
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
    wakeMissStreak = 0;
    voiceLoop = false;
    elements.hudOutput.textContent = "Stopped.";
    restartListeningIfReady(250);
    return decision;
  }

  if (decision.action === "submit") {
    wakeCommandArmed = false;
    wakeMissStreak = 0;
    voiceLoop = shouldContinueVoiceSession(decision);
    submitMessage(decision.prompt, decision.source);
    return decision;
  }

  if (decision.action === "arm-wake-followup") {
    pendingVoiceLatency = null;
    wakeCommandArmed = true;
    wakeMissStreak = 0;
    voiceLoop = false;
    elements.hudOutput.textContent = "Listening.";
    elements.voiceStatus.textContent = "Listening.";
    restartListeningIfReady(100);
    return decision;
  }

  if (decision.action === "wait-for-wake") {
    if (voiceLoop) {
      submitMessage(transcript, "voice-session");
      return decision;
    }
    pendingVoiceLatency = null;
    wakeCommandArmed = false;
  }
  return decision;
}

elements.hudForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  const text = elements.hudInput.value.trim();
  if (!text) {
    return;
  }

  submitMessage(text, "typed");
});

elements.hudInput.addEventListener("keydown", (event) => {
  if (
    shouldSubmitComposer({
      key: event.key,
      shiftKey: event.shiftKey,
      isComposing: event.isComposing
    })
  ) {
    event.preventDefault();
    elements.hudForm.requestSubmit();
  }
});

elements.hudInput.addEventListener("input", resizeComposerInput);

elements.voiceButton.addEventListener("click", () => {
  if (panicStopActive) {
    elements.hudOutput.textContent = panicStatusText(true);
    return;
  }
  if (listening && activeListenMode === "push") {
    stopListeningRequested = true;
    return;
  }

  stopListeningRequested = false;
  listenOnce("push");
});

elements.attachButton.addEventListener("click", () => {
  if (panicStopActive || thinking || speaking || cameraCaptureInProgress) {
    return;
  }
  elements.visionFileInput.click();
});

elements.memoryButton.addEventListener("click", () => {
  if (panicStopActive) {
    elements.hudOutput.textContent = panicStatusText(true);
    return;
  }
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

elements.panicButton.addEventListener("click", () => {
  togglePanicStop().catch((error) => {
    elements.hudOutput.textContent = String(error);
  });
});

elements.windowDragStrip.addEventListener("pointerdown", () => {
  startWindowDrag();
});

elements.responseResizeHandle.addEventListener("pointerdown", startResponseResize);
elements.responseResizeHandle.addEventListener("keydown", resizeResponseWithKeyboard);
elements.responseResizeHandle.addEventListener("dblclick", () => {
  setResponseHeight(responseDefaultHeight);
});
window.addEventListener("resize", () => {
  setResponseHeight(elements.responsePane.getBoundingClientRect().height);
});

elements.visionButton.addEventListener("click", () => {
  if (panicStopActive || thinking || speaking || cameraCaptureInProgress) {
    return;
  }
  lookWithCamera().catch((error) => {
    elements.hudOutput.textContent = String(error);
  });
});

elements.screenButton.addEventListener("click", () => {
  if (panicStopActive || thinking || speaking) {
    return;
  }
  submitScreenAreaMessage().catch((error) => {
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

function createTrustedAttachmentObjectUrl(blob) {
  const url = URL.createObjectURL(blob);
  trustedAttachmentObjectUrls.add(url);
  return url;
}

function revokeTrustedAttachmentObjectUrl(url) {
  if (!trustedAttachmentObjectUrls.delete(url)) {
    return;
  }
  URL.revokeObjectURL(url);
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
      throw new Error(unsupportedAttachmentMessage());
  }
}

async function cancelActiveAsr() {
  listenGeneration += 1;
  if (!invoke) {
    return;
  }
  try {
    await call("cancel_native_asr");
  } catch (error) {
    logVoice("native_asr_cancel_error", String(error));
  }
}

async function readVisionImage(file) {
  if (classifyAttachmentFile(file) !== "image") {
    throw new Error("Vision input supports png, jpg, jpeg, and webp images.");
  }
  validateImageSize(file);
  const buffer = await file.arrayBuffer();
  const previewUrl = createTrustedAttachmentObjectUrl(file);
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

async function lookWithCamera() {
  const prompt = elements.hudInput.value.trim() || defaultCameraPrompt;
  await captureCameraSnapshot();
  elements.hudInput.value = "";
  resizeComposerInput();
  await submitMessage(prompt, "camera-look");
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
    previewUrl: createTrustedAttachmentObjectUrl(blob),
    kindLabel: "Camera"
  };
}

async function snapshotFromVideoFile(file) {
  validateVideoSize(file);
  const video = document.createElement("video");
  video.muted = true;
  video.playsInline = true;
  video.preload = "metadata";
  const sourceUrl = createTrustedAttachmentObjectUrl(file);

  // codeql[js/xss-through-dom] local blob URL minted and tracked by this renderer.
  video.src = requireTrustedBlobUrl(sourceUrl, trustedAttachmentObjectUrls);
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
      previewUrl: createTrustedAttachmentObjectUrl(blob),
      kindLabel: "Video frame"
    };
  } finally {
    revokeTrustedAttachmentObjectUrl(sourceUrl);
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
    revokeTrustedAttachmentObjectUrl(selectedVisionImage.previewUrl);
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

    // codeql[js/xss-through-dom] preview accepts only local blob URLs minted and tracked by this renderer.
    preview.src = requireTrustedBlobUrl(selectedVisionImage.previewUrl, trustedAttachmentObjectUrls);
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

function resizeComposerInput() {
  elements.hudInput.style.height = "auto";
  elements.hudInput.style.height = `${composerHeightFor(elements.hudInput.scrollHeight)}px`;
}

function responseHeightLimit() {
  return Math.max(responseMinHeight, window.innerHeight - 194);
}

function setResponseHeight(requestedHeight) {
  const maximum = responseHeightLimit();
  const height = clampResponseHeight(requestedHeight, maximum);
  document.documentElement.style.setProperty("--response-height", `${height}px`);
  elements.responseResizeHandle.setAttribute("aria-valuenow", String(height));
  elements.responseResizeHandle.setAttribute("aria-valuemax", String(maximum));
  try {
    window.localStorage.setItem(responseHeightStorageKey, String(height));
  } catch {
    // Persisted layout is optional when webview storage is unavailable.
  }
  return height;
}

function storedResponseHeight() {
  try {
    const stored = window.localStorage.getItem(responseHeightStorageKey);
    return stored === null ? responseDefaultHeight : Number(stored);
  } catch {
    return responseDefaultHeight;
  }
}

function startResponseResize(event) {
  if (event.button !== 0) {
    return;
  }
  event.preventDefault();
  const startY = event.clientY;
  const startHeight = elements.responsePane.getBoundingClientRect().height;
  elements.responseResizeHandle.setPointerCapture(event.pointerId);

  const move = (moveEvent) => {
    setResponseHeight(responseHeightFromDrag(startHeight, startY, moveEvent.clientY));
  };
  const finish = () => {
    elements.responseResizeHandle.removeEventListener("pointermove", move);
    elements.responseResizeHandle.removeEventListener("pointerup", finish);
    elements.responseResizeHandle.removeEventListener("pointercancel", finish);
  };

  elements.responseResizeHandle.addEventListener("pointermove", move);
  elements.responseResizeHandle.addEventListener("pointerup", finish);
  elements.responseResizeHandle.addEventListener("pointercancel", finish);
}

function resizeResponseWithKeyboard(event) {
  const currentHeight = elements.responsePane.getBoundingClientRect().height;
  let nextHeight = responseHeightFromKeyboard(currentHeight, event.key);
  if (event.key === "Home") {
    nextHeight = responseMinHeight;
  } else if (event.key === "End") {
    nextHeight = responseHeightLimit();
  }
  if (nextHeight === null) {
    return;
  }
  event.preventDefault();
  setResponseHeight(nextHeight);
}

function initializeLayout() {
  resizeComposerInput();
  setResponseHeight(storedResponseHeight());
}

initializeLayout();
renderVoiceCapability();
renderAttachmentSelection();
renderPanicStop();
logVoice("app_started");
refreshDashboard();
warmRuntimeBeforeListening();
