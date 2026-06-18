export function classifyVoiceTranscript(transcript, state) {
  const normalized = normalizeTranscript(transcript);
  if (!normalized) {
    return { action: "ignore", prompt: "", source: "voice", status: "No speech transcript captured." };
  }
  if (isNoiseTranscript(normalized)) {
    return { action: "ignore", prompt: "", source: "voice", status: "No speech transcript captured." };
  }

  if (state.interruptionOnly) {
    if (isInterruption(normalized) || isBareWakeWord(normalized) || findWakeMatch(normalized)) {
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

export function classifyAsrError(error) {
  const message = String(error || "").trim();
  const normalized = message.toLowerCase();
  if (
    normalized.includes("microphone produced no audio samples") ||
    normalized.includes("no default microphone input device found") ||
    normalized === "no-speech"
  ) {
    return { severity: "nonfatal", event: "native_asr_no_input", status: "No speech transcript captured." };
  }
  return { severity: "error", event: "native_asr_error", status: message || "Native ASR failed." };
}

export function wakeRestartDelayMs(mode, transcript, action, consecutiveMisses = 0) {
  if (mode !== "wake") {
    return 650;
  }
  const misses = Math.max(0, Number(consecutiveMisses) || 0);
  if (misses >= 6) {
    return 10000;
  }
  if (misses >= 3) {
    return 5000;
  }
  if (!String(transcript || "").trim()) {
    return 1200;
  }
  if (action === "wait-for-wake" || action === "ignore") {
    return 2500;
  }
  return 650;
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

function isInterruption(text) {
  return /^(iris[\s,.:;!?-]+)?(stop|pause|quiet|cancel|interrupt)\b/i.test(text);
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
