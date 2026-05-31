# Kokoro Playback Policy

Status: active.

Kokoro speech playback must not clip the start of generated speech.

Canonical rule:

- scripts/play_iris_wav_bounded.ps1 accepts only WavPath.
- Active callers must pass WavPath.
- Do not add a Path alias unless an external compatibility requirement is proven.
- Bounded playback pads generated WAV files with leading silence.
- Default lead silence: 1000 ms.
- Default trailing silence: 250 ms.
- Playback remains bounded and stops after the requested playback window.

Strict run policy:

- Expected negative tests must not dump red stack traces during milestone runs.
- Real subprocess failures must stop immediately.
- Use captured subprocess execution for milestone validation.

Validation phrase:

Hello. This is Iris. This is a voice test.
