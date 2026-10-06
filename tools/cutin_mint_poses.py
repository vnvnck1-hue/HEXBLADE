"""사선 DOCKING 컷인 — 민트 메이드 추가 포즈 4장 가공 (docs/diagonal-docking-cutin.md "민트 메이드 포즈").

입력: output/mint-maid-poses-20261007/source/1~4.webp (사용자 제공 투명 전신, 1122×1402 · 1024×1536)
  1 두 손 모아 수줍게 · 2 가슴에 손 · 메롱 · 3 허리에 손 · 메롱 · 4 두 주먹 신남
출력 assets/portraits/mint_maid/
  · mint-maid-pose<N>.png       1402² — 기존 mint-maid-docking.png 와 같은 틀: 캐릭터 높이 1352px · 위 여백 15px · 가로 가운데
  · mint-maid-pose<N>-motion.png 움직임 마스크 256² RGB (R 머리카락 · G 치마(허리 0 → 밑단 1) · B 머리 리본(매단 곳 0 → 끝 1))
  webp 손실 압축 때문에 몸 안 알파가 252~254, 바깥에 알파 2 안팎 안개가 있어 16 미만 0 · 236 초과 255 로 정리한다.

실행: python -X utf8 tools/cutin_mint_poses.py   (좌표는 정규화된 1402² 픽셀)
"""
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "output", "mint-maid-poses-20261007", "source")
OUT = os.path.join(ROOT, "assets", "portraits", "mint_maid")
CHECK = os.path.join(ROOT, "output", "mint-maid-poses-20261007")
S = 1402
H_CHAR = 1352
TOP = 15
MASK = 256

# 포즈별: 치마 (허리 y, 밑단 y, x 범위) · 머리 리본 상자 (x0, y0, x1, y1)
POSES = {
    1: {"skirt": (650, 905, 400, 1000), "ribbon": (840, 60, 1010, 470)},
    2: {"skirt": (650, 905, 420, 940), "ribbon": (870, 70, 1050, 450)},
    3: {"skirt": (670, 895, 440, 960), "ribbon": (840, 70, 1010, 450)},
    4: {"skirt": (650, 890, 400, 990), "ribbon": (860, 70, 1030, 450)},
}


def ramp(h, w, y0, y1):
    y = np.arange(h, dtype=np.float32)[:, None]
    k = np.clip((y - y0) / (y1 - y0), 0.0, 1.0)
    return np.broadcast_to(k * k * (3.0 - 2.0 * k), (h, w))


def soft(m, grow, blur):
    img = Image.fromarray((np.clip(m, 0, 1) * 255).astype(np.uint8), "L")
    img = img.filter(ImageFilter.MaxFilter(grow))
    img = img.resize((MASK, MASK), Image.LANCZOS)
    return np.asarray(img.filter(ImageFilter.GaussianBlur(blur))).astype(np.float32) / 255.0


def box_mask(x0, y0, x1, y1):
    m = np.zeros((S, S), bool)
    m[y0:y1, x0:x1] = True
    return m


def main():
    os.makedirs(OUT, exist_ok=True)
    sheet = Image.new("RGB", (S // 2 * 4, S // 2), (40, 30, 70))
    for n, cfg in POSES.items():
        im = Image.open(os.path.join(SRC, "%d.webp" % n)).convert("RGBA")
        a = np.asarray(im).copy()
        al = a[..., 3].astype(np.int32)
        al[al < 16] = 0
        al[al > 236] = 255
        a[..., 3] = al
        im = Image.fromarray(a)
        ys, xs = np.nonzero(al > 0)
        crop = im.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
        k = H_CHAR / crop.size[1]
        crop = crop.resize((round(crop.size[0] * k), H_CHAR), Image.LANCZOS)
        sq = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        sq.paste(crop, ((S - crop.size[0]) // 2, TOP), crop)
        sq.save(os.path.join(OUT, "mint-maid-pose%d.png" % n), optimize=True)

        p = np.asarray(sq).astype(np.int32)
        r, g, b, al = p[..., 0], p[..., 1], p[..., 2], p[..., 3]
        solid = al > 128
        hair = solid & (g > r + 18) & (g > b - 4) & (g > 90)
        wy, hy, sx0, sx1 = cfg["skirt"]
        skirt = solid & ~hair & box_mask(sx0, wy - 20, sx1, hy + 10)
        skirt_w = skirt * ramp(S, S, wy, hy)
        rx0, ry0, rx1, ry1 = cfg["ribbon"]
        rib = solid & ~hair & box_mask(rx0, ry0, rx1, ry1)
        rib_w = rib * ramp(S, S, ry0 + 80, ry1)
        rgb = np.dstack([soft(hair, 13, 3.0), soft(skirt_w, 15, 3.5), soft(rib_w, 11, 2.5)])
        Image.fromarray((rgb * 255).round().astype(np.uint8), "RGB").save(os.path.join(OUT, "mint-maid-pose%d-motion.png" % n))

        # 확인 그림 (git 제외 폴더): 원화 위에 마스크 겹침
        dbg = Image.fromarray((rgb * 255).astype(np.uint8)).resize((S, S), Image.BILINEAR).convert("RGBA")
        dbg.putalpha(150)
        view = Image.alpha_composite(Image.alpha_composite(Image.new("RGBA", (S, S), (40, 30, 70, 255)), sq), dbg)
        sheet.paste(view.convert("RGB").resize((S // 2, S // 2)), ((n - 1) * (S // 2), 0))
        print("pose", n, "scale %.3f" % k, "hair px", int(hair.sum()), "skirt px", int(skirt.sum()), "ribbon px", int(rib.sum()))
    sheet.save(os.path.join(CHECK, "motionmask_check.png"))


if __name__ == "__main__":
    main()
