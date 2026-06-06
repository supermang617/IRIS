import assert from "node:assert/strict";
import test from "node:test";

import { classifyHermesRoute } from "./hermes-routing.js";

test("explicit Hermes research command routes to research mode", () => {
  assert.deepEqual(classifyHermesRoute("hermes research: find Iris notes"), {
    route: "explicit",
    mode: "research",
    text: "find Iris notes"
  });
});

test("natural online request routes through Hermes research", () => {
  assert.deepEqual(classifyHermesRoute("Iris, look online for the latest Ollama release"), {
    route: "implicit",
    mode: "research",
    text: "Iris, look online for the latest Ollama release"
  });
});

test("ordinary local chat stays with Iris", () => {
  assert.deepEqual(classifyHermesRoute("summarize what I said earlier"), {
    route: "none",
    mode: null,
    text: "summarize what I said earlier"
  });
});
