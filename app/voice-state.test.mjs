import assert from "node:assert/strict";
import { test } from "node:test";
import { classifyVoiceTranscript } from "./voice-state.js";

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

test("music and silence captions are ignored in voice loop", () => {
  for (const transcript of ["[MUSIC PLAYING]", "(upbeat music)", "[BLANK_AUDIO]", "[silence]"]) {
    const decision = classifyVoiceTranscript(transcript, {
      voiceLoop: true,
      wakeWord: true,
      wakeCommandArmed: false
    });

    assert.equal(decision.action, "ignore");
  }
});
