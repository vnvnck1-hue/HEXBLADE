"""패링 효과음 5차 — 1차 B_instant(parry_candidates.py) 를 기본으로 더 명쾌하게. 버전마다 1개.

B_instant 측정(clarity.py): 첫 정점 47ms(부풀어 오르듯 시작, 첫 5ms 가 뒤보다 1dB 작음), 200~800Hz 비중 -10dB(탁함),
1.77kHz 팅 선명도 22dB(이미 좋음). 층별로 나눠 보니 늦게 오는 쿵(저음 노이즈가 200~800Hz 로 샘)이 정점 지연과 탁함의
주원인, 다음이 본 타격 노이즈. → 음색은 그대로 두고 시작·탁함·노이즈 길이를 정리한다.
  C1_clean: 시작 클릭 + 본 타격을 바로 세움, 125~400Hz 노이즈 -6dB, 본 타격 0.11초에 끊음 (0.85초)
  C2_crisp: 더 센 클릭과 4~10kHz 순간 섬광, 탁함 -10dB, 0.07초에 끊음, 팅 +6dB — 가장 또렷하고 짧음 (0.7초)
  C3_bell : 본 타격 노이즈 자체를 -6dB, 낮은 울림·지글거리는 고역 울림을 줄이고 팅 +8dB — 맑은 종소리 쪽 (0.95초)

실행: python tools/sfx/parry5_clear.py  →  output/parry-sound-candidates-20261002/v5/
"""
import os, math
import numpy as np
import parry_synth as P
import mg_synth as G
from parry_candidates import base, instant, render, write

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', '..', 'output', 'parry-sound-candidates-20261002', 'v5')
SR = P.SR


def clean_common(q, cut, mud_db, click_db, dur):
    q = dict(q)
    q['ht_att'] = 0.001; q['th_att'] = 0.002          # 바로 서는 본 타격
    # 쿵이 충돌보다 41ms 늦게 와서 정점이 47ms 로 밀렸다 → 충돌과 함께. 쿵 노이즈가 200~800Hz 로 새던 것(탁함의 주원인)을 막는다
    q['th_t0'] = 0.0; q['th_g'] = [0.0, -3.0, -36.0, -40.0, -40.0, -40.0]
    q['drive'] = min(q['drive'], 1.6)
    q['ht_cut'] = cut; q['ht_rel'] = 0.008
    q['ht_g1'] += mud_db; q['ht_g2'] += mud_db        # 125~400Hz 노이즈 (탁함)
    q['tk_g1'] += mud_db; q['tk_g2'] += mud_db
    q['tk_lv'] += click_db; q['tk_tau'] = 0.004       # 시작 클릭: 짧고 세게
    q['_dur'] = dur
    return q


def c1(p):
    return clean_common(instant(p), 0.11, -6.0, 10.0, 0.85)


def c2(p):
    q = clean_common(instant(p), 0.07, -10.0, 14.0, 0.7)
    q['ting_lv'] += 6.0
    q['_flash'] = True
    return q


def c3(p):
    q = clean_common(instant(p), 0.09, -8.0, 8.0, 0.95)
    q['ht_lv'] -= 6.0
    q['rg_lo'] -= 8.0; q['rg_hi'] -= 6.0
    q['ting_lv'] += 8.0
    return q


def flash(n, rng):
    """4~10kHz 순간 섬광 (첫 15ms) — 시작을 더 밝고 또렷하게"""
    t = np.arange(n) / SR
    nz = G.shaped(G.octave_noise(int(rng.integers(0, 1 << 30)), n), [-40, -40, -40, -24, 0, -4])
    return nz * G.env(t, 0, 0.0003, 0.006)


def make(q, rng):
    x = render(q, rng)
    n = int(q['_dur'] * SR); x = x[:n].copy()
    if q.get('_flash'):
        x += flash(n, rng) * 0.9
    t = np.arange(n) / SR; k = t / q['_dur']
    x *= np.where(k < 0.7, 1.0, np.cos((k - 0.7) / 0.3 * math.pi / 2) ** 2)
    return x / (np.abs(x).max() + 1e-9) * 0.89


CANDIDATES = [
    ('C1_clean', c1, '시작 클릭 + 바로 서는 본 타격, 125~400Hz 노이즈 -6dB, 본 타격 0.11초에 끊음 (0.85초)'),
    ('C2_crisp', c2, '더 센 클릭과 4~10kHz 순간 섬광, 탁함 -10dB, 0.07초에 끊음, 팅 +6dB — 가장 또렷하고 짧음 (0.7초)'),
    ('C3_bell', c3, '본 타격 노이즈 -6dB, 낮은 울림·지글거리는 고역을 줄이고 팅 +8dB — 맑은 종소리 쪽 (0.95초)'),
]


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    p0 = base()
    for name, fn, _ in CANDIDATES:
        # B_instant_01 과 같은 무작위 시드 (같은 노이즈·위상에서 출발)
        write(os.path.join(OUT, f'{name}.wav'), make(fn(p0), np.random.default_rng(500 * 1 + 0)))
        print(name)
