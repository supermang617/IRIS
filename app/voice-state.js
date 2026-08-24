export const VOICE_SETUP_NEEDED_STATUS =
  "Voice setup needed: repair or upgrade Iris, and ensure Python 3.13 is installed";
export const MODEL_WARMUP_FAILED_STATUS =
  "Local model warm-up failed. Restart Ollama or run Iris Setup Wizard.";
export const MODEL_AND_VOICE_WARMUP_FAILED_STATUS =
  "Local model and voice warm-up failed. Run Iris Setup Wizard before continuing.";
export const RUNTIME_PREPARING_STATUS =
  "Iris is still preparing the local model and voice runtime.";

export function classifyVoiceTranscript(transcript, state) {
  const voiceState = state || {};
  const normalized = normalizeTranscript(transcript);
  if (!normalized) {
    return { action: "ignore", prompt: "", source: "voice", status: "No speech transcript captured." };
  }
  if (isNoiseTranscript(normalized)) {
    return { action: "ignore", prompt: "", source: "voice", status: "No speech transcript captured." };
  }

  if (voiceState.sleeping) {
    if (isWakeFromSleepCommand(normalized)) {
      return { action: "wake-from-sleep", prompt: "", source: "wake-word", status: "Awake." };
    }
    return { action: "sleep-ignore", prompt: "", source: "sleep", status: "Sleeping. Say Iris wake up." };
  }

  if (isSleepCommand(normalized)) {
    return { action: "sleep", prompt: "", source: "sleep", status: "Sleeping. Say Iris wake up." };
  }

  if (voiceState.interruptionOnly) {
    const interruption = interruptionMatch(normalized);
    if (interruption) {
      return {
        action: "interrupt",
        prompt: normalized.slice(interruption.end).trim(),
        source: "interruption",
        status: "Interrupted."
      };
    }
    const wakeMatch = findStrongWakeMatch(normalized);
    if (wakeMatch) {
      const prompt = normalized.slice(wakeMatch.length).trim();
      return { action: "interrupt", prompt, source: "interruption", status: "Interrupted." };
    }

    return { action: "ignore", prompt: "", source: "interruption", status: "Listening for interruption." };
  }

  if (isInterruption(normalized)) {
    return { action: "interrupt", prompt: "", source: "interruption", status: "Interrupted." };
  }

  if (voiceState.wakeCommandArmed) {
    return { action: "submit", prompt: normalized, source: "wake-followup", status: `Heard: ${normalized}` };
  }

  if (voiceState.voiceLoop) {
    return { action: "submit", prompt: normalized, source: "voice-loop", status: `Heard: ${normalized}` };
  }

  if (!voiceState.wakeWord) {
    return { action: "submit", prompt: normalized, source: "voice", status: `Heard: ${normalized}` };
  }

  const wakeMatch = findStrongWakeMatch(normalized);
  if (wakeMatch) {
    const prompt = normalized.slice(wakeMatch.length).trim();
    if (prompt && !isWakeOnlyPrompt(prompt)) {
      return { action: "submit", prompt, source: "wake-word", status: `Heard: ${normalized}` };
    }

    return {
      action: "arm-wake-followup",
      prompt: "",
      source: "wake-word",
      status: "Wake word heard. Listening for your request."
    };
  }

  if (isShortStandaloneWeakWake(normalized)) {
    return {
      action: "arm-wake-followup",
      prompt: "",
      source: "wake-word",
      status: "Wake word heard. Listening for your request."
    };
  }

  return { action: "wait-for-wake", prompt: "", source: "wake-word", status: "Waiting for wake word: Iris." };
}

export function voiceTranscriptStateForMode(mode, state) {
  const normalizedMode = String(mode || "").trim().toLowerCase();
  if (normalizedMode === "push") {
    return {
      ...state,
      wakeWord: false,
      wakeCommandArmed: false
    };
  }
  return state;
}

export function classifyAsrError(error) {
  const message = String(error || "").trim();
  const normalized = message.toLowerCase();
  if (normalized.includes("no default microphone input device found")) {
    return {
      severity: "error",
      event: "native_asr_error",
      status: "No microphone is available. Connect one and choose it as the Windows default input device."
    };
  }
  if (
    normalized.includes("microphone produced no audio samples") ||
    normalized === "no-speech"
  ) {
    return { severity: "nonfatal", event: "native_asr_no_input", status: "No speech transcript captured." };
  }
  if (
    normalized.includes("windows audio device handle became invalid") ||
    normalized.includes("hresult(0x80070006)") ||
    normalized.includes("the handle is invalid")
  ) {
    return {
      severity: "nonfatal",
      event: "native_asr_transient_error",
      status: "Audio capture reset. Retrying microphone."
    };
  }
  return { severity: "error", event: "native_asr_error", status: message || "Native ASR failed." };
}

export function runtimeWarmHudStatus(
  runtimeReady,
  voiceWarmReady,
  modelWarmReady = true,
  panicStopped = false
) {
  if (panicStopped) {
    return "Iris is paused.";
  }
  if (!runtimeReady) {
    return null;
  }
  if (!modelWarmReady && !voiceWarmReady) {
    return MODEL_AND_VOICE_WARMUP_FAILED_STATUS;
  }
  if (!modelWarmReady) {
    return MODEL_WARMUP_FAILED_STATUS;
  }
  return voiceWarmReady ? "Waiting for input." : VOICE_SETUP_NEEDED_STATUS;
}

export function voiceCaptureCanStart({
  runtimePreparing = false,
  panicStopped = false,
  enabled = true,
  thinking = false,
  speaking = false,
  listening = false,
  interruptionListening = false,
  stopRequested = false
} = {}) {
  return !(
    runtimePreparing ||
    panicStopped ||
    !enabled ||
    thinking ||
    speaking ||
    listening ||
    interruptionListening ||
    stopRequested
  );
}

export function wakeRestartDelayMs(mode, transcript, action, consecutiveMisses = 0) {
  if (mode !== "wake") {
    return 300;
  }
  if (action === "wait-for-wake" || action === "ignore" || !String(transcript || "").trim()) {
    return 300;
  }
  return 300;
}

export function voiceButtonAction({ listening, activeListenMode }) {
  if (listening && activeListenMode === "push") {
    return "stop-push";
  }
  if (listening) {
    return "switch-to-push";
  }
  return "start-push";
}

export function noSpeechStatusForMode(mode) {
  return mode === "wake" ? "Wake word armed. Say Iris." : "No speech transcript captured.";
}

export function shouldDisarmWakeFollowupAfterMisses(consecutiveMisses, limit = 3) {
  return Number(consecutiveMisses || 0) >= limit;
}

export function shouldDisplayVoiceTranscript(decision) {
  return decision?.action === "preview-transcript";
}

export function voiceSubmitKeepsSession(source) {
  return ["voice", "voice-loop", "wake-word", "wake-followup", "voice-session"].includes(source);
}

export function nextVoiceListenMode({ sleeping = false, wakeCommandArmed, wakeWord, voiceLoop }) {
  if (sleeping) {
    return "wake";
  }
  if (wakeCommandArmed) {
    return "command";
  }
  if (voiceLoop) {
    return "loop";
  }
  if (wakeWord) {
    return "wake";
  }
  return null;
}

export function shouldContinueVoiceSession(decision) {
  return decision?.action === "submit" && voiceSubmitKeepsSession(decision.source);
}

export function interruptionSignalIsCurrent(signal, state) {
  const signalRunId = Number(signal?.runId ?? signal?.run_id);
  const signalRequestId = Number(signal?.requestId ?? signal?.request_id);
  const activeRunId = Number(state?.activeRunId);
  const activeRequestId = Number(state?.activeRequestId);
  return (
    state?.speaking === true &&
    Number.isSafeInteger(signalRunId) &&
    Number.isSafeInteger(signalRequestId) &&
    signalRunId > 0 &&
    signalRequestId > 0 &&
    signalRunId === activeRunId &&
    signalRequestId === activeRequestId
  );
}

export function interruptionCaptureAttemptAllowed(completedAttempts, maximumAttempts = 96) {
  const attempts = Math.max(0, Number(completedAttempts) || 0);
  const maximum = Math.max(1, Number(maximumAttempts) || 96);
  return attempts < maximum;
}

export function interruptionCandidatePauseAllowed(rejectedPauses, maximumRejectedPauses = 2) {
  const rejected = Math.max(0, Number(rejectedPauses) || 0);
  const maximum = Math.max(1, Number(maximumRejectedPauses) || 2);
  return rejected < maximum;
}

export function interruptionSignalAllowsSpeculativePause(signal) {
  const aecApplied = signal?.aecApplied ?? signal?.aec_applied;
  const rawFallbackAllowed = signal?.rawFallbackAllowed ?? signal?.raw_fallback_allowed;
  return aecApplied === true || rawFallbackAllowed === true;
}

export function interruptionRetryDelayMs(completedAttempts, rejectedPauses) {
  const attempts = Math.max(0, Number(completedAttempts) || 0);
  const rejected = Math.max(0, Number(rejectedPauses) || 0);
  return Math.min(600, 100 + attempts * 50 + rejected * 100);
}

export function createInterruptionPauseCoordinator() {
  let active = null;
  const resolvedRequests = new Set();
  const maximumResolvedRequests = 128;

  const requestKey = (runId, requestId) => `${runId}:${requestId}`;
  const rememberResolved = (runId, requestId) => {
    const key = requestKey(runId, requestId);
    resolvedRequests.delete(key);
    resolvedRequests.add(key);
    while (resolvedRequests.size > maximumResolvedRequests) {
      resolvedRequests.delete(resolvedRequests.values().next().value);
    }
  };

  return {
    begin({ runId, requestId, method = "unknown", pause, resume }) {
      if (!Number.isSafeInteger(runId) || runId <= 0) {
        throw new TypeError("interruption pause run ID must be a positive integer");
      }
      if (!Number.isSafeInteger(requestId) || requestId <= 0) {
        throw new TypeError("interruption pause request ID must be a positive integer");
      }
      if (typeof pause !== "function" || typeof resume !== "function") {
        throw new TypeError("interruption pause controls must be functions");
      }

      const key = requestKey(runId, requestId);
      if (resolvedRequests.has(key)) {
        return Promise.resolve(false);
      }
      if (active?.runId === runId && active?.requestId === requestId) {
        return active.pausePromise;
      }
      if (active) {
        return Promise.resolve(false);
      }

      const attempt = {
        method: String(method || "unknown"),
        requestId,
        runId,
        resume
      };
      attempt.pausePromise = Promise.resolve().then(pause).then(Boolean);
      active = attempt;
      return attempt.pausePromise;
    },
    async resume(runId, requestId) {
      rememberResolved(runId, requestId);
      const attempt = active;
      if (attempt?.runId !== runId || attempt?.requestId !== requestId) {
        return {
          matched: false,
          method: "none",
          paused: false,
          resumed: false
        };
      }

      active = null;
      const paused = await attempt.pausePromise;
      const resumed = paused ? Boolean(await attempt.resume()) : false;
      return {
        matched: true,
        method: attempt.method,
        paused,
        resumed
      };
    },
    clear() {
      active = null;
      resolvedRequests.clear();
    }
  };
}

export function interruptionResumeRequiresCancellation(outcome) {
  return (
    outcome?.matched === true &&
    outcome?.paused === true &&
    outcome?.resumed !== true
  );
}

function isInterruption(text) {
  return interruptionMatch(text) !== null;
}

function interruptionMatch(text) {
  const match = text.match(interruptionPattern());
  return match ? { end: match[0].length } : null;
}

function isWakeOnlyPrompt(text) {
  return /^(wake\s*up|wake|wakeup|hello|hi|hey)[\s,.:;!?-]*$/i.test(text);
}

function isWakeFromSleepCommand(text) {
  const wakeMatch = findStrongWakeMatch(text);
  if (!wakeMatch) {
    return false;
  }
  const prompt = text.slice(wakeMatch.length).trim();
  return /^(?:wake\s*up|wakeup|wake\s+back\s+up)[\s,.:;!?-]*$/i.test(prompt);
}

function isSleepCommand(text) {
  return sleepCommandPattern().test(text);
}

function findStrongWakeMatch(text) {
  const match = text.match(strongWakePattern());
  return match ? { length: match[0].length } : null;
}

function isShortStandaloneWeakWake(text) {
  if (text.length > 32) {
    return false;
  }
  return (
    weakWakePattern().test(text) ||
    /^(?:hi\s+i'?m\s+)?eric\s+sway\s*up[\s,.:;!?-]*$/i.test(text) ||
    /^i\s+(?:are|hear|here)\s+a?\s*wake\s*up[\s,.:;!?-]*$/i.test(text)
  );
}

function wakeLeadInSource() {
  return "(?:(?:hey|hi|hello|okay|ok)(?:\\s+there)?[\\s,.:;!?-]+)?";
}

function strongWakeSource() {
  return "(?:iris|irish|airis|eyeris|i\\s+reese)";
}

function weakWakeSource() {
  return "(?:aires|ares|aris|eris)";
}

function strongWakePattern() {
  return new RegExp(`^${wakeLeadInSource()}${strongWakeSource()}\\b[\\s,.:;!?-]*`, "i");
}

function weakWakePattern() {
  return new RegExp(`^${wakeLeadInSource()}${weakWakeSource()}\\b[\\s,.:;!?-]*$`, "i");
}

function interruptionPattern() {
  return new RegExp(
    `^(?:${wakeLeadInSource()}(?:${strongWakeSource()}|${weakWakeSource()})[\\s,.:;!?-]+)?(?:stop|pause|quiet|cancel|interrupt)\\b[\\s,.:;!?-]*`,
    "i"
  );
}

function sleepCommandPattern() {
  return new RegExp(
    `^(?:${wakeLeadInSource()}(?:${strongWakeSource()}|${weakWakeSource()})[\\s,.:;!?-]+)?(?:sleep|go\\s+sleep|go\\s+to\\s+sleep|stop\\s+(?:and\\s+)?(?:go\\s+to\\s+)?sleep)\\b[\\s,.:;!?-]*(?:now|please|for\\s+now)?[\\s,.:;!?-]*$`,
    "i"
  );
}

function normalizeTranscript(text) {
  return String(text || "").trim().replace(/^>+\s*/, "").trim();
}

function isNoiseTranscript(text) {
  const normalized = text.trim().toLowerCase();
  const blocked = new Set([
    "[blank_audio]",
    "[music]",
    "[music playing]",
    "(music)",
    "(upbeat music)",
    "[typing]",
    "(typing)",
    "[keyboard clicking]",
    "(keyboard clicking)",
    "[silence]",
    "(silence)",
    "[inaudible]",
    "(inaudible)",
    "[no speech]",
    "(no speech)"
  ]);
  return (
    blocked.has(normalized) ||
    /^\[[^\]]+\]$/.test(normalized) ||
    /^\([^)]+\)$/.test(normalized) ||
    normalized.includes("music playing") ||
    normalized.includes("keyboard clicking") ||
    normalized.includes("inaudible")
  );
}
