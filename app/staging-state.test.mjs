import assert from "node:assert/strict";
import { test } from "node:test";
import {
  claimsActiveMemoryWrite,
  formatHermesMemoryTaskText,
  formatStagedMemories,
  hasMemoryWriteIntent,
  pendingStagedMemories
} from "./staging-state.js";

test("staging display only shows pending Hermes memories", () => {
  const staged = [
    { id: 1, text: "old accepted", status: "accepted", verdict: "staged" },
    { id: 10, text: "Alejandro is 45 years old", status: "pending", verdict: "staged" },
    { id: 2, text: "old rejected", status: "rejected", verdict: "staged" }
  ];

  assert.deepEqual(pendingStagedMemories(staged).map((item) => item.id), [10]);
  assert.equal(formatStagedMemories(staged), "10. Alejandro is 45 years old");
});

test("staging display names no pending items clearly", () => {
  assert.equal(formatStagedMemories([{ id: 1, text: "old accepted", status: "accepted" }]), "No pending Hermes memories.");
});

test("Hermes staged-memory output cannot claim active memory before approval", () => {
  const staged = [{ id: 7, text: "Alejandro is 45 years old", status: "pending" }];

  assert.equal(
    formatHermesMemoryTaskText("I have remembered that Alejandro is 45 years old.", staged),
    "Hermes staged a memory proposal for your approval."
  );
  assert.equal(
    formatHermesMemoryTaskText("Hermes saved that detail.", staged),
    "Hermes staged a memory proposal for your approval."
  );
  assert.equal(
    formatHermesMemoryTaskText("This still needs approval.", staged),
    "This still needs approval."
  );
});

test("Hermes memory-intent output cannot claim active memory without shaped proposals", () => {
  assert.equal(hasMemoryWriteIntent("remember that Alejandro is 45"), true);
  assert.equal(claimsActiveMemoryWrite("I have remembered that Alejandro is 45."), true);
  assert.equal(claimsActiveMemoryWrite("I've saved that to memory."), true);
  assert.equal(claimsActiveMemoryWrite("Hermes already stored that detail."), true);
  assert.equal(
    formatHermesMemoryTaskText(
      "I have remembered that Alejandro is 45 years old.",
      [],
      "remember that Alejandro is 45 years old"
    ),
    "Hermes did not stage a memory proposal."
  );
});

test("Hermes memory-intent output hides confusing raw text when staging succeeds", () => {
  assert.equal(
    formatHermesMemoryTaskText(
      "I need to propose a memory. Please provide confirmation.",
      [{ id: 12, text: "temporary reject check", status: "pending" }],
      "propose memory temporary reject check"
    ),
    "Hermes staged a memory proposal for your approval."
  );
});

test("Hermes memory-intent output does not claim pending approval when staging rejects", () => {
  assert.equal(
    formatHermesMemoryTaskText(
      "I could not stage that memory.",
      [{ id: 13, text: "temporary reject check final", status: "rejected" }],
      "propose memory temporary reject check final"
    ),
    "I could not stage that memory."
  );
  assert.equal(
    formatHermesMemoryTaskText(
      "",
      [{ id: 14, text: "temporary reject check final", status: "rejected" }],
      "remember temporary reject check final"
    ),
    "Hermes did not stage a memory proposal."
  );
});
