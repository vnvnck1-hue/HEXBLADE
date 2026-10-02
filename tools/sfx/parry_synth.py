"""패링 효과음 합성기 (노이즈·사인만 사용, 샘플 없음).

참고한 짜임(측정치, 참고음: 금속성 헤드샷 타격음)
- 0ms   : 짧은 광대역 예비 타격
- 0.1~0.3s: 1~10kHz 로 번지는 본 타격 + 40~150Hz 저음 쿵
- 0.13s~: 서로 배수가 아닌 지속음 20여 개가 겹친 금속 울림 (0.3~1.5초 감쇠) — 맑고 반짝이는 느낌의 핵심
재료
- tick  : 시작 순간의 짧은 노이즈 (스펙트럼 모양 6점)
- hit   : 본 타격 노이즈 (시작·상승·감쇠·모양, ht_cut 에서 빠르게 끊김)
- thump : 저역 노이즈 쿵 + 떨어지는 사인 약간
- ring  : 금속 울림 — 모드 목록 MODES 의 사인들 (저·중·고 묶음 음량, 시작·감쇠 배율, 1.77kHz '팅' 강조)
수치는 0~1 로 정규화한 u 를 RANGES 로 펼쳐 쓴다 (parry_fit.py 가 탐색).
"""
import math
import numpy as np
import mg_synth as G           # 옥타브 노이즈·env·drop 재사용

SR = G.SR
DUR = 1.25

# 금속 울림 모드: (주파수 Hz, 시작 s, 상대 음량 dB, 감쇠 dB/s) — 측정값을 반올림
MODES = [
    (334, 0.21, -21, 66), (441, 0.20, -29, 60), (678, 0.19, -17, 54), (781, 0.24, -33, 64),
    (1233, 0.17, -28, 47), (1518, 0.22, -25, 69), (1572, 0.24, -32, 69), (1771, 0.28, -15, 88),
    (1868, 0.15, -27, 37), (2724, 0.14, -28, 40), (3456, 0.15, -28, 37), (3924, 0.14, -27, 46),
    (4759, 0.20, -37, 76), (4931, 0.15, -23, 78), (5448, 0.25, -33, 74), (5620, 0.20, -43, 34),
    (6600, 0.17, -27, 44), (6918, 0.15, -24, 42), (7730, 0.25, -42, 39), (7854, 0.20, -28, 64),
    (8409, 0.25, -44, 61), (10153, 0.22, -39, 38), (10347, 0.17, -35, 49), (11235, 0.23, -48, 37),
    (13194, 0.15, -31, 53), (15455, 0.25, -49, 40),
]

RANGES = {}
for k in ('tk', 'ht'):
    for i in range(len(G.CTRL)):
        RANGES[f'{k}_g{i}'] = (-40.0, 0.0)
RANGES.update({
    'tk_lv': (-40.0, 6.0), 'tk_tau': (1.0, 40.0),
    'ht_lv': (-30.0, 6.0), 'ht_t0': (0.0, 160.0), 'ht_att': (1.0, 120.0), 'ht_tau': (10.0, 250.0),
    'ht_cut': (150.0, 500.0), 'ht_rel': (2.0, 40.0),
    'th_lv': (-40.0, 6.0), 'th_sine': (-30.0, 0.0), 'th_f0': (60.0, 400.0), 'th_f1': (30.0, 90.0), 'th_tf': (10.0, 150.0),
    'th_t0': (0.0, 160.0), 'th_att': (2.0, 80.0), 'th_tau': (20.0, 300.0),
    'rg_lv': (-40.0, 12.0), 'rg_lo': (-12.0, 12.0), 'rg_hi': (-12.0, 12.0), 'rg_t': (0.5, 1.5), 'rg_dk': (0.5, 1.6), 'rg_att': (0.5, 30.0),
    'ting_lv': (-30.0, 12.0), 'ting_tau': (5.0, 80.0),
    'drive': (1.0, 4.0),
})
MS = {'tk_tau', 'ht_t0', 'ht_att', 'ht_tau', 'ht_cut', 'ht_rel', 'ting_tau', 'th_tf', 'th_t0', 'th_att', 'th_tau', 'rg_att'}


def unpack(u):
    p = {}
    for k, (a, b) in RANGES.items():
        v = a + (b - a) * float(u[k])
        p[k] = v / 1000.0 if k in MS else v
    return p


def ring(t, p, rng, modes=MODES, fmul=1.0):
    out = np.zeros_like(t)
    for f, st, lv, dk in modes:
        f *= fmul
        if f >= SR * 0.47:
            continue
        s = st * p['rg_t']
        d = np.maximum(t - s, 0)
        e = np.where(t < s, 0.0, np.minimum(1.0, d / p['rg_att']) * 10 ** (-(dk * p['rg_dk']) * d / 20))
        g = lv + (p['rg_lo'] if f < 1000 else p['rg_hi'] if f > 3000 else 0.0)
        if 1700 < f < 1850 and (f, st) == max(((m[0], m[1]) for m in modes if 1700 < m[0] * fmul < 1850), default=(f, st)):
            # 가장 큰 1.77kHz 모드: 시작 순간 반짝 튀는 '팅'
            e = e * (1 + G.db(p['ting_lv']) * np.exp(-d / p['ting_tau']))
        out += G.db(g) * np.sin(2 * math.pi * f * d + rng.uniform(0, 2 * math.pi)) * e
    return out * G.db(p['rg_lv'])


def render(p, rng, modes=MODES, fmul=1.0):
    t = np.arange(int(DUR * SR)) / SR; n = len(t)
    s1, s2 = (int(v) for v in rng.integers(0, 1 << 30, 2))
    tk = G.shaped(G.octave_noise(s1, n), [p[f'tk_g{i}'] for i in range(len(G.CTRL))]) * G.env(t, 0, 0.0003, p['tk_tau']) * G.db(p['tk_lv'])
    cut = np.where(t < p['ht_cut'], 1.0, np.exp(-(t - p['ht_cut']) / p['ht_rel']))
    ht = G.shaped(G.octave_noise(s2, n), [p[f'ht_g{i}'] for i in range(len(G.CTRL))]) * G.env(t, p['ht_t0'], p['ht_att'], p['ht_tau']) * cut * G.db(p['ht_lv'])
    th_e = G.env(t, p['th_t0'], p['th_att'], p['th_tau'])
    low = G.shaped(G.octave_noise(s1 ^ 0x5bd1, n), p.get('th_g', [0.0, -2.0, -14.0, -40.0, -40.0, -40.0]))   # th_g: 5차에서 추가
    th = (low / (np.abs(low).max() + 1e-9) * 3 + G.drop(t, p['th_f0'], p['th_f1'], p['th_tf'], p['th_t0']) * G.db(p['th_sine'])) * th_e * G.db(p['th_lv'])
    x = tk + ht + th + ring(t, p, rng, modes, fmul)
    x = x / (np.abs(x).max() + 1e-9)
    x = np.tanh(x * p['drive']) / math.tanh(p['drive'])
    fade = int(0.01 * SR); x[-fade:] *= np.linspace(1, 0, fade)
    return x / (np.abs(x).max() + 1e-9) * 0.89
