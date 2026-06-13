import assert from "node:assert/strict";
import test from "node:test";

import { splitSpeechChunks } from "./speech-chunks.js";

test("splits long speech at sentence or word boundaries", () => {
  const text =
    "First sentence is short. Second sentence is deliberately longer so it needs another local synthesis request without delaying the first spoken words.";
  const chunks = splitSpeechChunks(text, 80);

  assert.ok(chunks.length >= 2);
  assert.ok(chunks.every((chunk) => chunk.length <= 80));
  assert.equal(chunks.join(" ").replace(/\s+/g, " "), text);
});

test("returns no chunks for blank speech", () => {
  assert.deepEqual(splitSpeechChunks("   "), []);
});
