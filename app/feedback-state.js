export function createFeedbackTurn({
  source,
  userText,
  assistantText,
  modelId,
  provider,
  tools = [],
  latencyMs = null,
  now = Date.now()
}) {
  const cleanAssistant = String(assistantText || "").trim();
  if (!cleanAssistant) {
    return null;
  }
  return {
    turnId: `turn-${Math.trunc(now)}-${Math.random().toString(36).slice(2, 8)}`,
    source: String(source || "unknown").trim() || "unknown",
    userText: String(userText || ""),
    assistantText: cleanAssistant,
    modelId: String(modelId || "unknown").trim() || "unknown",
    provider: String(provider || "unknown").trim() || "unknown",
    tools: Array.isArray(tools) ? tools.map((tool) => String(tool)).filter(Boolean).slice(0, 12) : [],
    latencyMs: Number.isFinite(Number(latencyMs)) ? Math.round(Number(latencyMs)) : null
  };
}

export function buildFeedbackCapture(turn, rating, reason = "", correction = "") {
  if (!turn || !["up", "down"].includes(rating)) {
    return null;
  }
  return {
    rating,
    reason: cleanOptional(reason),
    correction: cleanOptional(correction),
    userText: turn.userText,
    assistantText: turn.assistantText,
    metadata: {
      turnId: turn.turnId,
      source: turn.source,
      modelId: turn.modelId,
      provider: turn.provider,
      tools: turn.tools,
      latencyMs: turn.latencyMs
    }
  };
}

export function formatFeedbackStatus(status) {
  if (!status || Number(status.totalEvents || 0) === 0) {
    return "No feedback saved yet.";
  }
  return [
    `Feedback saved: ${status.totalEvents}`,
    `Positive: ${status.upCount}`,
    `Negative: ${status.downCount}`,
    `Corrections: ${status.correctionCount}`,
    `Learning summary: ${status.preferenceSummary}`,
    `Dynamic feedback context: ${status.instructionActive ? "active" : "waiting for more signal"}`
  ].join("\n");
}

export function feedbackFieldsVisible(rating) {
  return rating === "down";
}

function cleanOptional(value) {
  const clean = String(value || "").trim();
  return clean ? clean : null;
}
