import { classifyVoiceTranscript } from "./voice-state.js";

const invoke = window.__TAURI__?.core?.invoke;

const elements = {
  hudForm: document.querySelector("#hud-form"),
  hudInput: document.querySelector("#hud-input"),
  hudOutput: document.querySelector("#hud-output"),
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
const conversationHistory = [];
const maxHistoryTurns = 12;

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

async function submitMessage(text, source = "typed") {
  if (thinking || speaking) {
    return;
  }

  const turnStarted = performance.now();
  thinking = true;
  logVoice("submit_start", source);
  setInputsDisabled(true);
  elements.hudOutput.textContent = `${text}\n\nThinking locally...`;
  try {
    const history = conversationHistory.slice();
    const response = await call("submit_typed_hud", { text, history });
    elements.hudOutput.textContent = response.text;
    rememberTurn("user", text);
    rememberTurn("iris", response.text);
    logVoice(
      "turn_complete",
      `${source}; model_ms=${response.model_elapsed_ms}; total_ms=${Math.round(performance.now() - turnStarted)}`
    );
    thinking = false;
    setInputsDisabled(false);
    await speak(response.text);
  } catch (error) {
    elements.hudOutput.textContent = String(error);
    logVoice(
      "turn_error",
      `${source}; total_ms=${Math.round(performance.now() - turnStarted)}; ${String(error)}`
    );
  } finally {
    thinking = false;
    setInputsDisabled(false);
    logVoice("submit_end", source);
    restartListeningIfReady();
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

async function speak(text) {
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
        logVoice("speech_started", `run=${runId}; voice=${response.voice}; tts_ms=${response.elapsedMs}`);
        monitorSpeechInterruption(runId);
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
  elements.voiceButton.disabled = false;
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
    if (!isUsableTranscript(transcript)) {
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
    cancelSpeech();
    wakeCommandArmed = false;
    voiceLoop = true;
    elements.hudOutput.textContent = "Stopped.";
    restartListeningIfReady(250);
    return;
  }

  if (decision.action === "submit") {
    wakeCommandArmed = false;
    voiceLoop = true;
    submitMessage(decision.prompt, decision.source);
    return;
  }

  if (decision.action === "arm-wake-followup") {
    wakeCommandArmed = true;
    voiceLoop = true;
    speak("I'm listening.").finally(() => restartListeningIfReady(250));
    return;
  }

  if (decision.action === "wait-for-wake") {
    if (voiceLoop) {
      submitMessage(transcript, "voice-session");
      return;
    }
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

renderVoiceCapability();
logVoice("app_started");
refreshDashboard();
restartListeningIfReady(500);
