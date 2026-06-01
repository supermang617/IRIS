import argparse
import sys
from pathlib import Path

import soundfile as sf
from kokoro_onnx import Kokoro


def main() -> int:
    parser = argparse.ArgumentParser(description="Project Iris Kokoro ONNX TTS helper")
    parser.add_argument("--model", required=True)
    parser.add_argument("--voices", required=True)
    parser.add_argument("--voice", required=True)
    parser.add_argument("--lang", default="en-us")
    parser.add_argument("--speed", type=float, default=1.0)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    text = sys.stdin.read().strip()
    if not text:
        print("empty text", file=sys.stderr)
        return 2

    model_path = Path(args.model)
    voices_path = Path(args.voices)
    output_path = Path(args.output)
    if not model_path.exists():
        print(f"missing Kokoro model: {model_path}", file=sys.stderr)
        return 3
    if not voices_path.exists():
        print(f"missing Kokoro voices: {voices_path}", file=sys.stderr)
        return 4

    output_path.parent.mkdir(parents=True, exist_ok=True)
    kokoro = Kokoro(str(model_path), str(voices_path))
    samples, sample_rate = kokoro.create(
        text,
        voice=args.voice,
        speed=args.speed,
        lang=args.lang,
    )
    sf.write(str(output_path), samples, sample_rate)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
