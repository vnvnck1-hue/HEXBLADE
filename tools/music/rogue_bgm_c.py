"""HEX DEPTHS BGM 세 번째 곡 C. MIDNIGHT HEX (2차) — 80년대 신스팝 R&B (After Hours 시절 위켄드의 느린 곡 느낌)

1차(168 BPM · 탬버린 16분 · 쉬지 않는 리프 · 모음 필터 가짜 보컬)는 사용자 반려 → 2차:
템포 DEEP SIGNAL 과 같은 104 BPM, 여유 있는 그루브, 가짜 보컬 삭제. 멜로디는 모두 새로 씀.
numpy/scipy 합성만. 렌더 · 믹스 · 마스터는 rogue_bgm.py(→ lancaster_bgm.py 엔진)를 쓴다.
실행:
    uv run --no-project --with numpy --with scipy python tools/music/rogue_bgm_c.py

104 BPM · G 단조 · 루프 32마디
    HOOK   8마디  Gm7 Ebmaj7 F Dm7   미끄러지는 신스 리드 훅 + FM 일렉트릭 피아노 엇박 화음 + 엇박 킥 · 큰 스네어
    VERSE  8마디  같은 진행           낮은 리드 · 드럼 가볍게
    CHORUS 8마디  같은 진행           높은 리드 + 옥타브 아래 겹침 · 플럭 아르페지오 · 크래시
    BRIDGE 8마디  Cm7 Ebmaj7 Bbmaj7 D7 ×2  하프타임 · 긴 화음 · 끝 2마디 롤 · 라이저 → D7 에서 HOOK 로
"""
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lancaster_bgm as L  # noqa: E402
import rogue_bgm as R  # noqa: E402

SR = L.SR
ns = L.ns
hz = L.hz
filt = L.filt
rng = np.random.default_rng(104)

BPM = 104
SWING = 0.14                                           # 엇박 16분을 STEP 의 14% 늦게
CH = {'Gm7': [62, 65, 67, 70], 'Ebmaj7': [63, 67, 70, 74], 'F': [65, 67, 69, 72], 'Dm7': [62, 65, 69, 72],
      'Cm7': [63, 67, 70, 72], 'Bbmaj7': [62, 65, 69, 70], 'D7': [62, 66, 69, 72]}
ROOT = {'Gm7': 43, 'Ebmaj7': 39, 'F': 41, 'Dm7': 38, 'Cm7': 36, 'Bbmaj7': 34, 'D7': 38}
PROG = ['Gm7', 'Ebmaj7', 'F', 'Dm7'] * 2
BRIDGE = ['Cm7', 'Ebmaj7', 'Bbmaj7', 'D7'] * 2
GROOVE = [0, None, None, 0, None, None, 12, None, 0, None, None, 0, None, 12, None, 10]   # 엇박 베이스
EP_HITS = [(0, 5), (6, 3), (10, 5)]                    # 일렉트릭 피아노 (16분 위치, 길이)

# (마디, 16분 위치, 길이, 음) — 모두 새로 쓴 선율
HOOK = [
    (0, 2, 2, 74), (0, 4, 2, 77), (0, 6, 4, 79), (0, 10, 2, 77), (0, 12, 4, 74),
    (1, 2, 2, 75), (1, 4, 2, 74), (1, 6, 6, 70), (1, 12, 4, 67),
    (2, 2, 2, 72), (2, 4, 2, 74), (2, 6, 4, 77), (2, 10, 2, 79), (2, 12, 4, 81),
    (3, 0, 8, 77), (3, 10, 2, 74), (3, 12, 4, 72),
    (4, 2, 2, 74), (4, 4, 2, 77), (4, 6, 4, 79), (4, 10, 2, 77), (4, 12, 4, 74),
    (5, 2, 2, 75), (5, 4, 2, 74), (5, 6, 6, 70), (5, 12, 4, 74),
    (6, 2, 2, 77), (6, 4, 2, 79), (6, 6, 4, 81), (6, 10, 2, 82), (6, 12, 4, 81),
    (7, 0, 12, 77), (7, 12, 4, 74),
]
VERSE = [
    (0, 4, 2, 70), (0, 6, 2, 70), (0, 8, 4, 74), (0, 12, 4, 72),
    (1, 0, 6, 70), (1, 8, 2, 67), (1, 10, 2, 70), (1, 12, 4, 72),
    (2, 4, 2, 72), (2, 6, 2, 72), (2, 8, 4, 77), (2, 12, 4, 74),
    (3, 0, 10, 72), (3, 12, 4, 69),
    (4, 4, 2, 70), (4, 6, 2, 70), (4, 8, 4, 74), (4, 12, 4, 77),
    (5, 0, 6, 75), (5, 8, 2, 74), (5, 10, 2, 72), (5, 12, 4, 70),
    (6, 4, 2, 72), (6, 6, 2, 74), (6, 8, 4, 77), (6, 12, 4, 79),
    (7, 0, 16, 74),
]
CHORUS = [
    (0, 0, 6, 82), (0, 6, 2, 81), (0, 8, 8, 79),
    (1, 0, 6, 82), (1, 6, 2, 84), (1, 8, 8, 79),
    (2, 0, 4, 81), (2, 4, 4, 79), (2, 8, 4, 77), (2, 12, 4, 81),
    (3, 0, 12, 77), (3, 12, 4, 74),
    (4, 0, 6, 82), (4, 6, 2, 84), (4, 8, 8, 86),
    (5, 0, 6, 87), (5, 6, 2, 86), (5, 8, 8, 82),
    (6, 0, 4, 84), (6, 4, 4, 82), (6, 8, 4, 81), (6, 12, 4, 77),
    (7, 0, 16, 79),
]


def ts(step):
    """스윙: 엇박 16분만 살짝 늦게."""
    return R.T(step) + (SWING * L.STEP if step % 2 else 0.0)


# ── 이 곡 전용 악기 ───────────────────────────────────
def mk_clap():
    n = ns(0.35)
    t = np.arange(n) / SR
    env = np.zeros(n)
    for d in (0.0, 0.011, 0.022):
        m = t >= d
        env[m] += np.exp(-(t[m] - d) / 0.006)
    m = t >= 0.03
    env[m] += 0.6 * np.exp(-(t[m] - 0.03) / 0.09)
    return filt(rng.standard_normal(n), 'bandpass', (900, 3500)) * env * 0.8


def mk_shaker():
    n = ns(0.09)
    t = np.arange(n) / SR
    env = np.clip(t / 0.012, 0, 1) * np.exp(-t / 0.03)
    return filt(rng.standard_normal(n), 'bandpass', (4500, 11000)) * env * 0.6


_ep_cache = {}


def epiano(m, dur):
    """FM 일렉트릭 피아노 (DX 계열): 1:1 변조가 빨리 둥글어지고 14배 고음 '팅'이 짧게."""
    key = (m, round(dur, 4))
    if key in _ep_cache:
        return _ep_cache[key]
    n = ns(dur + 0.8)
    t = np.arange(n) / SR
    f = hz(m)
    idx = 1.8 * np.exp(-t / 0.3) + 0.25
    x = np.sin(2 * np.pi * f * t + idx * np.sin(2 * np.pi * f * t))
    x += 0.18 * np.sin(2 * np.pi * f * 14 * t) * np.exp(-t / 0.025)
    x *= 1 + 0.12 * np.sin(2 * np.pi * 4.5 * t)                     # 살짝 트레몰로
    out = x * L.adsr(n, 0.002, 0.9, 0.45, 0.22, dur) * 0.16
    _ep_cache[key] = out
    return out


def silk(m, dur, prev=None):
    """부드러운 신스 리드: 앞 음에서 미끄러져 들어옴 + 늦은 비브라토, 톱니 둘 + 사인 서브, 밝기는 시작 때만."""
    n = ns(dur + 0.4)
    t = np.arange(n) / SR
    glide = 0.0 if prev is None else (prev - m) * np.exp(-t / 0.028)
    vib = 0.16 * np.sin(2 * np.pi * 5.0 * t) * np.clip((t - 0.25) / 0.3, 0, 1)
    f = hz(m) * 2 ** ((glide + vib) / 12)
    x = L.saw(f * 2 ** (0.07 / 12), n, 0.3) + L.saw(f * 2 ** (-0.07 / 12), n, 0.8) + 0.6 * np.sin(2 * np.pi * np.cumsum(f / 2) / SR)
    fe = np.exp(-t / 0.18)
    x = filt(x, 'lowpass', 1700) * (1 - fe) + filt(x, 'lowpass', 3600) * fe
    return x * L.adsr(n, 0.012, 0.4, 0.78, 0.16, dur) * 0.26


# ── 배치 ──────────────────────────────────────────────
def kick(mx, step, gain=1.0):
    mx.add('drums', L.S['kick'], ts(step), gain=gain)
    mx.kicks.append(ts(step))


def big_snare(mx, step, gain=1.0):
    mx.add('drums', L.S['gsnare'], ts(step), gain=gain * 0.75, rev=0.55)
    mx.add('drums', L.S['clap'], ts(step), pan=-0.05, gain=gain * 0.5, rev=0.4)


def hat(mx, step, gain=1.0, open_=False):
    x = L.S['ohat'] if open_ else L.S['hat'][step % 4]
    mx.add('drums', x, ts(step), pan=0.25, gain=gain * 0.25)


def shaker(mx, step, gain=1.0):
    mx.add('drums', L.S['shaker'], ts(step), pan=-0.35, gain=gain * 0.22)


def groove(mx, s, bars, light=False, fill=False):
    for b in range(bars):
        bs = s + b * 16
        for st in (0, 7, 10) + ((14,) if b % 2 else ()):
            kick(mx, bs + st, 0.85 if light else 1.0)
        big_snare(mx, bs + 4, 0.85 if light else 1.0)
        if not (fill and b == bars - 1):
            big_snare(mx, bs + 12, 0.85 if light else 1.0)
        for st in range(0, 16, 2):
            hat(mx, bs + st, 0.55 if st % 4 else 0.75)
        if not light:
            hat(mx, bs + 14, 0.7, open_=True)
        for st in range(16):
            shaker(mx, bs + st, (0.8, 0.35, 0.55, 0.35)[st % 4] * (0.7 if light else 1.0))
        if fill and b == bars - 1:
            R.tom(mx, bs + 10)
            R.tom(mx, bs + 12)
            R.tom(mx, bs + 13, False)
            R.tom(mx, bs + 14, False)
            big_snare(mx, bs + 15, 0.7)


def bass(mx, s, chords, pat=GROOVE, fc=1100, length=1.6, gain=1.0):
    for b, c in enumerate(chords):
        for st, off in enumerate(pat):
            if off is None:
                continue
            acc = 1.0 if st == 0 else 0.85
            mx.add('bass', L.bass_note(ROOT[c] + off, L.STEP * length, fc), ts(s + b * 16 + st), gain=gain * acc * 0.55)


def ep_chords(mx, s, chords, gain=1.0, hits=EP_HITS):
    for b, c in enumerate(chords):
        for st, ln in hits:
            for i, m in enumerate(CH[c]):
                pan = (-0.35, -0.12, 0.12, 0.35)[i]
                mx.add('arp', epiano(m, ln * L.STEP), ts(s + b * 16 + st), pan=pan, gain=gain, rev=0.3, dly=0.08)


def lead(mx, s, phrase, gain=1.0, shift=0, octave=False, dly=0.25):
    prev = None
    for bar, st, ln, m in phrase:
        t0 = ts(s + bar * 16 + st)
        dur = ln * L.STEP * 0.95
        mx.add('lead', silk(m + shift, dur, prev), t0, pan=0.05, gain=gain, rev=0.3, dly=dly)
        if octave:
            mx.add('lead', silk(m + shift - 12, dur, None if prev is None else prev - 12), t0, pan=-0.2, gain=gain * 0.45, rev=0.2)
        prev = m + shift


def tones(ch):
    return sorted(ch + [m + 12 for m in ch])


def song_c(mx):
    s = 0                                              # HOOK
    R.crash(mx, s, 0.5)
    groove(mx, s, 8)
    bass(mx, s, PROG)
    R.pads(mx, s, PROG, CH, cutoff=2200, gain=0.9, rev=0.45)
    ep_chords(mx, s, PROG)
    lead(mx, s, HOOK)
    s = 128                                            # VERSE
    groove(mx, s, 8, light=True)
    bass(mx, s, PROG, fc=900)
    R.pads(mx, s, PROG, CH, cutoff=1600, gain=0.8, rev=0.45)
    ep_chords(mx, s, PROG, gain=0.85)
    lead(mx, s, VERSE, gain=0.9, dly=0.3)
    s = 256                                            # CHORUS
    R.crash(mx, s, 0.6)
    groove(mx, s, 8, fill=True)
    bass(mx, s, PROG, fc=1400)
    R.pads(mx, s, PROG, CH, cutoff=3000, gain=1.0, rev=0.45)
    ep_chords(mx, s, PROG, gain=0.8)
    R.arp(mx, s, PROG, CH, [0, 2, 4, 6, 5, 3, 1, 3], tones, gain=0.45, cutoff=3200, pan=0.5)
    lead(mx, s, CHORUS, gain=1.0, octave=True)
    s = 384                                            # BRIDGE: 하프타임 · 긴 화음
    R.crash(mx, s, 0.4)
    R.pads(mx, s, BRIDGE, CH, cutoff=2400, gain=1.1, rev=0.6)
    ep_chords(mx, s, BRIDGE, gain=0.9, hits=[(0, 14)])
    for b, c in enumerate(BRIDGE):
        mx.add('bass', L.bass_note(ROOT[c], L.STEP * 7, 700), ts(s + b * 16), gain=0.5)
        mx.add('bass', L.bass_note(ROOT[c], L.STEP * 5, 700), ts(s + b * 16 + 10), gain=0.4)
        bs = s + b * 16
        if b < 6:
            kick(mx, bs)
            kick(mx, bs + 10, 0.7)
            big_snare(mx, bs + 8, 0.9)
            for st in range(0, 16, 4):
                hat(mx, bs + st + 2, 0.5)
        else:                                          # 마지막 두 마디: 다시 몰아침
            for st in (0, 4, 8, 12):
                kick(mx, bs + st, 0.8)
            for st in range(0 if b == 7 else 8, 16, 1 if b == 7 else 2):
                R.snare(mx, bs + st, 0.35 + 0.6 * (st / 16) + (0.1 if b == 7 else 0))
    lead(mx, s, [(1, 0, 8, 74), (1, 8, 8, 70), (3, 0, 16, 72), (5, 0, 8, 74), (5, 8, 8, 77), (7, 0, 16, 78)],
         gain=0.75, dly=0.4)
    mx.add('fx', L.mk_riser(L.BAR * 2), R.T(s + 96), gain=0.8, rev=0.2)


SONG = {'id': 'C_midnight_hex', 'title': 'MIDNIGHT HEX', 'bpm': BPM, 'bars': 32, 'fn': song_c, 'sc': 0.35,
        'gain': {'drums': 0.72, 'bass': 1.0, 'pad': 1.15, 'lead': 1.1, 'arp': 0.75, 'fx': 0.8},
        'sections': (('HOOK', 0, 8), ('VERSE', 8, 16), ('CHORUS', 16, 24), ('BRIDGE', 24, 32))}


def main():
    os.makedirs(R.OUT, exist_ok=True)
    L.samples()
    L.S['clap'] = mk_clap()
    L.S['shaker'] = mk_shaker()
    L.IR = (L.make_ir(53, sec=3.0, tau=0.7), L.make_ir(59, sec=3.0, tau=0.7))
    mx, loop, prev, n = R.render(SONG)
    base = os.path.join(R.OUT, f"rogue_bgm_{SONG['id']}")
    L.write_wav(base + '_loop.wav', loop)
    L.write_wav(base + '_preview.wav', prev)
    w = ns(0.05)
    seam = float(np.max(np.abs(np.concatenate([loop[:, :w], loop[:, -w:]], axis=1)
                               - np.concatenate([prev[:, n:n + w], prev[:, n - w:n]], axis=1))))
    sec = {}
    for name, b0, b1 in SONG['sections']:
        seg = loop[:, ns(b0 * L.BAR):ns(b1 * L.BAR)]
        sec[name] = L.db(np.sqrt(np.mean(seg ** 2)))
    rep = {
        'title': SONG['title'] + ' (2차)', 'bpm': BPM, 'bars': SONG['bars'],
        'loop_seconds': round(n / SR, 4), 'loop_samples': n,
        'peak_dbfs': L.db(np.max(np.abs(loop))), 'rms_dbfs': L.db(np.sqrt(np.mean(loop ** 2))),
        'clipped_samples': int(np.sum(np.abs(loop) >= 0.999) + np.sum(np.abs(prev) >= 0.999)),
        'dc_offset': [round(float(np.mean(loop[0])), 5), round(float(np.mean(loop[1])), 5)],
        'seam_vs_natural_max_diff': round(seam, 6),
        'section_rms_dbfs': sec,
        'band_energy_db': L.bands(loop),
        'bus_rms_dbfs_premix': L.bus_rms(mx),
    }
    print(json.dumps(rep, ensure_ascii=False))
    vpath = os.path.join(R.OUT, 'validation.json')
    data = {}
    if os.path.exists(vpath):
        with open(vpath, encoding='utf-8') as f:
            data = json.load(f)
    data[SONG['id']] = rep
    with open(vpath, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


if __name__ == '__main__':
    main()
