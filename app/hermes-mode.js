export function parseHermesControlCommand(text) {
  const clean = String(text || "").trim();
  if (/^hermes\s+status$/i.test(clean)) {
    return { action: "status" };
  }
  if (/^hermes\s+mode\s+off$/i.test(clean)) {
    return { action: "set_mode", mode: "off" };
  }
  if (/^hermes\s+mode\s+safe$/i.test(clean)) {
    return { action: "set_mode", mode: "safe" };
  }
  if (/^hermes\s+mode\s+agentic$/i.test(clean)) {
    return { action: "agentic_workspace_required" };
  }
  const agentic = clean.match(/^hermes\s+agentic\s+(.+)$/i);
  if (agentic) {
    return { action: "create_agentic_session", workspacePath: agentic[1].trim() };
  }
  if (/^hermes\s+(?:session\s+end|agentic\s+off)$/i.test(clean)) {
    return { action: "end_agentic_session" };
  }
  return { action: "none" };
}

export function formatHermesMode(snapshot) {
  const mode = String(snapshot?.mode || "unknown");
  const session = snapshot?.agenticSession;
  if (!session) {
    return `Hermes mode: ${mode}`;
  }
  return [
    `Hermes mode: ${mode}`,
    `Session: ${session.sessionId}`,
    `Workspace: ${session.workspacePath}`,
    `Expires: ${new Date(Number(session.expiresAtMs)).toLocaleTimeString()}`,
    `Workspace boundary: ${session.workspaceBoundary}`
  ].join("\n");
}
