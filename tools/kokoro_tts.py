import argparse
import base64
import io
import json
import sys
from pathlib import Path

import soundfile as sf
import numpy as np
from kokoro_onnx import Kokoro

LEAD_SILENCE_SECONDS = 0.35
TAIL_SILENCE_SECONDS = 0.12


def main() -> int:
    parser = argparse.ArgumentParser(description="Project Iris Kokoro ONNX TTS helper")
    parser.add_argument("--model", required=True)
    parser.add_argument("--voices", required=True)
    parser.add_argument("--voice", required=True)
    parser.add_argument("--lang", default="en-us")
    parser.add_argument("--speed", type=float, default=1.0)
    parser.add_argument("--output")
    parser.add_argument("--server", action="store_true")
    args = parser.parse_args()

    model_path = Path(args.model)
    voices_path = Path(args.voices)
    if not model_path.exists():
        print(f"missing Kokoro model: {model_path}", file=sys.stderr)
        return 3
    if not voices_path.exists():
        print(f"missing Kokoro voices: {voices_path}", file=sys.stderr)
        return 4

    kokoro = Kokoro(str(model_path), str(voices_path))
    if args.server:
        return run_server(kokoro, args.voice, args.speed, args.lang)

    if not args.output:
        print("missing --output", file=sys.stderr)
        return 5
    text = sys.stdin.read().strip()
    if not text:
        print("empty text", file=sys.stderr)
        return 2
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    samples, sample_rate = kokoro.create(
        text,
        voice=args.voice,
        speed=args.speed,
        lang=args.lang,
    )
    sf.write(str(output_path), pad_silence(samples, sample_rate), sample_rate)
    return 0


def pad_silence(samples, sample_rate):
    if sample_rate <= 0:
        return samples
    lead = np.zeros(int(sample_rate * LEAD_SILENCE_SECONDS), dtype=samples.dtype)
    tail = np.zeros(int(sample_rate * TAIL_SILENCE_SECONDS), dtype=samples.dtype)
    return np.concatenate((lead, samples, tail))


def run_server(kokoro: Kokoro, voice: str, speed: float, lang: str) -> int:
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        request_id = None
        try:
            request = json.loads(line)
            request_id = request.get("id")
            text = str(request.get("text", "")).strip()
            if not text:
                raise ValueError("empty text")
            samples, sample_rate = kokoro.create(
                text,
                voice=voice,
                speed=speed,
                lang=lang,
            )
            wav = io.BytesIO()
            sf.write(wav, pad_silence(samples, sample_rate), sample_rate, format="WAV")
            response = {
                "id": request_id,
                "ok": True,
                "wav_b64": base64.b64encode(wav.getvalue()).decode("ascii"),
            }
        except Exception as error:
            response = {
                "id": request_id,
                "ok": False,
                "error": str(error),
            }
        print(json.dumps(response, separators=(",", ":")), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
