"""패링 효과음 합성기 2차 — 사건 단위 재료 (노이즈·사인만, 샘플 없음).

참고음(금속성 헤드샷 타격음)을 귀로 들리는 사건으로 나눠 측정한 값으로 만든다.
  1 whoosh  : 날아오는 '휘익' — 약 2kHz 에서 350Hz 로 곡선을 그리며 떨어지는 휘파람 3줄(약 65Hz 떨림) + 바람 노이즈
  2 impact  : 철판 충돌 — 짧은 클릭 + 10.5ms 간격으로 되풀이되는 금속 떨림 노이즈(빗살 지연) + 저음 쿵
  3 plate   : 철판 울림 — 배수가 아닌 모드 사인들 (parry_synth.MODES, 1.77kHz 제외)
  3b body   : 두꺼운 철판의 몸통 울림 — 180~600Hz 저음 모드 7개 (판 진동 비율), 무게감 담당 (3차에서 추가)
  4 ricochet: 도탄 '핑' — 2.2k → 3.1k → 1.77kHz 로 짧게 휘는 음(약 55Hz 떨림)과 이어지는 1.77kHz 울림.
              울림은 0.13초 간격으로 부풀었다 줄며(메아리), 그 사이 1~3kHz 금속 떨림 노이즈가 이어지다가
              0.25초 뒤 1.5k → 1.77kHz 두 번째 핑과 함께 끊긴다.
시각은 소리 시작(휘익) 기준. 층 음량(*_lv)과 몇몇 값만 parry2_fit.py 가 맞춘다.
"""
import math
import numpy as np
import mg_synth as G
import parry_synth as P1

SR = G.SR
DUR = 1.25

BASE = {
    # 1 휘익
    'wh_lv': -12.0, 'wh_f0': 2000.0, 'wh_f1': 330.0, 'wh_tau': 0.05, 'wh_pk': 0.05, 'wh_am': 65.0, 'wh_amd': 0.5,
    'wh_h': -6.0, 'wh_air': -8.0,
    # 2 충돌
    't_hit': 0.090,
    'ck_lv': -6.0, 'im_lv': 0.0, 'im_tau': 0.12, 'im_gate': 0.255, 'im_comb': 0.0105, 'im_fb': 0.6,
    'im_g': [-30.0, -12.0, -6.0, -4.0, -8.0, -20.0],          # 충돌 노이즈 스펙트럼 모양 (조절점 6)
    'th_lv': -2.0, 'th_att': 0.03, 'th_tau': 0.12,
    # 3 철판 울림
    'pl_lv': -20.0, 'pl_lo': -8.0, 'pl_dk': 1.0,
    # 4 도탄
    'rc_dt': 0.25, 'rc_lv': -4.0, 'rc_ch': -6.0, 'rc_f': 1771.0, 'rc_am': 55.0, 'rc_amd': 0.35, 'rc_dk': 60.0,
    'ec_dt': 0.13, 'ec_g': 0.6, 'ec_n': 4,
    'rt_lv': -14.0,                                            # 튕긴 뒤 1~3kHz 금속 떨림 노이즈
    'p2_dt': 0.25, 'p2_lv': -8.0,
    'drive': 1.6,
    # 3b 몸통 울림 · 길이 · 고역 꼬리 (3차에서 추가, 기본값은 2차와 같은 소리가 나도록 꺼 둠)
    'bd_lv': -60.0, 'bd_f': 180.0, 'bd_dk': 40.0, 'pl_hi': 0.0, 'dur': 1.25,
}
BODY = [(1.00, 0.0, 1.0), (1.59, -2.0, 1.1), (2.14, -3.0, 1.25), (2.30, -5.0, 1.3), (2.65, -4.0, 1.45), (2.92, -7.0, 1.6), (3.16, -8.0, 1.7)]
LV_KEYS = ['wh_lv', 'wh_h', 'wh_air', 'ck_lv', 'im_lv', 'th_lv', 'pl_lv', 'pl_lo', 'rc_lv', 'rc_ch', 'rt_lv', 'p2_lv']


def _bandnoise(n, rng, gains):
    return G.shaped(G.octave_noise(int(rng.integers(0, 1 << 30)), n), gains)


def lowpass(x, fc):
    X = np.fft.rfft(x); f = np.fft.rfftfreq(len(x), 1 / SR)
    return np.fft.irfft(X / np.sqrt(1 + (f / fc) ** 4), len(x))


def whoosh(t, p, rng):
    """지나가는 물체의 도플러 하강: f0 에서 f1 쪽으로 곡선을 그리며 떨어진다. 충돌 순간 끊긴다"""
    f = p['wh_f1'] + (p['wh_f0'] - p['wh_f1']) * np.exp(-t / p['wh_tau'])
    ph = 2 * math.pi * np.cumsum(f) / SR
    th = p['t_hit']
    e = np.clip(t / p['wh_pk'], 0, 1) ** 1.5 * np.where(t < th, 1.0, np.exp(-(t - th) / 0.004))
    am = 1 + p['wh_amd'] * np.sin(2 * math.pi * p['wh_am'] * t)
    tone = (np.sin(ph) + G.db(p['wh_h']) * np.sin(1.64 * ph) + G.db(p['wh_h'] - 4) * np.sin(0.62 * ph)) * am
    air = _bandnoise(len(t), rng, [-40, -40, -30, -18, -6, -8])
    return (tone + G.db(p['wh_air']) * air * 2.5) * e * G.db(p['wh_lv'])


def comb(x, d, fb):
    """되먹임 빗살 지연: d 초 간격으로 소리가 되풀이되며 줄어든다 (금속 떨림)"""
    k = max(1, int(d * SR)); y = x.copy()
    for i in range(k, len(y), k):
        y[i:i + k] += y[i - k:i][:len(y) - i] * fb
    return y


def impact(t, p, rng):
    th = p['t_hit']; d = np.maximum(t - th, 0); on = t >= th
    n0 = int(0.0008 * SR); click = np.zeros_like(t); i0 = int(th * SR); click[i0:i0 + n0] = rng.uniform(-1, 1, n0) * 4
    gate = np.where(d < p['im_gate'], 1.0, np.exp(-(d - p['im_gate']) / 0.012))
    nz = _bandnoise(len(t), rng, p['im_g']) * on * np.exp(-d / p['im_tau'])
    nz = comb(nz, p['im_comb'], p['im_fb']) * gate
    low = _bandnoise(len(t), rng, [0, -2, -14, -40, -40, -40]); low /= np.abs(low).max() + 1e-9
    thump = low * 3 * G.env(t, th + 0.005, p['th_att'], p['th_tau'])
    return click * G.db(p['ck_lv']) + nz * 3 * G.db(p['im_lv']) + thump * G.db(p['th_lv'])


def plate(t, p, rng, fmul=1.0):
    th = p['t_hit']; out = np.zeros_like(t)
    for f, st, lv, dk in P1.MODES:
        if 1700 < f < 1850:
            continue                                   # 1.77kHz 는 도탄 울림이 맡는다
        g = lv + (p['pl_lo'] if f < 1000 else 0.0) + (p.get('pl_hi', 0.0) if f > 6000 else 0.0)
        f *= fmul
        if f >= SR * 0.47:
            continue
        s = th + max(0.0, st - 0.14) * 0.5             # 충돌 직후 조금씩 늦게 울리기 시작
        dd = np.maximum(t - s, 0)
        e = np.where(t < s, 0.0, np.minimum(1.0, dd / 0.004) * 10 ** (-dk * p['pl_dk'] * dd / 20))
        out += G.db(g) * np.sin(2 * math.pi * f * dd + rng.uniform(0, 2 * math.pi)) * e
    return out * G.db(p['pl_lv']) * 8


def body(t, p, rng):
    """두꺼운 철판 몸통: 판 진동 비율의 저음 모드들 (높은 모드일수록 빨리 줄어든다)"""
    th = p['t_hit']; d = np.maximum(t - th, 0); out = np.zeros_like(t)
    for r, g, dkm in BODY:
        f = p['bd_f'] * r * float(np.exp(rng.normal(0, 0.01)))
        e = np.where(t < th, 0.0, np.minimum(1.0, d / 0.002) * 10 ** (-p['bd_dk'] * dkm * d / 20))
        out += G.db(g) * np.sin(2 * math.pi * f * d + rng.uniform(0, 6.28)) * e
    return out * G.db(p['bd_lv'])


def glide(t, t0, path, settle, fmul=1.0):
    """(시각, 주파수) 경로를 따라 휘다가 settle Hz 로 자리 잡는 위상"""
    d = t - t0
    ts = [0.0] + [a for a, _ in path]; fs = [path[0][1]] + [b for _, b in path]
    f = np.interp(d, ts, fs)
    f = np.where(d > ts[-1], settle + (fs[-1] - settle) * np.exp(-(d - ts[-1]) / 0.02), f) * fmul
    return 2 * math.pi * np.cumsum(np.where(d >= 0, f, 0)) / SR, ts[-1]


def ricochet(t, p, rng, fmul=1.0):
    t0 = p['t_hit'] + p['rc_dt']; d = t - t0; dp = np.maximum(d, 0)
    ph, tc = glide(t, t0, [(0.008, 2200.0), (0.016, 3100.0), (0.026, 1800.0)], p['rc_f'], fmul)
    am = 1 + p['rc_amd'] * np.sin(2 * math.pi * p['rc_am'] * dp + rng.uniform(0, 6.28))
    decay = np.where(d < 0, 0.0, np.minimum(1.0, dp / 0.002) * 10 ** (-p['rc_dk'] * dp / 20))
    # 휘는 부분은 짧게 (rc_ch), 자리 잡은 울림은 0.13초 간격으로 부풀었다 줄어든다 (메아리)
    chirp = G.db(p['rc_ch']) * np.exp(-0.5 * ((d - tc * 0.6) / (tc * 0.45)) ** 2)
    swell = np.ones_like(t)
    for k in range(1, int(p['ec_n']) + 1):
        swell += p['ec_g'] ** k * np.exp(-0.5 * ((d - k * p['ec_dt'] * (1 + 0.1 * (k % 2))) / 0.025) ** 2)
    ring = np.sin(ph) * am * decay * (np.clip(d / tc, 0, 1) * swell + chirp)
    # 튕긴 뒤 금속 떨림 노이즈 (두 번째 핑에서 끊김)
    tp2 = t0 + p['p2_dt']
    rt = _bandnoise(len(t), rng, [-40, -40, -20, -2, -10, -30]) * (d >= 0) * np.where(t < tp2, 1.0, np.exp(-(t - tp2) / 0.01))
    rt = comb(rt * np.exp(-dp / 0.3), p['im_comb'] * 1.3, 0.45)
    ph2, tc2 = glide(t, tp2, [(0.012, 1500.0), (0.030, 1520.0), (0.045, 1771.0)], p['rc_f'], fmul)
    d2 = t - tp2
    p2 = np.sin(ph2) * np.where(d2 < 0, 0.0, np.minimum(1.0, np.maximum(d2, 0) / 0.003) * np.exp(-np.maximum(d2, 0) / 0.06))
    return (ring + G.db(p['rt_lv']) * rt * 3 + G.db(p['p2_lv']) * p2) * G.db(p['rc_lv'])


def render(p, rng, fmul=1.0):
    dur = p.get('dur', DUR)
    t = np.arange(int(dur * SR)) / SR
    x = whoosh(t, p, rng) + impact(t, p, rng) + plate(t, p, rng, fmul) + ricochet(t, p, rng, fmul)
    if p.get('bd_lv', -60.0) > -59.0:
        x = x + body(t, p, rng)
    x = x / (np.abs(x).max() + 1e-9)
    x = np.tanh(x * p['drive']) / math.tanh(p['drive'])
    if dur < DUR:
        # 짧은 버전: 끝 30% 동안 부드럽게 줄여 잘린 느낌이 없게
        k = t / dur; x *= np.where(k < 0.7, 1.0, np.cos((k - 0.7) / 0.3 * math.pi / 2) ** 2)
    else:
        fade = int(0.01 * SR); x[-fade:] *= np.linspace(1, 0, fade)
    return x / (np.abs(x).max() + 1e-9) * 0.89
