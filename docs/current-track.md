# Current Track

Use this file to avoid drifting from the roadmap.

## Current goal

Stabilize the first basic text and voice response milestone.

## Voice direction

Current open-source local TTS backend:

Kokoro ONNX

Current default voice:

af_heart

Current playback fix:

Kokoro output includes lead-in silence before speech so the first words are not clipped by device wake-up latency.

Default lead-in silence:

700 ms

Default tail silence:

250 ms

## Useful voice commands

Test Kokoro voice only:

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\speak_iris_kokoro.ps1 -Text "Hello, I am Iris. This is my Kokoro voice."

Test with longer lead-in if first words are still clipped:

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\speak_iris_kokoro.ps1 -Text "Hello, I am Iris. This is my Kokoro voice." -LeadSilenceMs 1000

Text prompt to Kokoro spoken response:

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\test_iris_text_voice_response.ps1 -Prompt "hello iris"

Windows fallback:

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\test_iris_text_voice_response.ps1 -Prompt "hello iris" -TtsBackend Windows

## Do next

Verify the Kokoro lead-in silence fix.

Then run typed prompt -> Iris model -> response post-check -> Kokoro spoken output.

## Do not do yet

Do not add screen capture, OCR, memory database, full UI, dashboard, always-listening voice, or full Rust Kokoro integration before the basic text/voice milestone is stable.
