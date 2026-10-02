"""패링 효과음 후보 3종 — 노이즈·사인만으로 합성, 샘플 없음.

기준 수치(parry_fit_params.json)는 parry_fit.py 가 참고음(금속성 헤드샷 타격음)의
시간-주파수 에너지 분포에 맞춰 찾은 값이다. 금속 울림 모드 목록은 parry_synth.MODES.
  A_close  : 기준 그대로 — 예비 타격 → 본 타격 → 금속 울림의 시간 구조까지 참고음을 따름
  B_instant: 같은 음색, 본 타격과 울림이 판정 순간 바로 터짐 (예비 간격 제거)
  C_crystal: B 바탕, 울림을 더 높고(+9%) 길게, 저음을 줄여 맑고 시원한 쪽으로
각 후보 변형 4개 (재생마다 고르기용).

실행: python tools/sfx/parry_candidates.py  →  output/parry-sound-candidates-20261002/
"""
import os, json, wave
import numpy as np
import parry_synth as P

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', '..', 'output', 'parry-sound-candidates-20261002')
VARIANTS = 4


def base():
    b = json.load(open(os.path.join(HERE, 'parry_fit_params.json'), encoding='utf-8'))['base']
    p = {k: (v / 1000.0 if k in P.MS else v) for k, v in b.items()}
    # 탐색 위의 손 보정 (작은 격자 탐색, 기준 = 분포 오차 + 1.77kHz '팅' 두드러짐):
    # 울림 시작을 당겨 '팅'이 본 타격이 끊기는 0.3초쯤 드러나게 하고 '팅'을 8dB 키운다
    # (구간별 팅/주변 dB: 참고음 7/10/13/33/48, 보정 후 4/6/13/27/52)
    p['rg_t'] = 1.3; p['ht_rel'] = 0.015
    p['ting_lv'] += 8.0
    return p


def vary(p, rng, k=0.5):
    """변형: 음량·시간만 조금 흔든다 (울림 음높이는 renderer 의 fmul 로 따로)"""
    q = dict(p)
    for key, v in p.items():
        if key.endswith('_lv') or '_g' in key:
            q[key] = v + rng.normal(0, 2.0 * k)
        elif key in P.MS:
            q[key] = v * float(np.exp(rng.normal(0, 0.12 * k)))
        elif key in ('th_f0', 'th_f1'):
            q[key] = v * float(np.exp(rng.normal(0, 0.08 * k)))
    return q


def instant(p):
    """본 타격·쿵·울림을 판정 순간으로 당긴다. 당긴 만큼 예비 타격은 본 타격에 묻힌다"""
    q = dict(p)
    shift = min(q['ht_t0'], q['th_t0'])
    q['ht_t0'] -= shift; q['th_t0'] -= shift
    # 울림을 당긴 만큼 본 타격도 일찍 끊어 '팅'이 바로 드러나게 (참고음은 본 타격이 끊기는 순간 팅이 나온다)
    q['ht_cut'] = 0.17
    q['ht_att'] = min(q['ht_att'], 0.006)
    q['th_att'] = min(q['th_att'], 0.006)
    q['_mode_shift'] = shift
    return q


def crystal(p):
    q = instant(p)
    q['rg_dk'] *= 0.75
    q['rg_lv'] += 3.0
    q['th_lv'] -= 6.0
    for i in (0, 1):
        q[f'ht_g{i}'] -= 6.0
    for i in (4, 5):
        q[f'ht_g{i}'] += 3.0
    q['_fmul'] = 1.09
    return q


def shifted_modes(shift):
    """모드 시작 시각을 shift 만큼 당기되, 먼저 울리는 모드와의 간격은 절반만 남긴다"""
    return [(f, max(0.0, (st - shift) * 0.5), lv, dk) for f, st, lv, dk in P.MODES]


CANDIDATES = [
    ('A_close', lambda p: p, '참고음 구조 그대로 — 작은 예비 타격 뒤 0.1~0.2초에 본 타격·저음 쿵, 이어서 맑은 금속 울림'),
    ('B_instant', instant, '같은 음색을 판정 순간 바로 — 본 타격과 울림이 즉시 터져 패링 반응이 빠름'),
    ('C_crystal', crystal, 'B 바탕, 울림을 9% 높고 25% 길게, 저음은 줄임 — 더 맑고 시원한 쪽'),
]


def render(q, rng):
    modes = shifted_modes(q['_mode_shift']) if '_mode_shift' in q else P.MODES
    return P.render(q, rng, modes, q.get('_fmul', 1.0))


def write(path, x):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(P.SR)
        w.writeframes((np.clip(x, -1, 1) * 32000).astype('<i2').tobytes())


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    open(os.path.join(OUT, '.gdignore'), 'w').close()
    p0 = base()
    for ci, (name, fn, _) in enumerate(CANDIDATES):
        q = fn(p0)
        for v in range(VARIANTS):
            r = np.random.default_rng(500 * ci + v)
            qq = vary(q, r) if v else dict(q)
            write(os.path.join(OUT, name, f'{name}_{v + 1:02d}.wav'), render(qq, r))
        print(name)
