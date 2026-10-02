"""기관총 단발 합성기 (노이즈·사인만 사용, 샘플 없음).

재료
- blast1: 초반 노이즈 폭발 (옥타브 밴드 10개에 스펙트럼 모양 6점을 보간해 입힘)
- blast2: 뒤에 이어지는 노이즈 (따로 모양·시작·감쇠)
- sweep : 높은 음에서 낮은 음으로 떨어지는 사인 (tanh 로 배음)
- boom  : 늦게 오는 저음 쿵
- click : 시작 순간의 짧은 광대역 클릭
- crackle: 흩어진 작은 파열 입자 (밀도가 시간에 따라 줄어듦)
- sweep 2배음: 하강음 위로 따라가는 배음
- drive : 마지막 포화(밀도)
수치는 0~1 로 정규화한 u 를 RANGES 로 펼쳐 쓴다 (mg_fit.py 가 탐색).
"""
import math
import numpy as np

SR = 44100
DUR = 0.38
OCT = [31.25 * 2 ** i for i in range(10)]               # 31Hz ~ 16kHz
CTRL = [40, 125, 400, 1250, 4000, 12500]                # 스펙트럼 모양 조절점

RANGES = {}
for k in ('b1', 'b2'):
    for i in range(len(CTRL)):
        RANGES[f'{k}_g{i}'] = (-40.0, 0.0)              # dB
RANGES.update({
    'b1_lv': (-30.0, 6.0), 'b1_att': (0.2, 30.0), 'b1_tau': (3.0, 80.0),
    'b2_lv': (-40.0, 6.0), 'b2_t0': (0.0, 80.0), 'b2_att': (1.0, 80.0), 'b2_tau': (15.0, 250.0),
    'sw_lv': (-40.0, 6.0), 'sw_f0': (150.0, 2500.0), 'sw_f1': (30.0, 100.0), 'sw_tf': (8.0, 140.0),
    'sw_t0': (0.0, 140.0), 'sw_att': (1.0, 25.0), 'sw_tau': (10.0, 80.0), 'sw_drv': (1.0, 8.0), 'sw_h2': (-40.0, 0.0), 'sw_jit': (0.0, 40.0),
    'bm_lv': (-40.0, 6.0), 'bm_f0': (40.0, 320.0), 'bm_f1': (28.0, 80.0), 'bm_t0': (30.0, 150.0),
    'bm_att': (2.0, 50.0), 'bm_tau': (15.0, 160.0),
    'ck_lv': (-50.0, 0.0),
    'cr_lv': (-40.0, 6.0), 'cr_f': (150.0, 4000.0), 'cr_tau': (10.0, 200.0), 'cr_rate': (200.0, 4000.0),
    'drive': (1.0, 5.0),
})
MS = {'cr_tau', 'b1_att', 'b1_tau', 'b2_t0', 'b2_att', 'b2_tau', 'sw_tf', 'sw_t0', 'sw_att', 'sw_tau', 'bm_t0', 'bm_att', 'bm_tau'}


def unpack(u):
    p = {}
    for k, (a, b) in RANGES.items():
        v = a + (b - a) * float(u[k])
        p[k] = v / 1000.0 if k in MS else v
    return p


def db(v):
    return 10 ** (v / 20)


def t_axis():
    return np.arange(int(DUR * SR)) / SR


def env(t, start, att, tau):
    x = t - start
    return np.where(x < 0, 0.0, np.minimum(1.0, x / max(att, 1e-5)) * np.exp(-np.maximum(x, 0) / tau))


_band_cache = {}


def octave_noise(rng_seed, n):
    """옥타브 밴드로 나눈 노이즈 (FFT 가우시안 마스크, 합치면 거의 평탄)"""
    key = (rng_seed, n)
    if key not in _band_cache:
        rng = np.random.default_rng(rng_seed)
        X = np.fft.rfft(rng.uniform(-1, 1, n)); f = np.fft.rfftfreq(n, 1 / SR)
        lf = np.log2(np.maximum(f, 1.0))
        bands = []
        for c in OCT:
            m = np.exp(-0.5 * ((lf - math.log2(c)) / 0.42) ** 2)
            bands.append(np.fft.irfft(X * m, n))
        _band_cache[key] = np.array(bands)
    return _band_cache[key]


def shaped(bands, gains_db):
    g = np.interp(np.log2(OCT), np.log2(CTRL), gains_db)
    return (db(g)[:, None] * bands).sum(0)


def drop(t, f0, f1, tf, t0, jit=None):
    """f0 → f1 로 떨어지는 사인. jit 를 주면 주파수를 무작위로 흔들어 두툼하게 번지게 한다"""
    x = np.maximum(t - t0, 0)
    f = f1 + (f0 - f1) * np.exp(-x / tf)
    if jit is not None:
        f = f * (1 + jit)
    return np.where(t < t0, 0.0, np.sin(2 * math.pi * np.cumsum(f) / SR))


def wobble(n, rng, amount):
    """주파수 흔들림: 약 300Hz 이하로 걸러 낸 노이즈 (비율)"""
    X = np.fft.rfft(rng.normal(0, 1, n)); f = np.fft.rfftfreq(n, 1 / SR)
    w = np.fft.irfft(X * (f < 300), n)
    return w / (np.abs(w).max() + 1e-9) * amount / 100


def crackle(t, rng, fc, tau, rate):
    """푸아송 간격의 짧은 감쇠 펄스들을 fc 근처 대역으로 걸러 낸 파열 입자"""
    n = len(t); imp = np.zeros(n)
    dens = rate * np.exp(-t / tau) / SR
    hit = rng.uniform(0, 1, n) < dens
    imp[hit] = rng.uniform(-1, 1, hit.sum()) * (0.4 + rng.uniform(0, 1, hit.sum()))
    X = np.fft.rfft(imp); f = np.fft.rfftfreq(n, 1 / SR)
    m = np.exp(-0.5 * ((np.log2(np.maximum(f, 1.0)) - math.log2(fc)) / 1.0) ** 2)
    return np.fft.irfft(X * m, n) * 6


def render(p, rng):
    t = t_axis(); n = len(t)
    s1, s2 = (int(v) for v in rng.integers(0, 1 << 30, 2))
    b1 = shaped(octave_noise(s1, n), [p[f'b1_g{i}'] for i in range(len(CTRL))]) * env(t, 0, p['b1_att'], p['b1_tau']) * db(p['b1_lv'])
    b2 = shaped(octave_noise(s2, n), [p[f'b2_g{i}'] for i in range(len(CTRL))]) * env(t, p['b2_t0'], p['b2_att'], p['b2_tau']) * db(p['b2_lv'])
    sw_e = env(t, p['sw_t0'], p['sw_att'], p['sw_tau'])
    jit = wobble(n, rng, p['sw_jit'])
    sw = np.tanh(drop(t, p['sw_f0'], p['sw_f1'], p['sw_tf'], p['sw_t0'], jit) * p['sw_drv']) * sw_e * db(p['sw_lv'])         + drop(t, p['sw_f0'] * 2, p['sw_f1'] * 2, p['sw_tf'], p['sw_t0'], jit) * sw_e * db(p['sw_lv'] + p['sw_h2'])
    bm = drop(t, p['bm_f0'], p['bm_f1'], 0.04, p['bm_t0']) * env(t, p['bm_t0'], p['bm_att'], p['bm_tau']) * db(p['bm_lv'])
    ck = np.zeros(n); k = int(0.0006 * SR); ck[:k] = rng.uniform(-1, 1, k) * db(p['ck_lv']) * 4
    cr = crackle(t, rng, p['cr_f'], p['cr_tau'], p['cr_rate']) * db(p['cr_lv'])
    x = b1 + b2 + sw + bm + ck + cr
    x = x / (np.abs(x).max() + 1e-9)
    x = np.tanh(x * p['drive']) / math.tanh(p['drive'])
    fade = int(0.005 * SR); x[-fade:] *= np.linspace(1, 0, fade)
    return x / (np.abs(x).max() + 1e-9) * 0.89


def vary(p, rng, k=1.0):
    """변형 한 개: 시각·음높이·음량·스펙트럼 모양을 조금씩 흔든다 (k = 흔드는 정도)"""
    q = dict(p)
    for key, v in p.items():
        if key.endswith(('_lv', '_h2')) or '_g' in key:
            q[key] = v + rng.normal(0, 2.5 * k)                          # dB
        elif key.endswith(('_f0', '_f1', '_f')):
            q[key] = v * math.exp(rng.normal(0, 0.12 * k))               # 음높이
        elif key in MS or key == 'cr_rate':
            q[key] = v * math.exp(rng.normal(0, 0.15 * k))               # 시간
    return q
