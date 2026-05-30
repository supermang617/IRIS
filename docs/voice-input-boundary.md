# Voice Input Boundary

Status: active.

Iris voice input is explicit, bounded, one-shot, and permission-based.

Canonical scripts:

- `scripts/listen_iris_local_speak.ps1`
- `scripts/verify_iris_voice_input_boundary.ps1`
- `scripts/test_iris_voice_prompt_to_kokoro.ps1`

Boundary contract:

- Nested PowerShell calls pass anchor words as one CSV string.
- Do not pass a raw `string[]` through nested `powershell -File`.
- The verifier supports `-SimulatedTranscript` so script syntax and argument contracts can be tested without microphone input.

Expected phrase for the current milestone:

`Testing now, Iris local voice test.`

If the simulated boundary test passes but live capture fails, the remaining issue is Windows microphone input or Windows Speech recognition, not Qwen or Kokoro.
