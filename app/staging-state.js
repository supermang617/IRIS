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
