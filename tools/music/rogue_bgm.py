"""HEX DEPTHS (로그라이크 모드) BGM 두 곡 — 신스웨이브 두 스타일 (numpy/scipy 합성만, 샘플·외부 음원 없음)

악기 · 효과 · 마스터는 lancaster_bgm.py 엔진을 그대로 쓴다 (모듈 템포 값을 곡마다 바꿔 끼움).
실행:
    uv run --no-project --with numpy --with scipy python tools/music/rogue_bgm.py

A. NEON DESCENT — 밝은 아웃런. 132 BPM · A 단조 ↔ C 장조. 초반 층 · 빠른 전투.
    A  8마디  Am F C G        주제 리드 + 8분 옥타브 베이스 + 크게 울리는 스네어
    B  8마디  F G Em Am F G C E   올라가는 후렴, 마지막 E 장조로 긴장 → A
    A' 8마디  Am F C G        주제 + 옥타브 아래 겹침 + 아르페지오
    BR 8마디  F F C C Dm Dm E E   브레이크다운: 드럼 빠짐 → 킥 복귀 → 롤 · 라이저
B. DEEP SIGNAL — 카펜터풍 호러 신스. 104 BPM · E 단조(프리지안 F). 깊은 층 · 긴장.
    S1 8마디  Em Em F Em Em C Am B   반복 아르페지오 + 저음 드론 + 심장박동 킥 (성김)
    S2 8마디  같은 진행        하프타임 드럼 · 8분 베이스 · FM 종 선율
    S3 8마디  같은 진행        16분 베이스 · 톱니 리드 · 16분 하이햇
    S4 8마디  같은 진행        절정: 한 옥타브 위 선율 · 탐 · 크래시 → 가라앉으며 S1 로
결과: output/rogue-bgm-20261013/
    rogue_bgm_A_neon_descent_loop.wav · rogue_bgm_B_deep_signal_loop.wav   (그대로 반복 재생하면 이어짐)
    *_preview.wav   루프 두 번 (이음새 확인용)
    spectrogram_*.png (tools/music/spectro_png.py) · validation.json
"""
import json
import math
import os
import sys

import numpy as np
from scipy import signal

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lancaster_bgm as L  # noqa: E402

SR = L.SR
OUT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..',
                                    'output', 'rogue-bgm-20261013'))
rng = np.random.default_rng(13)
ns = L.ns
hz = L.hz
filt = L.filt


def set_tempo(bpm):
    L.BPM = bpm
    L.STEP = 60.0 / bpm / 4
    L.BAR = L.STEP * 16


def T(step):
    return step * L.STEP


# ── 추가 악기 ─────────────────────────────────────────
_bell_cache = {}


def bell(m, dur):
    """FM 종: 비배음 3.5 배 변조, 시작 때 밝고 빨리 둥글어짐."""
    key = (m, round(dur, 3))
    if key in _bell_cache:
        return _bell_cache[key]
    n = ns(dur + 1.6)
    t = np.arange(n) / SR
    f = hz(m)
    idx = 3.2 * np.exp(-t / 0.22) + 0.5
    x = np.sin(2 * np.pi * f * t + idx * np.sin(2 * np.pi * f * 3.5 * t))
    x += 0.35 * np.sin(2 * np.pi * f * 2 * t) * np.exp(-t / 0.4)
    env = np.clip(t / 0.002, 0, 1) * np.exp(-t / 1.1)
    out = x * env * 0.22
    _bell_cache[key] = out
    return out


def drone(m, dur):
    """저음 드론: 사인 + 아주 어둡게 거른 톱니 둘."""
    n = ns(dur + 0.6)
    t = np.arange(n) / SR
    f = hz(m)
    x = 0.8 * np.sin(2 * np.pi * f * t)
    x += 0.5 * filt(L.saw(f * 1.004, n, rng.random()) + L.saw(f * 0.996, n, rng.random()), 'lowpass', 260)
    return x * L.adsr(n, 0.4, 1.0, 0.9, 0.4, dur) * 0.45


def wind(dur):
    n = ns(dur)
    t = np.arange(n) / SR
    x = filt(rng.standard_normal(n), 'bandpass', (250, 1400))
    mod = 0.55 + 0.45 * np.sin(2 * np.pi * t / 5.3) * np.sin(2 * np.pi * t / 2.1 + 1)
    return x * mod * np.clip(t / 2.0, 0, 1) * np.clip((dur - t) / 2.0, 0, 1) * 0.12


def gated_snare():
    """아웃런식 큰 스네어: 기본 스네어 + 짧게 잘린 노이즈 꼬리."""
    base = L.S['snare']
    n = ns(0.32)
    t = np.arange(n) / SR
    tail = filt(rng.standard_normal(n), 'bandpass', (700, 7000)) * np.where(t < 0.22, 0.45, 0.45 * np.exp(-(t - 0.22) / 0.015))
    out = np.zeros(max(len(base), n))
    out[:len(base)] += base
    out[:n] += tail
    return np.tanh(out * 1.2)


# ── 공통 배치 도우미 ─────────────────────────────────
def kick(mx, step, gain=1.0):
    mx.add('drums', L.S['kick'], T(step), gain=gain)
    mx.kicks.append(T(step))


def snare(mx, step, gain=1.0, rev=0.28, big=False):
    x = L.S['gsnare'] if big else L.S['snare']
    mx.add('drums', x, T(step), gain=gain * 0.75, rev=rev)


def hat(mx, step, gain=1.0, open_=False, pan=0.25):
    x = L.S['ohat'] if open_ else L.S['hat'][step % 4]
    mx.add('drums', x, T(step), pan=pan, gain=gain * 0.25)


def crash(mx, step, gain=0.55):
    mx.add('drums', L.S['crash'], T(step), pan=-0.3, gain=gain, rev=0.2)


def tom(mx, step, hi=True, gain=0.75):
    mx.add('drums', L.S['tom_hi' if hi else 'tom_lo'], T(step), pan=0.3 if hi else -0.3, gain=gain, rev=0.25)


def roll(mx, bs, start=8, every=1, g0=0.4, g1=1.0, big=False):
    steps = list(range(bs + start, bs + 16, every))
    for i, st in enumerate(steps):
        snare(mx, st, g0 + (g1 - g0) * i / max(1, len(steps) - 1), big=big)


def pads(mx, s, chords, CH, cutoff=2400, gain=1.0, rev=0.35):
    for b, c in enumerate(chords):
        mx.add('pad', L.pad(CH[c], L.BAR, cutoff), T(s + b * 16), gain=gain * 0.55, rev=rev)


def bass(mx, s, chords, ROOT, pat, fc=1600, drive=0.0, gain=1.0, length=0.85):
    for b, c in enumerate(chords):
        for st, off in enumerate(pat):
            if off is None:
                continue
            acc = 1.0 if st % 4 == 0 else 0.82
            note = L.bass_note(ROOT[c] + off, L.STEP * length, fc, drive)
            mx.add('bass', note, T(s + b * 16 + st), gain=gain * acc * 0.5)


def lead(mx, s, phrase, gain=1.0, shift=0, octave_layer=False, pan=0.05, dly=0.22):
    for bar, st, ln, m in phrase:
        t0 = T(s + bar * 16 + st)
        dur = ln * L.STEP * 0.92
        mx.add('lead', L.lead_note(m + shift, dur), t0, pan=pan, gain=gain * 0.75, rev=0.22, dly=dly)
        if octave_layer:
            mx.add('lead', L.lead_note(m + shift - 12, dur), t0, pan=-0.15, gain=gain * 0.42, rev=0.15)


def bells(mx, s, phrase, gain=1.0, shift=0):
    for bar, st, ln, m in phrase:
        mx.add('lead', bell(m + shift, ln * L.STEP), T(s + bar * 16 + st), pan=-0.1, gain=gain, rev=0.45, dly=0.3)


def arp(mx, s, chords, CH, seq, tones_fn, gain=1.0, cutoff=4500, cut_fn=None, pan=0.45):
    for b, c in enumerate(chords):
        tones = tones_fn(CH[c])
        for st in range(16):
            i = b * 16 + st
            cu = cutoff if cut_fn is None else int(round(cut_fn(i) / 200.0) * 200)
            p = -pan if st % 2 else pan
            mx.add('arp', L.pluck(tones[seq[i % len(seq)]], cu), T(s + i), pan=p, gain=gain * 0.55, rev=0.25, dly=0.15)


# ── A. NEON DESCENT ───────────────────────────────────
A_BPM = 132
A_CH = {'Am': [69, 72, 76], 'F': [65, 69, 72], 'C': [67, 72, 76], 'G': [67, 71, 74],
        'Em': [64, 67, 71], 'E': [64, 68, 71], 'Dm': [65, 69, 74]}
A_ROOT = {'Am': 45, 'F': 41, 'C': 36, 'G': 43, 'Em': 40, 'E': 40, 'Dm': 38}
A_VERSE = ['Am', 'F', 'C', 'G'] * 2
A_CHORUS = ['F', 'G', 'Em', 'Am', 'F', 'G', 'C', 'E']
A_BREAK = ['F', 'F', 'C', 'C', 'Dm', 'Dm', 'E', 'E']
A_BASS = [0, None, 12, None, 0, None, 12, None, 0, None, 12, None, 0, None, 12, None]
A_BASS16 = [0, 0, 12, 0, 0, 0, 12, 0, 0, 0, 12, 0, 0, 12, 0, 12]
A_HOOK = [
    (0, 0, 4, 76), (0, 4, 2, 74), (0, 6, 2, 72), (0, 8, 6, 76), (0, 14, 2, 79),
    (1, 0, 4, 81), (1, 4, 4, 77), (1, 8, 8, 72),
    (2, 0, 2, 72), (2, 2, 2, 74), (2, 4, 4, 76), (2, 8, 4, 79), (2, 12, 4, 76),
    (3, 0, 6, 74), (3, 6, 2, 71), (3, 8, 8, 74),
    (4, 0, 4, 76), (4, 4, 2, 74), (4, 6, 2, 72), (4, 8, 6, 76), (4, 14, 2, 81),
    (5, 0, 4, 84), (5, 4, 4, 81), (5, 8, 8, 77),
    (6, 0, 4, 79), (6, 4, 4, 76), (6, 8, 4, 74), (6, 12, 4, 72),
    (7, 0, 8, 71), (7, 8, 8, 74),
]
A_CHORUS_MEL = [
    (0, 0, 6, 77), (0, 6, 2, 76), (0, 8, 8, 72),
    (1, 0, 6, 79), (1, 6, 2, 77), (1, 8, 8, 74),
    (2, 0, 4, 76), (2, 4, 4, 79), (2, 8, 4, 83), (2, 12, 4, 79),
    (3, 0, 12, 81), (3, 12, 4, 76),
    (4, 0, 4, 81), (4, 4, 4, 84), (4, 8, 8, 81),
    (5, 0, 4, 83), (5, 4, 4, 86), (5, 8, 8, 83),
    (6, 0, 4, 84), (6, 4, 4, 79), (6, 8, 4, 76), (6, 12, 4, 79),
    (7, 0, 8, 80), (7, 8, 8, 83),
]


def a_tones(ch):
    return sorted(ch + [m + 12 for m in ch])


def a_drums(mx, s, bars, fill=None):
    for b in range(bars):
        bs = s + b * 16
        last = b == bars - 1
        for st in (0, 4, 8, 12):
            kick(mx, bs + st)
        snare(mx, bs + 4, 1.0, rev=0.45, big=True)
        if not (last and fill):
            snare(mx, bs + 12, 1.0, rev=0.45, big=True)
        for st in range(16):
            if st % 4 == 2:
                hat(mx, bs + st, 0.85, open_=True)
            elif st % 2 == 0:
                hat(mx, bs + st, 0.55)
            else:
                hat(mx, bs + st, 0.3)
        if b % 2 == 1 and not last:
            snare(mx, bs + 15, 0.35)                      # 마디 끝 고스트 스네어
        if last and fill == 'snare':
            roll(mx, bs, 12, 1, 0.6, 1.0, big=True)
        elif last and fill == 'tom':
            tom(mx, bs + 10)
            tom(mx, bs + 12)
            tom(mx, bs + 13, False)
            tom(mx, bs + 14, False)
            snare(mx, bs + 15, 0.9, big=True)


def song_a(mx):
    s = 0                                              # A
    crash(mx, s)
    a_drums(mx, s, 8, 'snare')
    bass(mx, s, A_VERSE, A_ROOT, A_BASS, fc=1500)
    pads(mx, s, A_VERSE, A_CH, cutoff=2600)
    lead(mx, s, A_HOOK)
    s = 128                                            # B (후렴)
    crash(mx, s)
    a_drums(mx, s, 8, 'tom')
    bass(mx, s, A_CHORUS, A_ROOT, A_BASS16, fc=1900)
    pads(mx, s, A_CHORUS, A_CH, cutoff=3200, gain=1.05)
    arp(mx, s, A_CHORUS, A_CH, [0, 2, 4, 5, 4, 2, 1, 3], a_tones, gain=0.75, cutoff=3800)
    lead(mx, s, A_CHORUS_MEL, gain=1.05)
    s = 256                                            # A'
    crash(mx, s)
    a_drums(mx, s, 8, 'snare')
    bass(mx, s, A_VERSE, A_ROOT, A_BASS16, fc=1800)
    pads(mx, s, A_VERSE, A_CH, cutoff=3000, gain=1.05)
    arp(mx, s, A_VERSE, A_CH, [0, 1, 2, 3, 4, 5, 4, 3, 2, 1], a_tones, gain=0.65, cutoff=3200)
    lead(mx, s, A_HOOK, gain=1.05, octave_layer=True)
    s = 384                                            # BR: 브레이크다운
    crash(mx, s, 0.45)
    pads(mx, s, A_BREAK, A_CH, cutoff=2000, gain=1.15, rev=0.5)
    arp(mx, s, A_BREAK, A_CH, [0, 2, 4, 2, 5, 3, 1, 3], a_tones, gain=0.8,
        cut_fn=lambda i: 900 + 3400 * (i / 128) ** 1.4)
    for b, c in enumerate(A_BREAK):                    # 마디 처음 긴 베이스
        mx.add('bass', L.bass_note(A_ROOT[c], L.STEP * 15, 500), T(s + b * 16), gain=0.45)
    for b in range(4, 8):                              # 뒤 4마디: 킥 · 하이햇 복귀
        bs = s + b * 16
        for st in (0, 4, 8, 12):
            kick(mx, bs + st, 0.6 + 0.1 * (b - 4))
        if b >= 6:
            for st in range(0, 16, 2):
                hat(mx, bs + st, 0.45)
    roll(mx, s + 96, 8, 2, 0.35, 0.6)
    roll(mx, s + 112, 0, 1, 0.4, 1.0, big=True)
    mx.add('fx', L.mk_riser(L.BAR * 2), T(s + 96), gain=0.9, rev=0.2)


# ── B. DEEP SIGNAL ────────────────────────────────────
B_BPM = 104
B_CH = {'Em': [64, 67, 71], 'F': [65, 69, 72], 'C': [64, 67, 72], 'Am': [64, 69, 72], 'B': [63, 66, 71]}
B_ROOT = {'Em': 40, 'F': 41, 'C': 36, 'Am': 33, 'B': 35}
B_PROG = ['Em', 'Em', 'F', 'Em', 'Em', 'C', 'Am', 'B']
B_OST = [0, 1, 2, 1, 3, 1, 2, 4]                       # 최면적 반복 아르페지오


def b_tones(ch):
    r = ch[0] - 12
    return [r - 12, r, ch[1] - 12, ch[2] - 12, r + 12]


B_MEL = [
    (0, 0, 8, 76), (0, 8, 8, 79),
    (1, 0, 12, 83), (1, 12, 4, 81),
    (2, 0, 8, 81), (2, 8, 8, 77),
    (3, 0, 16, 76),
    (4, 0, 8, 79), (4, 8, 8, 83),
    (5, 0, 8, 84), (5, 8, 8, 79),
    (6, 0, 8, 81), (6, 8, 4, 76), (6, 12, 4, 72),
    (7, 0, 16, 75),
]
B_PULSE = [0, None, 0, None, 0, None, 0, None, 0, None, 0, None, 0, None, 0, None]
B_GALLOP = [0, 0, 0, 12, 0, 0, 0, 12, 0, 0, 0, 12, 0, 0, 12, 0]


def song_b(mx):
    n_bars = 32
    mx.add('fx', wind(n_bars * L.BAR + 2.0), 0.0, pan=-0.2, gain=1.0, rev=0.3)
    # 드론: 32마디 내내, 마디 화음 뿌리
    for sec in range(4):
        for b, c in enumerate(B_PROG):
            mx.add('bass', drone(B_ROOT[c] - 12 if B_ROOT[c] > 36 else B_ROOT[c], L.BAR),
                   T(sec * 128 + b * 16), gain=0.7 if sec == 0 else 0.45)
    # 반복 아르페지오: 4구간 내내, 필터가 구간마다 다르게 열림
    cuts = [lambda i: 600 + 1400 * (i / 128), lambda i: 1500 + 800 * math.sin(i / 128 * math.pi),
            lambda i: 2600, lambda i: 3200 + 1200 * (i / 128)]
    gains = [0.95, 0.85, 0.7, 0.8]
    for sec in range(4):
        arp(mx, sec * 128, B_PROG, B_CH, B_OST, b_tones, gain=gains[sec], cut_fn=cuts[sec], pan=0.3)

    s = 0                                              # S1: 성김, 심장박동 킥
    pads(mx, s, B_PROG, B_CH, cutoff=900, gain=0.75, rev=0.55)
    for b in range(8):
        kick(mx, s + b * 16, 0.55)
        kick(mx, s + b * 16 + 3, 0.35)
    for b in (3, 7):
        mx.add('lead', bell(88, L.STEP * 8), T(s + b * 16 + 8), pan=0.4, gain=0.6, rev=0.6, dly=0.4)
    s = 128                                            # S2: 하프타임 · 8분 베이스 · 종 선율
    crash(mx, s, 0.4)
    pads(mx, s, B_PROG, B_CH, cutoff=1500, gain=0.85, rev=0.45)
    bass(mx, s, B_PROG, B_ROOT, B_PULSE, fc=700, gain=1.0, length=1.6)
    bells(mx, s, B_MEL, gain=1.0)
    for b in range(8):
        bs = s + b * 16
        kick(mx, bs)
        kick(mx, bs + 10, 0.75)
        snare(mx, bs + 8, 1.0, rev=0.55)
        for st in range(0, 16, 2):
            hat(mx, bs + st, 0.45 if st % 4 else 0.6, pan=-0.2)
    s = 256                                            # S3: 16분 베이스 · 톱니 리드
    crash(mx, s)
    pads(mx, s, B_PROG, B_CH, cutoff=2200, gain=0.9)
    bass(mx, s, B_PROG, B_ROOT, B_GALLOP, fc=1300, drive=0.3, gain=0.95)
    lead(mx, s, B_MEL, gain=0.9, shift=-12, dly=0.3)
    bells(mx, s, B_MEL, gain=0.55)
    for b in range(8):
        bs = s + b * 16
        for st in (0, 8, 11):
            kick(mx, bs + st, 1.0 if st != 11 else 0.7)
        snare(mx, bs + 4, 0.9, rev=0.4)
        snare(mx, bs + 12, 1.0, rev=0.4)
        for st in range(16):
            hat(mx, bs + st, (0.55, 0.25, 0.4, 0.25)[st % 4], pan=-0.2)
    tom(mx, s + 7 * 16 + 12)
    tom(mx, s + 7 * 16 + 14, False)
    s = 384                                            # S4: 절정 → 가라앉음
    crash(mx, s, 0.65)
    crash(mx, s + 64, 0.5)
    pads(mx, s, B_PROG, B_CH, cutoff=3000, gain=1.0)
    bass(mx, s, B_PROG[:7], B_ROOT, B_GALLOP, fc=1600, drive=0.45, gain=1.0)
    lead(mx, s, [p for p in B_MEL if p[0] < 7], gain=1.0, shift=0, octave_layer=True, dly=0.3)
    bells(mx, s, B_MEL, gain=0.5, shift=12)
    for b in range(7):
        bs = s + b * 16
        for st in (0, 4, 8, 12):
            kick(mx, bs + st)
        snare(mx, bs + 4, 1.0, rev=0.4)
        snare(mx, bs + 12, 1.0, rev=0.4)
        for st in range(16):
            hat(mx, bs + st, (0.6, 0.3, 0.5, 0.3)[st % 4], pan=-0.2)
        if b in (3, 6):
            tom(mx, bs + 12)
            tom(mx, bs + 13)
            tom(mx, bs + 14, False)
            tom(mx, bs + 15, False)
    bs = s + 7 * 16                                    # 마지막 마디: 한 방 치고 S1 로 가라앉음
    kick(mx, bs, 1.1)
    crash(mx, bs, 0.5)
    mx.add('bass', L.bass_note(B_ROOT['B'], L.STEP * 14, 900, 0.3), T(bs), gain=0.6)
    mx.add('lead', bell(87, L.STEP * 16), T(bs), pan=0.2, gain=0.8, rev=0.6, dly=0.4)


# ── 믹스 · 렌더 ───────────────────────────────────────
def premix(mx, gain, sc_depth=0.65):
    N = mx.N
    sc = L.sidechain(N, mx.kicks, sc_depth)
    sc_l = L.sidechain(N, mx.kicks, sc_depth * 0.55)
    b = mx.bus
    out = b['drums'] * gain['drums'] + b['fx'] * gain['fx'] + b['lead'] * gain['lead']
    out += b['bass'] * sc * gain['bass'] + b['pad'] * sc * gain['pad'] + b['arp'] * sc_l * gain['arp']
    out += L.reverb(b['rev']) * sc_l + L.delay(b['dly'], d=L.STEP * 3, fb=0.4)
    return out


SONGS = [
    {'id': 'A_neon_descent', 'title': 'NEON DESCENT', 'bpm': A_BPM, 'bars': 32, 'fn': song_a, 'sc': 0.65,
     'gain': {'drums': 0.72, 'bass': 0.95, 'pad': 1.2, 'lead': 1.05, 'arp': 0.95, 'fx': 0.8},
     'sections': (('A', 0, 8), ('B', 8, 16), ("A'", 16, 24), ('BR', 24, 32))},
    {'id': 'B_deep_signal', 'title': 'DEEP SIGNAL', 'bpm': B_BPM, 'bars': 32, 'fn': song_b, 'sc': 0.5,
     'gain': {'drums': 0.72, 'bass': 1.0, 'pad': 1.1, 'lead': 1.0, 'arp': 1.0, 'fx': 0.9},
     'sections': (('S1', 0, 8), ('S2', 8, 16), ('S3', 16, 24), ('S4', 24, 32))},
]


def render(song):
    set_tempo(song['bpm'])
    L.S['gsnare'] = gated_snare()
    L_len = ns(song['bars'] * L.BAR)
    mx = L.Mix(song['bars'] * L.BAR + L.TAIL)
    song['fn'](mx)
    pre = premix(mx, song['gain'], song['sc'])
    wrapped = pre[:, :L_len].copy()
    wrapped[:, :pre.shape[1] - L_len] += pre[:, L_len:]
    g = 1.0 / np.percentile(np.abs(wrapped), 99.99)
    loop = L.master(np.concatenate([wrapped, wrapped], axis=1), g)[:, L_len:]
    prev = np.zeros((2, 2 * L_len + pre.shape[1]))
    prev[:, :pre.shape[1]] += pre
    prev[:, L_len:L_len + pre.shape[1]] += pre
    prev = L.master(prev[:, :2 * L_len + ns(L.TAIL)], g)
    loop, prev = L.peak_norm([loop, prev])
    return mx, loop, prev, L_len


def main():
    os.makedirs(OUT, exist_ok=True)
    L.samples()
    L.IR = (L.make_ir(31), L.make_ir(47))
    report = {}
    for song in SONGS:
        mx, loop, prev, n = render(song)
        base = os.path.join(OUT, f"rogue_bgm_{song['id']}")
        L.write_wav(base + '_loop.wav', loop)
        L.write_wav(base + '_preview.wav', prev)
        # 이음새: 루프 끝→처음 을, 미리듣기 안에서 끊김 없이 이어지는 같은 자리와 비교 (0 이면 동일)
        w = ns(0.05)
        seam = float(np.max(np.abs(np.concatenate([loop[:, :w], loop[:, -w:]], axis=1)
                                   - np.concatenate([prev[:, n:n + w], prev[:, n - w:n]], axis=1))))
        sec = {}
        for name, b0, b1 in song['sections']:
            seg = loop[:, ns(b0 * L.BAR):ns(b1 * L.BAR)]
            sec[name] = L.db(np.sqrt(np.mean(seg ** 2)))
        report[song['id']] = {
            'title': song['title'], 'bpm': song['bpm'], 'bars': song['bars'],
            'loop_seconds': round(n / SR, 4), 'loop_samples': n,
            'peak_dbfs': L.db(np.max(np.abs(loop))), 'rms_dbfs': L.db(np.sqrt(np.mean(loop ** 2))),
            'clipped_samples': int(np.sum(np.abs(loop) >= 0.999) + np.sum(np.abs(prev) >= 0.999)),
            'dc_offset': [round(float(np.mean(loop[0])), 5), round(float(np.mean(loop[1])), 5)],
            'seam_vs_natural_max_diff': round(seam, 6),
            'section_rms_dbfs': sec,
            'band_energy_db': L.bands(loop),
            'bus_rms_dbfs_premix': L.bus_rms(mx),
        }
        print(song['title'], json.dumps(report[song['id']], ensure_ascii=False))
    with open(os.path.join(OUT, 'validation.json'), 'w', encoding='utf-8') as f:
        json.dump(report, f, ensure_ascii=False, indent=2)


if __name__ == '__main__':
    main()
