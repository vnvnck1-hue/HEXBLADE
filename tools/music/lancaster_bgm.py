"""LANCASTER 보스전 BGM — 다크 신스웨이브 (numpy/scipy 합성만, 샘플·외부 음원 없음)

실행 (scipy 가 없는 PC 는 uv 로 격리 실행):
    uv run --no-project --with numpy --with scipy python tools/music/lancaster_bgm.py

124 BPM · D 단조 · 4/4
- 인트로 8마디 (한 번만): 거대 기체 발소리(쿵·금속 울림) + 경보 사이렌 + 닫힌 패드 → 베이스 열림 → 스네어 롤 · 라이저
- 루프 32마디 (끝 → 처음이 이어짐)
    A  8마디  Dm Bb C Am      주제 리드 + 16분 베이스 + 4박 킥
    B  8마디  Gm Dm Bb A      고조, 아르페지오, 높은 리드
    A' 8마디  Dm Bb C Am      주제 + 옥타브 아래 겹침 + 아르페지오
    BR 8마디  Dm Eb Dm Eb Bb C A A   하프타임 · 일그러진 베이스 · 화음 찌르기 · 발소리 · 사이렌 → 롤 · 라이저 → A
결과: output/lancaster-bgm-20261007/
    lancaster_bgm_loop.wav        루프 (처음부터 끝까지 반복 재생하면 이어짐)
    lancaster_bgm_intro_loop.wav  인트로 + 루프 두 번 (미리듣기, 루프 시작 = 인트로 길이)
    validation.json               음량 · 대역 · 루프 이음새 측정
"""
import json
import math
import os

import numpy as np
from scipy import signal
from scipy.io import wavfile

SR = 44100
BPM = 124
STEP = 60.0 / BPM / 4          # 16분음표 길이 (초)
BAR = STEP * 16
SQ2 = math.sqrt(2.0)
TAIL = 4.0                     # 잔향 · 딜레이 꼬리 (초)
OUT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..',
                                    'output', 'lancaster-bgm-20261007'))
rng = np.random.default_rng(7)


def hz(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def ns(sec):
    return int(round(sec * SR))


# ── 필터 ──────────────────────────────────────────────
_sos = {}


def filt(x, kind, fc, order=2):
    key = (kind, fc if np.isscalar(fc) else tuple(fc), order)
    if key not in _sos:
        _sos[key] = signal.butter(order, fc, btype=kind, fs=SR, output='sos')
    return signal.sosfilt(_sos[key], x, axis=-1)


# ── 대역 제한 오실레이터 (PolyBLEP) ────────────────────
def _blep(t, dt):
    out = np.zeros_like(t)
    m = t < dt
    x = t[m] / dt[m]
    out[m] = x + x - x * x - 1
    m = t > 1 - dt
    x = (t[m] - 1) / dt[m]
    out[m] = x * x + x + x + 1
    return out


def _phase(freq, n, ph0):
    f = np.broadcast_to(np.asarray(freq, float), (n,))
    dt = f / SR
    return (ph0 + np.cumsum(dt)) % 1.0, dt


def saw(freq, n, ph0=0.0):
    t, dt = _phase(freq, n, ph0)
    return 2 * t - 1 - _blep(t, dt)


def square(freq, n, ph0=0.0):
    t, dt = _phase(freq, n, ph0)
    t2 = (t + 0.5) % 1.0
    return (2 * t - 1 - _blep(t, dt)) - (2 * t2 - 1 - _blep(t2, dt))


def sine(freq, n, ph0=0.0):
    t, _ = _phase(freq, n, ph0)
    return np.sin(2 * np.pi * t)


def adsr(n, a, d, s, r, gate):
    t = np.arange(n) / SR
    env = np.where(t < a, t / max(a, 1e-4), s + (1 - s) * np.exp(-(t - a) / d))
    g = min(ns(gate), n - 1)
    lvl = env[g]
    env[g:] = lvl * np.exp(-(t[g:] - t[g]) / r)
    return env


def noise(n):
    return rng.standard_normal(n)


# ── 드럼 · 효과 (미리 구워 재사용) ────────────────────
def mk_kick():
    n = ns(0.5)
    t = np.arange(n) / SR
    f = 44 + 120 * np.exp(-t / 0.03) + 30 * np.exp(-t / 0.12)
    body = sine(f, n) * np.exp(-t / 0.3)
    click = filt(noise(n), 'highpass', 2500) * np.exp(-t / 0.003) * 0.5
    return np.tanh(2.2 * (body + click)) * 0.9


def mk_snare():
    n = ns(0.45)
    t = np.arange(n) / SR
    tone = (np.sin(2 * np.pi * 185 * t) + 0.5 * np.sin(2 * np.pi * 330 * t)) * np.exp(-t / 0.05) * 0.6
    nz = filt(noise(n), 'bandpass', (900, 9000)) * np.exp(-t / 0.12)
    return np.tanh(1.5 * (tone + nz * 0.9))


def mk_hat(open_=False):
    n = ns(0.45 if open_ else 0.07)
    t = np.arange(n) / SR
    x = filt(noise(n), 'highpass', 7000, 4) * np.exp(-t / (0.17 if open_ else 0.02))
    return x * 0.8


def mk_crash():
    n = ns(3.0)
    t = np.arange(n) / SR
    x = filt(noise(n), 'highpass', 3500) * np.exp(-t / 1.0)
    for f in (3170, 4410, 5280, 6930, 8120):
        x += 0.08 * np.sin(2 * np.pi * f * t + rng.random() * 6) * np.exp(-t / 0.8)
    return x * 0.55


def mk_tom(m):
    n = ns(0.4)
    t = np.arange(n) / SR
    f = hz(m) * (1 + 0.6 * np.exp(-t / 0.04))
    x = sine(f, n) * np.exp(-t / 0.2) + filt(noise(n), 'bandpass', (200, 2000)) * np.exp(-t / 0.02) * 0.3
    return np.tanh(1.4 * x)


def mk_stomp():
    """거대 기체 발소리: 서브 쿵 + 서로 배수가 아닌 금속 울림 + 둔탁한 충돌."""
    n = ns(2.2)
    t = np.arange(n) / SR
    sub = sine(30 + 60 * np.exp(-t / 0.08), n) * np.exp(-t / 0.5)
    metal = np.zeros(n)
    for r in (1, 1.47, 2.09, 2.56, 3.18, 4.11, 5.3, 6.7):
        metal += np.sin(2 * np.pi * 98 * r * t + rng.random() * 6) * np.exp(-t / (0.9 / r ** 0.5)) * (0.5 / r ** 0.3)
    hit = filt(noise(n), 'bandpass', (150, 2500)) * np.exp(-t / 0.035)
    return np.tanh(1.8 * sub) * 0.85 + filt(metal, 'lowpass', 5000) * 0.22 + hit * 0.55


def mk_siren(dur):
    """경보 사이렌: 반 마디 주기로 오르내림, 걸러 낸 사각파."""
    n = ns(dur)
    t = np.arange(n) / SR
    f = 520 + 360 * (0.5 - 0.5 * np.cos(2 * np.pi * t / (BAR / 2)))
    x = filt(square(f, n), 'bandpass', (350, 2600))
    env = np.clip(t / 0.8, 0, 1) * np.clip((dur - t) / 0.6, 0, 1)
    return x * env * 0.35


def mk_riser(dur):
    n = ns(dur)
    t = np.arange(n) / SR
    w = (t / dur) ** 2
    nz = noise(n)
    x = filt(nz, 'lowpass', 700) * (1 - w) + filt(nz, 'highpass', 1800) * w
    sweep = filt(saw(70 * 2 ** (4.2 * w), n), 'lowpass', 3000) * 0.35
    return (x * 0.5 + sweep) * (0.08 + 0.92 * w ** 1.5) * 0.55


# ── 음높이 악기 ───────────────────────────────────────
def bass_note(m, dur, fc=1600, drive=0.0):
    n = ns(dur + 0.03)
    t = np.arange(n) / SR
    f = hz(m)
    x = 0.5 * saw(f * 2 ** (0.07 / 12), n, rng.random()) + 0.5 * saw(f * 2 ** (-0.07 / 12), n, rng.random())
    x += 0.7 * np.sin(2 * np.pi * f * t)
    fe = np.exp(-t / 0.06)
    dark = filt(x, 'lowpass', 220)
    bright = filt(x, 'lowpass', fc * (1 + drive))
    x = dark + (bright - dark) * fe
    if drive:
        x = np.tanh(x * (1 + 3 * drive)) * 0.75
    return x * adsr(n, 0.002, 0.25, 0.65, 0.012, dur)


_lead_cache = {}


def lead_note(m, dur):
    key = (m, round(dur, 4))
    if key in _lead_cache:
        return _lead_cache[key]
    n = ns(dur + 0.35)
    t = np.arange(n) / SR
    vib = 2 ** ((0.2 / 12) * np.sin(2 * np.pi * 5.6 * t) * np.clip((t - 0.18) / 0.25, 0, 1))
    f = hz(m) * vib
    x = saw(f * 2 ** (0.09 / 12), n, 0.1) + saw(f * 2 ** (-0.09 / 12), n, 0.6) + 0.45 * square(f / 2, n)
    fe = np.exp(-t / 0.15)
    x = filt(x, 'lowpass', 2600) * (1 - fe) + filt(x, 'lowpass', 6000) * fe
    out = x * adsr(n, 0.008, 0.35, 0.72, 0.11, dur) * 0.3
    _lead_cache[key] = out
    return out


_pluck_cache = {}


def pluck(m, cutoff=4500):
    key = (m, cutoff)
    if key in _pluck_cache:
        return _pluck_cache[key]
    n = ns(0.4)
    t = np.arange(n) / SR
    f = hz(m)
    x = saw(f, n) + 0.5 * square(f * 2 ** (0.05 / 12), n)
    fe = np.exp(-t / 0.04)
    x = filt(x, 'lowpass', 700) * (1 - fe) + filt(x, 'lowpass', cutoff) * fe
    out = x * np.clip(t / 0.001, 0, 1) * np.exp(-t / 0.12) * 0.3
    _pluck_cache[key] = out
    return out


def pad(midis, dur, cutoff=2400):
    """7음 슈퍼소 화음, 짝/홀 음을 좌우로 벌림. (2, n)"""
    n = ns(dur + 0.8)
    st = np.zeros((2, n))
    for m in midis:
        for v in range(7):
            det = (v - 3) / 3 * 0.18
            x = saw(hz(m + det), n, rng.random())
            if v == 3:
                st += x * 0.7
            else:
                st[v % 2] += x
    st = filt(st, 'lowpass', cutoff)
    env = adsr(n, 0.12, 0.6, 0.85, 0.3, dur)
    return st * env / (len(midis) * 4.0)


def stab(midis, dur=STEP * 2):
    n = ns(dur + 0.3)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for m in midis:
        x += saw(hz(m) * 2 ** (0.1 / 12), n, rng.random()) + saw(hz(m) * 2 ** (-0.1 / 12), n, rng.random())
    fe = np.exp(-t / 0.08)
    x = filt(x, 'lowpass', 900) * (1 - fe) + filt(x, 'lowpass', 5000) * fe
    x = np.tanh(x * 0.6)
    return x * np.exp(-t / 0.18) * 0.35


# ── 화성 · 선율 ───────────────────────────────────────
CH = {'Dm': [62, 65, 69], 'Bb': [58, 62, 65], 'C': [60, 64, 67], 'Am': [57, 60, 64],
      'Gm': [55, 58, 62], 'A': [57, 61, 64], 'Eb': [55, 58, 63]}
ROOT = {'Dm': 38, 'Bb': 34, 'C': 36, 'Am': 33, 'Gm': 31, 'A': 33, 'Eb': 39}

A_CH = ['Dm', 'Bb', 'C', 'Am'] * 2
B_CH = ['Gm', 'Dm', 'Bb', 'A'] * 2
BR_CH = ['Dm', 'Eb', 'Dm', 'Eb', 'Bb', 'C', 'A', 'A']

BASS_PAT = [0, 0, 12, 0, 0, 0, 12, 0, 0, 0, 12, 0, 0, 12, 0, 12]
BR_PAT = [0, None, 0, None, 0, 0, None, 0, None, 0, 0, None, 12, None, 0, 0]

# (마디, 16분 위치, 길이, 음)
PH_A = [
    (0, 0, 3, 69), (0, 3, 3, 74), (0, 6, 2, 77), (0, 8, 4, 76), (0, 12, 4, 74),
    (1, 0, 6, 77), (1, 6, 2, 74), (1, 8, 8, 70),
    (2, 0, 3, 72), (2, 3, 3, 76), (2, 6, 2, 79), (2, 8, 4, 77), (2, 12, 4, 76),
    (3, 0, 12, 76), (3, 12, 2, 72), (3, 14, 2, 69),
    (4, 0, 3, 69), (4, 3, 3, 74), (4, 6, 2, 77), (4, 8, 4, 81), (4, 12, 4, 79),
    (5, 0, 6, 77), (5, 6, 2, 79), (5, 8, 8, 82),
    (6, 0, 3, 84), (6, 3, 3, 82), (6, 6, 2, 81), (6, 8, 4, 79), (6, 12, 4, 76),
    (7, 0, 14, 81),
]
PH_B = [
    (0, 0, 4, 79), (0, 4, 4, 82), (0, 8, 4, 81), (0, 12, 4, 79),
    (1, 0, 6, 77), (1, 6, 2, 81), (1, 8, 8, 86),
    (2, 0, 4, 86), (2, 4, 4, 84), (2, 8, 4, 82), (2, 12, 4, 81),
    (3, 0, 4, 76), (3, 4, 4, 81), (3, 8, 8, 85),
    (4, 0, 2, 79), (4, 2, 2, 82), (4, 4, 4, 86), (4, 8, 4, 84), (4, 12, 4, 82),
    (5, 0, 6, 81), (5, 6, 2, 77), (5, 8, 8, 74),
    (6, 0, 4, 77), (6, 4, 4, 82), (6, 8, 4, 86), (6, 12, 4, 84),
    (7, 0, 6, 85), (7, 6, 2, 88), (7, 8, 8, 81),
]


# ── 믹스 ──────────────────────────────────────────────
BUSES = ['drums', 'bass', 'pad', 'lead', 'arp', 'fx', 'rev', 'dly']


class Mix:
    def __init__(self, seconds):
        self.N = ns(seconds)
        self.bus = {k: np.zeros((2, self.N)) for k in BUSES}
        self.kicks = []

    def add(self, name, x, t0, pan=0.0, gain=1.0, rev=0.0, dly=0.0):
        i = ns(t0)
        if i >= self.N:
            return
        if x.ndim == 1:
            th = (pan + 1) * math.pi / 4
            x = np.vstack([x * math.cos(th) * SQ2, x * math.sin(th) * SQ2])
        m = min(x.shape[1], self.N - i)
        seg = x[:, :m] * gain
        self.bus[name][:, i:i + m] += seg
        if rev:
            self.bus['rev'][:, i:i + m] += seg * rev
        if dly:
            self.bus['dly'][:, i:i + m] += seg * dly


S = {}


def samples():
    S['kick'] = mk_kick()
    S['snare'] = mk_snare()
    S['hat'] = [mk_hat() for _ in range(4)]
    S['ohat'] = mk_hat(True)
    S['crash'] = mk_crash()
    S['stomp'] = mk_stomp()
    S['tom_hi'] = mk_tom(52)
    S['tom_lo'] = mk_tom(45)


def T(step):
    return step * STEP


def kick(mx, step, gain=1.0):
    mx.add('drums', S['kick'], T(step), gain=gain)
    mx.kicks.append(T(step))


def snare(mx, step, gain=1.0):
    mx.add('drums', S['snare'], T(step), gain=gain * 0.75, rev=0.28)


def hat(mx, step, gain=1.0, open_=False):
    x = S['ohat'] if open_ else S['hat'][step % 4]
    mx.add('drums', x, T(step), pan=0.25, gain=gain * 0.25)


def crash(mx, step):
    mx.add('drums', S['crash'], T(step), pan=-0.3, gain=0.55, rev=0.2)


def stomp(mx, step, gain=1.0):
    mx.add('fx', S['stomp'], T(step), gain=gain * 0.9, rev=0.35)


def fill(mx, s, toms=False):
    """마디 s 의 끝 박: 스네어 16분 롤 (+ 탐)."""
    if toms:
        mx.add('drums', S['tom_hi'], T(s + 8), pan=0.3, gain=0.7, rev=0.2)
        mx.add('drums', S['tom_hi'], T(s + 10), pan=0.1, gain=0.7, rev=0.2)
        mx.add('drums', S['tom_lo'], T(s + 11), pan=-0.2, gain=0.8, rev=0.2)
    for i, st in enumerate(range(12, 16)):
        snare(mx, s + st, 0.55 + 0.15 * i)


def drums_full(mx, s, bars, fill_kind='snare'):
    for b in range(bars):
        bs = s + b * 16
        for st in (0, 4, 8, 12):
            kick(mx, bs + st)
        last = b == bars - 1
        for st in (4, 12):
            if not (last and fill_kind and st == 12):
                snare(mx, bs + st)
        for st in range(16):
            if st % 4 == 2:
                hat(mx, bs + st, 0.9, open_=True)
            else:
                hat(mx, bs + st, (0.6, 0.35, 0, 0.45)[st % 4])
        if last and fill_kind:
            fill(mx, bs, toms=fill_kind == 'tom')


def bass_line(mx, s, chords, pat=BASS_PAT, fc=1600, drive=0.0, gain=1.0, fc_ramp=None):
    for b, c in enumerate(chords):
        for st, off in enumerate(pat):
            if off is None:
                continue
            f = fc if fc_ramp is None else fc_ramp(b * 16 + st)
            acc = 1.0 if st % 4 == 0 else 0.8
            mx.add('bass', bass_note(ROOT[c] + off, STEP * 0.85, f, drive), T(s + b * 16 + st), gain=gain * acc * 0.5)


def pads(mx, s, chords, cutoff=2400, gain=1.0):
    for b, c in enumerate(chords):
        mx.add('pad', pad(CH[c], BAR, cutoff), T(s + b * 16), gain=gain * 0.55, rev=0.35)


def lead_line(mx, s, phrase, gain=1.0, octave_layer=False):
    for bar, st, ln, m in phrase:
        t0 = T(s + bar * 16 + st)
        dur = ln * STEP * 0.92
        mx.add('lead', lead_note(m, dur), t0, pan=0.05, gain=gain * 0.75, rev=0.22, dly=0.22)
        if octave_layer:
            mx.add('lead', lead_note(m - 12, dur), t0, pan=-0.15, gain=gain * 0.42, rev=0.15)


def arp_line(mx, s, chords, gain=1.0, cutoff=4500):
    seq = [0, 1, 2, 3, 4, 5, 4, 3, 2, 1]
    for b, c in enumerate(chords):
        tones = sorted(CH[c] + [m + 12 for m in CH[c]])
        for st in range(16):
            i = b * 16 + st
            pan = -0.45 if st % 2 else 0.45
            mx.add('arp', pluck(tones[seq[i % 10]], cutoff), T(s + i), pan=pan, gain=gain * 0.55, rev=0.25, dly=0.15)


# ── 곡 구성 ──────────────────────────────────────────
INTRO_BARS = 8
LOOP_BARS = 32


def arrange_intro(mx):
    # 0~3 마디: 발소리가 다가오고, 닫힌 패드 · 저음 맥동 · 사이렌
    for st in (0, 16, 32, 40, 48, 56):
        stomp(mx, st, 0.8 + st / 160)
    pads(mx, 0, ['Dm'] * 4, cutoff=800, gain=0.8)
    for q in range(16):
        mx.add('bass', bass_note(26, STEP * 3.2, 300), T(q * 4), gain=0.55)
    mx.add('fx', mk_siren(BAR * 4), 0.0, pan=-0.2, gain=0.8, rev=0.5)
    # 4~7 마디: 진행 시작, 베이스 필터가 열림, 킥 → 하이햇 → 롤
    ch = ['Dm', 'Bb', 'C', 'A']
    pads(mx, 64, ch, cutoff=1600, gain=0.85)
    bass_line(mx, 64, ch, fc_ramp=lambda i: 300 + 1300 * (i / 64) ** 1.5)
    for b in range(4):
        bs = 64 + b * 16
        for st in (0, 4, 8, 12):
            kick(mx, bs + st, 0.85)
        if b >= 2:
            for st in range(0, 16, 2):
                hat(mx, bs + st, 0.5)
    for st in range(16 * 3 + 64, 16 * 3 + 64 + 8):          # 7마디 앞 절반: 8분 스네어
        if st % 2 == 0:
            snare(mx, st, 0.45)
    for i, st in enumerate(range(16 * 3 + 64 + 8, 16 * 4 + 64)):   # 뒤 절반: 16분 롤
        snare(mx, st, 0.5 + 0.06 * i)
    mx.add('fx', mk_riser(BAR * 2), T(96), gain=0.9, rev=0.2)


def arrange_loop(mx):
    # A
    s = 0
    crash(mx, s)
    drums_full(mx, s, 8)
    bass_line(mx, s, A_CH)
    pads(mx, s, A_CH)
    lead_line(mx, s, PH_A)
    # B
    s = 128
    crash(mx, s)
    drums_full(mx, s, 8, fill_kind='tom')
    bass_line(mx, s, B_CH, fc=2000)
    pads(mx, s, B_CH, cutoff=2800)
    arp_line(mx, s, B_CH, gain=0.9)
    lead_line(mx, s, PH_B)
    mx.add('fx', mk_riser(BAR), T(s + 112), gain=0.7, rev=0.2)
    # A'
    s = 256
    crash(mx, s)
    drums_full(mx, s, 8, fill_kind='tom')
    bass_line(mx, s, A_CH, fc=1900)
    pads(mx, s, A_CH, cutoff=2800, gain=1.05)
    arp_line(mx, s, A_CH, gain=0.7, cutoff=3200)
    lead_line(mx, s, PH_A, gain=1.05, octave_layer=True)
    # BR: 하프타임 · 일그러진 베이스 · 화음 찌르기 · 발소리
    s = 384
    crash(mx, s)
    stomp(mx, s, 1.1)
    stomp(mx, s + 64, 1.0)
    bass_line(mx, s, BR_CH, pat=BR_PAT, fc=1200, drive=0.9, gain=1.05)
    pads(mx, s, BR_CH, cutoff=1500, gain=0.9)
    arp_line(mx, s, BR_CH, gain=0.55, cutoff=2200)
    for b, c in enumerate(BR_CH):
        bs = s + b * 16
        for st in (0, 3, 6, 10, 12):
            mx.add('lead', stab([m + 12 for m in CH[c]]), T(bs + st), pan=(-0.3, 0.3)[st % 2], gain=0.8, rev=0.2, dly=0.1)
        if b < 6:
            kick(mx, bs)
            kick(mx, bs + 10)
            if b % 2:
                kick(mx, bs + 14, 0.8)
            snare(mx, bs + 8, 1.1)
            for st in range(0, 16, 2):
                hat(mx, bs + st, 0.55)
        else:                                       # 마지막 두 마디: 다시 몰아침
            for st in (0, 4, 8, 12):
                kick(mx, bs + st)
            for st in range(0, 16, 2 if b == 6 else 1):
                snare(mx, bs + st, 0.35 + 0.6 * (st / 16) + (0.15 if b == 7 else 0))
    mx.add('fx', mk_siren(BAR * 4), T(s + 64), pan=0.2, gain=0.7, rev=0.5)
    mx.add('fx', mk_riser(BAR * 2), T(s + 96), gain=1.0, rev=0.2)


# ── 효과 · 마스터 ─────────────────────────────────────
def make_ir(seed, sec=2.6, tau=0.55):
    n = ns(sec)
    t = np.arange(n) / SR
    r = np.random.default_rng(seed)
    ir = filt(r.standard_normal(n) * np.exp(-t / tau), 'lowpass', 5500)
    ir[:ns(0.015)] *= np.linspace(0, 1, ns(0.015))
    return ir / np.sqrt(np.sum(ir ** 2))


IR = None


def reverb(x):
    N = x.shape[1]
    src = filt(x, 'highpass', 200)
    return np.vstack([signal.fftconvolve(src[0], IR[0])[:N], signal.fftconvolve(src[1], IR[1])[:N]]) * 0.55


def delay(x, d=STEP * 3, fb=0.42, taps=5):
    N = x.shape[1]
    src = filt(filt((x[0] + x[1]) * 0.5, 'lowpass', 3500), 'highpass', 300)
    out = np.zeros_like(x)
    for k in range(1, taps + 1):
        sh = ns(d * k)
        if sh >= N:
            break
        out[k % 2, sh:] += src[:N - sh] * fb ** k
    return out


def sidechain(N, times, depth, tau=0.13):
    g = np.ones(N)
    n = ns(0.5)
    t = np.arange(n) / SR
    curve = 1 - depth * np.clip(t / 0.003, 0, 1) * np.exp(-t / tau)
    for k in times:
        i = ns(k)
        if i >= N:
            continue
        m = min(n, N - i)
        g[i:i + m] = np.minimum(g[i:i + m], curve[:m])
    return g


GAIN = {'drums': 0.72, 'bass': 0.95, 'pad': 1.25, 'lead': 1.05, 'arp': 0.95, 'fx': 0.8}


def premix(mx):
    """버스 합 (사이드체인 · 잔향 · 딜레이). 마스터 전."""
    N = mx.N
    sc = sidechain(N, mx.kicks, 0.65)
    sc_l = sidechain(N, mx.kicks, 0.35)
    b = mx.bus
    out = b['drums'] * GAIN['drums'] + b['fx'] * GAIN['fx'] + b['lead'] * GAIN['lead']
    out += b['bass'] * sc * GAIN['bass'] + b['pad'] * sc * GAIN['pad'] + b['arp'] * sc_l * GAIN['arp']
    out += reverb(b['rev']) * sc_l + delay(b['dly'])
    return out


def bus_rms(mx):
    return {k: round(20 * math.log10(np.sqrt(np.mean(mx.bus[k] ** 2)) + 1e-12), 1) for k in BUSES}


DRIVE = 1.35


def master(x, g):
    """HPF 28Hz → 게인 → tanh 소프트 클립 → -1 dBFS."""
    y = filt(x, 'highpass', 28) * g
    return np.tanh(DRIVE * y) / np.tanh(DRIVE)


def peak_norm(ys, dbfs=-1.0):
    pk = max(np.max(np.abs(y)) for y in ys)
    return [y * (10 ** (dbfs / 20) / pk) for y in ys]


def write_wav(path, y):
    d = (rng.random(y.shape) - rng.random(y.shape)) / 32768.0       # TPDF 디더
    pcm = np.clip(np.round((y + d) * 32767), -32768, 32767).astype(np.int16)
    wavfile.write(path, SR, pcm.T.copy())


def db(v):
    return round(20 * math.log10(max(v, 1e-12)), 2)


def bands(y):
    m = (y[0] + y[1]) * 0.5
    spec = np.abs(np.fft.rfft(m)) ** 2
    fr = np.fft.rfftfreq(len(m), 1 / SR)
    tot = spec.sum()
    out = {}
    for name, lo, hi in (('sub_<60', 0, 60), ('low_60-250', 60, 250), ('mid_250-2k', 250, 2000),
                         ('hi_2k-8k', 2000, 8000), ('air_8k+', 8000, SR / 2)):
        out[name] = round(10 * math.log10(spec[(fr >= lo) & (fr < hi)].sum() / tot), 1)
    return out


def main():
    global IR
    os.makedirs(OUT, exist_ok=True)
    samples()
    IR = (make_ir(11), make_ir(23))
    L = ns(LOOP_BARS * BAR)
    I = ns(INTRO_BARS * BAR)

    loop_mx = Mix(LOOP_BARS * BAR + TAIL)
    arrange_loop(loop_mx)
    intro_mx = Mix(INTRO_BARS * BAR + TAIL)
    arrange_intro(intro_mx)
    lp = premix(loop_mx)
    ip = premix(intro_mx)

    # 루프: 끝의 꼬리를 처음에 겹쳐 원형으로, HPF 상태도 두 번 이어 붙여 걸러 이음새를 없앰
    wrapped = lp[:, :L].copy()
    wrapped[:, :lp.shape[1] - L] += lp[:, L:]
    g = 1.0 / np.percentile(np.abs(wrapped), 99.99)
    loop = master(np.concatenate([wrapped, wrapped], axis=1), g)[:, L:]

    # 미리듣기: 인트로 + 루프 두 번 (같은 게인)
    full = np.zeros((2, I + 2 * L + lp.shape[1]))
    full[:, :ip.shape[1]] += ip
    full[:, I:I + lp.shape[1]] += lp
    full[:, I + L:I + L + lp.shape[1]] += lp
    full = master(full[:, :I + 2 * L + ns(TAIL)], g)
    loop, full = peak_norm([loop, full])

    write_wav(os.path.join(OUT, 'lancaster_bgm_loop.wav'), loop)
    write_wav(os.path.join(OUT, 'lancaster_bgm_intro_loop.wav'), full)

    # 측정
    diffs = np.abs(np.diff(loop, axis=1))
    seam = np.abs(loop[:, 0] - loop[:, -1])
    sec_rms = {}
    for name, b0, b1 in (('A', 0, 8), ('B', 8, 16), ("A'", 16, 24), ('BR', 24, 32)):
        seg = loop[:, ns(b0 * BAR):ns(b1 * BAR)]
        sec_rms[name] = db(np.sqrt(np.mean(seg ** 2)))
    iseg = full[:, :I]
    v = {
        'bpm': BPM, 'key': 'D minor', 'sr': SR,
        'intro_bars': INTRO_BARS, 'loop_bars': LOOP_BARS,
        'intro_seconds': round(I / SR, 4), 'loop_seconds': round(L / SR, 4),
        'loop_samples': L, 'intro_loop_start_sample': I,
        'loop_peak_dbfs': db(np.max(np.abs(loop))), 'loop_rms_dbfs': db(np.sqrt(np.mean(loop ** 2))),
        'full_peak_dbfs': db(np.max(np.abs(full))),
        'clipped_samples': int(np.sum(np.abs(loop) >= 0.999) + np.sum(np.abs(full) >= 0.999)),
        'dc_offset': [round(float(np.mean(loop[0])), 5), round(float(np.mean(loop[1])), 5)],
        'seam_jump': [round(float(s), 5) for s in seam],
        # 같은 자리(브리지 끝 → A)가 미리듣기 안에서 끊김 없이 이어질 때의 값 튐 — seam_jump 와 비슷하면 이음새가 자연스러움
        'natural_jump_same_spot': [round(float(abs(full[c, I + L] - full[c, I + L - 1])), 5) for c in (0, 1)],
        'seam_vs_natural_max_diff': round(float(np.max(np.abs(np.concatenate([loop[:, :ns(0.05)], loop[:, -ns(0.05):]], axis=1)
            - np.concatenate([full[:, I + L:I + L + ns(0.05)], full[:, I + L - ns(0.05):I + L]], axis=1)))), 5),
        'median_sample_step': round(float(np.median(diffs)), 5),
        'p99_sample_step': round(float(np.percentile(diffs, 99)), 5),
        'section_rms_dbfs': dict(sec_rms, intro=db(np.sqrt(np.mean(iseg ** 2)))),
        'band_energy_db': bands(loop),
        'bus_rms_dbfs_premix': bus_rms(loop_mx),
        'master_gain': round(float(g), 4),
    }
    with open(os.path.join(OUT, 'validation.json'), 'w', encoding='utf-8') as f:
        json.dump(v, f, ensure_ascii=False, indent=2)
    print(json.dumps(v, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
