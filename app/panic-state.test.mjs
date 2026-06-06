import assert from "node:assert/strict";
import { test } from "node:test";
import { canSubmitWhilePanicStopped, nextPanicState, panicStatusText } from "./panic-state.js";

test("panic stop toggles local UI submission gate", () => {
  assert.equal(nextPanicState(false), true);
  assert.equal(nextPanicState(true), false);
  assert.equal(canSubmitWhilePanicStopped(true), false);
  assert.equal(canSubmitWhilePanicStopped(false), true);
});

test("panic stop status text is explicit", () => {
  assert.equal(panicStatusText(true), "Panic Stop active. Iris is paused.");
  assert.equal(panicStatusText(false), "Panic Stop cleared. Iris is ready.");
});
