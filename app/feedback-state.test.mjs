import test from "node:test";
import assert from "node:assert/strict";
import {
  buildFeedbackCapture,
  createFeedbackTurn,
  feedbackFieldsVisible,
  formatFeedbackStatus
} from "./feedback-state.js";

test("feedback turn carries bounded metadata for the rated assistant answer", () => {
  const turn = createFeedbackTurn({
    source: "typed",
    userText: "private prompt",
    assistantText: "Useful answer",
    modelId: "gemma",
    provider: "ollama_local",
    tools: ["memory", "web"],
    latencyMs: 1234,
    now: 10
  });

  assert.equal(turn.source, "typed");
  assert.equal(turn.assistantText, "Useful answer");
  assert.equal(turn.modelId, "gemma");
  assert.equal(turn.provider, "ollama_local");
  assert.equal(turn.latencyMs, 1234);
  assert.match(turn.turnId, /^turn-10-/);
});

test("feedback capture keeps prompt text for backend hashing and correction for export", () => {
  const turn = createFeedbackTurn({
    source: "screen",
    userText: "what is on screen",
    assistantText: "I missed the visible title.",
    modelId: "gemma",
    provider: "ollama_local"
  });
  const capture = buildFeedbackCapture(
    turn,
    "down",
    "missed obvious text",
    "The screen title says Iris v1."
  );

  assert.equal(capture.rating, "down");
  assert.equal(capture.userText, "what is on screen");
  assert.equal(capture.assistantText, "I missed the visible title.");
  assert.equal(capture.correction, "The screen title says Iris v1.");
  assert.equal(capture.metadata.source, "screen");
});

test("plain thumbs up does not require reason fields", () => {
  const turn = createFeedbackTurn({
    source: "typed",
    userText: "question",
    assistantText: "Good answer",
    modelId: "gemma",
    provider: "ollama_local"
  });
  const capture = buildFeedbackCapture(turn, "up", "", "");

  assert.equal(capture.rating, "up");
  assert.equal(capture.reason, null);
  assert.equal(capture.correction, null);
  assert.equal(feedbackFieldsVisible("up"), false);
});

test("status text exposes learning state without raw feedback content", () => {
  const text = formatFeedbackStatus({
    totalEvents: 3,
    upCount: 1,
    downCount: 2,
    correctionCount: 1,
    preferenceSummary: "prefer tighter answers",
    instructionActive: true
  });

  assert.match(text, /Feedback saved: 3/);
  assert.match(text, /prefer tighter answers/);
  assert.match(text, /active/);
});
