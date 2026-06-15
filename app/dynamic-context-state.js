export function parseDynamicContextCommand(input) {
  const clean = String(input || "").trim();
  if (/^(?:dynamic context|communication profile)(?:\s+status)?$/i.test(clean)) {
    return { action: "status" };
  }
  if (/^(?:dynamic context|communication profile)\s+reset$/i.test(clean)) {
    return { action: "reset" };
  }
  const enabled = clean.match(
    /^(?:dynamic context|communication profile)\s+(on|off)$/i
  );
  if (enabled) {
    return { action: "set_enabled", enabled: enabled[1].toLowerCase() === "on" };
  }
  return { action: "none" };
}

export function formatDynamicContextStatus(status) {
  if (!status || typeof status !== "object") {
    return "Dynamic context status is unavailable.";
  }
  const state = status.enabled ? "On" : "Off";
  const count = Number.isFinite(status.observationCount) ? status.observationCount : 0;
  const sentence = String(status.sentenceStyle || "not established");
  const vocabulary = String(status.vocabularyStyle || "not established");
  const tone = String(status.tone || "natural");
  return [
    `Dynamic context: ${state}`,
    `Recent observations: ${count}`,
    `Sentence style: ${sentence}`,
    `Vocabulary: ${vocabulary}`,
    `Tone: ${tone}`,
    "",
    "Iris stores aggregate metrics only, not the text used to calculate them."
  ].join("\n");
}
