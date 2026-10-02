"""기관총 합성 수치를 참고음의 시간-주파수 에너지 분포에 맞춘다.

참고음 파형은 쓰지 않는다. 참고음에서 1/3옥타브 × 짧은 시간 구간의 평균 에너지(dB)만 재고,
노이즈·사인만으로 된 합성기(mg_synth.py)의 수치를 그 분포에 가깝게 탐색한다.

실행: python tools/sfx/mg_fit.py <참고 wav 폴더> <결과 json>
"""
import sys, glob, json, wave, math
import numpy as np
import mg_synth as S

FRAMES = [(0, 5), (5, 10), (10, 15), (15, 20)] + [(a, a + 10) for a in range(20, 300, 10)] + [(300, 350)]
BANDS = [25 * 2 ** (i / 3) for i in range(28)]          # 25Hz ~ 16kHz
NFFT = 8192


def load(p):
    w = wave.open(p); a = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(float) / 32768
    x = a.reshape(-1, w.getnchannels()).mean(1)
    if w.getframerate() != S.SR:
        x = np.interp(np.arange(0, len(x), w.getframerate() / S.SR), np.arange(len(x)), x)
    return x


_f = np.fft.rfftfreq(NFFT, 1 / S.SR)
_masks = [(_f >= b / 2 ** (1 / 6)) & (_f < b * 2 ** (1 / 6)) for b in BANDS]


def analyse(x):
    """정점 -1dB 로 맞춘 뒤 시작점부터 (밴드 × 구간) dB 행렬"""
    x = x / (np.abs(x).max() + 1e-12) * 0.89
    h = int(S.SR * 0.001); e = np.sqrt(np.convolve(x ** 2, np.ones(h) / h, 'same'))
    on = int(np.where(e > e.max() * 0.05)[0][0])
    M = np.zeros((len(BANDS), len(FRAMES)))
    for j, (a, b) in enumerate(FRAMES):
        seg = x[on + int(S.SR * a / 1000): on + int(S.SR * b / 1000)]
        if len(seg) < 8:
            M[:, j] = -90; continue
        P = np.abs(np.fft.rfft(seg, NFFT)) ** 2 / len(seg)
        for i, m in enumerate(_masks):
            M[i, j] = 10 * np.log10(P[m].sum() / NFFT + 1e-12)
    return np.maximum(M, -90)


def loss(M, T):
    w = 10 ** ((T - T.max()) / 20)            # 큰 칸일수록 중요
    w = np.maximum(w, 0.03)
    d = np.clip(M - T, -30, 30)
    return float(np.sum(w * d * d) / np.sum(w))


def fit(T, iters=4000, seed=1, init=None):
    rng = np.random.default_rng(seed)
    names = list(S.RANGES)
    best = np.array([(init or {}).get(k, 0.5) for k in names]); step = 0.25

    def ev(u):
        p = S.unpack(dict(zip(names, u)))
        # 노이즈 시드 두 개 평균 — 특정 무작위 결과에 맞춰지지 않게
        return 0.5 * sum(loss(analyse(S.render(p, np.random.default_rng(sd))), T) for sd in (7, 8))
    # 무작위 시작 몇 개 중 가장 좋은 것
    starts = [best] + [rng.uniform(0, 1, len(names)) for _ in range(40)]
    scores = [ev(u) for u in starts]
    best = starts[int(np.argmin(scores))]; bs = min(scores)
    for it in range(iters):
        cand = np.clip(best + rng.normal(0, step, len(names)) * (rng.uniform(0, 1, len(names)) < 0.3), 0, 1)
        s = ev(cand)
        if s < bs:
            best, bs = cand, s; step = min(0.3, step * 1.2)
        else:
            step = max(0.01, step * 0.985)
        if it % 500 == 0:
            print(f'  {it:5d} loss {bs:7.2f} step {step:.3f}', flush=True)
    return dict(zip(names, best.tolist())), bs


if __name__ == '__main__':
    refs = sorted(glob.glob(sys.argv[1] + '/*.wav'))
    Ms = np.array([analyse(load(p)) for p in refs])
    T = Ms.mean(0)
    print('참고음', len(refs), '개, 변형 간 표준편차', round(float(Ms.std(0).mean()), 2), 'dB')
    u, s = fit(T)
    json.dump({'u': u, 'loss': s, 'target_std': float(Ms.std(0).mean())}, open(sys.argv[2], 'w'), indent=1)
    print('최종 loss', round(s, 2))
