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
  buildCameraCapturePlan,
  cameraAttemptDiagnostic,
  cameraErrorMessage,
  createCameraPermissionPromptTimeoutError,
  createCameraUnavailableError
} from "./camera-state.js";
import {
  formatDynamicContextStatus,
  parseDynamicContextCommand
} from "./dynamic-context-state.js";
import {
  buildFeedbackCapture,
  createFeedbackTurn,
  feedbackFieldsVisible,
  formatFeedbackStatus
} from "./feedback-state.js";
import {
  clampResponseHeight,
  composerHeightFor,
  responseDefaultHeight,
  responseHeightFromDrag,
  responseHeightFromKeyboard,
  responseHeightLimitForViewport,
  responseMinHeight,
  shouldSubmitComposer
} from "./composer-state.js";
import {
  formatAgenticHermesPrompt,
  isAgenticMemoryStageRequest
} from "./hermes-agentic-prompt.js";
import { formatAgenticTaskResult } from "./hermes-agentic-result.js";
import { formatHermesMode, parseHermesControlCommand } from "./hermes-mode.js";
import { classifyHermesRoute } from "./hermes-routing.js";
import { shouldClearInputOnSubmit } from "./input-state.js";
import { canSubmitWhilePanicStopped, nextPanicState, panicStatusText } from "./panic-state.js";
import {
  nativeSpeechPlaybackArguments,
  playWavBytes
} from "./speech-output.js";
import { splitSpeechChunks } from "./speech-chunks.js";
import {
  createPipelinedSpeechQueue,
  createSpeechPlaybackRegistry,
  drainCompletedSpeech,
  speechRunIsCurrent
} from "./speech-stream.js";
import {
  formatHermesMemoryTaskText,
  formatHermesTaskStagedSection,
  formatStagedMemories
} from "./staging-state.js";
import {
  RUNTIME_PREPARING_STATUS,
  VOICE_SETUP_NEEDED_STATUS,
  classifyAsrError,
  classifyVoiceTranscript,
  createInterruptionPauseCoordinator,
  interruptionCandidatePauseAllowed,
  interruptionCaptureAttemptAllowed,
  interruptionResumeRequiresCancellation,
  interruptionRetryDelayMs,
  interruptionSignalIsCurrent,
  nextVoiceListenMode,
  noSpeechStatusForMode,
  runtimeWarmHudStatus,
  shouldDisarmWakeFollowupAfterMisses,
  shouldContinueVoiceSession,
  shouldDisplayVoiceTranscript,
  voiceButtonAction,
  voiceCaptureCanStart,
  voiceTranscriptStateForMode,
  wakeRestartDelayMs
} from "./voice-state.js";

const invoke = window.__TAURI__?.core?.invoke;
const currentWindow = window.__TAURI__?.window?.getCurrentWindow?.();
const tauriEventApi = window.__TAURI__?.event;
const listenTauriEvent = tauriEventApi?.listen?.bind(tauriEventApi);
const interruptionOnsetEvent = "iris://voice/interruption-onset";
const playbackOnsetEvent = "iris://voice/playback-onset";
const modelChunkEvent = "iris://model/chunk";

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
  feedbackCorrection: document.querySelector("#feedback-correction"),
  feedbackDown: document.querySelector("#feedback-down"),
  feedbackExport: document.querySelector("#feedback-export"),
  feedbackPanel: document.querySelector("#feedback-panel"),
  feedbackReason: document.querySelector("#feedback-reason"),
  feedbackSave: document.querySelector("#feedback-save"),
  feedbackUp: document.querySelector("#feedback-up"),
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
let wakeCommandMissStreak = 0;
let thinking = false;
let speaking = false;
let runtimePreparing = true;
let speechRunId = 0;
let interruptionListening = false;
let interruptionMonitorGeneration = 0;
let interruptionRequestSequence = 0;
let activeInterruptionRequestId = 0;
let activeInterruptionCaptureStartedAt = 0;
let rejectedInterruptionPauseCount = 0;
let activeAudio = null;
let activeNativePlaybackOnset = null;
const activeSpeechPlayback = createSpeechPlaybackRegistry();
const interruptionPause = createInterruptionPauseCoordinator();
let activeSpeechQueue = null;
let modelRequestSequence = 0;
let activeModelStream = null;
let pendingInterruptionPrompt = "";
let activeListenMode = "idle";
let listenGeneration = 0;
let wakeRestartTimer = null;
let stopListeningRequested = false;
let panicStopActive = false;
let pendingVoiceLatency = null;
let lastAudioInputDevice = "";
let lastAudioOutputDevice = "";
let selectedVisionImage = null;
let selectedDocument = null;
let memoryPanelOpen = false;
let cameraCaptureInProgress = false;
let activeApprovalResolver = null;
let browserPreviewRestoreHeight = null;
let lastFeedbackTurn = null;
let selectedFeedbackRating = null;
const conversationHistory = [];
const maxHistoryTurns = 8;
const feedbackModelId = "huihui_ai/gemma-4-abliterated:e2b";
const feedbackProvider = "ollama_local";
const cameraSnapshotWidth = 640;
const cameraSnapshotHeight = 480;
const cameraPermissionTimeoutMs = 12000;
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
    this.ttsSynthesisMs = null;
    this.ttsPlaybackMs = null;
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
      ttsSynthesisMs: this.ttsSynthesisMs,
      ttsPlaybackMs: this.ttsPlaybackMs,
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

function logAudioRoute(event, deviceLabel) {
  const label = String(deviceLabel || "").trim();
  if (!label) {
    return;
  }
  if (event === "audio_input_device") {
    if (label === lastAudioInputDevice) {
      return;
    }
    lastAudioInputDevice = label;
  } else if (event === "audio_output_device") {
    if (label === lastAudioOutputDevice) {
      return;
    }
    lastAudioOutputDevice = label;
  }
  logVoice(event, `device=${label}`);
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
    return true;
  } catch (error) {
    logVoice("kokoro_warm_error", String(error));
    if (!panicStopActive) {
      elements.voiceStatus.textContent = VOICE_SETUP_NEEDED_STATUS;
    }
    return false;
  }
}

async function warmModel() {
  try {
    logVoice("ollama_warm_start");
    await call("warm_ollama_model");
    logVoice("ollama_warm_ready");
    return true;
  } catch (error) {
    logVoice("ollama_warm_error", String(error));
    return false;
  }
}

function showFeedbackForTurn(turn) {
  lastFeedbackTurn = turn;
  selectedFeedbackRating = null;
  elements.feedbackUp.classList.remove("active");
  elements.feedbackDown.classList.remove("active");
  elements.feedbackReason.value = "";
  elements.feedbackCorrection.value = "";
  elements.feedbackReason.hidden = true;
  elements.feedbackCorrection.hidden = true;
  elements.feedbackSave.hidden = true;
  elements.feedbackPanel.hidden = !turn;
}

function hideFeedbackPanel() {
  lastFeedbackTurn = null;
  selectedFeedbackRating = null;
  elements.feedbackPanel.hidden = true;
}

function setFeedbackRating(rating) {
  if (!lastFeedbackTurn) {
    return;
  }
  selectedFeedbackRating = rating;
  elements.feedbackUp.classList.toggle("active", rating === "up");
  elements.feedbackDown.classList.toggle("active", rating === "down");
  const showFields = feedbackFieldsVisible(rating);
  elements.feedbackReason.hidden = !showFields;
  elements.feedbackCorrection.hidden = !showFields;
  elements.feedbackSave.hidden = false;
  if (!showFields) {
    elements.feedbackReason.value = "";
    elements.feedbackCorrection.value = "";
  }
}

async function saveSelectedFeedback() {
  const capture = buildFeedbackCapture(
    lastFeedbackTurn,
    selectedFeedbackRating,
    elements.feedbackReason.value,
    elements.feedbackCorrection.value
  );
  if (!capture) {
    return;
  }
  try {
    await call("record_feedback", { capture });
    const status = await call("feedback_status");
    elements.hudOutput.textContent = formatFeedbackStatus(status);
    showFeedbackForTurn(null);
  } catch (error) {
    elements.hudOutput.textContent = `Feedback was not saved: ${error}`;
  }
}

async function exportFeedbackPairs() {
  try {
    const result = await call("export_feedback_preference_pairs");
    elements.hudOutput.textContent = `Preference-pair export complete.\nPairs: ${result.pairCount}\nSaved: ${result.path}`;
  } catch (error) {
    elements.hudOutput.textContent = `Preference-pair export failed: ${error}`;
  }
}

async function warmRuntimeBeforeListening() {
  if (!panicStopActive) {
    elements.hudOutput.textContent = "Iris is starting.";
  }
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
    const message = String(error || "");
    if (!panicStopActive) {
      elements.hudOutput.textContent = message.includes("ollama pull")
        ? message
        : "Local model service is unavailable. Run Iris Setup Wizard or install Ollama for Windows.";
    }
  }
  if (runtimeReady && !panicStopActive) {
    elements.hudOutput.textContent = "Iris is warming voice and model.";
  }
  const [voiceWarmResult, modelWarmResult] = await Promise.allSettled([
    warmVoice(),
    runtimeReady ? warmModel() : Promise.resolve(false)
  ]);
  const voiceWarmReady =
    voiceWarmResult.status === "fulfilled" && voiceWarmResult.value === true;
  const modelWarmReady =
    modelWarmResult.status === "fulfilled" && modelWarmResult.value === true;
  logVoice(
    "runtime_warm_complete",
    `runtime_ready=${runtimeReady}; voice_ready=${voiceWarmReady}; model_ready=${modelWarmReady}`
  );
  runtimePreparing = false;
  setInputsDisabled(inputBlockingWorkActive());
  if (panicStopActive) {
    elements.hudOutput.textContent = runtimeWarmHudStatus(
      runtimeReady,
      voiceWarmReady,
      modelWarmReady,
      true
    );
    elements.voiceStatus.textContent = panicStatusText(true);
  } else if (runtimeReady) {
    elements.hudOutput.textContent = runtimeWarmHudStatus(
      runtimeReady,
      voiceWarmReady,
      modelWarmReady,
      false
    );
    restartListeningIfReady(100);
  }
}

async function submitMessage(text, source = "typed") {
  if (runtimePreparing) {
    elements.hudOutput.textContent = RUNTIME_PREPARING_STATUS;
    return;
  }
  if (!canSubmitWhilePanicStopped(panicStopActive)) {
    elements.hudOutput.textContent = panicStatusText(true);
    return;
  }
  if (thinking || speaking) {
    return;
  }
  await cancelActiveAsr();
  wakeCommandArmed = false;
  wakeCommandMissStreak = 0;
  voiceLoop = false;
  if (shouldClearInputOnSubmit(text, thinking || speaking)) {
    elements.hudInput.value = "";
    resizeComposerInput();
  }
  const latencyTrace = new VoiceLatencyTrace();
  hideFeedbackPanel();
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
  let turnStream = null;
  try {
    const history = conversationHistory.slice();
    const speechSession = speakReplies ? await beginSpeechSession(latencyTrace) : null;
    const requestId = ++modelRequestSequence;
    turnStream = {
      requestId,
      text: "",
      speechRemainder: "",
      speechSession,
      latencyTrace,
      modelStartedAt: performance.now(),
      cancelRequested: false
    };
    activeModelStream = turnStream;
    const response = await call("submit_typed_hud_stream", {
      text,
      history,
      styleText: originalText,
      requestId
    });
    latencyTrace.llmFullResponseMs = optionalTiming(response.model_elapsed_ms);
    if (response.error) {
      if (activeModelStream === turnStream) {
        activeModelStream = null;
      }
      if (turnStream.speechSession) {
        await turnStream.speechSession.cancel();
      }
      elements.hudOutput.textContent = String(response.error);
      logVoice(
        "turn_model_error",
        `${source}; request=${requestId}; model_ms=${response.model_elapsed_ms}; ${String(response.error)}`
      );
      return;
    }
    if (activeModelStream === turnStream && !turnStream.cancelRequested) {
      if (!turnStream.text && response.text) {
        appendModelStreamText(turnStream, response.text);
      } else if (String(response.text || "").startsWith(turnStream.text)) {
        appendModelStreamText(
          turnStream,
          String(response.text || "").slice(turnStream.text.length)
        );
      }
      if (turnStream.speechSession) {
        const finalSpeech = drainCompletedSpeech(turnStream.speechRemainder, {
          final: true
        });
        turnStream.speechRemainder = finalSpeech.remainder;
        for (const speechChunk of finalSpeech.chunks) {
          turnStream.speechSession.push(speechChunk);
        }
      }
    }
    if (activeModelStream === turnStream) {
      activeModelStream = null;
    }
    if (response.cancelled || turnStream.cancelRequested) {
      if (turnStream.speechSession) {
        void turnStream.speechSession.cancel();
      }
      elements.hudOutput.textContent = "Stopped.";
      logVoice(
        "turn_cancelled",
        `${source}; request=${requestId}; model_ms=${response.model_elapsed_ms}`
      );
      return;
    }
    elements.hudOutput.textContent = response.text;
    rememberTurn("user", documentAttached ? `[document] ${originalText}` : originalText);
    rememberTurn("iris", response.text);
    showFeedbackForTurn(createFeedbackTurn({
      source: documentAttached ? "document" : source,
      userText: documentAttached ? `[document] ${originalText}` : originalText,
      assistantText: response.text,
      modelId: feedbackModelId,
      provider: feedbackProvider,
      tools: documentAttached ? ["attachment"] : [],
      latencyMs: response.model_elapsed_ms
    }));
    logVoice(
      "turn_complete",
      `${source}; model_ms=${response.model_elapsed_ms}; total_ms=${Math.round(performance.now() - turnStarted)}`
    );
    thinking = false;
    setInputsDisabled(false);
    if (turnStream.speechSession) {
      await turnStream.speechSession.finish();
    }
  } catch (error) {
    if (activeModelStream === turnStream) {
      await cancelActiveModelGeneration("turn-error");
      activeModelStream = null;
    }
    if (turnStream?.speechSession) {
      void turnStream.speechSession.cancel();
    }
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
  await submitVisualProbeMessage(image, prompt, latencyTrace, {
    source: "image",
    userPrefix: "[image]",
    tools: ["vision"],
    statusText: "Image selected.\n\nThinking locally...",
    startEvent: "image_probe_start",
    endEvent: "image_probe_complete",
    errorEvent: "image_probe_error",
    submitEndSource: "image-probe"
  });
}

async function submitVisualProbeMessage(image, prompt, latencyTrace, options) {
  const turnStarted = performance.now();
  thinking = true;
  hideFeedbackPanel();
  logVoice(options.startEvent, `bytes=${image.bytes.length}; source=${options.source}`);
  setInputsDisabled(true);
  elements.hudOutput.textContent = options.statusText;
  try {
    const response = await call("submit_image_probe", {
      imageName: image.name,
      imageBytes: image.bytes,
      prompt
    });
    latencyTrace.llmFullResponseMs = optionalTiming(response.model_elapsed_ms);
    elements.hudOutput.textContent = response.text;
    rememberTurn("user", `${options.userPrefix} ${prompt}`);
    rememberTurn("iris", response.text);
    showFeedbackForTurn(createFeedbackTurn({
      source: options.source,
      userText: `${options.userPrefix} ${prompt}`,
      assistantText: response.text,
      modelId: feedbackModelId,
      provider: feedbackProvider,
      tools: options.tools,
      latencyMs: response.model_elapsed_ms
    }));
    logVoice(
      options.endEvent,
      `model_ms=${response.model_elapsed_ms}; total_ms=${Math.round(performance.now() - turnStarted)}; source=${options.source}`
    );
    thinking = false;
    setInputsDisabled(false);
    await speak(response.text, latencyTrace);
  } catch (error) {
    elements.hudOutput.textContent = String(error);
    logVoice(
      options.errorEvent,
      `total_ms=${Math.round(performance.now() - turnStarted)}; source=${options.source}; ${String(error)}`
    );
  } finally {
    latencyTrace.finishTotal();
    await logVoiceLatencyReport(latencyTrace);
    thinking = false;
    setInputsDisabled(false);
    logVoice("submit_end", options.submitEndSource);
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
  await cancelActiveAsr();
  wakeCommandArmed = false;
  wakeCommandMissStreak = 0;
  voiceLoop = false;
  const latencyTrace = new VoiceLatencyTrace();
  const prompt = elements.hudInput.value.trim() || defaultScreenPrompt;
  const turnStarted = performance.now();
  thinking = true;
  hideFeedbackPanel();
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
    showFeedbackForTurn(createFeedbackTurn({
      source: "screen",
      userText: `[screen] ${prompt}`,
      assistantText: response.text,
      modelId: feedbackModelId,
      provider: feedbackProvider,
      tools: ["screen"],
      latencyMs: response.model_elapsed_ms
    }));
    if (response.diagnostic_path) {
      logVoice("screen_probe_diagnostic", response.diagnostic_path);
    }
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
  if (/^feedback\s+status$/i.test(clean)) {
    const status = await call("feedback_status");
    elements.hudOutput.textContent = formatFeedbackStatus(status);
    hideFeedbackPanel();
    return true;
  }
  if (/^feedback\s+export$/i.test(clean)) {
    await exportFeedbackPairs();
    hideFeedbackPanel();
    return true;
  }
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

  const addMatch = clean.match(/^(?:remember\s*:|memory\s+add\s*[:,-]?)\s+(.+)$/i);
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
      "Memory and context commands:\nremember: <text>\nmemory list\nmemory edit <number>: <text>\nmemory delete <number>\ndynamic context\ndynamic context on\ndynamic context off\ndynamic context reset\nfeedback status\nfeedback export\nhermes: <task>\nhermes research: <task>\nhermes code: <task>\nhermes status\nhermes mode off\nhermes mode safe\nhermes agentic C:\\path\\to\\workspace\nhermes session end\nhermes staging\nhermes accept <number>\nhermes reject <number>\n\nIris stores up to 40 short memories. Dynamic context stores only decaying aggregate communication metrics. Feedback stores local ratings and corrections for preference summaries and export only. Online, browser, and research requests can be asked directly through Iris.";
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
    hideFeedbackPanel();
    setInputsDisabled(true);
    elements.hudOutput.textContent =
      mode === "research"
        ? "Iris is checking current sources."
        : "Iris is working through Agentic Hermes.";
    try {
      const response = await runAgenticTaskWithApprovals(
        formatAgenticHermesPrompt(mode, clean, route)
      );
      let output = formatAgenticTaskResult(response);
      if (mode === "reason" && isAgenticMemoryStageRequest(clean)) {
        const staged = await call("hermes_staging_list");
        const stagedSection = formatHermesTaskStagedSection(staged);
        if (stagedSection) {
          output = `${formatHermesMemoryTaskText(output, staged, clean)}${stagedSection}`;
        }
      }
      elements.hudOutput.textContent = output;
      showFeedbackForTurn(createFeedbackTurn({
        source: `hermes-agentic-${mode}`,
        userText: clean,
        assistantText: output,
        modelId: feedbackModelId,
        provider: "hermes_acp",
        tools: ["hermes", "agentic"]
      }));
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
  hideFeedbackPanel();
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
  const output = route === "implicit" ? `Iris found this:\n\n${responseText}${staged}` : `${responseText}${staged}`;
  elements.hudOutput.textContent = output;
  showFeedbackForTurn(createFeedbackTurn({
    source: `hermes-safe-${mode}`,
    userText: clean,
    assistantText: output,
    modelId: feedbackModelId,
    provider: "hermes_sidecar",
    tools: ["hermes", mode]
  }));
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
  hideFeedbackPanel();
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
    showFeedbackForTurn(createFeedbackTurn({
      source: "image-generation",
      userText: clean,
      assistantText: formatImageGenerationResult(response),
      modelId: response?.provenance?.model || feedbackModelId,
      provider: response?.provenance?.provider || "image_provider",
      tools: ["image_generation"]
    }));
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

async function cancelInterruptionMonitoring(reason) {
  const cancelledRequestId = activeInterruptionRequestId;
  interruptionMonitorGeneration += 1;
  activeInterruptionRequestId = 0;
  activeInterruptionCaptureStartedAt = 0;
  interruptionPause.clear();
  interruptionListening = false;
  if (!invoke) {
    return;
  }
  try {
    await call("cancel_native_asr");
    if (cancelledRequestId > 0) {
      logVoice(
        "speech_interruption_capture_cancelled",
        `request=${cancelledRequestId}; reason=${reason}`
      );
    }
  } catch (error) {
    logVoice("speech_interruption_cancel_error", String(error));
  }
}

async function setNativePlaybackPaused(paused, runId, requestId) {
  if (!invoke || runId <= 0 || requestId <= 0) {
    return false;
  }
  try {
    return Boolean(
      await call("set_tts_playback_paused", {
        paused,
        playbackId: runId,
        requestId
      })
    );
  } catch (error) {
    logVoice("speech_native_pause_error", `run=${runId}; request=${requestId}; ${String(error)}`);
    return false;
  }
}

async function cancelNativePlayback(runId) {
  if (!invoke || runId <= 0) {
    return;
  }
  try {
    await call("cancel_tts_playback", { playbackId: runId });
  } catch (error) {
    logVoice("speech_native_cancel_error", `run=${runId}; ${String(error)}`);
  }
}

function cancelSpeech(reason = "requested") {
  const cancelledRunId = speechRunId;
  speechRunId += 1;
  speaking = false;
  const speechQueue = activeSpeechQueue;
  activeSpeechQueue = null;
  if (speechQueue) {
    void speechQueue.cancel();
  }
  const interruptionCancellation = cancelInterruptionMonitoring(reason);
  const playbackCancellation = cancelNativePlayback(cancelledRunId);
  const modelCancellation = cancelActiveModelGeneration(reason);
  if (activeAudio) {
    const fallbackAudio = activeAudio;
    activeAudio = null;
    fallbackAudio.pause();
    fallbackAudio.src = "";
  }
  if (activeNativePlaybackOnset?.runId === cancelledRunId) {
    activeNativePlaybackOnset = null;
  }
  activeSpeechPlayback.cancelRun(cancelledRunId);
  return Promise.allSettled([
    interruptionCancellation,
    playbackCancellation,
    modelCancellation
  ]);
}

async function cancelActiveModelGeneration(reason = "requested") {
  const stream = activeModelStream;
  if (!stream || stream.requestId <= 0 || stream.cancelRequested) {
    return false;
  }
  stream.cancelRequested = true;
  logVoice("model_stream_cancel_requested", `request=${stream.requestId}; reason=${reason}`);
  try {
    return Boolean(
      await call("cancel_model_generation", {
        requestId: stream.requestId
      })
    );
  } catch (error) {
    logVoice(
      "model_stream_cancel_error",
      `request=${stream.requestId}; ${String(error)}`
    );
    return false;
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
  const session = await beginSpeechSession(latencyTrace);
  for (const chunk of chunks) {
    session.push(chunk);
  }
  await session.finish();
}

async function beginSpeechSession(latencyTrace = null) {
  await cancelInterruptionMonitoring("speech-start");
  rejectedInterruptionPauseCount = 0;
  const runId = ++speechRunId;
  const speechPipelineStartedAt = performance.now();
  speaking = true;
  let totalTtsSynthesisMs = 0;
  let totalTtsPlaybackMs = 0;
  let queuedChunks = 0;
  const queue = createPipelinedSpeechQueue({
    isCancelled: () => speechRunId !== runId || panicStopActive,
    synthesize: (text, index) => synthesizeSpeechChunk(text, runId, index === 0),
    play: async ({ prepared, index }) => {
      if (!prepared) {
        return;
      }
      totalTtsSynthesisMs += optionalTiming(prepared.elapsedMs) || 0;
      const playbackStartedAt = performance.now();
      await playPreparedSpeechChunk(
        prepared,
        runId,
        latencyTrace,
        index === 0
      );
      totalTtsPlaybackMs += Math.round(performance.now() - playbackStartedAt);
      if (latencyTrace) {
        latencyTrace.ttsSynthesisMs = totalTtsSynthesisMs;
        latencyTrace.ttsPlaybackMs = totalTtsPlaybackMs;
        latencyTrace.ttsFullMs = Math.round(
          performance.now() - speechPipelineStartedAt
        );
      }
    }
  });
  activeSpeechQueue = queue;
  let finalized = false;

  async function finalizeSpeech(reason) {
    if (finalized) {
      return;
    }
    finalized = true;
    if (activeSpeechQueue === queue) {
      activeSpeechQueue = null;
    }
    if (speechRunId === runId) {
      speaking = false;
      await cancelInterruptionMonitoring(reason);
    }
    activeSpeechPlayback.clearRun(runId);
    logVoice(reason, `run=${runId}; chunks=${queuedChunks}`);
  }

  return {
    push(chunk) {
      if (speechRunId === runId && !panicStopActive) {
        queuedChunks += 1;
        queue.push(chunk);
      }
    },
    async finish() {
      try {
        await queue.close();
      } finally {
        await finalizeSpeech("speech_finished");
      }
    },
    async cancel() {
      if (speechRunId === runId) {
        await cancelSpeech("speech-session-cancel");
      } else {
        await queue.cancel();
      }
      await finalizeSpeech("speech_cancelled");
    },
    get runId() {
      return runId;
    }
  };
}

async function synthesizeSpeechChunk(text, runId, firstChunk) {
  const ttsStartedAt = performance.now();
  logVoice("kokoro_tts_start", `run=${runId}; first=${firstChunk}`);
  try {
    const response = await call("kokoro_tts_wav", {
      text,
      synthesisId: runId
    });
    if (!speechRunIsCurrent(runId, speechRunId, panicStopActive)) {
      return null;
    }
    return {
      bytes: new Uint8Array(response.wavBytes),
      elapsedMs: response.elapsedMs,
      ttsStartedAt,
      voice: response.voice
    };
  } catch (error) {
    if (!speechRunIsCurrent(runId, speechRunId, panicStopActive)) {
      logVoice("kokoro_tts_cancelled", `run=${runId}`);
      return null;
    }
    logVoice("kokoro_tts_error", String(error));
    elements.voiceStatus.textContent = "Speech generation failed. Check diagnostics.";
    return null;
  }
}

function playPreparedSpeechChunk(prepared, runId, latencyTrace, firstChunk) {
  return new Promise((resolve) => {
    let resolved = false;
    let playbackLease = null;
    const resolveOnce = (elapsedMs = 0) => {
      if (resolved) {
        return;
      }
      resolved = true;
      if (playbackLease) {
        activeSpeechPlayback.clear(playbackLease);
      }
      resolve(optionalTiming(elapsedMs) || 0);
    };
    const cancelChunk = () => resolveOnce();
    playbackLease = activeSpeechPlayback.claim(runId, cancelChunk);
    if (speechRunId !== runId) {
      resolveOnce();
      return;
    }
    let speechMarkedPlaying = false;
    let playbackCompleted = false;
    const markSpeechPlaying = (method) => {
      if (speechMarkedPlaying || speechRunId !== runId) {
        return;
      }
      speechMarkedPlaying = true;
      logVoice(
        "speech_started",
        `run=${runId}; method=${method}; voice=${prepared.voice}; tts_ms=${prepared.elapsedMs}`
      );
      if (latencyTrace && latencyTrace.ttsFirstAudioMs === null) {
        latencyTrace.ttsFirstAudioMs = Math.round(
          performance.now() - prepared.ttsStartedAt
        );
        latencyTrace.timeToFirstSpokenWordMs = Math.round(
          performance.now() - latencyTrace.turnStartedAt
        );
      }
      if (firstChunk) {
        monitorSpeechInterruption(runId);
      }
    };
    playNativeSpeech(prepared.bytes, runId, firstChunk, markSpeechPlaying)
      .catch((nativeError) => {
        if (!speechRunIsCurrent(runId, speechRunId, panicStopActive)) {
          logVoice("speech_native_playback_cancelled", `run=${runId}`);
          return null;
        }
        logVoice("speech_native_playback_error", `run=${runId}; ${String(nativeError)}`);
        return playWavBytes(prepared.bytes, {
          clearActiveHandle: (handle) => {
            if (activeAudio === handle) {
              activeAudio = null;
            }
          },
          onDiagnostic: (event, message) => {
            logVoice(event, `run=${runId}; ${message}`);
          },
          isCancelled: () =>
            !speechRunIsCurrent(runId, speechRunId, panicStopActive),
          onPlaying: markSpeechPlaying,
          setActiveHandle: (handle) => {
            activeAudio = handle;
          }
        });
      })
      .then((method) => {
        if (
          speechRunId === runId &&
          method &&
          method !== "cancelled"
        ) {
          playbackCompleted = true;
        }
        if (!speechMarkedPlaying && speechRunId === runId) {
          logVoice(
            "speech_playback_onset_missing",
            `run=${runId}; method=${method}`
          );
        }
      })
      .catch((error) => {
        if (!speechRunIsCurrent(runId, speechRunId, panicStopActive)) {
          logVoice("speech_fallback_playback_cancelled", `run=${runId}`);
          return;
        }
        logVoice("speech_playback_error", `run=${runId}; ${String(error)}`);
        elements.voiceStatus.textContent =
          "Speech output failed. Check the Windows audio output device and app volume.";
      })
      .finally(() => {
        if (speechRunId === runId && speechMarkedPlaying && playbackCompleted) {
          logVoice("speech_playback_finished", `run=${runId}`);
        }
        resolveOnce(prepared.elapsedMs);
      });
  });
}

async function playNativeSpeech(bytes, runId, firstChunk, markSpeechPlaying) {
  if (!invoke) {
    throw new Error("native playback is unavailable");
  }
  const onset = { runId, markSpeechPlaying };
  activeNativePlaybackOnset = onset;
  try {
    await call(
      "play_tts_wav",
      nativeSpeechPlaybackArguments(bytes, runId, firstChunk)
    );
    return "native_cpal";
  } finally {
    if (activeNativePlaybackOnset === onset) {
      activeNativePlaybackOnset = null;
    }
  }
}

function handlePlaybackOnset(event) {
  const payload = event?.payload ?? event;
  const playbackId = Number(payload?.playbackId ?? payload?.playback_id);
  const onset = activeNativePlaybackOnset;
  if (!onset || playbackId !== onset.runId || playbackId !== speechRunId) {
    if (playbackId > 0) {
      logVoice("speech_native_stale_onset", `run=${playbackId}`);
    }
    return;
  }
  activeNativePlaybackOnset = null;
  onset.markSpeechPlaying("native_cpal");
  logAudioRoute(
    "audio_output_device",
    payload?.outputDevice ?? payload?.output_device
  );
  logVoice(
    "speech_native_onset",
    `run=${playbackId}; preroll_ms=${optionalTiming(payload?.prerollMs ?? payload?.preroll_ms) ?? "unknown"}`
  );
}

async function initializePlaybackOnsetListener() {
  if (!listenTauriEvent) {
    logVoice("speech_native_onset_event_unavailable");
    return;
  }
  try {
    await listenTauriEvent(playbackOnsetEvent, handlePlaybackOnset);
    logVoice("speech_native_onset_event_ready");
  } catch (error) {
    logVoice("speech_native_onset_event_error", String(error));
  }
}

async function resumePlaybackAfterRejectedInterruption(runId, requestId, reason) {
  const outcome = await interruptionPause.resume(runId, requestId);
  if (!outcome.matched) {
    return true;
  }
  if (outcome.paused) {
    rejectedInterruptionPauseCount += 1;
  }
  logVoice(
    "speech_interruption_playback_resumed",
    `run=${runId}; request=${requestId}; method=${outcome.method}; paused=${outcome.paused}; resumed=${outcome.resumed}; reason=${reason}; rejected_pauses=${rejectedInterruptionPauseCount}`
  );
  if (!interruptionCandidatePauseAllowed(rejectedInterruptionPauseCount)) {
    logVoice(
      "speech_interruption_pause_suppressed",
      `run=${runId}; rejected_pauses=${rejectedInterruptionPauseCount}; aec=false`
    );
  }
  if (interruptionResumeRequiresCancellation(outcome)) {
    logVoice(
      "speech_interruption_resume_error",
      `run=${runId}; request=${requestId}; method=${outcome.method}; reason=${reason}; terminal=true`
    );
    elements.voiceStatus.textContent =
      "Speech playback could not resume. Iris stopped that reply and returned to listening.";
    await cancelSpeech("interruption-resume-failed");
    restartListeningIfReady(100);
    return false;
  }
  return true;
}

async function handleInterruptionOnset(event) {
  const signal = event?.payload ?? event;
  if (
    !interruptionSignalIsCurrent(signal, {
      activeRunId: speechRunId,
      activeRequestId: activeInterruptionRequestId,
      speaking
    })
  ) {
    logVoice(
      "speech_interruption_stale_onset",
      `run=${signal?.runId ?? signal?.run_id ?? "unknown"}; request=${signal?.requestId ?? signal?.request_id ?? "unknown"}`
    );
    return;
  }

  const runId = Number(signal.runId ?? signal.run_id);
  const requestId = Number(signal.requestId ?? signal.request_id);
  if (!interruptionCandidatePauseAllowed(rejectedInterruptionPauseCount)) {
    logVoice(
      "speech_interruption_vad_candidate_suppressed",
      `run=${runId}; request=${requestId}; rejected_pauses=${rejectedInterruptionPauseCount}; aec=false`
    );
    return;
  }
  const fallbackHandle = activeAudio;
  const playbackMethod = fallbackHandle?.method || "native_cpal";
  const eventReceivedAt = performance.now();
  const captureToVadMs = optionalTiming(
    signal.captureElapsedMs ?? signal.capture_elapsed_ms
  );
  logVoice(
    "speech_interruption_vad_candidate",
    `run=${runId}; request=${requestId}; method=${playbackMethod}; capture_to_vad_ms=${captureToVadMs ?? "unknown"}; aec=false`
  );
  const paused = await interruptionPause.begin({
    runId,
    requestId,
    method: playbackMethod,
    pause: () => {
      if (fallbackHandle) {
        if (activeAudio !== fallbackHandle || speechRunId !== runId) {
          return false;
        }
        return fallbackHandle.pauseForInterruption?.() ?? false;
      }
      return setNativePlaybackPaused(true, runId, requestId);
    },
    resume: () => {
      if (fallbackHandle) {
        if (activeAudio !== fallbackHandle || speechRunId !== runId) {
          return false;
        }
        return fallbackHandle.resumeAfterInterruption?.() ?? false;
      }
      return setNativePlaybackPaused(false, runId, requestId);
    }
  });
  const vadToPauseMs = Math.round(performance.now() - eventReceivedAt);
  if (
    !interruptionSignalIsCurrent(signal, {
      activeRunId: speechRunId,
      activeRequestId: activeInterruptionRequestId,
      speaking
    })
  ) {
    await interruptionPause.resume(runId, requestId);
    return;
  }
  logVoice(
    "speech_interruption_vad_pause",
    `run=${runId}; request=${requestId}; method=${playbackMethod}; capture_to_vad_ms=${captureToVadMs ?? "unknown"}; vad_to_pause_ms=${vadToPauseMs}; paused=${paused}`
  );
}

async function initializeInterruptionOnsetListener() {
  if (!listenTauriEvent) {
    logVoice("speech_interruption_event_unavailable");
    return;
  }
  try {
    await listenTauriEvent(interruptionOnsetEvent, handleInterruptionOnset);
    logVoice("speech_interruption_event_ready");
  } catch (error) {
    logVoice("speech_interruption_event_error", String(error));
  }
}

function appendModelStreamText(stream, text) {
  const chunk = String(text || "");
  if (
    !chunk ||
    activeModelStream !== stream ||
    stream.cancelRequested
  ) {
    return;
  }
  if (stream.text.length === 0) {
    stream.latencyTrace.llmFirstTokenMs = Math.round(
      performance.now() - stream.modelStartedAt
    );
    logVoice(
      "model_stream_first_token",
      `request=${stream.requestId}; elapsed_ms=${stream.latencyTrace.llmFirstTokenMs}`
    );
  }
  stream.text += chunk;
  elements.hudOutput.textContent = `${stream.text}▍`;
  if (!stream.speechSession) {
    return;
  }
  const drained = drainCompletedSpeech(stream.speechRemainder + chunk);
  stream.speechRemainder = drained.remainder;
  for (const speechChunk of drained.chunks) {
    stream.speechSession.push(speechChunk);
  }
}

function handleModelChunk(event) {
  const payload = event?.payload ?? event;
  const requestId = Number(payload?.requestId ?? payload?.request_id);
  const stream = activeModelStream;
  if (!stream || requestId !== stream.requestId) {
    if (requestId > 0) {
      logVoice("model_stream_stale_chunk", `request=${requestId}`);
    }
    return;
  }
  appendModelStreamText(stream, payload?.text);
}

async function initializeModelStreamListener() {
  if (!listenTauriEvent) {
    logVoice("model_stream_event_unavailable");
    return;
  }
  try {
    await listenTauriEvent(modelChunkEvent, handleModelChunk);
    logVoice("model_stream_event_ready");
  } catch (error) {
    logVoice("model_stream_event_error", String(error));
  }
}

async function monitorSpeechInterruption(runId) {
  if (interruptionListening || !invoke) {
    return;
  }

  const monitorGeneration = ++interruptionMonitorGeneration;
  let completedAttempts = 0;
  interruptionListening = true;
  try {
    while (
      speaking &&
      speechRunId === runId &&
      monitorGeneration === interruptionMonitorGeneration &&
      interruptionCaptureAttemptAllowed(completedAttempts)
    ) {
      completedAttempts += 1;
      const requestId = ++interruptionRequestSequence;
      activeInterruptionRequestId = requestId;
      activeInterruptionCaptureStartedAt = performance.now();
      logVoice("speech_interruption_listen_start", `run=${runId}; request=${requestId}`);
      const result = await call("native_asr_listen_interrupt", { runId, requestId });
      const signal = { runId, requestId };
      if (
        monitorGeneration !== interruptionMonitorGeneration ||
        !interruptionSignalIsCurrent(signal, {
          activeRunId: speechRunId,
          activeRequestId: activeInterruptionRequestId,
          speaking
        })
      ) {
        logVoice("speech_interruption_stale_result", `run=${runId}; request=${requestId}`);
        return;
      }
      const transcript = String(result.text || "").trim();
      logAudioRoute(
        "audio_input_device",
        result.inputDevice ?? result.input_device
      );
      const captureElapsedMs = result.captureElapsedMs ?? result.capture_elapsed_ms;
      const sttElapsedMs = result.sttElapsedMs ?? result.stt_elapsed_ms;
      const resolutionMs = Math.round(performance.now() - activeInterruptionCaptureStartedAt);
      logVoice(
        "speech_interruption_result",
        `${result.elapsed_ms}ms; capture_ms=${captureElapsedMs ?? "unknown"}; stt_ms=${sttElapsedMs ?? "unknown"}; ${transcript}`
      );
      if (!isUsableTranscript(transcript)) {
        const playbackHealthy = await resumePlaybackAfterRejectedInterruption(
          runId,
          requestId,
          "no-usable-transcript"
        );
        if (!playbackHealthy) {
          return;
        }
        logVoice(
          "speech_interruption_resolved",
          `run=${runId}; request=${requestId}; resolution_ms=${resolutionMs}; action=ignore`
        );
        await new Promise((resolve) =>
          window.setTimeout(
            resolve,
            interruptionRetryDelayMs(completedAttempts, rejectedInterruptionPauseCount)
          )
        );
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
        logVoice(
          "speech_interruption_detected",
          `${transcript}; resolution_ms=${resolutionMs}; request=${requestId}`
        );
        await cancelSpeech("confirmed-interruption");
        wakeCommandArmed = false;
        wakeCommandMissStreak = 0;
        voiceLoop = true;
        pendingInterruptionPrompt = String(decision.prompt || "").trim();
        elements.hudOutput.textContent = "Stopped.";
        elements.voiceStatus.textContent = pendingInterruptionPrompt
          ? `Interrupted. Continuing with: ${pendingInterruptionPrompt}`
          : "Interrupted. Listening.";
        restartListeningIfReady(250);
        return;
      }
      const playbackHealthy = await resumePlaybackAfterRejectedInterruption(
        runId,
        requestId,
        "decision-ignore"
      );
      if (!playbackHealthy) {
        return;
      }
      logVoice(
        "speech_interruption_resolved",
        `run=${runId}; request=${requestId}; resolution_ms=${resolutionMs}; action=${decision.action}`
      );
      await new Promise((resolve) =>
        window.setTimeout(
          resolve,
          interruptionRetryDelayMs(completedAttempts, rejectedInterruptionPauseCount)
        )
      );
    }
    if (
      speaking &&
      speechRunId === runId &&
      monitorGeneration === interruptionMonitorGeneration &&
      !interruptionCaptureAttemptAllowed(completedAttempts)
    ) {
      logVoice(
        "speech_interruption_monitor_bounded",
        `run=${runId}; attempts=${completedAttempts}; rejected_pauses=${rejectedInterruptionPauseCount}`
      );
    }
  } catch (error) {
    if (monitorGeneration === interruptionMonitorGeneration) {
      await resumePlaybackAfterRejectedInterruption(
        runId,
        activeInterruptionRequestId,
        "capture-error"
      );
      logVoice("speech_interruption_error", String(error));
    }
  } finally {
    if (monitorGeneration === interruptionMonitorGeneration) {
      interruptionListening = false;
      activeInterruptionRequestId = 0;
      activeInterruptionCaptureStartedAt = 0;
    }
    if (
      monitorGeneration === interruptionMonitorGeneration &&
      !speaking &&
      speechRunId === runId
    ) {
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
  elements.voiceButton.disabled = !voiceCaptureCanStart({ runtimePreparing });
  elements.visionButton.disabled = gatedDisabled;
  elements.screenButton.disabled = gatedDisabled;
  elements.memoryButton.disabled = gatedDisabled;
  elements.memoryAddButton.disabled = gatedDisabled;
  elements.memoryAddInput.disabled = gatedDisabled;
  elements.feedbackUp.disabled = gatedDisabled;
  elements.feedbackDown.disabled = gatedDisabled;
  elements.feedbackSave.disabled = gatedDisabled;
  elements.feedbackExport.disabled = gatedDisabled;
  elements.feedbackReason.disabled = gatedDisabled;
  elements.feedbackCorrection.disabled = gatedDisabled;
}

function renderPanicStop() {
  elements.panicButton.classList.toggle("active", panicStopActive);
  elements.irisConsole.classList.toggle("panic-active", panicStopActive);
  elements.panicButton.setAttribute("aria-pressed", panicStopActive ? "true" : "false");
  elements.panicButton.setAttribute("title", panicStopActive ? "Resume Iris" : "Pause Iris");
  elements.panicButton.setAttribute("aria-label", panicStopActive ? "Resume Iris" : "Pause Iris");
  setInputsDisabled(inputBlockingWorkActive());
}

function inputBlockingWorkActive() {
  return runtimePreparing || thinking || speaking || (listening && activeListenMode === "push");
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
    clearWakeRestartTimer();
    voiceLoop = false;
    wakeCommandArmed = false;
    wakeMissStreak = 0;
    wakeCommandMissStreak = 0;
    pendingVoiceLatency = null;
    setListening(false);
    activeListenMode = "idle";
    await cancelSpeech("panic-stop");
    elements.voiceStatus.textContent = "Iris paused.";
  } else {
    stopListeningRequested = false;
    wakeMissStreak = 0;
    wakeCommandMissStreak = 0;
    elements.voiceStatus.textContent = runtimePreparing
      ? RUNTIME_PREPARING_STATUS
      : "Wake word armed. Say Iris.";
    restartListeningIfReady(250);
  }
  elements.hudOutput.textContent = !panicStopActive && runtimePreparing
    ? RUNTIME_PREPARING_STATUS
    : panicStatusText(panicStopActive);
  logVoice(panicStopActive ? "panic_stop_active" : "panic_stop_cleared");
  renderPanicStop();
}

elements.approvalAllow.addEventListener("click", () => hideAgenticApproval(true));
elements.approvalDeny.addEventListener("click", () => hideAgenticApproval(false));
elements.browserPreviewClose.addEventListener("click", () => {
  void hideBrowserPreview();
});
elements.feedbackUp.addEventListener("click", () => setFeedbackRating("up"));
elements.feedbackDown.addEventListener("click", () => setFeedbackRating("down"));
elements.feedbackSave.addEventListener("click", () => {
  void saveSelectedFeedback();
});
elements.feedbackExport.addEventListener("click", () => {
  void exportFeedbackPairs();
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
  setInputsDisabled(inputBlockingWorkActive());
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
  clearWakeRestartTimer();
  if (!voiceCaptureCanStart({
    runtimePreparing,
    panicStopped: panicStopActive,
    enabled: voiceLoop || wakeWord,
    thinking,
    speaking,
    listening,
    interruptionListening,
    stopRequested: stopListeningRequested
  })) {
    return;
  }

  wakeRestartTimer = window.setTimeout(() => {
    wakeRestartTimer = null;
    if (!voiceCaptureCanStart({
      runtimePreparing,
      panicStopped: panicStopActive,
      enabled: voiceLoop || wakeWord,
      thinking,
      speaking,
      listening,
      interruptionListening,
      stopRequested: stopListeningRequested
    })) {
      return;
    }
    if (pendingInterruptionPrompt) {
      const prompt = pendingInterruptionPrompt;
      pendingInterruptionPrompt = "";
      void submitMessage(prompt, "interruption-followup");
      return;
    }
    const mode = nextVoiceListenMode({ wakeCommandArmed, wakeWord, voiceLoop });
    if (mode) {
      listenOnce(mode);
    }
  }, delayMs);
}

function clearWakeRestartTimer() {
  if (wakeRestartTimer !== null) {
    window.clearTimeout(wakeRestartTimer);
    wakeRestartTimer = null;
  }
}

async function listenOnce(mode) {
  if (runtimePreparing) {
    elements.hudOutput.textContent = RUNTIME_PREPARING_STATUS;
    return;
  }
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
    logAudioRoute(
      "audio_input_device",
      result.inputDevice ?? result.input_device
    );
    const captureElapsedMs = result.captureElapsedMs ?? result.capture_elapsed_ms;
    const sttElapsedMs = result.sttElapsedMs ?? result.stt_elapsed_ms;
    logVoice(
      "native_asr_result",
      `${result.elapsed_ms}ms; capture_ms=${captureElapsedMs ?? "unknown"}; stt_ms=${sttElapsedMs ?? "unknown"}; ${transcript}`
    );
    pendingVoiceLatency = {
      captureElapsedMs,
      sttElapsedMs
    };
    if (!isUsableTranscript(transcript)) {
      pendingVoiceLatency = null;
      elements.voiceStatus.textContent = noSpeechStatusForMode(mode);
      if (mode === "wake") {
        wakeMissStreak += 1;
      } else if (mode === "command" && wakeCommandArmed) {
        wakeCommandMissStreak += 1;
        if (shouldDisarmWakeFollowupAfterMisses(wakeCommandMissStreak)) {
          wakeCommandArmed = false;
          wakeCommandMissStreak = 0;
          elements.voiceStatus.textContent = "Wake follow-up timed out. Say Iris.";
          logVoice("wake_followup_timeout");
        }
      }
      restartDelayMs = wakeRestartDelayMs(mode, transcript, "ignore", wakeMissStreak);
      return;
    }
    const decision = handleVoiceTranscript(transcript, mode);
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
    if (generation === listenGeneration) {
      setListening(false);
    }
    if (generation === listenGeneration && mode !== "push") {
      restartListeningIfReady(restartDelayMs);
    }
  }
}

function handleVoiceTranscript(transcript, mode = activeListenMode) {
  const decision = classifyVoiceTranscript(
    transcript,
    voiceTranscriptStateForMode(mode, {
      voiceLoop,
      wakeWord,
      wakeCommandArmed,
      interruptionOnly: false
    })
  );
  elements.voiceStatus.textContent = decision.status;
  logVoice("voice_decision", `${decision.action}:${decision.source}:${decision.prompt}`);

  if (decision.action === "interrupt") {
    pendingVoiceLatency = null;
    cancelSpeech();
    wakeCommandArmed = false;
    wakeCommandMissStreak = 0;
    wakeMissStreak = 0;
    voiceLoop = false;
    elements.hudOutput.textContent = "Stopped.";
    restartListeningIfReady(250);
    return decision;
  }

  if (decision.action === "submit") {
    wakeCommandArmed = false;
    wakeCommandMissStreak = 0;
    wakeMissStreak = 0;
    voiceLoop = shouldContinueVoiceSession(decision);
    submitMessage(decision.prompt, decision.source);
    return decision;
  }

  if (decision.action === "arm-wake-followup") {
    pendingVoiceLatency = null;
    wakeCommandArmed = true;
    wakeCommandMissStreak = 0;
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
    wakeCommandMissStreak = 0;
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
  if (runtimePreparing) {
    elements.hudOutput.textContent = RUNTIME_PREPARING_STATUS;
    return;
  }
  if (panicStopActive) {
    elements.hudOutput.textContent = panicStatusText(true);
    return;
  }
  const action = voiceButtonAction({ listening, activeListenMode });
  if (action === "stop-push") {
    stopListeningRequested = true;
    void cancelActiveAsr();
    return;
  }
  stopListeningRequested = false;
  if (action === "switch-to-push") {
    void switchToPushToTalk();
    return;
  }
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
    logVoice("camera_snapshot_error", String(error));
    elements.hudOutput.textContent = cameraErrorMessage(error);
    restartListeningIfReady();
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
  interruptionMonitorGeneration += 1;
  activeInterruptionRequestId = 0;
  activeInterruptionCaptureStartedAt = 0;
  interruptionPause.clear();
  interruptionListening = false;
  clearWakeRestartTimer();
  setListening(false);
  activeListenMode = "idle";
  if (!invoke) {
    return;
  }
  try {
    await call("cancel_native_asr");
  } catch (error) {
    logVoice("native_asr_cancel_error", String(error));
  }
}

async function switchToPushToTalk() {
  stopListeningRequested = true;
  await cancelActiveAsr();
  await new Promise((resolve) => window.setTimeout(resolve, 80));
  stopListeningRequested = false;
  listenOnce("push");
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
  await cancelActiveAsr();
  wakeCommandArmed = false;
  wakeCommandMissStreak = 0;
  voiceLoop = false;
  const snapshot = await captureCameraSnapshot();
  elements.hudInput.value = "";
  resizeComposerInput();
  const latencyTrace = new VoiceLatencyTrace();
  await submitVisualProbeMessage(snapshot, prompt, latencyTrace, {
    source: "camera",
    userPrefix: "[camera]",
    tools: ["camera"],
    statusText: "Camera snapshot captured.\n\nThinking locally...",
    startEvent: "camera_probe_start",
    endEvent: "camera_probe_complete",
    errorEvent: "camera_probe_error",
    submitEndSource: "camera-probe"
  });
}

async function captureCameraSnapshot() {
  if (!navigator.mediaDevices?.getUserMedia) {
    throw new Error("Camera input is unavailable in this Iris window.");
  }

  cameraCaptureInProgress = true;
  elements.visionButton.disabled = true;
  elements.hudOutput.textContent = "Camera starting.";
  const videoConstraints = {
    width: { ideal: cameraSnapshotWidth, max: cameraSnapshotWidth },
    height: { ideal: cameraSnapshotHeight, max: cameraSnapshotHeight },
    frameRate: { ideal: 5, max: 10 }
  };
  const devices = await enumerateCameraDevices();
  const capturePlan = buildCameraCapturePlan(devices, videoConstraints);
  const attempts = [];
  try {
    for (const attempt of capturePlan) {
      let stream = null;
      try {
        elements.hudOutput.textContent =
          attempt.attemptId === "default"
            ? "Camera starting."
            : `Trying ${attempt.label}.`;
        stream = await getUserMediaWithTimeout(attempt.constraints, cameraPermissionTimeoutMs);
        const snapshot = await snapshotFromStream(stream);
        await saveCameraSnapshotDiagnostic(snapshot, attempt, attempts.length + 1);
        return snapshot;
      } catch (error) {
        attempts.push(cameraAttemptDiagnostic(attempt, error));
        if (String(error?.name || "") === "CameraPermissionPromptTimeoutError") {
          await saveCameraCaptureErrorDiagnostic(error.message, attempts);
          throw error;
        }
      } finally {
        if (stream) {
          for (const track of stream.getTracks()) {
            track.stop();
          }
        }
      }
    }

    const error =
      capturePlan.length > 1
        ? createCameraUnavailableError()
        : cameraErrorFromAttemptDiagnostic(attempts[0]);
    await saveCameraCaptureErrorDiagnostic(error.message, attempts);
    throw error;
  } finally {
    cameraCaptureInProgress = false;
    elements.visionButton.disabled = false;
  }
}

function getUserMediaWithTimeout(constraints, timeoutMs) {
  let timedOut = false;
  return new Promise((resolve, reject) => {
    const timeout = window.setTimeout(() => {
      timedOut = true;
      reject(createCameraPermissionPromptTimeoutError());
    }, timeoutMs);
    navigator.mediaDevices.getUserMedia(constraints).then(
      (stream) => {
        window.clearTimeout(timeout);
        if (timedOut) {
          for (const track of stream.getTracks()) {
            track.stop();
          }
          return;
        }
        resolve(stream);
      },
      (error) => {
        window.clearTimeout(timeout);
        reject(error);
      }
    );
  });
}

function cameraErrorFromAttemptDiagnostic(attempt) {
  const error = new Error(attempt?.errorMessage || "Camera snapshot failed.");
  error.name = attempt?.errorName || "Error";
  return error;
}

async function enumerateCameraDevices() {
  if (!navigator.mediaDevices?.enumerateDevices) {
    return [];
  }

  try {
    return await navigator.mediaDevices.enumerateDevices();
  } catch (error) {
    logVoice("camera_enumerate_error", String(error));
    return [];
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
    width,
    height,
    previewUrl: createTrustedAttachmentObjectUrl(blob),
    kindLabel: "Camera"
  };
}

async function saveCameraSnapshotDiagnostic(snapshot, selectedAttempt, attemptCount) {
  try {
    const diagnostic = await call("save_camera_snapshot_diagnostic", {
      imageBytes: snapshot.bytes,
      width: snapshot.width,
      height: snapshot.height,
      selectedDeviceLabel: selectedAttempt?.label || null,
      attemptCount
    });
    const imagePath = diagnostic.imagePath || diagnostic.image_path || "";
    logVoice(
      "camera_snapshot_diagnostic",
      `bytes=${snapshot.bytes.length}; width=${snapshot.width}; height=${snapshot.height}; device=${selectedAttempt?.label || "unknown"}; attempts=${attemptCount}; path=${imagePath}`
    );
  } catch (error) {
    logVoice("camera_snapshot_diagnostic_error", String(error));
  }
}

async function saveCameraCaptureErrorDiagnostic(message, attempts) {
  try {
    const diagnostic = await call("save_camera_capture_error_diagnostic", {
      message,
      attempts
    });
    const jsonPath = diagnostic.jsonPath || diagnostic.json_path || "";
    logVoice("camera_capture_error_diagnostic", `attempts=${attempts.length}; path=${jsonPath}`);
  } catch (error) {
    logVoice("camera_capture_error_diagnostic_error", String(error));
  }
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
  return responseHeightLimitForViewport(window.innerHeight);
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
void initializeInterruptionOnsetListener();
void initializePlaybackOnsetListener();
void initializeModelStreamListener();
refreshDashboard();
warmRuntimeBeforeListening();
