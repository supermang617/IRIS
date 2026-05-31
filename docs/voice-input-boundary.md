# Voice Input Boundary

Status: active.

Iris voice input is explicit, bounded, one-shot, and permission-based.

Current milestone:

voice input -> transcript -> Qwen response -> Kokoro speech

Boundary contract:

- Use one `AnchorWordsCsv` string across nested PowerShell calls.
- Do not pass repeated `-AnchorWords` parameters.
- Do not pass raw `string[]` values into nested `powershell -File` calls.
- Live voice tests require a non-empty transcript.
- Anchor words are diagnostics by default because Windows Speech may mishear words.
- Use `-StrictAnchorGate` only for calibration tests.

Canonical scripts:

- `scripts/listen_iris_local_speak.ps1`
- `scripts/verify_iris_voice_input_boundary.ps1`
- `scripts/test_iris_voice_prompt_to_kokoro.ps1`

Expected phrase for current milestone:

`Testing now, Iris local voice test.`
