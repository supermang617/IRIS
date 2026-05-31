# Voice Input Boundary

Status: active.

Iris voice input is explicit, bounded, one-shot, and permission-based.

Current milestone:

voice input -> transcript -> Qwen response -> Kokoro speech

Gate policy:

- Live voice tests require a non-empty transcript.
- The transcript must pass a quality gate before Qwen receives it.
- Current test phrase requires at least two anchor words from: testing, voice, test.
- Bad transcripts must stop before model response.
- If the listener hears gibberish, calibrate Windows microphone input instead of changing Qwen or Kokoro.

Canonical scripts:

- scripts/listen_iris_local_speak.ps1
- scripts/verify_iris_voice_input_boundary.ps1
- scripts/verify_iris_transcript_quality_gate.ps1
- scripts/test_iris_voice_prompt_to_kokoro.ps1

Expected phrase for current milestone:

Testing now, Iris local voice test.
