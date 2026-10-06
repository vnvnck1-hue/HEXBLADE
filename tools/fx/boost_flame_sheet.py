"""부스터 불꽃 시트 애니메이션 생성기 (코드로 그린 2톤 카툰 불꽃, 4프레임).

레퍼런스: 2D 애니메이션 FX 'BOOST PROCESS' — 노란 바탕 + 밝은 안쪽, 외곽선 없음.
  1. 물방울: 분사구 쪽이 둥글고 끝이 뾰족
  2. 길게 늘어남: 머리는 작아지고 꼬리가 가늘고 길게
  3. 끊김: 분사구에 작은 불씨 + 떨어져 나간 둥근 덩어리
  4. 터짐: 떨어진 덩어리가 울퉁불퉁 부풀어 퍼짐
이 넷을 빠르게(초당 약 14) 돌리면 '퐁퐁' 끊어 뿜는 만화 불꽃이 된다.

프레임 128×256, 분사구 = 프레임 위 가운데, 불꽃은 아래(+y)로 뻗는다. 시트 = 가로 4칸 512×256 RGBA.
python tools/fx/boost_flame_sheet.py → assets/vfx/boost_flame/boost_flame_sheet.png
                                     + output/boost-flame-20261006/preview.gif · sheet_preview.png
"""

import math
import os

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_ASSET = os.path.join(ROOT, "assets", "vfx", "boost_flame")
OUT_PREV = os.path.join(ROOT, "output", "boost-flame-20261006")
W, H = 128, 256
SS = 4                                   # 슈퍼샘플
OUTER = (250, 204, 70)                   # 노랑
INNER = (255, 238, 150)                  # 밝은 안쪽


def grid():
    ys, xs = np.mgrid[0:H * SS, 0:W * SS].astype(np.float64)
    x = (xs + 0.5) / SS - W / 2
    y = (ys + 0.5) / SS
    return x, y


def circle(x, y, cx, cy, r):
    return np.hypot(x - cx, y - cy) - r


def cone(x, y, ax, ay, ra, bx, by, rb):
    """두 원(a, b)을 접선으로 이은 물방울 / 끝이 가는 캡슐 (거리장, 음수 = 안)."""
    dx, dy = bx - ax, by - ay
    h = math.hypot(dx, dy)
    ux, uy = dx / h, dy / h
    px, py = x - ax, y - ay
    # 축 좌표계: q.y = 축 방향, q.x = 옆
    qy = px * ux + py * uy
    qx = np.abs(px * uy - py * ux)
    b = (ra - rb) / h
    a = math.sqrt(max(1.0 - b * b, 0.0))
    k = qx * (-b) + qy * a   # dot(q, (-b, a))
    d = np.where(k < 0.0, np.hypot(qx, qy) - ra,
                 np.where(k > a * h, np.hypot(qx, qy - h) - rb, qx * a + qy * b - ra))
    return d


def wobble(x, y, cx, cy, r, seed):
    """울퉁불퉁한 덩어리 (반지름이 각도마다 출렁)."""
    th = np.arctan2(y - cy, x - cx)
    rr = r * (1.0 + 0.16 * np.sin(3 * th + seed) + 0.09 * np.sin(5 * th - seed * 1.7) + 0.05 * np.sin(7 * th + seed * 0.3))
    return np.hypot(x - cx, y - cy) - rr


def frames():
    x, y = grid()
    out = []
    # 1. 물방울
    out.append((cone(x, y, 0, 60, 48, 0, 214, 4),
                cone(x, y, -3, 56, 27, 0, 150, 3)))
    # 2. 길게 늘어남
    out.append((cone(x, y, 0, 42, 34, 2, 248, 3),
                cone(x, y, -2, 38, 17, 1, 156, 2)))
    # 3. 끊김: 분사구 불씨 + 떨어진 덩어리
    o = np.minimum(np.minimum(circle(x, y, 0, 13, 9), cone(x, y, 0, 13, 5, 0, 44, 2)), circle(x, y, 2, 152, 34))
    i = np.minimum(circle(x, y, 0, 12, 4), circle(x, y, -4, 146, 18))
    out.append((o, i))
    # 4. 터짐: 울퉁불퉁 퍼진 덩어리
    out.append((wobble(x, y, 3, 172, 47, 0.9), wobble(x, y, -5, 162, 25, 2.3)))
    return out


def render(o, i):
    a_out = np.clip(0.5 - o, 0, 1)
    a_in = np.clip(0.5 - i, 0, 1) * a_out
    rgb = np.zeros(o.shape + (3,))
    for c in range(3):
        rgb[..., c] = OUTER[c] * (1 - a_in) + INNER[c] * a_in
    rgba = np.dstack([rgb, a_out * 255.0])
    img = Image.fromarray(np.clip(rgba, 0, 255).astype(np.uint8), "RGBA")
    return img.resize((W, H), Image.LANCZOS)


def main():
    os.makedirs(OUT_ASSET, exist_ok=True)
    os.makedirs(OUT_PREV, exist_ok=True)
    fr = [render(o, i) for o, i in frames()]
    sheet = Image.new("RGBA", (W * len(fr), H), (0, 0, 0, 0))
    for k, f in enumerate(fr):
        sheet.paste(f, (k * W, 0))
    sheet.save(os.path.join(OUT_ASSET, "boost_flame_sheet.png"))
    # 미리보기: 남보라 바탕
    bg = (66, 60, 104, 255)
    prev = Image.new("RGBA", sheet.size, bg)
    prev.alpha_composite(sheet)
    prev.convert("RGB").resize((sheet.width * 2, sheet.height * 2), Image.NEAREST).save(os.path.join(OUT_PREV, "sheet_preview.png"))
    gif = []
    for f in fr:
        g = Image.new("RGBA", (W, H), bg)
        g.alpha_composite(f)
        gif.append(g.convert("RGB").resize((W * 2, H * 2), Image.NEAREST))
    gif[0].save(os.path.join(OUT_PREV, "preview.gif"), save_all=True, append_images=gif[1:], duration=70, loop=0)
    print("saved", os.path.join(OUT_ASSET, "boost_flame_sheet.png"))


if __name__ == "__main__":
    main()
