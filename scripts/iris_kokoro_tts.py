import argparse
from pathlib import Path

import soundfile as sf
from kokoro_onnx import Kokoro


def main() -> int:
    parser = argparse.ArgumentParser(description="Project Iris Kokoro ONNX local TTS helper")
    parser.add_argument("--text", required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--voices", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--voice", default="af_heart")
    parser.add_argument("--speed", type=float, default=1.0)
    parser.add_argument("--lang", default="en-us")

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

    output_path.parent.mkdir(parents=True, exist_ok=True)

    kokoro = Kokoro(str(model_path), str(voices_path))
    samples, sample_rate = kokoro.create(
        args.text,
        voice=args.voice,
        speed=args.speed,
        lang=args.lang,
    )

    sf.write(str(output_path), samples, sample_rate)
    print(str(output_path))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
