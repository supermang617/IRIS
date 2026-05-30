import argparse
import os
import soundfile as sf
from kokoro_onnx import Kokoro


def main() -> None:
    parser = argparse.ArgumentParser(description="Project Iris Kokoro ONNX TTS helper")
    parser.add_argument("--text", required=True)
    parser.add_argument("--voice", default="af_heart")
    parser.add_argument("--speed", type=float, default=1.0)
    parser.add_argument("--out", default="iris_output.wav")
    parser.add_argument("--model", default="kokoro-v1.0.onnx")
    parser.add_argument("--voices", default="voices-v1.0.bin")
    args = parser.parse_args()

    base_dir = os.path.dirname(os.path.abspath(__file__))
    model_path = os.path.join(base_dir, args.model)
    voices_path = os.path.join(base_dir, args.voices)
    output_path = os.path.abspath(args.out)

    if not args.text.strip():
        raise ValueError("Text must not be empty.")

    if not os.path.exists(model_path):
        raise FileNotFoundError(f"Missing Kokoro model file: {model_path}")

    if not os.path.exists(voices_path):
        raise FileNotFoundError(f"Missing Kokoro voices file: {voices_path}")

    kokoro = Kokoro(model_path, voices_path)

    audio, sample_rate = kokoro(
        args.text,
        voice=args.voice,
        speed=args.speed,
    )

    sf.write(output_path, audio, sample_rate)
    print(output_path)


if __name__ == "__main__":
    main()
