import assert from "node:assert/strict";
import { test } from "node:test";
import {
  clampResponseHeight,
  composerHeightFor,
  composerMaxHeight,
  composerMinHeight,
  responseDefaultHeight,
  responseHeightFromDrag,
  responseHeightFromKeyboard,
  responseMinHeight,
  shouldSubmitComposer
} from "./composer-state.js";

test("composer Enter submits while Shift+Enter preserves multiline input", () => {
  assert.equal(
    shouldSubmitComposer({ key: "Enter", shiftKey: false, isComposing: false }),
    true
  );
  assert.equal(
    shouldSubmitComposer({ key: "Enter", shiftKey: true, isComposing: false }),
    false
  );
  assert.equal(
    shouldSubmitComposer({ key: "Enter", shiftKey: false, isComposing: true }),
    false
  );
});

test("composer height remains inside production layout bounds", () => {
  assert.equal(composerHeightFor(10), composerMinHeight);
  assert.equal(composerHeightFor(92.2), 93);
  assert.equal(composerHeightFor(800), composerMaxHeight);
});

test("response height respects minimum, available space, and stable default", () => {
  assert.equal(clampResponseHeight(40, 420), responseMinHeight);
  assert.equal(clampResponseHeight(260, 220), 220);
  assert.equal(clampResponseHeight("invalid", 420), responseDefaultHeight);
});

test("response resize grows upward because the pane sits above the handle", () => {
  assert.equal(responseHeightFromDrag(180, 300, 260), 220);
  assert.equal(responseHeightFromDrag(180, 300, 340), 140);
  assert.equal(responseHeightFromKeyboard(180, "ArrowUp"), 196);
  assert.equal(responseHeightFromKeyboard(180, "ArrowDown"), 164);
  assert.equal(responseHeightFromKeyboard(180, "Escape"), null);
});
