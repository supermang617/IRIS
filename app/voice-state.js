export function classifyVoiceTranscript(transcript, state) {
  const normalized = normalizeTranscript(transcript);
  if (!normalized) {
    return { action: "ignore", prompt: "", source: "voice", status: "No speech transcript captured." };
  }
  if (isNoiseTranscript(normalized)) {
    return { action: "ignore", prompt: "", source: "voice", status: "No speech transcript captured." };
  }

  if (state.interruptionOnly) {
    if (isInterruption(normalized) || isBareWakeWord(normalized)) {
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

function isInterruption(text) {
  return /^(iris[\s,.:;!?-]+)?(stop|pause|quiet|cancel|interrupt)\b/i.test(text);
}

function isBareWakeWord(text) {
  return /^iris[\s,.:;!?-]*$/i.test(text) || /^eric\s+sway\s*up[\s,.:;!?-]*$/i.test(text);
}

function isWakeOnlyPrompt(text) {
  return /^(wake\s*up|wake|wakeup|hello|hi|hey)[\s,.:;!?-]*$/i.test(text);
}

function findWakeMatch(text) {
  const patterns = [
    /\biris\b[\s,.:;!?-]*/i,
    /\birish\b[\s,.:;!?-]*/i,
    /\beric\s+sway\s*up\b[\s,.:;!?-]*/i,
    /\bhi\s+i'?m\s+eric\s+sway\s*up\b[\s,.:;!?-]*/i,
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
