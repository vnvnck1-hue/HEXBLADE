"""기관총 효과음 후보 3종 (2차) — 노이즈·사인만으로 합성, 샘플 없음.

기준 수치(mg_fit_params.json)는 mg_fit.py 가 참고음의 시간-주파수 에너지 분포(1/3옥타브 × 5~10ms)에
맞춰 찾은 값이다. 참고음 파형은 쓰지 않는다.
  A_close : 기준 그대로 (분포가 참고음에 가장 가까움)
  B_crack : 파열음 강조 — 시작을 날카롭게, 고역·파열 입자·클릭을 키움
  C_heavy : 묵직함 강조 — 하강음·저음 쿵·저역을 키우고 음높이를 낮춤
각 후보는 원본처럼 무작위 변형 8개 + 게임 간격 연사 미리듣기.

실행: python tools/sfx/mg_candidates.py  →  output/mg-sound-candidates-20261002/v2/
"""
import os, json, wave, random
import numpy as np
import mg_synth as S

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', '..', 'output', 'mg-sound-candidates-20261002', 'v2')
FIRE_INTERVAL = 0.085   # scripts/player.gd FIRE_INTERVAL
VARIANTS = 8
VARY = 0.75             # 변형 간 차이 ≈ 참고음 수준 (약 3.6dB)


def base():
    b = json.load(open(os.path.join(HERE, 'mg_fit_params.json'), encoding='utf-8'))['base']
    return {k: (v / 1000.0 if k in S.MS else v) for k, v in b.items()}


def crack(p):
    q = dict(p)
    for i in (3, 4, 5):
        q[f'b1_g{i}'] += 5.0
    q['b1_att'] = 0.004
    q['ck_lv'] += 14.0
    q['cr_lv'] += 5.0
    q['drive'] = 1.6
    return q


def heavy(p):
    q = dict(p)
    for k in ('b1_g0', 'b1_g1', 'b2_g0', 'b2_g1'):
        q[k] += 4.0
    q['bm_lv'] += 5.0; q['sw_lv'] += 4.0
    for k in ('sw_f0', 'sw_f1', 'bm_f0', 'bm_f1'):
        q[k] *= 0.88
    q['bm_tau'] *= 1.1
    q['drive'] = 1.4
    return q


CANDIDATES = [
    ('A_close', lambda p: p, '참고음 분포에 가장 가깝게 맞춘 기준 — 짙은 광대역 폭발 + 하강음 + 늦은 저음 쿵 + 파열 입자'),
    ('B_crack', crack, '파열음 강조 — 시작이 더 날카롭고 고역·파열 입자·클릭이 큼'),
    ('C_heavy', heavy, '묵직함 강조 — 하강음·저음 쿵·저역을 키우고 음높이를 12% 낮춤'),
]


def shots(p, seed=0):
    return [S.render(S.vary(p, np.random.default_rng(1000 * seed + 100 + v), VARY), np.random.default_rng(1000 * seed + v))
            for v in range(VARIANTS)]


def write(path, x):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(S.SR)
        w.writeframes((np.clip(x, -1, 1) * 32000).astype('<i2').tobytes())


def burst(shots, count=16, jitter=0.06, seed=7):
    """게임과 같은 간격(0.085초)·피치 흔들림(±6%)으로 연사"""
    rng = random.Random(seed)
    total = int((FIRE_INTERVAL * count + 0.5) * S.SR)
    y = np.zeros(total)
    for i in range(count):
        s = shots[rng.randrange(len(shots))]
        r = 1.0 + rng.uniform(-jitter, jitter)
        s2 = np.interp(np.arange(0, len(s) - 1, r), np.arange(len(s)), s) * 0.55
        k = int(i * FIRE_INTERVAL * S.SR)
        y[k:k + len(s2)] += s2[:total - k]
    return y / (np.abs(y).max() + 1e-9) * 0.89


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    open(os.path.join(OUT, '..', '.gdignore'), 'w').close()
    p0 = base()
    for ci, (name, fn, _) in enumerate(CANDIDATES):
        xs = shots(fn(p0), ci)
        for v, s in enumerate(xs):
            write(os.path.join(OUT, name, f'{name}_{v + 1:02d}.wav'), s)
        write(os.path.join(OUT, f'{name}_burst.wav'), burst(xs))
        print(name, f'{len(xs[0]) / S.SR:.2f}s x{VARIANTS} + burst')
