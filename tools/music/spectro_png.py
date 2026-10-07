"""WAV → 로그 주파수 스펙트로그램 PNG (numpy·zlib 만, matplotlib 불필요).

    python tools/music/spectro_png.py in.wav out.png [마디 길이(초)] [시작 오프셋(초)]
세로 = 30Hz~16kHz 로그 축, 가로 = 시간, 마디마다 옅은 세로선(4마디마다 진하게).
"""
import struct
import sys
import zlib

import numpy as np
from scipy.io import wavfile


def png(path, rgb):
    h, w, _ = rgb.shape
    raw = b''.join(b'\x00' + rgb[y].tobytes() for y in range(h))

    def chunk(t, d):
        c = struct.pack('>I', len(d)) + t + d
        return c + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    with open(path, 'wb') as f:
        f.write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
                + chunk(b'IDAT', zlib.compress(raw, 6)) + chunk(b'IEND', b''))


def main():
    src, dst = sys.argv[1], sys.argv[2]
    bar = float(sys.argv[3]) if len(sys.argv) > 3 else 0
    off = float(sys.argv[4]) if len(sys.argv) > 4 else 0
    sr, x = wavfile.read(src)
    x = x.astype(np.float32) / 32768.0
    m = x.mean(axis=1) if x.ndim == 2 else x
    W, H, nfft = 1600, 360, 4096
    hop = max(1, (len(m) - nfft) // W)
    win = np.hanning(nfft)
    frames = np.stack([m[i * hop:i * hop + nfft] * win for i in range(W)])
    spec = np.abs(np.fft.rfft(frames, axis=1))
    fr = np.fft.rfftfreq(nfft, 1 / sr)
    edges = np.geomspace(30, 16000, H + 1)
    img = np.zeros((H, W))
    for r in range(H):
        sel = (fr >= edges[r]) & (fr < edges[r + 1])
        if not sel.any():
            sel = np.argmin(np.abs(fr - edges[r]))
            img[H - 1 - r] = spec[:, sel]
        else:
            img[H - 1 - r] = spec[:, sel].mean(axis=1)
    d = 20 * np.log10(img + 1e-9)
    d = np.clip((d - (d.max() - 70)) / 70, 0, 1)
    rgb = np.stack([np.clip(d * 2.2 - 0.9, 0, 1), np.clip(d * 1.6 - 0.35, 0, 1) * 0.85, np.clip(np.sin(d * 3.1) * 0.9, 0, 1)], -1)
    if bar > 0:
        sec_per_px = hop / sr
        k = 0
        while True:
            t = off + k * bar
            px = int(t / sec_per_px)
            if px >= W:
                break
            if px >= 0:
                rgb[:, px] = rgb[:, px] * 0.4 + (0.6 if k % 4 == 0 else 0.25)
            k += 1
    png(dst, (rgb * 255).astype(np.uint8))


if __name__ == '__main__':
    main()
