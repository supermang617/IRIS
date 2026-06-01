export function classifyVoiceTranscript(transcript, state) {
  const normalized = String(transcript || "").trim();
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

  const wakeMatch = normalized.match(/\biris\b[\s,.:;!?-]*/i);
  if (wakeMatch) {
    const prompt = normalized.slice((wakeMatch.index || 0) + wakeMatch[0].length).trim();
    if (prompt) {
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
  return /^iris[\s,.:;!?-]*$/i.test(text);
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
    "(silence)"
  ]);
  return (
    blocked.has(normalized) ||
    normalized.includes("music playing") ||
    normalized.includes("keyboard clicking")
  );
}
