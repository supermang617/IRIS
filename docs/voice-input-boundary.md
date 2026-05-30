# Voice Input Boundary

Status: active.

Iris voice input is explicit, bounded, one-shot, and permission-based.

Canonical scripts:

- `scripts/listen_iris_local_speak.ps1`
- `scripts/verify_iris_voice_input_boundary.ps1`
- `scripts/test_iris_voice_prompt_to_kokoro.ps1`

Boundary contract:

- External/nested PowerShell calls pass anchor words as one CSV string.
- Do not pass a raw `string[]` through a nested `powershell -File` call.
- This avoids PowerShell treating words after the first one as invalid positional arguments.

Expected phrase for current milestone:

`Testing now, Iris local voice test.`
