import assert from "node:assert/strict";
import { test } from "node:test";
import { shouldClearInputOnSubmit } from "./input-state.js";

test("submitted input clears when Iris accepts the prompt", () => {
  assert.equal(shouldClearInputOnSubmit("summarize this", false), true);
  assert.equal(shouldClearInputOnSubmit("   ", false), false);
  assert.equal(shouldClearInputOnSubmit("summarize this", true), false);
});
