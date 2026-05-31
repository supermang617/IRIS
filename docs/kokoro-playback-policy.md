# Kokoro Playback Policy

Status: active.

Kokoro speech playback must not clip the start of generated speech.

Canonical rule:

- scripts/play_iris_wav_bounded.ps1 accepts only WavPath.
- Callers must use WavPath.
- Do not add a Path alias unless an external compatibility requirement is proven.
- Bounded playback pads generated WAV files with leading silence.
- Default lead silence: 1000 ms.
- Default trailing silence: 250 ms.
- Playback remains bounded and stops after the requested playback window.

Canonical scripts:

- scripts/speak_iris_kokoro.ps1
- scripts/play_iris_wav_bounded.ps1
- scripts/pad_iris_wav.py
- scripts/validate_iris_kokoro_full_playback.ps1

Validation phrase:

Hello. This is Iris. This is a voice test.

If the user hears only the end of the phrase, increase LeadSilenceMs before changing Kokoro, Qwen, or STT.
