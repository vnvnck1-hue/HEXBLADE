"""카툰 액체 튐 시트 애니메이션 생성기 (노이즈 + 거리장, 손그림 없이 코드로).

레퍼런스: 노란 카툰 액체가 얇은 막으로 늘어나다 구멍이 뚫리고 찢어져 방울로 흩어지는 모습.
같은 노이즈 장(field)을 프레임마다 매개변수만 바꿔 쓰므로 프레임 사이 모양이 튀지 않는다.

채널 (색은 굽지 않는다 — 게임 셰이더가 팔레트로 칠한다. 감염 체액 · 벌레 체액에 같은 시트):
  R = 두께 (0 = 바깥. 셰이더가 문턱으로 잘라 내고, 얇은 곳은 반투명한 막으로 칠한다)
  G = 명암 (왼쪽 위 빛을 받은 정도 0~1. 셰이더가 2~3단으로 끊는다)
  B = 하이라이트 (젖은 반짝임)
  A = 미리보기용 가장자리 (게임에서는 R 로 자른다)

종류 (4×4 = 16프레임, 프레임 256px, 시트 1024²):
  crown  부채꼴 왕관: 아래 가운데에서 위로 솟는 액체 벽. 위 가장자리에 손가락이 뻗고 끝이 방울로 떨어져 나간다.
         (u = 부채꼴 각도 방향, v = 아래 → 위). 부채꼴 메시에 입힌다.
  sheet  날아가는 막: 두꺼운 테두리 + 안쪽 얇은 막. 막에 구멍이 뚫려 번지고 테두리가 끊겨 방울이 된다 (레퍼런스와 같은 동작).
  glob   길쭉한 덩어리: 머리 방울 + 꼬리. 꼬리가 출렁이다 작은 방울로 끊긴다 (진행 방향 = +u).
  splat  바닥 철퍽: 가운데 웅덩이 + 별 모양 팔. 팔 끝 방울이 떨어지고 웅덩이가 자리 잡는다 (위에서 본 모습).

python tools/fx/liquid_sheets.py  → assets/vfx/liquid/liquid_<종류>.png
                                   + output/liquid-sheets-20261005/preview_<종류>_<팔레트>.gif · sheet_preview.png
"""

import math
import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_ASSET = os.path.join(ROOT, "assets", "vfx", "liquid")
OUT_PREV = os.path.join(ROOT, "output", "liquid-sheets-20261005")
FRAME = 256
SS = 2                      # 슈퍼샘플 (가장자리 계단 줄이기)
GRID = 4
N = FRAME * SS


# ── 노이즈 · 도우미 ─────────────────────────────────────────

class Noise2:
    """값 노이즈 (부드러운 보간). 같은 시드면 같은 장 — 프레임 사이 일관성."""

    def __init__(self, seed, size=64):
        rng = np.random.default_rng(seed)
        self.g = rng.random((size + 1, size + 1))
        self.size = size

    def __call__(self, x, y, freq):
        s = self.size
        fx = (x * freq) % s
        fy = (y * freq) % s
        ix = np.floor(fx).astype(int)
        iy = np.floor(fy).astype(int)
        tx = fx - ix
        ty = fy - iy
        tx = tx * tx * (3 - 2 * tx)
        ty = ty * ty * (3 - 2 * ty)
        g = self.g
        a = g[iy, ix]
        b = g[iy, ix + 1]
        c = g[iy + 1, ix]
        d = g[iy + 1, ix + 1]
        return (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty

    def fbm(self, x, y, freq, octaves=3):
        v = 0.0
        amp = 0.5
        tot = 0.0
        for o in range(octaves):
            v = v + self(x + o * 17.3, y + o * 9.1, freq * (2 ** o)) * amp
            tot += amp
            amp *= 0.5
        return v / tot


def ring_noise(theta, seed, kmin=2, kmax=8, falloff=1.0):
    """원 둘레를 따라 매끈하게 이어지는 1차원 노이즈 (-1~1)."""
    rng = np.random.default_rng(seed)
    v = np.zeros_like(theta)
    tot = 0.0
    for k in range(kmin, kmax + 1):
        a = rng.uniform(0.5, 1.0) / (k ** falloff)
        v = v + a * np.sin(k * theta + rng.uniform(0, math.tau))
        tot += a
    return v / tot


def line_noise(u, seed, kmin=1, kmax=7):
    rng = np.random.default_rng(seed)
    v = np.zeros_like(u)
    tot = 0.0
    for k in range(kmin, kmax + 1):
        a = rng.uniform(0.5, 1.0) / k
        v = v + a * np.sin(k * 2.3 * u + rng.uniform(0, math.tau))
        tot += a
    return v / tot


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def ease_out(t, p=2.2):
    return 1 - (1 - t) ** p


def blur(a, r):
    """분리형 박스 블러 3번 ≈ 가우시안 (r 픽셀)."""
    if r <= 0:
        return a
    out = a
    k = 2 * r + 1
    for _ in range(3):
        p = np.pad(out, ((r, r), (0, 0)), mode="edge")
        c = np.cumsum(p, axis=0)
        c = np.vstack([np.zeros((1, c.shape[1])), c])
        out = (c[k:] - c[:-k]) / k
        p = np.pad(out, ((0, 0), (r, r)), mode="edge")
        c = np.cumsum(p, axis=1)
        c = np.hstack([np.zeros((c.shape[0], 1)), c])
        out = (c[:, k:] - c[:, :-k]) / k
    return out


def blob(x, y, cx, cy, rx, ry=None):
    """타원 방울의 두께 (가운데 1, 가장자리 0, 바깥 음수 → 0)."""
    ry = rx if ry is None else ry
    d = ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2
    return np.sqrt(np.clip(1 - d, 0, 1))


def smax(a, b, k=0.08):
    """두께 장 부드러운 합 (덩어리끼리 녹아 붙게)."""
    h = np.clip(0.5 + 0.5 * (a - b) / k, 0, 1)
    return b + (a - b) * h + k * h * (1 - h)


# 좌표: x 오른쪽 + , y 위쪽 + (이미지 행은 뒤집어 저장), 범위 -1~1
_lin = (np.arange(N) + 0.5) / N * 2 - 1
X, Y = np.meshgrid(_lin, -_lin)
R = np.sqrt(X * X + Y * Y)
TH = np.arctan2(Y, X)


# ── 종류별 두께 장 (t = 0~1) ─────────────────────────────────

NS = Noise2(11)
NH = Noise2(23)


def field_sheet(t):
    """날아가는 막: 테두리 + 얇은 막 → 구멍 번짐 → 테두리 끊김 → 방울."""
    grow = ease_out(min(1.0, t / 0.55), 2.6)
    r0 = 0.22 + 0.58 * grow
    wob = ring_noise(TH + t * 0.6, 5, 2, 6) * 0.22 + ring_noise(TH, 9, 5, 9) * 0.06
    rad = r0 * (1 + wob)
    # 테두리: 반지름 근처 두꺼운 띠. 둘레를 따라 두께가 들쭉날쭉 (두꺼운 곳이 나중에 방울)
    rim_w = (0.075 + 0.06 * (1 - grow)) * (1 + 0.6 * ring_noise(TH, 13, 1, 5))
    lump = 0.6 + 0.4 * ring_noise(TH, 17, 2, 7)
    rim = np.exp(-((R - rad) / rim_w) ** 2) * lump
    # 끊김: 테두리의 얇은 곳부터 사라진다
    brk = smooth(0.5, 0.95, t)
    rim = rim * (1 - brk * smooth(0.25, 0.85, 1 - (lump - 0.2) / 0.8)) - brk * 0.35
    # 막: 안쪽 얇은 면. 노이즈 구멍이 점점 커진다
    inside = smooth(0.0, 0.08, rad - R)
    hn = NH.fbm(X * 1.6 + 3.0, Y * 1.6 + 1.0, 2.2, 3)
    hole_thr = 0.25 + smooth(0.08, 0.6, t) * 0.75
    mem = inside * 0.22 * smooth(hole_thr - 0.06, hole_thr + 0.06, hn) * (1 - smooth(0.55, 0.75, t))
    # 처음 순간: 가운데 덩어리
    core = blob(X, Y, 0, 0, 0.42 * (1 - grow) + 0.05) * (1 - smooth(0.0, 0.35, t))
    T = smax(smax(np.clip(rim, 0, None), mem, 0.05), core, 0.1)
    # 떨어져 나간 방울 (테두리 두꺼운 곳 밖으로)
    rng = np.random.default_rng(31)
    for i in range(7):
        a = rng.uniform(0, math.tau)
        st = rng.uniform(0.35, 0.65)
        if t < st:
            continue
        k = (t - st) / (1 - st)
        dist = (r0 * 1.05 + 0.1 + k * rng.uniform(0.15, 0.3))
        rr = rng.uniform(0.035, 0.07) * (1 - 0.5 * k)
        T = smax(T, blob(X, Y, math.cos(a) * dist, math.sin(a) * dist, rr * 1.3, rr), 0.03)
    # 끝: 전체가 줄어들며 사라짐
    T = T - smooth(0.82, 1.0, t) * 0.6
    return np.clip(T, 0, None)


def field_crown(t):
    """부채꼴 왕관: u = x (-1~1), v = (y+1)/2 (0 아래 ~ 1 위)."""
    u = X
    v = (Y + 1) * 0.5
    grow = ease_out(min(1.0, t / 0.45), 2.4)
    fall = smooth(0.5, 1.0, t)
    h = (0.22 + 0.42 * grow) * (1 + 0.15 * line_noise(u, 3)) * (1 - 0.35 * fall)
    # 옆 가장자리: 아래는 좁고 위로 벌어지며 들쭉날쭉 (상자처럼 보이지 않게)
    side = 0.35 + 0.5 * smooth(0.0, 0.7, v / np.maximum(h, 0.05)) + 0.1 * line_noise(v * 3.0, 19)
    edge = 1 - smooth(side - 0.12, side + 0.02, np.abs(u))
    # 벽: 위 가장자리가 두껍게 말린 테 + 아래쪽 얇은 막
    rim = np.exp(-((v - h) / (0.06 + 0.03 * (1 - grow))) ** 2) * (0.75 + 0.25 * line_noise(u, 7))
    wall = 0.22 * smooth(h + 0.02, h - 0.05, v) * smooth(0.0, 0.05, v)
    hn = NH.fbm(u * 1.4 + 5.0, v * 2.0, 2.4, 3)
    hole_thr = 0.2 + smooth(0.15, 0.7, t) * 0.8
    wall = wall * smooth(hole_thr - 0.06, hole_thr + 0.06, hn + (0.3 - v) * 0.6)
    base = blob(u, v, 0, 0.0, 0.45 * (1 - 0.5 * fall), 0.1 + 0.05 * (1 - fall)) * 0.9 * (1 - smooth(0.4, 0.7, t))
    T = smax(rim * edge, wall * edge, 0.05)
    T = smax(T, base, 0.06)
    # 손가락: 테에서 위로 뻗고 끝 방울이 떨어져 솟는다
    rng = np.random.default_rng(41)
    for i in range(6):
        fu = -0.75 + 1.5 * (i + rng.uniform(0.2, 0.8)) / 6
        st = rng.uniform(0.05, 0.25)
        if t < st:
            continue
        k = min(1.0, (t - st) / 0.5)
        ln = rng.uniform(0.1, 0.2) * ease_out(k)
        hb = h + 0.0
        top = hb + ln
        w = rng.uniform(0.035, 0.06) * (1 - 0.4 * k)
        # 줄기 (위로 갈수록 가늘어짐)
        along = np.clip((v - hb) / max(ln, 1e-3), 0, 1)
        stem = np.exp(-((u - fu) / (w * (1 - 0.6 * along))) ** 2) * (v > hb - 0.02) * (v < top) * 0.7
        detach = smooth(0.45, 0.6, t)
        stem = stem * (1 - detach * smooth(0.3, 0.6, along))
        drop_v = np.minimum(top + detach * (t - 0.45) * 0.5, 0.9) - smooth(0.75, 1.0, t) * 0.3
        dr = w * 1.6
        T = smax(T, stem, 0.04)
        T = smax(T, blob(u, v, fu, drop_v, dr, dr * 1.15) * 0.9, 0.04)
    T = T - smooth(0.84, 1.0, t) * 0.6
    return np.clip(T, 0, None)


def field_glob(t):
    """길쭉한 덩어리: 진행 +x. 머리 방울 + 출렁이는 꼬리가 끊겨 방울로."""
    sq = 1 + 0.18 * math.sin(t * 14.0) * (1 - t)
    hx = 0.35
    head = blob(X, Y, hx, 0, 0.3 * sq, 0.3 / sq) * 1.0
    # 꼬리: 뒤로 가늘어지는 줄. 출렁임
    along = np.clip((hx - X) / 1.25, 0, 1)
    wig = np.sin(along * 7.0 - t * 12.0) * 0.06 * along
    width = 0.2 * (1 - along) ** 1.4 + 0.015
    tail = np.exp(-((Y - wig) / width) ** 2) * smooth(hx + 0.05, hx - 0.15, X) * (X > hx - 1.25) * (1 - along * 0.3)
    # 꼬리 끊김: 얇은 곳부터 마디로
    seg = 0.5 + 0.5 * np.sin(along * 22.0 + 1.3)
    brk = smooth(0.35, 0.85, t)
    tail = tail * (1 - brk * smooth(0.25, 0.7, along) * smooth(0.35, 0.85, 1 - seg)) - brk * 0.15 * along
    T = smax(head, np.clip(tail * 0.75, 0, None), 0.08)
    # 머리 표면 혹 (매끈하지 않게)
    T = T * (1 + 0.12 * (NS.fbm(X * 2 + t * 0.5, Y * 2, 2.0, 2) - 0.5))
    T = T - smooth(0.85, 1.0, t) * 0.6
    return np.clip(T, 0, None)


def field_splat(t):
    """바닥 철퍽 (위에서 본 모습): 가운데 웅덩이 + 별 팔 + 팔 끝 방울."""
    grow = ease_out(min(1.0, t / 0.35), 3.0)
    settle = smooth(0.35, 1.0, t)
    pool_r = (0.25 + 0.25 * grow) * (1 + 0.15 * ring_noise(TH, 51, 2, 6))
    pool = np.sqrt(np.clip(1 - (R / pool_r) ** 2, 0, 1)) * (0.8 - 0.35 * settle)
    T = pool
    rng = np.random.default_rng(57)
    n_arm = 9
    for i in range(n_arm):
        a = math.tau * i / n_arm + rng.uniform(-0.25, 0.25)
        ln = rng.uniform(0.45, 0.85) * grow
        w = rng.uniform(0.05, 0.09)
        dx, dy = math.cos(a), math.sin(a)
        along = X * dx + Y * dy
        side = -X * dy + Y * dx
        k = np.clip(along / max(ln, 1e-3), 0, 1)
        arm = np.exp(-(side / (w * (1 - 0.65 * k) + 0.008)) ** 2) * (along > 0) * (along < ln) * (0.55 - 0.25 * k)
        arm = arm * (1 - settle * smooth(0.5, 0.9, k) * 0.9)
        T = smax(T, arm, 0.05)
        dr = w * 1.1
        d_off = ln + 0.06 + settle * 0.08
        T = smax(T, blob(X, Y, dx * d_off, dy * d_off, dr) * 0.6, 0.03)
    T = T - smooth(0.9, 1.0, t) * 0.08
    return np.clip(T, 0, None)


FIELDS = {"crown": field_crown, "sheet": field_sheet, "glob": field_glob, "splat": field_splat}


# ── 두께 장 → 채널 ──────────────────────────────────────────

THR = 0.035                 # 이보다 얇으면 바깥 (셰이더 cut 과 같은 값)
LIGHT = np.array([-0.55, 0.65, 0.52])     # 왼쪽 위 (x 오른쪽, y 위, z 화면 밖)
LIGHT = LIGHT / np.linalg.norm(LIGHT)
HALF = LIGHT + np.array([0, 0, 1.0])
HALF = HALF / np.linalg.norm(HALF)


BORDER = smooth(0.985, 0.93, np.maximum(np.abs(X), np.abs(Y)))   # 칸 가장자리는 비운다 (이웃 프레임으로 번지지 않게)


def channels(T):
    T = np.clip(T * BORDER - 0.02, 0, None)            # 가우시안 꼬리의 아주 얇은 번짐을 잘라 낸다
    h = blur(T, 5 * SS)
    gy, gx = np.gradient(h)
    gy = -gy                                 # 이미지 행은 아래로, y 는 위로
    k = 140.0 / SS
    nx, ny, nz = -gx * k, -gy * k, np.ones_like(h)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    nx, ny, nz = nx / ln, ny / ln, nz / ln
    shade = np.clip(nx * LIGHT[0] + ny * LIGHT[1] + nz * LIGHT[2], 0, 1)
    # 가장자리 안쪽은 어둡게 말려 들어간다 (카툰 테두리 그림자)
    edge = smooth(THR, THR + 0.12, T)
    shade = shade * (0.55 + 0.45 * edge)
    hl = smooth(0.955, 0.985, nx * HALF[0] + ny * HALF[1] + nz * HALF[2]) * smooth(0.25, 0.4, T)
    mask = smooth(THR - 0.008, THR + 0.008, T)
    return np.clip(T, 0, 1), shade, hl, mask


def downsample(a):
    return a.reshape(FRAME, SS, FRAME, SS).mean(axis=(1, 3))


def build(kind):
    f = FIELDS[kind]
    frames = []
    for i in range(GRID * GRID):
        t = i / (GRID * GRID - 1)
        T = f(t)
        frames.append([downsample(c) for c in channels(T)])
    sheet = np.zeros((FRAME * GRID, FRAME * GRID, 4))
    for i, (r, g, b, a) in enumerate(frames):
        y0 = (i // GRID) * FRAME
        x0 = (i % GRID) * FRAME
        sheet[y0:y0 + FRAME, x0:x0 + FRAME] = np.stack([r, g, b, a], axis=-1)
    return sheet, frames


# ── 미리보기 (게임 셰이더와 같은 칠 방식) ─────────────────────

PALETTES = {
    "yellow": {"shadow": (150, 92, 10), "mid": (205, 184, 22), "light": (236, 236, 92), "hi": (252, 252, 190), "mem": (98, 78, 22)},
    "wine": {"shadow": (58, 16, 52), "mid": (126, 36, 98), "light": (184, 70, 128), "hi": (255, 160, 210), "mem": (64, 22, 58)},
}


def paint(r, g, b, a, pal, bg=(24, 22, 26)):
    c = {k: np.array(v, float) for k, v in pal.items()}
    tone = np.where(g[..., None] < 0.32, c["shadow"], np.where(g[..., None] < 0.74, c["mid"], c["light"]))
    # 얇은 막은 어두운 반투명
    mem = smooth(0.11, 0.06, r)[..., None]
    col = tone * (1 - mem) + c["mem"] * mem
    col = col * (1 - b[..., None]) + c["hi"] * b[..., None]
    alpha = (a * (1 - mem[..., 0] * 0.35))[..., None]
    out = np.array(bg, float) * (1 - alpha) + col * alpha
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8))


def main():
    os.makedirs(OUT_ASSET, exist_ok=True)
    os.makedirs(OUT_PREV, exist_ok=True)
    gdi = os.path.join(OUT_PREV, ".gdignore")
    if not os.path.exists(gdi):
        open(gdi, "w").close()
    kinds = sys.argv[1:] or list(FIELDS)
    rows = []
    for kind in kinds:
        sheet, frames = build(kind)
        img = Image.fromarray((np.clip(sheet, 0, 1) * 255).astype(np.uint8), "RGBA")
        img.save(os.path.join(OUT_ASSET, "liquid_%s.png" % kind))
        for pn, pal in PALETTES.items():
            gif = [paint(*fr, pal) for fr in frames]
            gif[0].save(os.path.join(OUT_PREV, "preview_%s_%s.gif" % (kind, pn)), save_all=True,
                        append_images=gif[1:], duration=50, loop=0)
        strip = Image.new("RGB", (FRAME * 8, FRAME))
        for i in range(8):
            strip.paste(paint(*frames[i * 2], PALETTES["yellow"]), (i * FRAME, 0))
        rows.append(strip)
        print("built", kind)
    prev = Image.new("RGB", (FRAME * 8, FRAME * len(rows)))
    for i, s in enumerate(rows):
        prev.paste(s, (0, i * FRAME))
    prev.save(os.path.join(OUT_PREV, "sheet_preview.png"))


if __name__ == "__main__":
    main()
