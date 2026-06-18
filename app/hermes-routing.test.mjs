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

test("natural online request routes through Iris background research", () => {
  assert.deepEqual(classifyHermesRoute("Iris, look online for the latest Ollama release"), {
    route: "implicit",
    mode: "research",
    text: "Iris, look online for the latest Ollama release"
  });
});

test("natural browser request routes without requiring the Hermes name", () => {
  assert.deepEqual(classifyHermesRoute("open the website https://example.com and summarize it"), {
    route: "implicit",
    mode: "research",
    text: "open the website https://example.com and summarize it"
  });
});

test("natural image generation request routes to the image provider", () => {
  assert.deepEqual(classifyHermesRoute("generate an image of Iris in glass style"), {
    route: "implicit",
    mode: "image_generation",
    text: "generate an image of Iris in glass style"
  });
});

test("ordinary local chat stays with Iris", () => {
  assert.deepEqual(classifyHermesRoute("summarize what I said earlier"), {
    route: "none",
    mode: null,
    text: "summarize what I said earlier"
  });
});
