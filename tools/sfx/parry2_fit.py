"""parry2_synth 의 층 음량·일부 값을 참고음에 맞춘다.

오차 = 대역 분포(parry_fit.analyse) + 꼬리 1/12옥타브 스펙트럼 + 1.77kHz '팅' 두드러짐 프로필.
참고음 파형은 쓰지 않는다. 시각·음높이는 측정값(parry2_synth.BASE)으로 고정하고 음량 위주로만 움직인다.
실행: python tools/sfx/parry2_fit.py <참고 wav> <결과 json> [seed]
"""
import sys, json
import numpy as np
import mg_fit as M
import parry_fit as F
import parry2_synth as Q

# 탐색할 값: (키, 최소, 최대)
FREE = [(k, -30.0, 12.0) for k in Q.LV_KEYS] + [
    ('im_tau', 0.04, 0.3), ('im_fb', 0.2, 0.8), ('rc_dk', 30.0, 120.0), ('pl_dk', 0.5, 1.5),
    ('ec_g', 0.2, 0.9), ('drive', 1.0, 3.5), ('wh_amd', 0.0, 0.9),
]
WIN = ((0.0, 0.1), (0.1, 0.2), (0.2, 0.3), (0.3, 0.4), (0.4, 0.6), (0.6, 0.9))


def ting(x, fc=1771.0):
    sr = Q.SR; x = x / np.abs(x).max() * 0.89
    h = int(sr * 0.001); e = np.sqrt(np.convolve(x ** 2, np.ones(h) / h, 'same')); on = np.where(e > e.max() * 0.02)[0][0]
    out = []
    for a, b in WIN:
        seg = x[on + int(sr * a): on + int(sr * b)]
        S = np.abs(np.fft.rfft(seg * np.hanning(len(seg)), 1 << 15)) ** 2; f = np.fft.rfftfreq(1 << 15, 1 / sr)
        out.append(10 * np.log10(S[(f > fc * 0.983) & (f < fc * 1.017)].max() / np.median(S[(f > fc * 0.73) & (f < fc * 1.3)])))
    return np.array(out)


def setup(ref_path):
    ref = M.load(ref_path)
    F.TARGET_TAIL = F.tail_spec(ref)
    return F.analyse(ref), ting(ref)


def score(x, T, TP):
    return F.full_loss(x, T) + float(np.mean(np.clip(ting(x) - TP, -25, 25) ** 2))


def apply(base, v):
    p = dict(base)
    for (k, lo, hi), u in zip(FREE, v):
        p[k] = lo + (hi - lo) * u
    return p


def to_u(base):
    return np.array([np.clip((base[k] - lo) / (hi - lo), 0, 1) for k, lo, hi in FREE])


def fit(T, TP, iters=1500, seed=1):
    rng = np.random.default_rng(seed)
    ev = lambda u: 0.5 * sum(score(Q.render(apply(Q.BASE, u), np.random.default_rng(sd)), T, TP) for sd in (7, 8))
    best = to_u(Q.BASE); bs = ev(best); step = 0.15
    for it in range(iters):
        cand = np.clip(best + rng.normal(0, step, len(best)) * (rng.uniform(0, 1, len(best)) < 0.35), 0, 1)
        s = ev(cand)
        if s < bs:
            best, bs = cand, s; step = min(0.25, step * 1.2)
        else:
            step = max(0.01, step * 0.99)
        if it % 250 == 0:
            print(f'  {it:5d} score {bs:7.2f}', flush=True)
    return apply(Q.BASE, best), bs


if __name__ == '__main__':
    T, TP = setup(sys.argv[1])
    print('기준(손 설정) score', round(0.5 * sum(score(Q.render(dict(Q.BASE), np.random.default_rng(sd)), T, TP) for sd in (7, 8)), 1))
    p, s = fit(T, TP, seed=int(sys.argv[3]) if len(sys.argv) > 3 else 1)
    json.dump({'score': s, 'base': {k: v for k, v in p.items()}}, open(sys.argv[2], 'w', encoding='utf-8'), indent=1, ensure_ascii=False)
    print('최종 score', round(s, 2))
