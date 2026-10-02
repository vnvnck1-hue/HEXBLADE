"""패링 효과음 3차 — 짧게(0.45~0.75초), 버전마다 1개, 철판 몸통 울림(중저음 무게감) 추가.

2차(parry2_candidates.py) 검토: 길다, 철판 무게감이 약하다(중저음). 측정해 보니 100~800Hz '양'은 이미
참고음보다 많았고, 빠진 것은 '둥~' 하고 울리는 몸통 음과 과한 8kHz+ 꼬리였다.
그래서 parry2_synth 에 몸통 모드(body: 판 진동 비율의 180~600Hz 사인 7개)와 고역 꼬리 조절(pl_hi)을 넣고,
도탄·메아리·충돌 노이즈를 앞당기고 짧게 줄였다. 기준 수치는 parry2_fit_params.json.
  S1_short : 2차 A 를 0.6초로 압축 + 몸통 울림 — 가장 원본에 가까운 짧은 판
  S2_heavy : 몸통 울림을 크게·낮게(150Hz), 울림 전체를 12% 낮춤 — 무거운 철판
  S3_anvil : 0.45초, 휘익 40ms, 단단한 몸통(220Hz) + 한 번의 핑 — 짧고 단단한 '캉'
  S4_gong  : 0.75초, 낮고 긴 몸통(130Hz) '둥~' 위에 핑과 메아리 — 무겁게 울리는 쪽

실행: python tools/sfx/parry3_candidates.py  →  output/parry-sound-candidates-20261002/v3/
"""
import os
import numpy as np
import parry2_synth as Q
from parry2_candidates import base
from parry_candidates import write

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', '..', 'output', 'parry-sound-candidates-20261002', 'v3')


def short(p, dur=0.6, t_hit=0.07):
    """공통 압축: 휘익·도탄·메아리를 당기고 노이즈·울림을 빨리 줄인다, 8kHz+ 꼬리 줄임"""
    q = dict(p)
    k = t_hit / q['t_hit']
    q['t_hit'] = t_hit; q['wh_tau'] *= k; q['wh_pk'] *= k
    q['rc_dt'] = 0.16; q['p2_dt'] = 0.16; q['ec_dt'] = 0.10; q['ec_n'] = 2
    q['rc_dk'] = 120.0; q['pl_dk'] *= 1.6
    q['im_gate'] = 0.16; q['im_tau'] = 0.12
    q['pl_hi'] = -10.0
    q['dur'] = dur
    # 몸통 울림이 '음'으로 들리도록 충돌 노이즈의 125~400Hz 를 낮춘다 (노이즈가 몸통 음을 덮지 않게)
    g = list(q['im_g']); g[1] -= 6.0; g[2] -= 6.0; q['im_g'] = g
    return q


def s1(p):
    q = short(p)
    q['bd_lv'] = 0.0; q['bd_f'] = 190.0; q['bd_dk'] = 45.0
    return q, 1.0


def s2(p):
    q = short(p, 0.65)
    q['bd_lv'] = 6.0; q['bd_f'] = 150.0; q['bd_dk'] = 30.0
    q['th_lv'] += 3.0
    return q, 0.88


def s3(p):
    q = short(p, 0.45, 0.04)
    q['bd_lv'] = 4.0; q['bd_f'] = 220.0; q['bd_dk'] = 55.0
    q['rc_dt'] = 0.10; q['p2_lv'] = -40.0; q['ec_n'] = 1; q['im_gate'] = 0.10; q['rt_lv'] -= 6.0
    return q, 1.0


def s4(p):
    q = short(p, 0.75)
    q['bd_lv'] = 5.0; q['bd_f'] = 130.0; q['bd_dk'] = 22.0
    q['ec_n'] = 3; q['rc_dk'] = 95.0
    return q, 0.8


CANDIDATES = [
    ('S1_short', s1, '2차 A 를 0.6초로 압축 + 몸통 울림 — 가장 원본에 가까운 짧은 판'),
    ('S2_heavy', s2, '몸통 울림을 크게·낮게(150Hz), 울림 전체를 12% 낮춤 — 무거운 철판 (0.65초)'),
    ('S3_anvil', s3, '0.45초, 휘익 40ms, 단단한 몸통(220Hz) + 한 번의 핑 — 짧고 단단한 캉'),
    ('S4_gong', s4, '0.75초, 낮고 긴 몸통(130Hz) 둥~ 위에 핑과 메아리 — 무겁게 울림'),
]


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    p0 = base()
    for ci, (name, fn, _) in enumerate(CANDIDATES):
        q, fmul = fn(p0)
        write(os.path.join(OUT, f'{name}.wav'), Q.render(q, np.random.default_rng(900 + ci), fmul))
        print(name, q['dur'])
