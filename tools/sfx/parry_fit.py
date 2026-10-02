"""패링 합성 수치를 참고음의 시간-주파수 에너지 분포에 맞춘다 (mg_fit.py 와 같은 방식, 구간을 1.1초까지 늘림).

참고음 파형은 쓰지 않는다. 1/3옥타브 × 시간 구간의 에너지(dB)만 재고 parry_synth.py 의 수치를 탐색한다.
실행: python tools/sfx/parry_fit.py <참고 wav> <결과 json>
"""
import sys, json
import numpy as np
import mg_fit as M
import parry_synth as P

FRAMES = [(0, 5), (5, 10), (10, 20), (20, 40)] + [(a, a + 20) for a in range(40, 300, 20)] + [(a, a + 50) for a in range(300, 1100, 50)]
ONSET = 0.02     # 정점 대비 -34dB 를 넘는 첫 순간 (작은 예비 타격도 시작으로 본다)

_f = np.fft.rfftfreq(M.NFFT, 1 / P.SR)
_masks = [(_f >= b / 2 ** (1 / 6)) & (_f < b * 2 ** (1 / 6)) for b in M.BANDS]


def analyse(x):
    x = x / (np.abs(x).max() + 1e-12) * 0.89
    h = int(P.SR * 0.001); e = np.sqrt(np.convolve(x ** 2, np.ones(h) / h, 'same'))
    on = int(np.where(e > e.max() * ONSET)[0][0])
    A = np.zeros((len(M.BANDS), len(FRAMES)))
    for j, (a, b) in enumerate(FRAMES):
        seg = x[on + int(P.SR * a / 1000): on + int(P.SR * b / 1000)]
        if len(seg) < 8:
            A[:, j] = -90; continue
        S = np.abs(np.fft.rfft(seg, M.NFFT)) ** 2 / len(seg)
        for i, m in enumerate(_masks):
            A[i, j] = 10 * np.log10(S[m].sum() / M.NFFT + 1e-12)
    return np.maximum(A, -90)


_tf = np.fft.rfftfreq(1 << 15, 1 / P.SR)
_fine = [(_tf >= c / 2 ** (1 / 24)) & (_tf < c * 2 ** (1 / 24)) for c in np.geomspace(300, 16000, 70)]


def tail_spec(x):
    """꼬리(시작 후 0.3~1.0초)의 1/12옥타브 스펙트럼 dB — 가는 지속음(금속 울림)이 잘 드러난다"""
    x = x / (np.abs(x).max() + 1e-12) * 0.89
    h = int(P.SR * 0.001); e = np.sqrt(np.convolve(x ** 2, np.ones(h) / h, 'same'))
    on = int(np.where(e > e.max() * ONSET)[0][0])
    seg = x[on + int(0.3 * P.SR): on + int(1.0 * P.SR)]
    S = np.abs(np.fft.rfft(seg * np.hanning(len(seg)), 1 << 15)) ** 2
    return np.array([10 * np.log10(S[m].max() + 1e-12) for m in _fine])


def tail_loss(a, b):
    d = np.clip(a - b, -30, 30); w = np.maximum(10 ** ((b - b.max()) / 20), 0.05)
    return float(np.sum(w * d * d) / np.sum(w))


TARGET_TAIL = None


def full_loss(x, T):
    l = M.loss(analyse(x), T)
    if TARGET_TAIL is not None:
        l += 0.5 * tail_loss(tail_spec(x), TARGET_TAIL)
    return l


def fit(T, iters=3000, seed=1, init=None):
    rng = np.random.default_rng(seed)
    names = list(P.RANGES)

    def ev(u):
        p = P.unpack(dict(zip(names, u)))
        return 0.5 * sum(full_loss(P.render(p, np.random.default_rng(sd)), T) for sd in (7, 8))
    best = np.array([(init or {}).get(k, 0.5) for k in names])
    starts = [best] + [rng.uniform(0, 1, len(names)) for _ in range(30)]
    scores = [ev(u) for u in starts]
    best = starts[int(np.argmin(scores))]; bs = min(scores); step = 0.25
    for it in range(iters):
        cand = np.clip(best + rng.normal(0, step, len(names)) * (rng.uniform(0, 1, len(names)) < 0.3), 0, 1)
        s = ev(cand)
        if s < bs:
            best, bs = cand, s; step = min(0.3, step * 1.2)
        else:
            step = max(0.01, step * 0.985)
        if it % 1000 == 0:
            print(f'  {it:5d} loss {bs:7.2f}', flush=True)
    return dict(zip(names, best.tolist())), bs


if __name__ == '__main__':
    ref = M.load(sys.argv[1])
    T = analyse(ref); TARGET_TAIL = tail_spec(ref)
    init = json.load(open(sys.argv[4]))['u'] if len(sys.argv) > 4 else None
    u, s = fit(T, seed=int(sys.argv[3]) if len(sys.argv) > 3 else 1, init=init)
    json.dump({'u': u, 'loss': s}, open(sys.argv[2], 'w'), indent=1)
    print('최종 loss', round(s, 2))
