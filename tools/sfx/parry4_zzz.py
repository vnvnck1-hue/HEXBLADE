"""패링 효과음 4차 — 액션 게임식(젠레스 존 제로 류) 패링 연출 방향, 버전마다 중심 재료를 다르게.

실제 게임 소리는 쓰지 않았다(이벤트 이름 목록이 없어 찾을 수 없었다). 액션 게임 패링 연출의 흔한 재료를
노이즈·사인으로 직접 합성한다. 3차 검토: "다 똑같이 들린다" → 버전마다 시간 구조·음역·주재료를 다르게 잡았다.
  Z1_clash   : 검격 '챙!' — 아주 날카로운 시작 + 2.5~9kHz 금속 배음 묶음이 밝게 빨리 줄어듦, 짧은 킥. 휘익 없음. 0.45초
  Z2_slam    : 묵직한 '쾅!' — 120→38Hz 서브 낙하 + 두꺼운 철판 몸통(140Hz) + 포화된 크런치, 고역은 짧게. 0.6초
  Z3_timestop: 시간 정지 — 0.18초 역방향으로 차오르는 소리 → '칭' → 전체가 느려지듯 음이 내려가는 '뷰웅~' 꼬리 + 반짝임. 0.9초
  Z4_spark   : 전기 스파크 — '빠직' 하는 지글거림 + 밝은 '딩' + 30ms 간격으로 3번 끊겨 반복되는 디지털 잔향. 0.55초

실행: python tools/sfx/parry4_zzz.py  →  output/parry-sound-candidates-20261002/v4/
"""
import os, math
import numpy as np
import mg_synth as G
from parry2_synth import comb, glide, lowpass
from parry_candidates import write

SR = G.SR
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', '..', 'output', 'parry-sound-candidates-20261002', 'v4')


def taxis(dur):
    return np.arange(int(dur * SR)) / SR


def noise(t, rng, gains):
    return G.shaped(G.octave_noise(int(rng.integers(0, 1 << 30)), len(t)), gains)


def partials(t, t0, freqs, amps_db, decays, rng, fmul=None):
    """t0 에서 시작하는 사인 묶음 (decays: dB/s). fmul 이 배열이면 시간에 따라 음높이가 변한다"""
    d = np.maximum(t - t0, 0); on = t >= t0; out = np.zeros_like(t)
    k = np.ones_like(t) if fmul is None else fmul
    for f, a, dk in zip(freqs, amps_db, decays):
        ph = 2 * math.pi * np.cumsum(f * k * on) / SR + rng.uniform(0, 6.28)
        out += G.db(a) * np.sin(ph) * on * np.minimum(1.0, d / 0.0015) * 10 ** (-dk * d / 20)
    return out


def finish(x, drive, dur):
    x = x / (np.abs(x).max() + 1e-9)
    x = np.tanh(x * drive) / math.tanh(drive)
    t = taxis(dur); k = t / dur
    x *= np.where(k < 0.75, 1.0, np.cos((k - 0.75) / 0.25 * math.pi / 2) ** 2)
    return x / (np.abs(x).max() + 1e-9) * 0.89


def z1_clash(rng):
    dur = 0.45; t = taxis(dur)
    click = noise(t, rng, [-40, -30, -18, -6, 0, -2]) * G.env(t, 0, 0.0002, 0.003) * 2.5
    # 검이 부딪는 금속 배음: 높고 서로 배수가 아님, 높을수록 빨리 줄어듦
    fr = [2480, 3170, 3905, 4620, 5340, 6260, 7410, 8890]
    ring = partials(t, 0.0005, fr, [-2, 0, -3, -2, -5, -6, -9, -12], [55, 60, 70, 80, 95, 110, 130, 150], rng)
    shimmer = noise(t, rng, [-40, -40, -40, -30, -8, -2]) * G.env(t, 0.002, 0.004, 0.06) * 0.5
    kick = G.drop(t, 160, 55, 0.012, 0.0) * G.env(t, 0, 0.001, 0.05) * 0.8
    return finish(click + ring * 0.6 + shimmer + kick, 1.8, dur)


def z2_slam(rng):
    dur = 0.6; t = taxis(dur)
    sub = G.drop(t, 120, 38, 0.06, 0.0) * G.env(t, 0, 0.002, 0.16) * 1.2
    crunch = noise(t, rng, [-6, 0, -2, -6, -14, -26]) * G.env(t, 0, 0.0005, 0.035) * 3
    crunch = np.tanh(comb(crunch, 0.0085, 0.5) * 3)
    body = partials(t, 0.002, [140 * r for r in (1.0, 1.59, 2.14, 2.30, 2.65, 2.92)], [0, -2, -3, -5, -4, -7], [30, 34, 40, 44, 50, 55], rng)
    clang = partials(t, 0.003, [1180, 1640, 2310], [-6, -8, -12], [110, 130, 160], rng)
    return finish(sub + crunch * 0.7 + body * 0.55 + clang * 0.4, 2.6, dur)


def z3_timestop(rng):
    dur = 0.9; t = taxis(dur); th = 0.18
    # 역방향으로 차오르는 소리: 대역 노이즈 + 올라가는 음, th 에서 뚝 끊김
    rise = np.clip(t / th, 0, 1) ** 3 * (t < th)
    swell = (noise(t, rng, [-40, -30, -14, -6, -4, -10]) * 0.8 + np.sin(2 * math.pi * np.cumsum(300 + 1700 * np.clip(t / th, 0, 1) ** 2) / SR) * 0.35) * rise
    hit = noise(t, rng, [-30, -14, -6, -2, -2, -8]) * G.env(t, th, 0.0003, 0.012) * 2.5
    # 시간이 느려지듯 '칭' 울림 전체가 아래로 미끄러짐 (1.0 → 0.55배)
    slow = np.where(t < th, 1.0, 0.55 + 0.45 * np.exp(-(t - th) / 0.28))
    ching = partials(t, th, [1760, 2640, 3520, 5280, 7040], [0, -4, -6, -9, -12], [16, 20, 24, 30, 40], rng, slow)
    boom = G.drop(t, 90, 40, 0.1, th) * G.env(t, th, 0.003, 0.25) * 0.9
    sparkle = noise(t, rng, [-40, -40, -40, -40, -10, 0]) * G.env(t, th, 0.01, 0.2) * 0.25
    return finish(swell + hit + ching * 0.55 + boom + sparkle, 1.5, dur)


def z4_spark(rng):
    dur = 0.55; t = taxis(dur)
    # 전기 지글거림: 아주 촘촘한 무작위 펄스를 고역으로 걸러 냄
    n = len(t); imp = np.zeros(n); hit = rng.uniform(0, 1, n) < 6000 * np.exp(-t / 0.05) / SR
    imp[hit] = rng.uniform(-1, 1, hit.sum())
    zap = lowpass(imp, 9000) - lowpass(imp, 1500)
    buzz = np.sign(np.sin(2 * math.pi * 120 * t)) * G.env(t, 0, 0.001, 0.04) * 0.3
    ding = partials(t, 0.004, [2093, 3136, 4186], [0, -5, -9], [45, 55, 70], rng)
    core = zap * 4 + buzz + ding * 0.6 + G.drop(t, 200, 70, 0.015, 0) * G.env(t, 0, 0.001, 0.04) * 0.6
    # 디지털 잔향: 30ms 간격으로 3번, 매번 작아지고 고역이 깎임 (끊어지는 반복)
    out = core.copy(); k = int(0.03 * SR)
    for r in range(1, 4):
        seg = np.r_[np.zeros(k * r), core[:-k * r]] * (0.55 ** r)
        out += lowpass(seg, 9000 / (r + 1)) * ((t * 1000 // 7) % 2 == 0)     # 7ms 단위로 끊기는 스터터
    return finish(out, 1.7, dur)


CANDIDATES = [
    ('Z1_clash', z1_clash, "검격 '챙!' — 아주 날카로운 시작, 2.5~9kHz 금속 배음이 밝게 빨리 사라짐, 짧은 킥. 휘익 없음 (0.45초)"),
    ('Z2_slam', z2_slam, "묵직한 '쾅!' — 120→38Hz 서브 낙하, 두꺼운 철판 몸통(140Hz), 포화된 크런치 (0.6초)"),
    ('Z3_timestop', z3_timestop, "시간 정지 — 0.18초 차오름 → '칭' → 느려지듯 음이 내려가는 '뷰웅~' 꼬리 + 반짝임 (0.9초)"),
    ('Z4_spark', z4_spark, "전기 스파크 — '빠직' 지글거림 + 밝은 '딩' + 30ms 간격으로 끊겨 반복되는 디지털 잔향 (0.55초)"),
]


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    for ci, (name, fn, _) in enumerate(CANDIDATES):
        write(os.path.join(OUT, f'{name}.wav'), fn(np.random.default_rng(40 + ci)))
        print(name)
