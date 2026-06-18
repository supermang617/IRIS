import assert from "node:assert/strict";
import { test } from "node:test";
import { canSubmitWhilePanicStopped, nextPanicState, panicStatusText } from "./panic-state.js";

test("panic stop toggles local UI submission gate", () => {
  assert.equal(nextPanicState(false), true);
  assert.equal(nextPanicState(true), false);
  assert.equal(canSubmitWhilePanicStopped(true), false);
  assert.equal(canSubmitWhilePanicStopped(false), true);
});

test("panic status text describes the visible pause behavior", () => {
  assert.equal(panicStatusText(true), "Iris is paused.");
  assert.equal(panicStatusText(false), "Iris resumed. Wake word armed.");
});
