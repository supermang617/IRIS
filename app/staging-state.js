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

export function hasMemoryWriteIntent(text) {
  return /\b(remember|save|store|stage|propose)\b/i.test(String(text || ""));
}

export function claimsActiveMemoryWrite(text) {
  return /\b(i|iris|hermes)\s+(have\s+)?(remembered|saved|stored)\b/i.test(String(text || ""));
}

export function formatHermesMemoryTaskText(text, staged, taskText = "") {
  const clean = String(text || "").trim();
  const hasPending = pendingStagedMemories(staged).length > 0;
  if (hasPending && hasMemoryWriteIntent(taskText)) {
    return "Hermes staged a memory proposal for your approval.";
  }
  if (!hasPending && Array.isArray(staged) && staged.length > 0) {
    return clean || "Hermes did not stage a memory proposal.";
  }
  if (!hasPending && !(hasMemoryWriteIntent(taskText) && claimsActiveMemoryWrite(clean))) {
    return clean;
  }
  if (claimsActiveMemoryWrite(clean)) {
    return "Hermes staged a memory proposal for your approval.";
  }
  return clean || "Hermes staged a memory proposal for your approval.";
}
