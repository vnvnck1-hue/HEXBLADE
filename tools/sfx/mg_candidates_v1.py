"""(1차, 사용자 검토에서 파열음·묵직함·다양함 부족으로 반려) 기관총 효과음 후보 3종 — 2차는 mg_candidates.py.

참고한 짜임(측정치): 0~20ms 중고역 기계 '딱' → 약 70~150ms 늦은 저음 '쿵' → 4kHz 이상 금속 꼬리, 전체 약 0.3초.
나중에 scripts/sfx.gd 로 옮기기 쉽도록 단순한 재료만 쓴다.

실행: python tools/sfx/mg_candidates.py  →  output/mg-sound-candidates-20261002/
"""
import os, math, wave, random
import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), '..', '..', 'output', 'mg-sound-candidates-20261002')
FIRE_INTERVAL = 0.085   # scripts/player.gd FIRE_INTERVAL


# ---------- 재료 ----------
def tt(dur):
    return np.arange(int(dur * SR)) / SR


def noise(n, rng):
    return rng.uniform(-1.0, 1.0, n)


def env(t, start=0.0, attack=0.0005, tau=0.02):
    """start 에서 attack 동안 올라가고 tau 로 지수 감쇠"""
    x = t - start
    e = np.where(x < 0, 0.0, np.minimum(1.0, x / max(attack, 1e-6)) * np.exp(-np.maximum(x, 0) / tau))
    return e


def biquad(x, kind, f, q=0.707):
    w = 2 * math.pi * f / SR; c = math.cos(w); a = math.sin(w) / (2 * q)
    if kind == 'bp':
        b0, b1, b2 = a, 0.0, -a
    elif kind == 'lp':
        b0, b1, b2 = (1 - c) / 2, 1 - c, (1 - c) / 2
    else:  # hp
        b0, b1, b2 = (1 + c) / 2, -(1 + c), (1 + c) / 2
    a0, a1, a2 = 1 + a, -2 * c, 1 - a
    b0, b1, b2, a1, a2 = b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0
    y = np.zeros_like(x); x1 = x2 = y1 = y2 = 0.0
    for i, v in enumerate(x):
        o = b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, v, y1, o
        y[i] = o
    return y


def drop_sine(t, f0, f1, tau_f, start=0.0, square=0.0):
    """f0 에서 f1 로 떨어지는 사인(선택적으로 사각파 섞음)"""
    x = np.maximum(t - start, 0)
    f = f1 + (f0 - f1) * np.exp(-x / tau_f)
    ph = 2 * math.pi * np.cumsum(f) / SR
    s = np.sin(ph)
    if square:
        s = (1 - square) * s + square * np.sign(s)
    return np.where(t < start, 0.0, s)


def ring(t, freqs, taus, amps, start=0.0, rng=None):
    out = np.zeros_like(t)
    for f, tau, a in zip(freqs, taus, amps):
        ph = rng.uniform(0, 2 * math.pi) if rng else 0.0
        out += a * np.sin(2 * math.pi * f * (t - start) + ph) * env(t, start, 0.0003, tau)
    return out


def reflections(x, taps=((0.023, 0.20), (0.041, 0.14), (0.067, 0.09))):
    """구워 넣는 짧은 초기 반사(저역 위주)"""
    lo = biquad(x, 'lp', 2500)
    y = x.copy()
    for d, g in taps:
        k = int(d * SR)
        y[k:] += lo[:-k] * g
    return y


def finish(x, drive=1.0):
    if drive != 1.0:
        x = np.tanh(x * drive) / math.tanh(drive)
    x = biquad(x, 'hp', 35)
    fade = int(0.004 * SR)
    x[-fade:] *= np.linspace(1, 0, fade)
    return x / (np.abs(x).max() + 1e-9) * 0.89   # 약 -1 dBFS


# ---------- 후보 ----------
def clack(t, n, rng, p, f_bp, amp, tau):
    """중역 기계 '딱': 대역 노이즈 + 짧은 중역 공진"""
    return biquad(noise(n, rng), 'bp', f_bp * p, 0.7) * env(t, 0, 0.0003, tau) * amp         + ring(t, [1150 * p, 1780 * p, 2450 * p], [tau * 4, tau * 3, tau * 2.5], [amp * 0.22, amp * 0.16, amp * 0.1], rng=rng)


def heavy(rng):
    """A · 묵직한 산업용: 중역 딱 → 늦게 오는 깊은 쿵 → 긴 금속 꼬리 (0.36초)"""
    p = rng.uniform(0.95, 1.05); t = tt(0.36); n = len(t)
    crack = clack(t, n, rng, p, 1700, 1.5, 0.007)         + biquad(noise(n, rng), 'hp', 5000) * env(t, 0, 0.0002, 0.003) * 0.5
    body = drop_sine(t, 240 * p, 120 * p, 0.012) * env(t, 0, 0.001, 0.02) * 0.3
    chunk_t = rng.uniform(0.060, 0.072)
    chunk = drop_sine(t, 130 * p, 52 * p, 0.04, chunk_t) * env(t, chunk_t, 0.004, 0.06) * 1.0         + biquad(noise(n, rng), 'lp', 700) * env(t, chunk_t, 0.002, 0.012) * 0.6
    mech = ring(t, [3150 * p, 4620 * p, 6880 * p, 8900 * p], [0.12, 0.14, 0.15, 0.09],
                [0.16, 0.13, 0.10, 0.06], start=0.015, rng=rng)         + biquad(noise(n, rng), 'hp', 5200) * env(t, 0.05, 0.03, 0.12) * 0.22         + biquad(noise(n, rng), 'bp', 1600 * p, 0.8) * env(t, 0.03, 0.02, 0.07) * 0.22
    x = crack + body + chunk + mech
    return finish(reflections(x), drive=2.0)


def tight(rng):
    """B · 짧고 빠른 연사용: 밝은 딱 + 노리쇠 틱 + 짧은 쿵, 꼬리를 줄여 연사가 뭉개지지 않음 (0.24초)"""
    p = rng.uniform(0.95, 1.05); t = tt(0.24); n = len(t)
    crack = clack(t, n, rng, p, 2600, 1.6, 0.005)         + biquad(noise(n, rng), 'hp', 6000) * env(t, 0, 0.0002, 0.0025) * 0.7
    bolt_t = rng.uniform(0.028, 0.034)
    bolt = biquad(noise(n, rng), 'bp', 1900 * p, 2.0) * env(t, bolt_t, 0.0002, 0.003) * 0.9
    chunk_t = rng.uniform(0.040, 0.048)
    chunk = drop_sine(t, 170 * p, 80 * p, 0.02, chunk_t) * env(t, chunk_t, 0.002, 0.035) * 0.75
    mech = ring(t, [4200 * p, 6300 * p, 9100 * p], [0.07, 0.08, 0.05], [0.14, 0.10, 0.06],
                start=0.006, rng=rng)         + biquad(noise(n, rng), 'hp', 6500) * env(t, 0.03, 0.015, 0.06) * 0.16
    x = crack + bolt + chunk + mech
    return finish(reflections(x, ((0.017, 0.14), (0.031, 0.09))), drive=2.6)


def servo(rng):
    """C · 로봇 기계음: 딱 + 래칫 딸깍 3번 + 사각파 저음 으르렁 + 서보 휘파람 (0.32초)"""
    p = rng.uniform(0.95, 1.05); t = tt(0.32); n = len(t)
    crack = clack(t, n, rng, p, 1400, 1.4, 0.007)
    clicks = np.zeros(n)
    for i, (ct, g) in enumerate(((0.024, 0.8), (0.046, 0.6), (0.068, 0.45))):
        ct += rng.uniform(-0.003, 0.003)
        clicks += biquad(noise(n, rng), 'bp', (2600 + 500 * i) * p, 2.5) * env(t, ct, 0.0002, 0.0025) * g
    chunk_t = rng.uniform(0.055, 0.065)
    growl = biquad(drop_sine(t, 96 * p, 62 * p, 0.05, chunk_t, square=0.85), 'lp', 650) * env(t, chunk_t, 0.004, 0.06) * 0.8         + drop_sine(t, 140 * p, 55 * p, 0.035, chunk_t) * env(t, chunk_t, 0.003, 0.05) * 0.6
    whine = np.sin(2 * math.pi * np.cumsum(1500 * p - 600 * p * np.clip((t - 0.02) / 0.12, 0, 1)) / SR)         * env(t, 0.02, 0.02, 0.07) * 0.07
    mech = ring(t, [2700 * p, 4100 * p, 5900 * p, 7700 * p], [0.12, 0.11, 0.09, 0.07], [0.13, 0.11, 0.07, 0.05],
                start=0.012, rng=rng)         + biquad(noise(n, rng), 'hp', 4800) * env(t, 0.06, 0.03, 0.10) * 0.17         + biquad(noise(n, rng), 'bp', 1900 * p, 0.8) * env(t, 0.05, 0.02, 0.07) * 0.2
    x = crack + clicks + growl + whine + mech
    return finish(reflections(x), drive=2.2)


CANDIDATES = [
    ('A_heavy', heavy, '묵직한 산업용 — 깊은 몸통과 늦게 따라오는 저음 쿵, 금속 꼬리'),
    ('B_tight', tight, '짧고 빠른 연사용 — 밝은 파열음과 노리쇠 틱, 꼬리를 줄여 연사가 뭉개지지 않음'),
    ('C_servo', servo, '로봇 기계음 — 사각파 저음 으르렁과 래칫 딸깍, 서보 휘파람'),
]
VARIANTS = 4


def write(path, x):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32000).astype('<i2').tobytes())


def burst(shots, count=16, jitter=0.06, seed=7):
    """게임과 같은 간격(0.085초)·피치 흔들림(±6%)으로 연사"""
    rng = random.Random(seed)
    total = int((FIRE_INTERVAL * count + 0.5) * SR)
    y = np.zeros(total)
    for i in range(count):
        s = shots[rng.randrange(len(shots))]
        r = 1.0 + rng.uniform(-jitter, jitter)
        idx = np.arange(0, len(s) - 1, r)
        s2 = np.interp(idx, np.arange(len(s)), s) * 0.55
        k = int(i * FIRE_INTERVAL * SR)
        y[k:k + len(s2)] += s2[:total - k]
    return y / (np.abs(y).max() + 1e-9) * 0.89


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    open(os.path.join(OUT, '.gdignore'), 'w').close()
    for name, fn, _ in CANDIDATES:
        shots = [fn(np.random.default_rng(100 + v)) for v in range(VARIANTS)]
        for v, s in enumerate(shots):
            write(os.path.join(OUT, name, f'{name}_{v + 1:02d}.wav'), s)
        write(os.path.join(OUT, f'{name}_burst.wav'), burst(shots))
        print(name, f'{len(shots[0]) / SR:.2f}s x{VARIANTS} + burst')
