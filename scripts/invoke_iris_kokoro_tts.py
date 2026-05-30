import argparse
import os
import sys
import wave

def fail(message: str, code: int) -> None:
    print(message, file=sys.stderr)
    sys.exit(code)

def load_kokoro(model_path: str, voices_path: str):
    try:
        from kokoro_onnx import Kokoro
    except Exception as exc:
        fail(f"Missing Python package kokoro_onnx: {exc}", 20)

    attempts = [
        lambda: Kokoro(model_path, voices_path),
        lambda: Kokoro(model_path=model_path, voices_path=voices_path),
    ]

    last_error = None

    for attempt in attempts:
        try:
            return attempt()
        except Exception as exc:
            last_error = exc

    fail(f"Could not initialize Kokoro: {last_error}", 21)

def synthesize(kokoro, text: str, voice_list: list[str], speed: float, lang: str):
    last_error = None

    for voice in voice_list:
        voice = voice.strip()
        if not voice:
            continue

        attempts = [
            lambda: kokoro.create(text, voice=voice, speed=speed, lang=lang),
            lambda: kokoro.create(text, voice=voice, speed=speed),
            lambda: kokoro.create(text, voice=voice),
            lambda: kokoro.create(text),
        ]

        for attempt in attempts:
            try:
                result = attempt()

                if isinstance(result, tuple) and len(result) >= 2:
                    a = result[0]
                    b = result[1]

                    if isinstance(a, (int, float)):
                        return b, int(a), voice

                    return a, int(b), voice

                return result, 24000, voice
            except Exception as exc:
                last_error = exc

    fail(f"Kokoro synthesis failed. Last error: {last_error}", 22)

def write_wav(path: str, samples, sample_rate: int):
    try:
        import numpy as np
    except Exception as exc:
        fail(f"Missing numpy: {exc}", 23)

    arr = np.asarray(samples, dtype=np.float32).reshape(-1)
    arr = np.nan_to_num(arr)
    arr = np.clip(arr, -1.0, 1.0)

    pcm = (arr * 32767.0).astype("<i2").tobytes()

    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)

    with wave.open(path, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(int(sample_rate))
        wav.writeframes(pcm)

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True)
    parser.add_argument("--voices", required=True)
    parser.add_argument("--text", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--voice", default="af_heart,af_bella,af_sky,am_adam")
    parser.add_argument("--speed", type=float, default=1.0)
    parser.add_argument("--lang", default="en-us")
    args = parser.parse_args()

    if not os.path.isfile(args.model):
        fail(f"Kokoro model file not found: {args.model}", 30)

    if not os.path.isfile(args.voices):
        fail(f"Kokoro voices file not found: {args.voices}", 31)

    kokoro = load_kokoro(args.model, args.voices)
    samples, sample_rate, voice = synthesize(kokoro, args.text, args.voice.split(","), args.speed, args.lang)

    write_wav(args.out, samples, sample_rate)

    print(f"Kokoro WAV written: {args.out}")
    print(f"Sample rate: {sample_rate}")
    print(f"Voice: {voice}")

    return 0

if __name__ == "__main__":
    raise SystemExit(main())
