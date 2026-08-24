import assert from "node:assert/strict";
import test from "node:test";

import { formatHermesMode, parseHermesControlCommand } from "./hermes-mode.js";

test("Hermes mode commands are explicit", () => {
  assert.deepEqual(parseHermesControlCommand("hermes mode off"), {
    action: "set_mode",
    mode: "off"
  });
  assert.deepEqual(parseHermesControlCommand("hermes mode safe"), {
    action: "set_mode",
    mode: "safe"
  });
  assert.deepEqual(parseHermesControlCommand("hermes mode agentic"), {
    action: "agentic_workspace_required"
  });
});

test("Agentic session command requires a workspace path", () => {
  assert.deepEqual(parseHermesControlCommand("hermes agentic C:\\Projects\\IRIS"), {
    action: "create_agentic_session",
    workspacePath: "C:\\Projects\\IRIS"
  });
  assert.deepEqual(parseHermesControlCommand("hermes session end"), {
    action: "end_agentic_session"
  });
});

test("Hermes mode formatter exposes active session boundary", () => {
  const formatted = formatHermesMode({
    mode: "agentic",
    agenticSession: {
      sessionId: "session-1",
      workspacePath: "C:\\Projects\\IRIS",
      expiresAtMs: 1_800_000,
      workspaceBoundary: "selected_workspace_no_shell_process"
    }
  });
  assert.match(formatted, /Hermes mode: agentic/);
  assert.match(formatted, /Session: session-1/);
  assert.match(formatted, /selected_workspace_no_shell_process/);
});
