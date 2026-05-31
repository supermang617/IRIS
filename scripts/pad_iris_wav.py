import argparse
import os
import wave

def main():
    parser = argparse.ArgumentParser(description='Pad a PCM WAV with leading/trailing silence.')
    parser.add_argument('--inwav', required=True)
    parser.add_argument('--outwav', required=True)
    parser.add_argument('--lead-ms', type=int, default=750)
    parser.add_argument('--trail-ms', type=int, default=250)
    args = parser.parse_args()

    inwav = os.path.abspath(args.inwav)
    outwav = os.path.abspath(args.outwav)

    if not os.path.exists(inwav):
        raise SystemExit(f'Missing input WAV: {inwav}')

    os.makedirs(os.path.dirname(outwav), exist_ok=True)

    with wave.open(inwav, 'rb') as src:
        params = src.getparams()
        channels = src.getnchannels()
        sample_width = src.getsampwidth()
        frame_rate = src.getframerate()
        frames = src.readframes(src.getnframes())

    lead_frames = max(0, int(frame_rate * args.lead_ms / 1000))
    trail_frames = max(0, int(frame_rate * args.trail_ms / 1000))
    silent_frame = b'\x00' * channels * sample_width
    padded = (silent_frame * lead_frames) + frames + (silent_frame * trail_frames)

    with wave.open(outwav, 'wb') as dst:
        dst.setparams(params)
        dst.writeframes(padded)

    original_seconds = len(frames) / float(channels * sample_width * frame_rate)
    padded_seconds = len(padded) / float(channels * sample_width * frame_rate)
    print(f'input={inwav}')
    print(f'output={outwav}')
    print(f'lead_ms={args.lead_ms}')
    print(f'trail_ms={args.trail_ms}')
    print(f'original_seconds={original_seconds:.3f}')
    print(f'padded_seconds={padded_seconds:.3f}')

if __name__ == '__main__':
    main()
