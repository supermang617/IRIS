# Voice Input Boundary

Status: active.

Iris voice input is explicit, bounded, one-shot, and permission-based.

Current milestone:

voice input -> transcript -> Qwen response -> Kokoro speech

Recognition policy:

- Test milestones use bounded phrase recognition by default.
- Low-confidence transcripts are rejected before they reach Qwen.
- Current default minimum confidence is `0.35`.
- Anchor words are diagnostics unless `-StrictAnchorGate` is used.
- If phrase recognition passes but dictation is poor, the remaining issue is STT quality, not Qwen or Kokoro.

Canonical scripts:

- `scripts/listen_iris_local_speak.ps1`
- `scripts/verify_iris_voice_input_boundary.ps1`
- `scripts/test_iris_voice_prompt_to_kokoro.ps1`

Expected phrase for current milestone:

`Testing now, Iris local voice test.`
