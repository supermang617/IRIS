import assert from "node:assert/strict";
import { test } from "node:test";
import { formatStagedMemories, pendingStagedMemories } from "./staging-state.js";

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
