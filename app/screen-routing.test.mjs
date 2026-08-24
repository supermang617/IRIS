import assert from "node:assert/strict";
import test from "node:test";

import {
  classifyScreenProbeRoute,
  screenProbeStatusText
} from "./screen-routing.js";

test("natural screen requests route to full visible desktop capture", () => {
  for (const prompt of [
    "what can you see on my screen?",
    "read the page on my screen",
    "look at the YouTube video and tell me what is playing",
    "describe this window",
    "what's on my desktop?"
  ]) {
    assert.deepEqual(classifyScreenProbeRoute(prompt), {
      route: "implicit",
      target: "virtual-screen",
      prompt
    });
  }
});

test("explicit under Iris requests keep the narrow hidden-window capture", () => {
  assert.deepEqual(classifyScreenProbeRoute("describe what is underneath Iris"), {
    route: "implicit",
    target: "under-iris",
    prompt: "describe what is underneath Iris"
  });
});

test("ordinary local chat does not trigger screen capture", () => {
  assert.deepEqual(classifyScreenProbeRoute("tell me a story about a window"), {
    route: "none",
    target: null,
    prompt: "tell me a story about a window"
  });
});

test("screen probe status avoids exposing implementation names", () => {
  assert.equal(
    screenProbeStatusText("virtual-screen"),
    "Looking at the visible desktop.\n\nThinking locally..."
  );
  assert.equal(
    screenProbeStatusText("under-iris"),
    "Looking under Iris.\n\nThinking locally..."
  );
});
