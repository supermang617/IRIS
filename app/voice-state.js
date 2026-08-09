export function classifyVoiceTranscript(transcript, state) {
  const normalized = normalizeTranscript(transcript);
  if (!normalized) {
    return { action: "ignore", prompt: "", source: "voice", status: "No speech transcript captured." };
  }
  if (isNoiseTranscript(normalized)) {
    return { action: "ignore", prompt: "", source: "voice", status: "No speech transcript captured." };
  }

  if (state.interruptionOnly) {
    const interruption = interruptionMatch(normalized);
    if (interruption) {
      return {
        action: "interrupt",
        prompt: normalized.slice(interruption.end).trim(),
        source: "interruption",
        status: "Interrupted."
      };
    }
    const wakeMatch = findWakeMatch(normalized);
    if (wakeMatch) {
      const prompt = wakeMatch.index === 0
        ? normalized.slice(wakeMatch.length).trim()
        : "";
      return { action: "interrupt", prompt, source: "interruption", status: "Interrupted." };
    }
    if (isBareWakeWord(normalized)) {
      return { action: "interrupt", prompt: "", source: "interruption", status: "Interrupted." };
    }

    return { action: "ignore", prompt: "", source: "interruption", status: "Listening for interruption." };
  }

  if (isInterruption(normalized)) {
    return { action: "interrupt", prompt: "", source: "interruption", status: "Interrupted." };
  }

  if (state.voiceLoop) {
    return { action: "submit", prompt: normalized, source: "voice-loop", status: `Heard: ${normalized}` };
  }

  if (!state.wakeWord) {
    return { action: "submit", prompt: normalized, source: "voice", status: `Heard: ${normalized}` };
  }

  const wakeMatch = findWakeMatch(normalized);
  if (wakeMatch) {
    const prompt = normalized.slice(wakeMatch.index + wakeMatch.length).trim();
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

  if (state.wakeCommandArmed) {
    return { action: "submit", prompt: normalized, source: "wake-followup", status: `Heard: ${normalized}` };
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
  return { severity: "error", event: "native_asr_error", status: message || "Native ASR failed." };
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

export function nextVoiceListenMode({ wakeCommandArmed, wakeWord, voiceLoop }) {
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
  return (
    decision?.action === "submit" &&
    ["voice", "voice-loop", "wake-word", "wake-followup", "voice-session"].includes(decision.source)
  );
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
  const match = text.match(
    /^(?:iris[\s,.:;!?-]+)?(?:stop|pause|quiet|cancel|interrupt)\b[\s,.:;!?-]*/i
  );
  return match ? { end: match[0].length } : null;
}

function isBareWakeWord(text) {
  return (
    /^(?:hey|hi|okay|ok)?\s*(?:iris|irish|airis|eyeris|aires|ares|aris|eris|i\s+reese)[\s,.:;!?-]*$/i.test(
      text
    ) || /^eric\s+sway\s*up[\s,.:;!?-]*$/i.test(text)
  );
}

function isWakeOnlyPrompt(text) {
  return /^(wake\s*up|wake|wakeup|hello|hi|hey)[\s,.:;!?-]*$/i.test(text);
}

function findWakeMatch(text) {
  const patterns = [
    /\b(?:hey|hi|okay|ok)\s+(?:iris|irish|airis|eyeris|aires|ares|aris|eris)\b[\s,.:;!?-]*/i,
    /\b(?:iris|irish|airis|eyeris|aires|ares|aris|eris)\b[\s,.:;!?-]*/i,
    /\bi\s+reese\b[\s,.:;!?-]*/i,
    /\beric\s+sway\s*up\b[\s,.:;!?-]*/i,
    /\bhi\s+i'?m\s+eric\s+sway\s*up\b[\s,.:;!?-]*/i,
    /\bi\s+always\b[\s,.:;!?-]*/i,
    /\bi\s+(?:are|hear|here)\s+a?\s*wake\s*up\b[\s,.:;!?-]*/i
  ];
  for (const pattern of patterns) {
    const match = text.match(pattern);
    if (match) {
      return { index: match.index || 0, length: match[0].length };
    }
  }
  return null;
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
