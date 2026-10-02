"""패링 효과음 후보 2차 3종 — 사건 단위 합성(parry2_synth), 노이즈·사인만, 샘플 없음.

1차(parry_candidates.py)는 휘익·철판 충돌·튕기는 메아리가 잘 안 느껴진다는 검토로 다시 만들었다.
기준 수치(parry2_fit_params.json)는 parry2_fit.py 가 참고음에 맞춘 값.
  A_close : 참고음 구조 그대로 — 휘익(90ms) → 철판 충돌·떨림 → 철판 울림 → 도탄 핑·메아리
  B_snappy: 휘익을 절반(45ms)으로 줄여 충돌이 빨리 온다 — 패링 반응감
  C_echo  : 튕기는 핑과 메아리, 튕긴 뒤 금속 떨림을 강조
각 후보 변형 4개.

실행: python tools/sfx/parry2_candidates.py  →  output/parry-sound-candidates-20261002/v2/
"""
import os, json
import numpy as np
import parry2_synth as Q
from parry_candidates import write

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', '..', 'output', 'parry-sound-candidates-20261002', 'v2')
VARIANTS = 4


def base():
    p = dict(Q.BASE)
    path = os.path.join(HERE, 'parry2_fit_params.json')
    if os.path.exists(path):
        p.update(json.load(open(path, encoding='utf-8'))['base'])
    return p


def vary(p, rng):
    q = dict(p)
    for k in Q.LV_KEYS:
        q[k] = p[k] + rng.normal(0, 1.5)
    q['wh_f0'] = p['wh_f0'] * float(np.exp(rng.normal(0, 0.06)))
    q['rc_dt'] = p['rc_dt'] * float(np.exp(rng.normal(0, 0.08)))
    q['ec_dt'] = p['ec_dt'] * float(np.exp(rng.normal(0, 0.08)))
    return q


def snappy(p):
    q = dict(p)
    q['t_hit'] = 0.045; q['wh_tau'] *= 0.5; q['wh_pk'] *= 0.5
    return q


def echo(p):
    q = dict(p)
    q['rc_lv'] += 3.0; q['ec_g'] = min(0.85, q['ec_g'] + 0.15); q['ec_n'] = 6
    q['rt_lv'] += 4.0; q['p2_lv'] += 4.0; q['rc_dk'] *= 0.8
    return q


CANDIDATES = [
    ('A_close', lambda p: p, '참고음 구조 그대로 — 휘익(90ms) → 철판 충돌·떨림 → 철판 울림 → 도탄 핑·메아리'),
    ('B_snappy', snappy, '휘익을 절반(45ms)으로 줄여 충돌이 빨리 온다 — 패링 반응감'),
    ('C_echo', echo, '튕기는 핑과 메아리, 튕긴 뒤 금속 떨림을 강조'),
]


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    p0 = base()
    for ci, (name, fn, _) in enumerate(CANDIDATES):
        q = fn(p0)
        for v in range(VARIANTS):
            r = np.random.default_rng(700 * ci + v)
            write(os.path.join(OUT, name, f'{name}_{v + 1:02d}.wav'), Q.render(vary(q, r) if v else dict(q), r))
        print(name)
