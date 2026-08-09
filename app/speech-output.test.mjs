import assert from "node:assert/strict";
import test from "node:test";

import {
  createSpeechStopHandle,
  nativeSpeechPlaybackArguments,
  playWavBytes,
  standaloneArrayBuffer
} from "./speech-output.js";

test("standaloneArrayBuffer copies only the visible Uint8Array slice", () => {
  const source = new Uint8Array([9, 1, 2, 3, 9]);
  const slice = source.subarray(1, 4);
  const copied = new Uint8Array(standaloneArrayBuffer(slice));

  assert.deepEqual([...copied], [1, 2, 3]);
});

test("native playback marks only the first speech chunk for device preroll", () => {
  const source = new Uint8Array([9, 1, 2, 9]);
  const first = nativeSpeechPlaybackArguments(source.subarray(1, 3), 17, true);
  const continuation = nativeSpeechPlaybackArguments(source.subarray(1, 3), 17, false);

  assert.deepEqual(first, {
    wavBytes: [1, 2],
    playbackId: 17,
    firstChunk: true
  });
  assert.deepEqual(continuation, {
    wavBytes: [1, 2],
    playbackId: 17,
    firstChunk: false
  });
  assert.equal(nativeSpeechPlaybackArguments(source, 17).firstChunk, true);
  assert.throws(
    () => nativeSpeechPlaybackArguments(source, 0, true),
    /positive integer/
  );
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

test("speech stop handle can speculatively pause and resume without stopping", async () => {
  const events = [];
  const handle = createSpeechStopHandle(
    () => events.push("stop"),
    {
      method: "web_audio",
      pauseForInterruption: async () => {
        events.push("pause");
        return true;
      },
      resumeAfterInterruption: async () => {
        events.push("resume");
        return true;
      }
    }
  );

  assert.equal(await handle.pauseForInterruption(), true);
  assert.equal(await handle.resumeAfterInterruption(), true);
  assert.equal(handle.stopped, false);
  assert.equal(handle.method, "web_audio");
  assert.deepEqual(events, ["pause", "resume"]);

  handle.pause();
  assert.equal(handle.stopped, true);
  assert.deepEqual(events, ["pause", "resume", "stop"]);
});

test("permanent stop wins while a speculative pause is awaiting", async () => {
  const events = [];
  let releasePause;
  const pausePending = new Promise((resolve) => {
    releasePause = resolve;
  });
  const handle = createSpeechStopHandle(
    () => events.push("stop"),
    {
      pauseForInterruption: async () => {
        events.push("pause");
        await pausePending;
        return true;
      },
      resumeAfterInterruption: async () => {
        events.push("resume");
        return true;
      },
      cleanupAfterStoppedPause: async () => {
        events.push("cleanup");
      }
    }
  );

  const pauseResult = handle.pauseForInterruption();
  handle.pause();
  releasePause();

  assert.equal(await pauseResult, false);
  assert.equal(await handle.resumeAfterInterruption(), false);
  assert.deepEqual(events, ["pause", "stop", "cleanup"]);
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

test("Web Audio fallback suspends and resumes for an unconfirmed interruption", async () => {
  const events = [];
  let activeHandle = null;
  const fakeSource = {
    connect() {},
    disconnect() {},
    start() {
      events.push("source.start");
    },
    stop() {
      events.push("source.stop");
    }
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
    async decodeAudioData() {
      return {};
    },
    async suspend() {
      events.push("context.suspend");
      this.state = "suspended";
    },
    async resume() {
      events.push("context.resume");
      this.state = "running";
    }
  };

  const playback = playWavBytes(new Uint8Array([1, 2, 3]), {
    clearActiveHandle(handle) {
      if (activeHandle === handle) {
        activeHandle = null;
      }
    },
    getAudioContext: () => fakeContext,
    setActiveHandle(handle) {
      activeHandle = handle;
    }
  });
  await waitFor(() => activeHandle !== null);

  assert.equal(await activeHandle.pauseForInterruption(), true);
  assert.equal(fakeContext.state, "suspended");
  assert.equal(activeHandle.stopped, false);
  assert.equal(await activeHandle.resumeAfterInterruption(), true);
  assert.equal(fakeContext.state, "running");
  assert.equal(activeHandle.stopped, false);

  fakeSource.onended?.();
  assert.equal(await playback, "web_audio");
  assert.equal(activeHandle, null);
  assert.deepEqual(events, ["source.start", "context.suspend", "context.resume"]);
});

test("Web Audio stop during speculative pause restores context without restarting source", async () => {
  const events = [];
  let activeHandle = null;
  let releaseSuspend;
  const suspendPending = new Promise((resolve) => {
    releaseSuspend = resolve;
  });
  const fakeSource = {
    connect() {},
    disconnect() {},
    start() {
      events.push("source.start");
    },
    stop() {
      events.push("source.stop");
    }
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
    async decodeAudioData() {
      return {};
    },
    async suspend() {
      events.push("context.suspend");
      await suspendPending;
      this.state = "suspended";
    },
    async resume() {
      events.push("context.resume");
      this.state = "running";
    }
  };

  const playback = playWavBytes(new Uint8Array([1, 2, 3]), {
    clearActiveHandle(handle) {
      if (activeHandle === handle) {
        activeHandle = null;
      }
    },
    getAudioContext: () => fakeContext,
    setActiveHandle(handle) {
      activeHandle = handle;
    }
  });
  await waitFor(() => activeHandle !== null);

  const pauseResult = activeHandle.pauseForInterruption();
  activeHandle.pause();
  releaseSuspend();

  assert.equal(await pauseResult, false);
  assert.equal(await playback, "web_audio");
  assert.equal(fakeContext.state, "running");
  assert.equal(activeHandle, null);
  assert.deepEqual(events, [
    "source.start",
    "context.suspend",
    "source.stop",
    "context.resume"
  ]);
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

test("HTML audio fallback pauses and resumes without ending playback", async () => {
  let activeHandle = null;
  let pauseCount = 0;
  let playCount = 0;
  const fakeAudio = {
    error: null,
    pause() {
      pauseCount += 1;
    },
    play() {
      playCount += 1;
      queueMicrotask(() => this.onplaying?.());
      return Promise.resolve();
    }
  };

  const playback = playWavBytes(new Uint8Array([4, 5, 6]), {
    clearActiveHandle(handle) {
      if (activeHandle === handle) {
        activeHandle = null;
      }
    },
    createAudioElement: () => fakeAudio,
    createBlob: () => ({ blob: true }),
    createObjectUrl: () => "blob:resume-test",
    getAudioContext: () => ({
      state: "running",
      async decodeAudioData() {
        throw new Error("decode failed");
      }
    }),
    revokeObjectUrl() {},
    setActiveHandle(handle) {
      activeHandle = handle;
    }
  });
  await waitFor(() => activeHandle !== null);

  assert.equal(await activeHandle.pauseForInterruption(), true);
  assert.equal(pauseCount, 1);
  assert.equal(await activeHandle.resumeAfterInterruption(), true);
  assert.equal(playCount, 2);
  assert.equal(activeHandle.stopped, false);

  fakeAudio.onended?.();
  assert.equal(await playback, "html_audio");
  assert.equal(activeHandle, null);
});

test("HTML audio stop during speculative pause never restarts revoked playback", async () => {
  let activeHandle = null;
  let objectUrlRevoked = false;
  let pauseCount = 0;
  let playCount = 0;
  let playedAfterRevoke = false;
  const fakeAudio = {
    error: null,
    pause() {
      pauseCount += 1;
    },
    play() {
      playCount += 1;
      if (objectUrlRevoked) {
        playedAfterRevoke = true;
        throw new Error("revoked playback was restarted");
      }
      queueMicrotask(() => this.onplaying?.());
      return Promise.resolve();
    }
  };

  const playback = playWavBytes(new Uint8Array([4, 5, 6]), {
    clearActiveHandle(handle) {
      if (activeHandle === handle) {
        activeHandle = null;
      }
    },
    createAudioElement: () => fakeAudio,
    createBlob: () => ({ blob: true }),
    createObjectUrl: () => "blob:stop-during-pause",
    getAudioContext: () => ({
      state: "running",
      async decodeAudioData() {
        throw new Error("decode failed");
      }
    }),
    revokeObjectUrl() {
      objectUrlRevoked = true;
    },
    setActiveHandle(handle) {
      activeHandle = handle;
    }
  });
  await waitFor(() => activeHandle !== null);

  const pauseResult = activeHandle.pauseForInterruption();
  activeHandle.pause();

  assert.equal(await pauseResult, false);
  assert.equal(await playback, "html_audio");
  assert.equal(objectUrlRevoked, true);
  assert.equal(playedAfterRevoke, false);
  assert.equal(playCount, 1);
  assert.equal(pauseCount, 2);
  assert.equal(activeHandle, null);
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

async function waitFor(predicate) {
  for (let attempt = 0; attempt < 100; attempt += 1) {
    if (predicate()) {
      return;
    }
    await new Promise((resolve) => setTimeout(resolve, 0));
  }
  throw new Error("condition was not reached");
}
