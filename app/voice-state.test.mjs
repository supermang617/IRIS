import assert from "node:assert/strict";
import { test } from "node:test";
import {
  MODEL_AND_VOICE_WARMUP_FAILED_STATUS,
  MODEL_WARMUP_FAILED_STATUS,
  RUNTIME_PREPARING_STATUS,
  VOICE_SETUP_NEEDED_STATUS,
  classifyAsrError,
  classifyVoiceTranscript,
  createInterruptionPauseCoordinator,
  interruptionResumeRequiresCancellation,
  interruptionCandidatePauseAllowed,
  interruptionSignalAllowsSpeculativePause,
  interruptionCaptureAttemptAllowed,
  interruptionRetryDelayMs,
  interruptionSignalIsCurrent,
  nextVoiceListenMode,
  noSpeechStatusForMode,
  runtimeWarmHudStatus,
  shouldDisarmWakeFollowupAfterMisses,
  shouldContinueVoiceSession,
  shouldDisplayVoiceTranscript,
  voiceSubmitKeepsSession,
  voiceButtonAction,
  voiceCaptureCanStart,
  voiceTranscriptStateForMode,
  wakeRestartDelayMs
} from "./voice-state.js";

test("runtime warm status preserves actionable voice setup failures", () => {
  assert.equal(runtimeWarmHudStatus(true, true, true), "Waiting for input.");
  assert.equal(runtimeWarmHudStatus(true, false, true), VOICE_SETUP_NEEDED_STATUS);
  assert.equal(runtimeWarmHudStatus(true, true, false), MODEL_WARMUP_FAILED_STATUS);
  assert.equal(runtimeWarmHudStatus(true, false, false), MODEL_AND_VOICE_WARMUP_FAILED_STATUS);
  assert.equal(runtimeWarmHudStatus(true, true, true, true), "Iris is paused.");
  assert.equal(runtimeWarmHudStatus(false, false, false), null);
});

test("runtime preparation blocks push-to-talk and post-panic voice capture", () => {
  assert.equal(
    RUNTIME_PREPARING_STATUS,
    "Iris is still preparing the local model and voice runtime."
  );
  assert.equal(voiceCaptureCanStart(), true);
  assert.equal(voiceCaptureCanStart({ runtimePreparing: true }), false);
  assert.equal(
    voiceCaptureCanStart({
      runtimePreparing: true,
      panicStopped: false,
      enabled: true
    }),
    false
  );
  assert.equal(voiceCaptureCanStart({ panicStopped: true }), false);
  assert.equal(voiceCaptureCanStart({ enabled: false }), false);
  for (const state of [
    { thinking: true },
    { speaking: true },
    { listening: true },
    { interruptionListening: true },
    { stopRequested: true }
  ]) {
    assert.equal(voiceCaptureCanStart(state), false);
  }
});

test("push-to-talk submits the full transcript", () => {
  assert.deepEqual(
    classifyVoiceTranscript("What can you do?", {
      voiceLoop: false,
      wakeWord: false,
      wakeCommandArmed: false
    }),
    {
      action: "submit",
      prompt: "What can you do?",
      source: "voice",
      status: "Heard: What can you do?"
    }
  );
});

test("voice loop submits without requiring the wake word", () => {
  const decision = classifyVoiceTranscript("tell me the time", {
    voiceLoop: true,
    wakeWord: false,
    wakeCommandArmed: false
  });

  assert.equal(decision.action, "submit");
  assert.equal(decision.prompt, "tell me the time");
  assert.equal(decision.source, "voice-loop");
});

test("wake word plus request strips Iris from the submitted prompt", () => {
  const decision = classifyVoiceTranscript("Iris, summarize this", {
    voiceLoop: false,
    wakeWord: true,
    wakeCommandArmed: false
  });

  assert.equal(decision.action, "submit");
  assert.equal(decision.prompt, "summarize this");
  assert.equal(decision.source, "wake-word");
});

test("bare wake word arms the next utterance", () => {
  const decision = classifyVoiceTranscript("Iris", {
    voiceLoop: false,
    wakeWord: true,
    wakeCommandArmed: false
  });

  assert.equal(decision.action, "arm-wake-followup");
});

test("wake up phrase arms the next utterance instead of submitting wake up", () => {
  const decision = classifyVoiceTranscript("Iris wake up", {
    voiceLoop: false,
    wakeWord: true,
    wakeCommandArmed: false
  });

  assert.equal(decision.action, "arm-wake-followup");
});

test("sleep command enters hard sleep mode", () => {
  for (const transcript of ["sleep", "Iris sleep", "Iris go to sleep", "stop and sleep"]) {
    const decision = classifyVoiceTranscript(transcript, {
      voiceLoop: true,
      wakeWord: true,
      wakeCommandArmed: false
    });

    assert.equal(decision.action, "sleep", transcript);
    assert.equal(decision.source, "sleep", transcript);
  }
});

test("sleep command is honored during speech interruption listening", () => {
  const decision = classifyVoiceTranscript("Iris sleep", {
    voiceLoop: true,
    wakeWord: true,
    wakeCommandArmed: false,
    interruptionOnly: true
  });

  assert.equal(decision.action, "sleep");
  assert.equal(decision.source, "sleep");
});

test("sleep mode ignores every utterance except Iris wake up", () => {
  for (const transcript of ["tell me something", "Iris", "Iris hello", "wake up", "Ares wake up"]) {
    const decision = classifyVoiceTranscript(transcript, {
      sleeping: true,
      voiceLoop: false,
      wakeWord: true,
      wakeCommandArmed: false
    });

    assert.equal(decision.action, "sleep-ignore", transcript);
  }
});

test("sleep mode wakes only on explicit Iris wake up", () => {
  for (const transcript of ["Iris wake up", "Hey Iris, wake up", "Iris wake back up"]) {
    const decision = classifyVoiceTranscript(transcript, {
      sleeping: true,
      voiceLoop: false,
      wakeWord: true,
      wakeCommandArmed: false
    });

    assert.equal(decision.action, "wake-from-sleep", transcript);
    assert.equal(decision.source, "wake-word", transcript);
  }
});

test("common Iris wake word mishear arms listening", () => {
  for (const transcript of ["Hi Im Eric Swayup", "Hey Airis", "Hey, Iris", "Hello Irish", "Ares", "I Reese"]) {
    const decision = classifyVoiceTranscript(transcript, {
      voiceLoop: false,
      wakeWord: true,
      wakeCommandArmed: false
    });

    assert.equal(decision.action, "arm-wake-followup", transcript);
  }
});

test("weak Iris wake word mishear never submits a following request", () => {
  const decision = classifyVoiceTranscript("Ares tell me the alphabet", {
    voiceLoop: false,
    wakeWord: true,
    wakeCommandArmed: false
  });

  assert.equal(decision.action, "wait-for-wake");
  assert.equal(decision.prompt, "");
  assert.equal(decision.source, "wake-word");
});

test("speaker marker before Iris still arms listening", () => {
  const decision = classifyVoiceTranscript(">> Iris.", {
    voiceLoop: false,
    wakeWord: true,
    wakeCommandArmed: false
  });

  assert.equal(decision.action, "arm-wake-followup");
});

test("wake up mishear from diagnostics arms listening", () => {
  const decision = classifyVoiceTranscript("I are a wake up", {
    voiceLoop: false,
    wakeWord: true,
    wakeCommandArmed: false
  });

  assert.equal(decision.action, "arm-wake-followup");
});

test("ordinary I always speech cannot act as the wake word", () => {
  const decision = classifyVoiceTranscript("I always tell me one long sentence about law.", {
    voiceLoop: false,
    wakeWord: true,
    wakeCommandArmed: false
  });

  assert.equal(decision.action, "wait-for-wake");
  assert.equal(decision.prompt, "");
  assert.equal(decision.source, "wake-word");
});

test("common Iris wake word mishear plus bounded request submits directly", () => {
  for (const transcript of ["Irish, summarize this", "Hey, Iris, summarize this"]) {
    const decision = classifyVoiceTranscript(transcript, {
      voiceLoop: false,
      wakeWord: true,
      wakeCommandArmed: false
    });

    assert.equal(decision.action, "submit", transcript);
    assert.equal(decision.prompt, "summarize this", transcript);
    assert.equal(decision.source, "wake-word", transcript);
  }
});

test("armed wake word submits the follow-up utterance", () => {
  const decision = classifyVoiceTranscript("what can you do right now", {
    voiceLoop: false,
    wakeWord: true,
    wakeCommandArmed: true
  });

  assert.equal(decision.action, "submit");
  assert.equal(decision.prompt, "what can you do right now");
  assert.equal(decision.source, "wake-followup");
});

test("armed wake follow-up preserves wake-like words in the full utterance", () => {
  const transcript = "tell me why Iris and Ares appear in this story";
  const decision = classifyVoiceTranscript(transcript, {
    voiceLoop: false,
    wakeWord: true,
    wakeCommandArmed: true
  });

  assert.equal(decision.action, "submit");
  assert.equal(decision.prompt, transcript);
  assert.equal(decision.source, "wake-followup");
});

test("armed wake follow-up owns the full utterance even if stale voice-loop state remains", () => {
  const transcript = "Iris is part of the question, do not strip it";
  const decision = classifyVoiceTranscript(transcript, {
    voiceLoop: true,
    wakeWord: true,
    wakeCommandArmed: true
  });

  assert.equal(decision.action, "submit");
  assert.equal(decision.prompt, transcript);
  assert.equal(decision.source, "wake-followup");
});

test("embedded strong wake words in music or TV speech cannot activate Iris", () => {
  for (const transcript of [
    "The host said Iris would return after the commercial break",
    "Tonight the singer calls for Iris in the final chorus"
  ]) {
    const decision = classifyVoiceTranscript(transcript, {
      voiceLoop: false,
      wakeWord: true,
      wakeCommandArmed: false
    });

    assert.equal(decision.action, "wait-for-wake", transcript);
    assert.equal(decision.prompt, "", transcript);
  }
});

test("long explicit strong-prefix requests submit directly", () => {
  for (const transcript of [
    "Iris this is a longer real request with more than twelve spoken words after the wake phrase",
    "Iris the desktop test should keep working even when Alejandro gives a natural longer command"
  ]) {
    const decision = classifyVoiceTranscript(transcript, {
      voiceLoop: false,
      wakeWord: true,
      wakeCommandArmed: false
    });

    assert.equal(decision.action, "submit", transcript);
    assert.ok(decision.prompt.length > 64 || decision.prompt.split(/\s+/).length > 12, transcript);
    assert.equal(decision.source, "wake-word", transcript);
  }
});

test("strong-prefix requests over the old character bound still submit", () => {
  const decision = classifyVoiceTranscript(
    "Iris pneumonoultramicroscopicsilicovolcanoconiosis pseudopseudohypoparathyroidism",
    {
      voiceLoop: false,
      wakeWord: true,
      wakeCommandArmed: false
    }
  );

  assert.equal(decision.action, "submit");
  assert.equal(
    decision.prompt,
    "pneumonoultramicroscopicsilicovolcanoconiosis pseudopseudohypoparathyroidism"
  );
});

test("bounded strong-prefix requests still submit directly", () => {
  const decision = classifyVoiceTranscript("Hey Airis, summarize this page for me", {
    voiceLoop: false,
    wakeWord: true,
    wakeCommandArmed: false
  });

  assert.equal(decision.action, "submit");
  assert.equal(decision.prompt, "summarize this page for me");
  assert.equal(decision.source, "wake-word");
});

test("wake mode ignores speech that does not include Iris", () => {
  const decision = classifyVoiceTranscript("background conversation", {
    voiceLoop: false,
    wakeWord: true,
    wakeCommandArmed: false
  });

  assert.equal(decision.action, "wait-for-wake");
});

test("interruption word stops speech in any voice mode", () => {
  for (const transcript of ["Iris stop", "Irish stop", "Ares stop", "Hey, Iris, stop"]) {
    const decision = classifyVoiceTranscript(transcript, {
      voiceLoop: true,
      wakeWord: true,
      wakeCommandArmed: false,
      interruptionOnly: false
    });

    assert.equal(decision.action, "interrupt", transcript);
    assert.equal(decision.source, "interruption", transcript);
  }
});

test("bare Iris interrupts only during speech interruption listening", () => {
  const decision = classifyVoiceTranscript("Iris", {
    voiceLoop: true,
    wakeWord: true,
    wakeCommandArmed: false,
    interruptionOnly: true
  });

  assert.equal(decision.action, "interrupt");
  assert.equal(decision.source, "interruption");
});

test("wake-word interruption keeps the user's immediate correction", () => {
  for (const transcript of [
    "Iris, actually give me the shorter version",
    "Irish, actually give me the shorter version"
  ]) {
    const decision = classifyVoiceTranscript(transcript, {
      voiceLoop: true,
      wakeWord: true,
      wakeCommandArmed: false,
      interruptionOnly: true
    });

    assert.equal(decision.action, "interrupt", transcript);
    assert.equal(decision.prompt, "actually give me the shorter version", transcript);
    assert.equal(decision.source, "interruption", transcript);
  }
});

test("stop interruption keeps an explicit follow-up request", () => {
  const decision = classifyVoiceTranscript("stop, tell me just the answer", {
    voiceLoop: true,
    wakeWord: true,
    wakeCommandArmed: false,
    interruptionOnly: true
  });

  assert.equal(decision.action, "interrupt");
  assert.equal(decision.prompt, "tell me just the answer");
});

test("embedded Iris in ambient speech does not interrupt playback", () => {
  const decision = classifyVoiceTranscript("- Stamps it. - Iris. - And these.", {
    voiceLoop: false,
    wakeWord: true,
    wakeCommandArmed: false,
    interruptionOnly: true
  });

  assert.equal(decision.action, "ignore");
  assert.equal(decision.prompt, "");
  assert.equal(decision.source, "interruption");
});

test("speech interruption mode ignores non-interruption transcripts", () => {
  const decision = classifyVoiceTranscript("the assistant is speaking right now", {
    voiceLoop: true,
    wakeWord: true,
    wakeCommandArmed: false,
    interruptionOnly: true
  });

  assert.equal(decision.action, "ignore");
  assert.equal(decision.source, "interruption");
});

test("current interruption onset belongs to the active speech capture", () => {
  assert.equal(
    interruptionSignalIsCurrent(
      { runId: 8, requestId: 13 },
      { activeRunId: 8, activeRequestId: 13, speaking: true }
    ),
    true
  );
});

test("stale interruption signals cannot affect another speech run", () => {
  const current = { activeRunId: 8, activeRequestId: 13, speaking: true };
  assert.equal(interruptionSignalIsCurrent({ runId: 7, requestId: 13 }, current), false);
  assert.equal(interruptionSignalIsCurrent({ runId: 8, requestId: 12 }, current), false);
  assert.equal(
    interruptionSignalIsCurrent(
      { run_id: 8, request_id: 13 },
      { ...current, speaking: false }
    ),
    false
  );
  assert.equal(interruptionSignalIsCurrent({ runId: "not-a-run", requestId: 13 }, current), false);
});

test("interruption retries and speculative pauses are bounded", () => {
  assert.equal(interruptionCaptureAttemptAllowed(0), true);
  assert.equal(interruptionCaptureAttemptAllowed(95), true);
  assert.equal(interruptionCaptureAttemptAllowed(96), false);
  assert.equal(interruptionCandidatePauseAllowed(0), true);
  assert.equal(interruptionCandidatePauseAllowed(1), true);
  assert.equal(interruptionCandidatePauseAllowed(2), false);
  assert.equal(interruptionRetryDelayMs(0, 0), 100);
  assert.equal(interruptionRetryDelayMs(6, 2), 600);
  assert.equal(interruptionRetryDelayMs(500, 500), 600);
});

test("speaker interruption pauses require processed AEC audio", () => {
  assert.equal(
    interruptionSignalAllowsSpeculativePause({ aecApplied: true, rawFallbackAllowed: false }),
    true
  );
  assert.equal(
    interruptionSignalAllowsSpeculativePause({ aecApplied: false, rawFallbackAllowed: true }),
    true
  );
  assert.equal(
    interruptionSignalAllowsSpeculativePause({ aecApplied: false, rawFallbackAllowed: false }),
    false
  );
  assert.equal(interruptionSignalAllowsSpeculativePause({}), false);
});

test("interruption resume waits for an in-flight speculative pause", async () => {
  const coordinator = createInterruptionPauseCoordinator();
  const events = [];
  let releasePause;
  const pausePending = new Promise((resolve) => {
    releasePause = resolve;
  });

  coordinator.begin({
    runId: 8,
    requestId: 13,
    method: "web_audio",
    async pause() {
      events.push("pause-start");
      await pausePending;
      events.push("pause-end");
      return true;
    },
    async resume() {
      events.push("resume");
      return true;
    }
  });
  const resumed = coordinator.resume(8, 13);
  await Promise.resolve();
  assert.deepEqual(events, ["pause-start"]);

  releasePause();
  assert.deepEqual(await resumed, {
    matched: true,
    method: "web_audio",
    paused: true,
    resumed: true
  });
  assert.deepEqual(events, ["pause-start", "pause-end", "resume"]);
});

test("stale interruption requests cannot resume another playback", async () => {
  const coordinator = createInterruptionPauseCoordinator();
  let resumeCount = 0;
  coordinator.begin({
    runId: 8,
    requestId: 13,
    method: "native_cpal",
    pause: async () => true,
    resume: async () => {
      resumeCount += 1;
      return true;
    }
  });

  assert.deepEqual(await coordinator.resume(8, 12), {
    matched: false,
    method: "none",
    paused: false,
    resumed: false
  });
  assert.equal(resumeCount, 0);
  assert.deepEqual(await coordinator.resume(8, 13), {
    matched: true,
    method: "native_cpal",
    paused: true,
    resumed: true
  });
  assert.equal(resumeCount, 1);
});

test("a result resolved before onset prevents a late speculative pause", async () => {
  const coordinator = createInterruptionPauseCoordinator();
  let pauseCount = 0;

  assert.deepEqual(await coordinator.resume(8, 13), {
    matched: false,
    method: "none",
    paused: false,
    resumed: false
  });
  assert.equal(
    await coordinator.begin({
      runId: 8,
      requestId: 13,
      method: "native_cpal",
      pause: async () => {
        pauseCount += 1;
        return true;
      },
      resume: async () => true
    }),
    false
  );
  assert.equal(pauseCount, 0);
});

test("every playback backend treats a failed resume as terminal", async () => {
  for (const method of ["native_cpal", "web_audio", "html_audio"]) {
    const coordinator = createInterruptionPauseCoordinator();
    await coordinator.begin({
      runId: 8,
      requestId: 13,
      method,
      pause: async () => true,
      resume: async () => false
    });
    const outcome = await coordinator.resume(8, 13);
    assert.equal(outcome.method, method);
    assert.equal(interruptionResumeRequiresCancellation(outcome), true);
  }
  assert.equal(
    interruptionResumeRequiresCancellation({
      matched: true,
      paused: false,
      resumed: false
    }),
    false
  );
});

test("ambient captions are ignored in voice loop", () => {
  for (const transcript of [
    "[MUSIC PLAYING]",
    "(upbeat music)",
    "[BLANK_AUDIO]",
    "[silence]",
    "[inaudible]",
    "[typing]",
    "(keyboard clicking)"
  ]) {
    const decision = classifyVoiceTranscript(transcript, {
      voiceLoop: true,
      wakeWord: true,
      wakeCommandArmed: false
    });

    assert.equal(decision.action, "ignore");
  }
});

test("empty microphone captures are nonfatal ASR diagnostics", () => {
  assert.deepEqual(classifyAsrError("microphone produced no audio samples"), {
    severity: "nonfatal",
    event: "native_asr_no_input",
    status: "No speech transcript captured."
  });
});

test("transient Windows audio handle failures are nonfatal ASR diagnostics", () => {
  assert.deepEqual(
    classifyAsrError(
      "Native ASR capture failed because the Windows audio device handle became invalid. Iris will retry listening."
    ),
    {
      severity: "nonfatal",
      event: "native_asr_transient_error",
      status: "Audio capture reset. Retrying microphone."
    }
  );
  assert.deepEqual(
    classifyAsrError('called `Result::unwrap()` on an `Err` value: HRESULT(0x80070006), "The handle is invalid."'),
    {
      severity: "nonfatal",
      event: "native_asr_transient_error",
      status: "Audio capture reset. Retrying microphone."
    }
  );
});

test("missing default microphone reports actionable device recovery", () => {
  assert.deepEqual(classifyAsrError("no default microphone input device found"), {
    severity: "error",
    event: "native_asr_error",
    status: "No microphone is available. Connect one and choose it as the Windows default input device."
  });
});

test("unexpected ASR failures remain errors", () => {
  assert.deepEqual(classifyAsrError("model crashed"), {
    severity: "error",
    event: "native_asr_error",
    status: "model crashed"
  });
});

test("wake listener backs off after empty or ambient captures", () => {
  assert.equal(wakeRestartDelayMs("wake", "", "ignore"), 300);
  assert.equal(
    wakeRestartDelayMs("wake", "background television", "wait-for-wake"),
    300
  );
  assert.equal(wakeRestartDelayMs("wake", "", "ignore", 3), 300);
  assert.equal(wakeRestartDelayMs("wake", "background television", "wait-for-wake", 6), 300);
  assert.equal(wakeRestartDelayMs("wake", "Iris hello", "submit"), 300);
  assert.equal(wakeRestartDelayMs("push", "", "ignore"), 300);
});

test("push-to-talk can override an active wake listener", () => {
  assert.equal(
    voiceButtonAction({ listening: true, activeListenMode: "wake" }),
    "switch-to-push"
  );
  assert.equal(
    voiceButtonAction({ listening: true, activeListenMode: "push" }),
    "stop-push"
  );
  assert.equal(
    voiceButtonAction({ listening: false, activeListenMode: "idle" }),
    "start-push"
  );
});

test("push-to-talk mode submits without requiring the wake word", () => {
  const state = voiceTranscriptStateForMode("push", {
    voiceLoop: false,
    wakeWord: true,
    wakeCommandArmed: false
  });

  const decision = classifyVoiceTranscript("tell me a short answer", state);

  assert.equal(decision.action, "submit");
  assert.equal(decision.prompt, "tell me a short answer");
  assert.equal(decision.source, "voice");
});

test("wake silence keeps armed status instead of showing a failure", () => {
  assert.equal(noSpeechStatusForMode("wake"), "Wake word armed. Say Iris.");
  assert.equal(noSpeechStatusForMode("push"), "No speech transcript captured.");
});

test("armed wake follow-up disarms after repeated empty captures", () => {
  assert.equal(shouldDisarmWakeFollowupAfterMisses(0), false);
  assert.equal(shouldDisarmWakeFollowupAfterMisses(2), false);
  assert.equal(shouldDisarmWakeFollowupAfterMisses(3), true);
});

test("raw wake transcripts are hidden until a decision owns the UI", () => {
  for (const action of ["ignore", "wait-for-wake", "arm-wake-followup", "submit", "interrupt"]) {
    assert.equal(shouldDisplayVoiceTranscript({ action }), false);
  }
});

test("active voice session uses loop endpointing before wake endpointing", () => {
  assert.equal(
    nextVoiceListenMode({ wakeCommandArmed: false, wakeWord: true, voiceLoop: true }),
    "loop"
  );
});

test("sleep mode forces wake endpointing before any active session", () => {
  assert.equal(
    nextVoiceListenMode({ sleeping: true, wakeCommandArmed: true, wakeWord: true, voiceLoop: true }),
    "wake"
  );
});

test("armed wake follow-up uses command endpointing before voice session endpointing", () => {
  assert.equal(
    nextVoiceListenMode({ wakeCommandArmed: true, wakeWord: true, voiceLoop: true }),
    "command"
  );
  assert.equal(
    nextVoiceListenMode({ wakeCommandArmed: false, wakeWord: true, voiceLoop: false }),
    "wake"
  );
  assert.equal(
    nextVoiceListenMode({ wakeCommandArmed: false, wakeWord: false, voiceLoop: true }),
    "loop"
  );
});

test("voice submissions continue the active conversation session", () => {
  for (const source of ["voice", "voice-loop", "wake-word", "wake-followup", "voice-session"]) {
    assert.equal(voiceSubmitKeepsSession(source), true);
  }
  for (const source of ["typed", "screen-probe", "image-probe", "memory"]) {
    assert.equal(voiceSubmitKeepsSession(source), false);
  }
  assert.equal(
    shouldContinueVoiceSession({ action: "submit", source: "wake-word" }),
    true
  );
  assert.equal(
    shouldContinueVoiceSession({ action: "submit", source: "wake-followup" }),
    true
  );
  assert.equal(
    shouldContinueVoiceSession({ action: "submit", source: "voice-loop" }),
    true
  );
  assert.equal(
    shouldContinueVoiceSession({ action: "wait-for-wake", source: "wake-word" }),
    false
  );
});
