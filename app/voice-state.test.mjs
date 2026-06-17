import assert from "node:assert/strict";
import { test } from "node:test";
import {
  classifyAsrError,
  classifyVoiceTranscript,
  nextVoiceListenMode,
  shouldDisplayVoiceTranscript,
  wakeRestartDelayMs
} from "./voice-state.js";

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

test("common Iris wake word mishear arms listening", () => {
  const decision = classifyVoiceTranscript("Hi Im Eric Swayup", {
    voiceLoop: false,
    wakeWord: true,
    wakeCommandArmed: false
  });

  assert.equal(decision.action, "arm-wake-followup");
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

test("Iris command misheard as I always still submits request", () => {
  const decision = classifyVoiceTranscript("I always tell me one long sentence about law.", {
    voiceLoop: false,
    wakeWord: true,
    wakeCommandArmed: false
  });

  assert.equal(decision.action, "submit");
  assert.equal(decision.prompt, "tell me one long sentence about law.");
  assert.equal(decision.source, "wake-word");
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

test("wake mode ignores speech that does not include Iris", () => {
  const decision = classifyVoiceTranscript("background conversation", {
    voiceLoop: false,
    wakeWord: true,
    wakeCommandArmed: false
  });

  assert.equal(decision.action, "wait-for-wake");
});

test("interruption word stops speech in any voice mode", () => {
  const decision = classifyVoiceTranscript("Iris stop", {
    voiceLoop: true,
    wakeWord: true,
    wakeCommandArmed: false,
    interruptionOnly: false
  });

  assert.equal(decision.action, "interrupt");
  assert.equal(decision.source, "interruption");
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

test("embedded Iris interrupts during speech interruption listening", () => {
  const decision = classifyVoiceTranscript("- Stamps it. - Iris. - And these.", {
    voiceLoop: false,
    wakeWord: true,
    wakeCommandArmed: false,
    interruptionOnly: true
  });

  assert.equal(decision.action, "interrupt");
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

test("unexpected ASR failures remain errors", () => {
  assert.deepEqual(classifyAsrError("model crashed"), {
    severity: "error",
    event: "native_asr_error",
    status: "model crashed"
  });
});

test("wake listener backs off after empty or ambient captures", () => {
  assert.equal(wakeRestartDelayMs("wake", "", "ignore"), 1200);
  assert.equal(
    wakeRestartDelayMs("wake", "background television", "wait-for-wake"),
    2500
  );
  assert.equal(wakeRestartDelayMs("wake", "", "ignore", 3), 5000);
  assert.equal(wakeRestartDelayMs("wake", "background television", "wait-for-wake", 6), 10000);
  assert.equal(wakeRestartDelayMs("wake", "Iris hello", "submit"), 650);
  assert.equal(wakeRestartDelayMs("push", "", "ignore"), 650);
});

test("raw wake transcripts are hidden until a decision owns the UI", () => {
  for (const action of ["ignore", "wait-for-wake", "arm-wake-followup", "submit", "interrupt"]) {
    assert.equal(shouldDisplayVoiceTranscript({ action }), false);
  }
});

test("armed wake follow-up uses command endpointing instead of wake endpointing", () => {
  assert.equal(
    nextVoiceListenMode({ wakeCommandArmed: true, wakeWord: true, voiceLoop: false }),
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
