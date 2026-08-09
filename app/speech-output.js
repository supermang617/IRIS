const fallbackPlaybackStartTimeoutMs = 2500;

let sharedSpeechAudioContext = null;

export function standaloneArrayBuffer(bytes) {
  const view = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes || []);
  return view.buffer.slice(view.byteOffset, view.byteOffset + view.byteLength);
}

export function nativeSpeechPlaybackArguments(bytes, runId, firstChunk = true) {
  if (!Number.isSafeInteger(runId) || runId <= 0) {
    throw new TypeError("speech playback run ID must be a positive integer");
  }
  const view = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes || []);
  return {
    wavBytes: Array.from(view),
    playbackId: runId,
    firstChunk: firstChunk === true
  };
}

export function createSpeechStopHandle(stop, options = {}) {
  let stopped = false;
  let interruptionPaused = false;
  return {
    pause() {
      if (stopped) {
        return;
      }
      stopped = true;
      interruptionPaused = false;
      stop();
    },
    async pauseForInterruption() {
      if (stopped) {
        return false;
      }
      if (interruptionPaused) {
        return true;
      }
      if (typeof options.pauseForInterruption !== "function") {
        return false;
      }
      const paused = Boolean(await options.pauseForInterruption());
      if (stopped) {
        if (paused && typeof options.cleanupAfterStoppedPause === "function") {
          await options.cleanupAfterStoppedPause();
        }
        return false;
      }
      interruptionPaused = paused;
      return paused;
    },
    async resumeAfterInterruption() {
      if (stopped || !interruptionPaused) {
        return false;
      }
      if (typeof options.resumeAfterInterruption !== "function") {
        return false;
      }
      const resumed = Boolean(await options.resumeAfterInterruption());
      if (resumed) {
        interruptionPaused = false;
      }
      return resumed;
    },
    complete() {
      stopped = true;
      interruptionPaused = false;
    },
    set src(_value) {},
    get src() {
      return "";
    },
    get stopped() {
      return stopped;
    },
    get method() {
      return String(options.method || "fallback");
    }
  };
}

export async function playWavBytes(bytes, options = {}) {
  const onDiagnostic = options.onDiagnostic || (() => {});
  if (playbackCancelled(options)) {
    return "cancelled";
  }
  try {
    await playWithWebAudio(bytes, options);
    return "web_audio";
  } catch (error) {
    if (playbackCancelled(options)) {
      return "cancelled";
    }
    onDiagnostic("speech_web_audio_error", errorMessage(error));
    await playWithHtmlAudio(bytes, options);
    return playbackCancelled(options) ? "cancelled" : "html_audio";
  }
}

async function playWithWebAudio(bytes, options) {
  throwIfPlaybackCancelled(options);
  const context = (options.getAudioContext || defaultAudioContext)();
  if (!context) {
    throw new Error("Web Audio is unavailable");
  }
  if (context.state === "suspended") {
    await context.resume();
  }
  throwIfPlaybackCancelled(options);

  const decoded = await context.decodeAudioData(standaloneArrayBuffer(bytes));
  throwIfPlaybackCancelled(options);

  await new Promise((resolve, reject) => {
    let finished = false;
    let source = null;
    let gain = null;
    let handle = null;

    const finish = (error = null) => {
      if (finished) {
        return;
      }
      finished = true;
      if (handle) {
        handle.complete();
        options.clearActiveHandle?.(handle);
      }
      safeDisconnect(source);
      safeDisconnect(gain);
      if (error) {
        reject(error);
      } else {
        resolve();
      }
    };

    try {
      source = context.createBufferSource();
      gain = context.createGain();
      gain.gain.value = 1;
      source.buffer = decoded;
      source.connect(gain);
      gain.connect(context.destination);
      const resumeContextAfterInterruption = async () => {
        try {
          if (context.state === "suspended") {
            await context.resume();
          }
          return context.state !== "suspended";
        } catch (error) {
          onDiagnostic("speech_fallback_resume_error", errorMessage(error));
          return false;
        }
      };
      handle = createSpeechStopHandle(
        () => {
          try {
            source.stop(0);
          } catch (_error) {
            // The source may already have ended; cancellation should still settle.
          }
          finish();
        },
        {
          method: "web_audio",
          async pauseForInterruption() {
            try {
              if (context.state !== "suspended") {
                await context.suspend();
              }
              return context.state === "suspended";
            } catch (error) {
              onDiagnostic("speech_fallback_pause_error", errorMessage(error));
              return false;
            }
          },
          async resumeAfterInterruption() {
            return resumeContextAfterInterruption();
          },
          cleanupAfterStoppedPause: resumeContextAfterInterruption
        }
      );
      options.setActiveHandle?.(handle);
      source.onended = () => finish();
      throwIfPlaybackCancelled(options);
      source.start(0);
      options.onPlaying?.("web_audio");
    } catch (error) {
      finish(error);
    }
  });
}

function playWithHtmlAudio(bytes, options) {
  return new Promise((resolve, reject) => {
    let url = null;
    let audio = null;
    let handle = null;
    let finished = false;
    let started = false;
    let playbackStartTimer = null;

    const finish = (error = null) => {
      if (finished) {
        return;
      }
      finished = true;
      if (playbackStartTimer) {
        clearTimeout(playbackStartTimer);
      }
      if (handle) {
        handle.complete();
        options.clearActiveHandle?.(handle);
      }
      if (url) {
        (options.revokeObjectUrl || URL.revokeObjectURL)(url);
      }
      if (error) {
        reject(error);
      } else {
        resolve();
      }
    };

    try {
      throwIfPlaybackCancelled(options);
      const blobFactory = options.createBlob || ((parts, init) => new Blob(parts, init));
      const createObjectUrl = options.createObjectUrl || URL.createObjectURL;
      url = createObjectUrl(blobFactory([bytes], { type: "audio/wav" }));
      audio = (options.createAudioElement || ((objectUrl) => new Audio(objectUrl)))(url);
      audio.preload = "auto";
      audio.volume = 1;
      audio.muted = false;
      handle = createSpeechStopHandle(
        () => {
          audio.pause();
          finish();
        },
        {
          method: "html_audio",
          pauseForInterruption() {
            try {
              audio.pause();
              return true;
            } catch (error) {
              options.onDiagnostic?.("speech_fallback_pause_error", errorMessage(error));
              return false;
            }
          },
          async resumeAfterInterruption() {
            try {
              const playResult = audio.play();
              if (playResult && typeof playResult.then === "function") {
                await playResult;
              }
              return true;
            } catch (error) {
              options.onDiagnostic?.("speech_fallback_resume_error", errorMessage(error));
              return false;
            }
          }
        }
      );
      options.setActiveHandle?.(handle);
      throwIfPlaybackCancelled(options);

      playbackStartTimer = setTimeout(() => {
        if (!started) {
          options.onDiagnostic?.(
            "speech_playback_stalled",
            `method=html_audio; timeout_ms=${options.playbackStartTimeoutMs || fallbackPlaybackStartTimeoutMs}`
          );
        }
      }, options.playbackStartTimeoutMs || fallbackPlaybackStartTimeoutMs);

      audio.onplaying = () => {
        if (started) {
          return;
        }
        started = true;
        if (playbackStartTimer) {
          clearTimeout(playbackStartTimer);
          playbackStartTimer = null;
        }
        options.onPlaying?.("html_audio");
      };
      audio.onended = () => finish();
      audio.onerror = () => {
        finish(new Error(formatMediaElementError(audio.error)));
      };

      const playResult = audio.play();
      if (playResult && typeof playResult.catch === "function") {
        playResult.catch((error) => finish(error));
      }
    } catch (error) {
      finish(error);
    }
  });
}

function defaultAudioContext() {
  const AudioContextClass = globalThis.AudioContext || globalThis.webkitAudioContext;
  if (!AudioContextClass) {
    return null;
  }
  if (!sharedSpeechAudioContext || sharedSpeechAudioContext.state === "closed") {
    sharedSpeechAudioContext = new AudioContextClass({ latencyHint: "interactive" });
  }
  return sharedSpeechAudioContext;
}

function formatMediaElementError(mediaError) {
  if (!mediaError) {
    return "unknown media element error";
  }
  return `code=${mediaError.code}; message=${mediaError.message || "n/a"}`;
}

function errorMessage(error) {
  return error instanceof Error ? error.message : String(error);
}

function playbackCancelled(options) {
  return options.isCancelled?.() === true;
}

function throwIfPlaybackCancelled(options) {
  if (playbackCancelled(options)) {
    throw new Error("speech playback cancelled");
  }
}

function safeDisconnect(node) {
  try {
    node?.disconnect?.();
  } catch (_error) {
    // Disconnect can throw after a node is already detached.
  }
}
