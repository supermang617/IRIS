import assert from "node:assert/strict";
import test from "node:test";

import {
  createSpeechStopHandle,
  playWavBytes,
  standaloneArrayBuffer
} from "./speech-output.js";

test("standaloneArrayBuffer copies only the visible Uint8Array slice", () => {
  const source = new Uint8Array([9, 1, 2, 3, 9]);
  const slice = source.subarray(1, 4);
  const copied = new Uint8Array(standaloneArrayBuffer(slice));

  assert.deepEqual([...copied], [1, 2, 3]);
});

test("createSpeechStopHandle calls stop exactly once", () => {
  let stopCount = 0;
  const handle = createSpeechStopHandle(() => {
    stopCount += 1;
  });

  handle.pause();
  handle.pause();
  handle.src = "";

  assert.equal(stopCount, 1);
  assert.equal(handle.stopped, true);
  assert.equal(handle.src, "");
});

test("playWavBytes uses Web Audio when it is available", async () => {
  const events = [];
  let activeHandle = null;
  const fakeSource = {
    connect() {},
    disconnect() {},
    start() {
      events.push("source.start");
      queueMicrotask(() => this.onended?.());
    },
    stop() {}
  };
  const fakeContext = {
    state: "running",
    destination: {},
    createBufferSource() {
      return fakeSource;
    },
    createGain() {
      return {
        gain: { value: 0 },
        connect() {},
        disconnect() {}
      };
    },
    async decodeAudioData(buffer) {
      events.push(`decode:${buffer.byteLength}`);
      return {};
    }
  };

  const method = await playWavBytes(new Uint8Array([1, 2, 3]), {
    clearActiveHandle(handle) {
      if (activeHandle === handle) {
        activeHandle = null;
      }
    },
    getAudioContext: () => fakeContext,
    onPlaying: (playbackMethod) => events.push(`playing:${playbackMethod}`),
    setActiveHandle: (handle) => {
      activeHandle = handle;
    }
  });

  assert.equal(method, "web_audio");
  assert.deepEqual(events, ["decode:3", "source.start", "playing:web_audio"]);
  assert.equal(activeHandle, null);
});

test("playWavBytes falls back to HTML audio after Web Audio failure", async () => {
  const events = [];
  let objectUrlRevoked = false;
  const fakeAudio = {
    error: null,
    muted: true,
    preload: "",
    volume: 0,
    pause() {},
    play() {
      queueMicrotask(() => {
        this.onplaying?.();
        this.onended?.();
      });
      return Promise.resolve();
    }
  };

  const method = await playWavBytes(new Uint8Array([4, 5, 6]), {
    createAudioElement(url) {
      events.push(`audio:${url}`);
      return fakeAudio;
    },
    createBlob: () => ({ blob: true }),
    createObjectUrl: () => "blob:test",
    getAudioContext: () => ({
      state: "running",
      async decodeAudioData() {
        throw new Error("decode failed");
      }
    }),
    onDiagnostic: (event, message) => events.push(`${event}:${message}`),
    onPlaying: (playbackMethod) => events.push(`playing:${playbackMethod}`),
    revokeObjectUrl(url) {
      objectUrlRevoked = url === "blob:test";
    }
  });

  assert.equal(method, "html_audio");
  assert.equal(fakeAudio.preload, "auto");
  assert.equal(fakeAudio.volume, 1);
  assert.equal(fakeAudio.muted, false);
  assert.equal(objectUrlRevoked, true);
  assert.deepEqual(events, [
    "speech_web_audio_error:decode failed",
    "audio:blob:test",
    "playing:html_audio"
  ]);
});

test("cancellation during Web Audio decoding cannot start stale playback", async () => {
  let cancelled = false;
  let releaseDecode;
  let sourceCreated = false;
  const decodePending = new Promise((resolve) => {
    releaseDecode = resolve;
  });

  const playback = playWavBytes(new Uint8Array([7, 8, 9]), {
    getAudioContext: () => ({
      state: "running",
      destination: {},
      createBufferSource() {
        sourceCreated = true;
        throw new Error("stale playback created a source");
      },
      async decodeAudioData() {
        await decodePending;
        return {};
      }
    }),
    isCancelled: () => cancelled
  });

  await Promise.resolve();
  cancelled = true;
  releaseDecode();

  assert.equal(await playback, "cancelled");
  assert.equal(sourceCreated, false);
});
