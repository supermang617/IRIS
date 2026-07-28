import { normalizeSpeechText, splitSpeechChunks } from "./speech-chunks.js";

const defaultMaxChars = 180;

export function speechRunIsCurrent(runId, activeRunId, panicStopActive = false) {
  return (
    Number.isSafeInteger(runId) &&
    runId > 0 &&
    runId === activeRunId &&
    panicStopActive !== true
  );
}

export function createSpeechPlaybackRegistry() {
  let active = null;

  return {
    claim(runId, cancel) {
      if (!Number.isSafeInteger(runId) || runId <= 0) {
        throw new TypeError("speech playback run ID must be a positive integer");
      }
      if (typeof cancel !== "function") {
        throw new TypeError("speech playback cancellation must be a function");
      }
      const lease = { runId, cancel };
      active = lease;
      return lease;
    },
    clear(lease) {
      if (active !== lease) {
        return false;
      }
      active = null;
      return true;
    },
    clearRun(runId) {
      if (active?.runId !== runId) {
        return false;
      }
      active = null;
      return true;
    },
    cancelRun(runId) {
      if (active?.runId !== runId) {
        return false;
      }
      const { cancel } = active;
      active = null;
      cancel();
      return true;
    },
    cancelActive() {
      if (!active) {
        return false;
      }
      const { cancel } = active;
      active = null;
      cancel();
      return true;
    },
    get activeRunId() {
      return active?.runId ?? 0;
    }
  };
}

export function drainCompletedSpeech(text, options = {}) {
  let remainder = String(text || "");
  const chunks = [];
  const maxChars = Math.max(80, Number(options.maxChars) || defaultMaxChars);
  const final = options.final === true;

  while (remainder.trim()) {
    const boundary = nextClauseBoundary(remainder, maxChars, final);
    if (boundary === null) {
      break;
    }
    const raw = remainder.slice(0, boundary);
    remainder = remainder.slice(boundary);
    for (const chunk of splitSpeechChunks(raw, maxChars)) {
      if (chunk) {
        chunks.push(chunk);
      }
    }
  }

  if (final && remainder.trim()) {
    chunks.push(...splitSpeechChunks(remainder, maxChars));
    remainder = "";
  }

  return { chunks, remainder };
}

export function createPipelinedSpeechQueue(options) {
  const synthesisQueue = createAsyncQueue();
  const playbackQueue = createAsyncQueue();
  let cancelled = false;
  let nextIndex = 0;
  let failure = null;

  const shouldStop = () => cancelled || options.isCancelled?.() === true;

  const synthesisLoop = (async () => {
    try {
      while (true) {
        const entry = await synthesisQueue.shift();
        if (entry.done || shouldStop()) {
          break;
        }
        const text = normalizeSpeechText(entry.value);
        if (!text) {
          continue;
        }
        const index = nextIndex++;
        const prepared = await options.synthesize(text, index);
        if (shouldStop()) {
          break;
        }
        playbackQueue.push({ prepared, text, index });
      }
    } catch (error) {
      failure = error;
      cancelled = true;
      synthesisQueue.close();
    } finally {
      playbackQueue.close();
    }
  })();

  const playbackLoop = (async () => {
    try {
      while (true) {
        const entry = await playbackQueue.shift();
        if (entry.done || shouldStop()) {
          break;
        }
        await options.play(entry.value);
      }
    } catch (error) {
      failure = error;
      cancelled = true;
      synthesisQueue.close();
      playbackQueue.close();
    }
  })();

  const done = Promise.all([synthesisLoop, playbackLoop]).then(() => {
    if (failure) {
      throw failure;
    }
  });

  return {
    push(text) {
      if (!cancelled) {
        synthesisQueue.push(String(text || ""));
      }
    },
    close() {
      synthesisQueue.close();
      return done;
    },
    cancel() {
      cancelled = true;
      synthesisQueue.close();
      playbackQueue.close();
      options.onCancel?.();
      return done.catch(() => {});
    },
    get cancelled() {
      return cancelled;
    },
    done
  };
}

function nextClauseBoundary(text, maxChars, final) {
  const searchLimit = Math.min(text.length, maxChars + 1);
  const candidate = text.slice(0, searchLimit);
  const punctuation = /[.!?](?:["')\]]{0,2})(?=\s|$)/g;
  let match;
  while ((match = punctuation.exec(candidate)) !== null) {
    const boundary = match.index + match[0].length;
    if (boundary >= 4) {
      return consumeFollowingWhitespace(text, boundary);
    }
  }

  if (text.length > maxChars) {
    const wordBoundary = text.lastIndexOf(" ", maxChars);
    return wordBoundary >= 40 ? wordBoundary + 1 : maxChars;
  }

  return final ? text.length : null;
}

function consumeFollowingWhitespace(text, boundary) {
  let index = boundary;
  while (index < text.length && /\s/.test(text[index])) {
    index += 1;
  }
  return index;
}

function createAsyncQueue() {
  const values = [];
  const waiters = [];
  let closed = false;

  return {
    push(value) {
      if (closed) {
        return;
      }
      const waiter = waiters.shift();
      if (waiter) {
        waiter({ done: false, value });
      } else {
        values.push(value);
      }
    },
    shift() {
      if (values.length > 0) {
        return Promise.resolve({ done: false, value: values.shift() });
      }
      if (closed) {
        return Promise.resolve({ done: true });
      }
      return new Promise((resolve) => waiters.push(resolve));
    },
    close() {
      if (closed) {
        return;
      }
      closed = true;
      while (waiters.length > 0) {
        waiters.shift()({ done: true });
      }
    }
  };
}
