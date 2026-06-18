const MEMORY_PROPOSAL_STAGED_TEXT = "Hermes staged a memory proposal for your approval.";
const MEMORY_PROPOSAL_NOT_STAGED_TEXT = "Hermes did not stage a memory proposal.";

export function pendingStagedMemories(staged) {
  if (!Array.isArray(staged)) {
    return [];
  }
  return staged.filter((item) => String(item.status || "").toLowerCase() === "pending");
}

export function formatStagedMemories(staged) {
  const pending = pendingStagedMemories(staged);
  if (pending.length === 0) {
    return "No pending Hermes memories.";
  }
  return pending.map((item) => `${item.id}. ${item.text}`).join("\n");
}

export function formatHermesTaskStagedSection(staged) {
  const pending = pendingStagedMemories(staged);
  if (pending.length === 0) {
    return "";
  }
  return `\n\nStaged memory:\n${formatStagedMemories(pending)}`;
}

export function hasMemoryWriteIntent(text) {
  return /\b(remember|save|store|stage|propose)\b/i.test(String(text || ""));
}

export function claimsActiveMemoryWrite(text) {
  return /\b(i|iris|hermes)\s+(have\s+|just\s+|already\s+)?(remembered|saved|stored)\b|\bi've\s+(remembered|saved|stored)\b/i.test(
    String(text || "")
  );
}

export function formatHermesMemoryTaskText(text, staged, taskText = "") {
  const clean = String(text || "").trim();
  const hasPending = pendingStagedMemories(staged).length > 0;
  if (hasPending && hasMemoryWriteIntent(taskText)) {
    return MEMORY_PROPOSAL_STAGED_TEXT;
  }
  if (!hasPending && Array.isArray(staged) && staged.length > 0) {
    return clean || MEMORY_PROPOSAL_NOT_STAGED_TEXT;
  }
  if (!hasPending && hasMemoryWriteIntent(taskText) && claimsActiveMemoryWrite(clean)) {
    return MEMORY_PROPOSAL_NOT_STAGED_TEXT;
  }
  if (!hasPending) {
    return clean;
  }
  if (claimsActiveMemoryWrite(clean)) {
    return MEMORY_PROPOSAL_STAGED_TEXT;
  }
  return clean || MEMORY_PROPOSAL_STAGED_TEXT;
}
