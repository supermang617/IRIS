import argparse
import math
from pathlib import Path

import numpy as np
import soundfile as sf
from kokoro_onnx import Kokoro


def make_silence(samples: np.ndarray, sample_rate: int, ms: int) -> np.ndarray:
    count = max(0, int(sample_rate * ms / 1000))

    if samples.ndim == 1:
        return np.zeros((count,), dtype=samples.dtype)

    channels = samples.shape[1]
    return np.zeros((count, channels), dtype=samples.dtype)


def make_wake_signal(
    samples: np.ndarray,
    sample_rate: int,
    ms: int,
    amplitude: float,
    frequency_hz: float,
) -> np.ndarray:
    count = max(0, int(sample_rate * ms / 1000))

    if count == 0 or amplitude <= 0:
        return make_silence(samples, sample_rate, 0)

    t = np.arange(count, dtype=np.float32) / float(sample_rate)
    tone = amplitude * np.sin(2.0 * math.pi * frequency_hz * t)

    ramp_count = min(count // 2, max(1, int(sample_rate * 0.05)))

    if ramp_count > 0:
        ramp_in = np.linspace(0.0, 1.0, ramp_count, dtype=np.float32)
        ramp_out = np.linspace(1.0, 0.0, ramp_count, dtype=np.float32)
        tone[:ramp_count] *= ramp_in
        tone[-ramp_count:] *= ramp_out

    tone = tone.astype(samples.dtype, copy=False)

    if samples.ndim == 1:
        return tone

    channels = samples.shape[1]
    return np.repeat(tone[:, np.newaxis], channels, axis=1)


def add_preroll_and_tail(
    samples: np.ndarray,
    sample_rate: int,
    wake_signal_ms: int,
    wake_signal_amplitude: float,
    wake_signal_hz: float,
    lead_silence_ms: int,
    tail_silence_ms: int,
) -> np.ndarray:
    samples = np.asarray(samples)

    wake_signal = make_wake_signal(
        samples=samples,
        sample_rate=sample_rate,
        ms=wake_signal_ms,
        amplitude=wake_signal_amplitude,
        frequency_hz=wake_signal_hz,
    )

    lead_silence = make_silence(samples, sample_rate, lead_silence_ms)
    tail_silence = make_silence(samples, sample_rate, tail_silence_ms)

    return np.concatenate([wake_signal, lead_silence, samples, tail_silence], axis=0)


def main() -> int:
    parser = argparse.ArgumentParser(description="Project Iris Kokoro ONNX local TTS helper")
    parser.add_argument("--text", required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--voices", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--voice", default="af_heart")
    parser.add_argument("--speed", type=float, default=0.95)
    parser.add_argument("--lang", default="en-us")
    parser.add_argument("--wake-signal-ms", type=int, default=900)
    parser.add_argument("--wake-signal-amplitude", type=float, default=0.004)
    parser.add_argument("--wake-signal-hz", type=float, default=220.0)
    parser.add_argument("--lead-silence-ms", type=int, default=300)
    parser.add_argument("--tail-silence-ms", type=int, default=300)

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

    if args.wake_signal_ms < 0:
        raise ValueError("wake-signal-ms must not be negative")

    if args.wake_signal_amplitude < 0:
        raise ValueError("wake-signal-amplitude must not be negative")

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

    samples = add_preroll_and_tail(
        samples=np.asarray(samples),
        sample_rate=sample_rate,
        wake_signal_ms=args.wake_signal_ms,
        wake_signal_amplitude=args.wake_signal_amplitude,
        wake_signal_hz=args.wake_signal_hz,
        lead_silence_ms=args.lead_silence_ms,
        tail_silence_ms=args.tail_silence_ms,
    )

    sf.write(str(output_path), samples, sample_rate)
    print(str(output_path))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
