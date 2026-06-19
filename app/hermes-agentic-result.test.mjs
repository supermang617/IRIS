import assert from "node:assert/strict";
import test from "node:test";

import { formatAgenticTaskResult } from "./hermes-agentic-result.js";

test("completed agentic responses show final text before tool activity", () => {
  const output = formatAgenticTaskResult({
    text: "Latest Ollama release: v0.30.10",
    events: [
      {
        type: "tool_activity",
        payload: "browser_open: completed\nhttps://github.com/ollama/ollama/releases/tag/v0.30.10"
      }
    ]
  });

  assert.match(output, /^Latest Ollama release: v0\.30\.10/);
  assert.match(output, /Tool activity:/);
  assert.match(output, /browser_open: completed/);
});

test("completed agentic responses hide stale in progress tool lines", () => {
  const output = formatAgenticTaskResult({
    text: "Latest Ollama release: v0.30.10",
    events: [
      {
        type: "tool_activity",
        payload: "browser_open: in_progress\nhttps://github.com/ollama/ollama/releases/latest"
      }
    ]
  });

  assert.equal(output, "Latest Ollama release: v0.30.10");
});

test("agentic progress still shows tool activity before final text exists", () => {
  const output = formatAgenticTaskResult({
    text: "",
    events: [
      {
        type: "tool_activity",
        payload: "browser_open: in_progress"
      }
    ]
  });

  assert.equal(output, "Tool activity:\nbrowser_open: in_progress");
});
