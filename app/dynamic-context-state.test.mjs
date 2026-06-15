import assert from "node:assert/strict";
import test from "node:test";

import {
  formatDynamicContextStatus,
  parseDynamicContextCommand
} from "./dynamic-context-state.js";

test("dynamic context commands require an explicit control phrase", () => {
  assert.deepEqual(parseDynamicContextCommand("dynamic context"), { action: "status" });
  assert.deepEqual(parseDynamicContextCommand("communication profile reset"), {
    action: "reset"
  });
  assert.deepEqual(parseDynamicContextCommand("dynamic context off"), {
    action: "set_enabled",
    enabled: false
  });
  assert.deepEqual(parseDynamicContextCommand("analyze the context dynamically"), {
    action: "none"
  });
});

test("dynamic context status explains local aggregate storage", () => {
  const text = formatDynamicContextStatus({
    enabled: true,
    observationCount: 7,
    sentenceStyle: "medium-length, clear sentences",
    vocabularyStyle: "balanced vocabulary",
    tone: "direct, analytical"
  });

  assert.match(text, /Dynamic context: On/);
  assert.match(text, /Recent observations: 7/);
  assert.match(text, /aggregate metrics only/);
});
