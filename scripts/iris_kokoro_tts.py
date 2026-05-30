import argparse
from pathlib import Path

import numpy as np
import soundfile as sf
from kokoro_onnx import Kokoro


def add_silence(samples: np.ndarray, sample_rate: int, lead_ms: int, tail_ms: int) -> np.ndarray:
    if lead_ms <= 0 and tail_ms <= 0:
        return samples

    samples = np.asarray(samples)

    lead_count = max(0, int(sample_rate * lead_ms / 1000))
    tail_count = max(0, int(sample_rate * tail_ms / 1000))

    if samples.ndim == 1:
        lead = np.zeros((lead_count,), dtype=samples.dtype)
        tail = np.zeros((tail_count,), dtype=samples.dtype)
    else:
        channels = samples.shape[1]
        lead = np.zeros((lead_count, channels), dtype=samples.dtype)
        tail = np.zeros((tail_count, channels), dtype=samples.dtype)

    return np.concatenate([lead, samples, tail], axis=0)


def main() -> int:
    parser = argparse.ArgumentParser(description="Project Iris Kokoro ONNX local TTS helper")
    parser.add_argument("--text", required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--voices", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--voice", default="af_heart")
    parser.add_argument("--speed", type=float, default=1.0)
    parser.add_argument("--lang", default="en-us")
    parser.add_argument("--lead-silence-ms", type=int, default=700)
    parser.add_argument("--tail-silence-ms", type=int, default=250)

    args = parser.parse_args()

    model_path = Path(args.model)
    voices_path = Path(args.voices)
    output_path = Path(args.output)

    if not model_path.exists():
        raise FileNotFoundError(f"Kokoro model not found: {model_path}")

    if not voices_path.exists():
        raise FileNotFoundError(f"Kokoro voices file not found: {voices_path}")

    if not args.text.strip():
        raise ValueError("Text must not be empty")

    if args.lead_silence_ms < 0:
        raise ValueError("lead-silence-ms must not be negative")

    if args.tail_silence_ms < 0:
        raise ValueError("tail-silence-ms must not be negative")

    output_path.parent.mkdir(parents=True, exist_ok=True)

    kokoro = Kokoro(str(model_path), str(voices_path))
    samples, sample_rate = kokoro.create(
        args.text,
        voice=args.voice,
        speed=args.speed,
        lang=args.lang,
    )

    samples = add_silence(
        samples=np.asarray(samples),
        sample_rate=sample_rate,
        lead_ms=args.lead_silence_ms,
        tail_ms=args.tail_silence_ms,
    )

    sf.write(str(output_path), samples, sample_rate)
    print(str(output_path))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
