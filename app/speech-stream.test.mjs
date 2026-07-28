import assert from "node:assert/strict";
import test from "node:test";

import {
  createPipelinedSpeechQueue,
  createSpeechPlaybackRegistry,
  drainCompletedSpeech,
  speechRunIsCurrent
} from "./speech-stream.js";

test("drains complete clauses while retaining an unfinished fragment", () => {
  const result = drainCompletedSpeech(
    "I heard you. I am checking the local files now"
  );
  assert.deepEqual(result.chunks, ["I heard you."]);
  assert.equal(result.remainder, "I am checking the local files now");
});

test("final drain emits the remaining speech", () => {
  const result = drainCompletedSpeech("One complete thought without punctuation", {
    final: true
  });
  assert.deepEqual(result.chunks, ["One complete thought without punctuation"]);
  assert.equal(result.remainder, "");
});

test("long unfinished output is bounded at a word boundary", () => {
  const text = `${"word ".repeat(45)}tail`;
  const result = drainCompletedSpeech(text, { maxChars: 100 });
  assert.ok(result.chunks.length >= 1);
  assert.ok(result.chunks.every((chunk) => chunk.length <= 100));
  assert.ok(result.remainder.length < text.length);
});

test("synthesis overlaps playback while preserving spoken order", async () => {
  const events = [];
  let releaseFirstPlayback;
  const firstPlayback = new Promise((resolve) => {
    releaseFirstPlayback = resolve;
  });

  const queue = createPipelinedSpeechQueue({
    async synthesize(text, index) {
      events.push(`synth:${index}:${text}`);
      return { index, text };
    },
    async play({ index, text }) {
      events.push(`play-start:${index}:${text}`);
      if (index === 0) {
        await firstPlayback;
      }
      events.push(`play-end:${index}:${text}`);
    }
  });

  queue.push("First sentence.");
  queue.push("Second sentence.");
  const completion = queue.close();

  await waitFor(() => events.includes("synth:1:Second sentence."));
  assert.deepEqual(events.slice(0, 3), [
    "synth:0:First sentence.",
    "play-start:0:First sentence.",
    "synth:1:Second sentence."
  ]);
  releaseFirstPlayback();
  await completion;
  assert.ok(
    events.indexOf("play-end:0:First sentence.") <
      events.indexOf("play-start:1:Second sentence.")
  );
});

test("cancellation prevents queued speech from playing", async () => {
  const played = [];
  let cancelled = false;
  const queue = createPipelinedSpeechQueue({
    isCancelled: () => cancelled,
    async synthesize(text) {
      cancelled = true;
      return text;
    },
    async play({ prepared }) {
      played.push(prepared);
    }
  });
  queue.push("Do not play this.");
  await queue.close();
  assert.deepEqual(played, []);
});

test("a delayed old-run finalizer cannot clear the new run cancellation", () => {
  const registry = createSpeechPlaybackRegistry();
  const cancelled = [];

  registry.claim(1, () => cancelled.push(1));
  assert.equal(registry.cancelRun(1), true);
  assert.deepEqual(cancelled, [1]);

  registry.claim(2, () => cancelled.push(2));
  assert.equal(registry.activeRunId, 2);

  // Run 1 finishes after run 2 has already taken ownership.
  assert.equal(registry.clearRun(1), false);
  assert.equal(registry.activeRunId, 2);

  assert.equal(registry.cancelRun(2), true);
  assert.deepEqual(cancelled, [1, 2]);
  assert.equal(registry.activeRunId, 0);
});

test("a delayed playback callback clears only its own lease", () => {
  const registry = createSpeechPlaybackRegistry();
  const firstLease = registry.claim(1, () => {});
  registry.claim(2, () => {});

  assert.equal(registry.clear(firstLease), false);
  assert.equal(registry.activeRunId, 2);
});

test("stale and panic-stopped speech runs cannot start fallback playback", () => {
  assert.equal(speechRunIsCurrent(2, 2, false), true);
  assert.equal(speechRunIsCurrent(1, 2, false), false);
  assert.equal(speechRunIsCurrent(2, 2, true), false);
  assert.equal(speechRunIsCurrent(0, 0, false), false);
});

async function waitFor(predicate) {
  for (let attempt = 0; attempt < 100; attempt += 1) {
    if (predicate()) {
      return;
    }
    await new Promise((resolve) => setTimeout(resolve, 0));
  }
  throw new Error("condition was not reached");
}
