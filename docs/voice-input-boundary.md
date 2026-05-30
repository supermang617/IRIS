# Voice Input Boundary

Status: active.

Iris voice input is explicit, bounded, one-shot, and permission-based.

Current milestone:

voice input -> transcript -> Qwen response -> Kokoro speech

Gate policy:

- Live voice tests require a non-empty transcript.
- Anchor words are diagnostics by default because Windows Speech recognition may mishear words.
- Use `-StrictAnchorGate` only for strict calibration tests.
- Do not block the pipeline just because Windows Speech misheard one word.

Canonical scripts:

- `scripts/listen_iris_local_speak.ps1`
- `scripts/verify_iris_voice_input_boundary.ps1`
- `scripts/test_iris_voice_prompt_to_kokoro.ps1`

Expected phrase for current milestone:

`Testing now, Iris local voice test.`
