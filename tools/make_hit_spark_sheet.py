"""적 피격 섬광 스프라이트 시트 생성기 (카툰풍, 3프레임).

출력: assets/fx/hit_spark_sheet.png  (가로 3칸, 칸당 CELL px, 투명 배경)
  1프레임  임팩트: 흰 심지 네 갈래 별 + 화면을 긋는 긴 대각 줄기 + 두꺼운 노란 초승달
  2프레임  확산: 심지가 작아지고 줄기는 더 길고 가늘게, 고리는 커지며 가시가 돋고 파편이 튄다
  3프레임  소멸: 심지 없이 줄기 끝 조각 · 끊어진 가는 고리 · 멀리 흩어진 작은 파편

모든 도형은 외곽선 없이 평면 채색(바깥 색 → 안쪽 흰색) + 같은 색의 부드러운 번짐으로 그려
게임의 다른 연출(외곽선 없는 발광 도형)과 결을 맞춘다.
실행: python tools/make_hit_spark_sheet.py
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter

CELL = 256
SS = 4                      # 슈퍼샘플링 배율
C = CELL * SS
MAGENTA = (255, 60, 225)
PINK = (255, 150, 245)
WHITE = (255, 255, 255)
YELLOW = (255, 214, 50)
PALE_Y = (255, 244, 160)


def spike(cx, cy, ang, length_a, length_b, width, n=24):
    """가운데가 굵고 양 끝이 뾰족한 줄기 (옆선이 오목하게 휜다). length_a/b: 양쪽 길이."""
    pts = []
    ca, sa = math.cos(ang), math.sin(ang)

    def put(x, y):
        pts.append((cx + x * ca - y * sa, cy + x * sa + y * ca))

    for i in range(n + 1):
        x = length_a * (1 - i / n)
        put(x, width * (1 - x / length_a) ** 2)
    for i in range(1, n + 1):
        x = -length_b * i / n
        put(x, width * (1 + x / length_b) ** 2)
    for i in range(n - 1, 0, -1):
        x = -length_b * i / n
        put(x, -width * (1 + x / length_b) ** 2)
    for i in range(0, n):
        x = length_a * i / n
        put(x, -width * (1 - x / length_a) ** 2)
    return pts


def astroid(cx, cy, r, ang, n=64, squash=1.0):
    """오목한 네 갈래 별 (아스트로이드)."""
    pts = []
    ca, sa = math.cos(ang), math.sin(ang)
    for i in range(n):
        t = 2 * math.pi * i / n
        x = r * math.cos(t) ** 3
        y = r * squash * math.sin(t) ** 3
        pts.append((cx + x * ca - y * sa, cy + x * sa + y * ca))
    return pts


def crescent(cx, cy, r, thick, ang, gap=0.9, n=96):
    """한쪽(ang)이 가장 두껍고 반대쪽으로 가늘어지다 gap(라디안) 만큼 끊기는 고리."""
    outer, inner = [], []
    span = 2 * math.pi - gap
    for i in range(n + 1):
        a = ang + math.pi + gap / 2 + span * i / n
        k = 0.5 + 0.5 * math.cos(a - ang)
        th = thick * (0.08 + 0.92 * k ** 1.4)
        outer.append((cx + math.cos(a) * (r + th / 2), cy + math.sin(a) * (r + th / 2)))
        inner.append((cx + math.cos(a) * (r - th / 2), cy + math.sin(a) * (r - th / 2)))
    return outer + inner[::-1]


def thorn(cx, cy, r, a, length, width):
    """고리 바깥으로 돋은 가시 (고리 진행 방향으로 살짝 휜 삼각형)."""
    base = (cx + math.cos(a) * r, cy + math.sin(a) * r)
    tip_a = a + 0.12
    tip = (cx + math.cos(tip_a) * (r + length), cy + math.sin(tip_a) * (r + length))
    d = width / r
    b1 = (cx + math.cos(a - d) * r * 0.97, cy + math.sin(a - d) * r * 0.97)
    b2 = (cx + math.cos(a + d) * r * 0.97, cy + math.sin(a + d) * r * 0.97)
    return [b1, tip, b2, base]


def shard(cx, cy, dist, a, size):
    """바깥으로 튀는 작은 마름모 파편 (진행 방향으로 길쭉)."""
    px, py = cx + math.cos(a) * dist, cy + math.sin(a) * dist
    return spike(px, py, a, size, size * 0.5, size * 0.28, 6)


def mask_of(polys, grow_px=0):
    """도형 마스크. grow_px > 0 이면 그만큼 부풀리고, < 0 이면 깎는다 (둘레에 선을 그어서)."""
    m = Image.new("L", (C, C), 0)
    d = ImageDraw.Draw(m)
    for p in polys:
        d.polygon(p, fill=255)
    if grow_px != 0:
        v = 255 if grow_px > 0 else 0
        for p in polys:
            d.line(p + [p[0]], fill=v, width=int(abs(grow_px) * 2), joint="curve")
    return m


def layer(canvas, m, color, alpha=1.0):
    if alpha < 1.0:
        m = m.point(lambda v: int(v * alpha))
    solid = Image.new("RGBA", (C, C), color + (255,))
    solid.putalpha(m)
    canvas.alpha_composite(solid)


def paint(canvas, polys, outer, inner, glow=None, core_in=10, core_polys=None):
    """번짐 → 바깥색 → 안쪽 흰 심지 순서로 칠한다."""
    m = mask_of(polys)
    if glow:
        g = mask_of(polys, 10 * SS).filter(ImageFilter.GaussianBlur(14 * SS))
        layer(canvas, g, glow, 0.75)
    layer(canvas, m, outer)
    # 안쪽 심지: 합친 마스크를 흐린 뒤 높은 문턱으로 잘라 둘레를 고르게 깎는다 (도형이 겹쳐도 이음새가 없다)
    core = m.filter(ImageFilter.GaussianBlur(core_in * 1.0)).point(lambda v: 255 if v > 200 else 0)
    if core_polys:
        # 별 심지는 따로 그린 뾰족한 흰 도형으로 (깎은 모양은 뭉툭해진다)
        core = mask_of(core_polys)
    layer(canvas, core.filter(ImageFilter.GaussianBlur(SS * 0.6)), inner)


def frame(i):
    cv = Image.new("RGBA", (C, C), (0, 0, 0, 0))
    cx = cy = C / 2
    u = C / 256.0                       # 1칸 = 256 단위
    main = math.radians(-35)            # 긴 줄기 방향 (게임에서 맞은 방향으로 돌린다)
    ring_a = math.radians(200)
    if i == 0:
        # 임팩트: 두꺼운 초승달 + 큰 별 심지 + 굵은 대각 줄기
        paint(cv, [crescent(cx, cy, 66 * u, 22 * u, ring_a, 1.1)], YELLOW, PALE_Y, YELLOW, 8 * SS)
        paint(cv, [spike(cx, cy, main, 124 * u, 96 * u, 19 * u),
                   spike(cx, cy, main + math.pi / 2, 48 * u, 42 * u, 16 * u),
                   astroid(cx, cy, 58 * u, main + math.pi / 4)],
              MAGENTA, WHITE, MAGENTA, 8 * SS,
              [spike(cx, cy, main, 104 * u, 78 * u, 7 * u), spike(cx, cy, main + math.pi / 2, 34 * u, 30 * u, 6 * u),
               astroid(cx, cy, 44 * u, main + math.pi / 4)])
    elif i == 1:
        # 확산: 고리가 커지며 가시가 돋고, 줄기는 길고 가늘게, 파편이 튄다
        ring = [crescent(cx, cy, 92 * u, 13 * u, ring_a, 1.4)]
        for a, ln in ((ring_a - 0.5, 24), (ring_a + 0.9, 18), (ring_a - 1.9, 14), (ring_a + 2.4, 12)):
            ring.append(thorn(cx, cy, 92 * u, a, ln * u, 6 * u))
        paint(cv, ring, YELLOW, PALE_Y, YELLOW, 5 * SS)
        shards = [shard(cx, cy, 78 * u, a, 16 * u) for a in (main + 2.2, main - 1.3, main + 0.9, main + 3.6)]
        paint(cv, [spike(cx, cy, main, 126 * u, 106 * u, 12 * u),
                   spike(cx, cy, main + math.pi / 2, 36 * u, 32 * u, 10 * u),
                   astroid(cx, cy, 34 * u, main + math.pi / 4)] + shards,
              MAGENTA, WHITE, MAGENTA, 6 * SS,
              [spike(cx, cy, main, 108 * u, 88 * u, 4 * u), spike(cx, cy, main + math.pi / 2, 24 * u, 21 * u, 4 * u),
               astroid(cx, cy, 24 * u, main + math.pi / 4)])
    else:
        # 소멸: 끊어진 가는 고리 조각 · 줄기 끝 조각 · 멀리 흩어진 파편
        ring = []
        for a0, a1 in ((ring_a - 1.3, ring_a - 0.2), (ring_a + 0.4, ring_a + 1.2), (ring_a + 2.1, ring_a + 2.6)):
            n = 20
            r, th = 108 * u, 6 * u
            o = [(cx + math.cos(a0 + (a1 - a0) * k / n) * (r + th), cy + math.sin(a0 + (a1 - a0) * k / n) * (r + th)) for k in range(n + 1)]
            n_ = [(cx + math.cos(a0 + (a1 - a0) * k / n) * (r - th), cy + math.sin(a0 + (a1 - a0) * k / n) * (r - th)) for k in range(n + 1)]
            ring.append(o + n_[::-1])
        paint(cv, ring, YELLOW, PALE_Y, YELLOW, 3 * SS)
        ca, sa = math.cos(main), math.sin(main)
        tips = [spike(cx + ca * 96 * u, cy + sa * 96 * u, main, 26 * u, 22 * u, 5 * u, 10),
                spike(cx - ca * 80 * u, cy - sa * 80 * u, main, 18 * u, 20 * u, 4 * u, 10)]
        shards = [shard(cx, cy, 104 * u, a, 11 * u) for a in (main + 2.3, main - 1.2, main + 1.0, main + 3.5, main - 2.6)]
        paint(cv, tips + shards + [astroid(cx, cy, 12 * u, main + math.pi / 4)], MAGENTA, PINK, MAGENTA, 3 * SS)
    return cv.resize((CELL, CELL), Image.LANCZOS)


def main():
    sheet = Image.new("RGBA", (CELL * 3, CELL), (0, 0, 0, 0))
    for i in range(3):
        sheet.alpha_composite(frame(i), (CELL * i, 0))
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out = os.path.join(root, "assets", "fx", "hit_spark_sheet.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    sheet.save(out)
    print(out)


if __name__ == "__main__":
    main()
