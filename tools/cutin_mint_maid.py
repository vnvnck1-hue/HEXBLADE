"""사선 DOCKING 컷인 — 민트 메이드 원화 가공 (docs/diagonal-docking-cutin.md "민트 메이드").

입력: output/mint-maid-cutout-20261006/mint_maid_transparent.png (배경을 지운 1122×1402 전신, cutout.py)
출력 assets/portraits/mint_maid/
  · mint-maid-docking.png     정사각 1402² (가로 가운데 정렬, 아래는 컷인 하단선에서 잘림)
  · mint-maid-motionmask.png  움직임 마스크 256² RGB (흐림) — 셰이더가 채널마다 따로 UV 를 민다
      R 머리카락(민트색 픽셀) · 끝으로 갈수록 크게는 셰이더가 뿌리 거리²로 곱한다
      G 치마 · 앞치마 · 프릴: 허리(무게 0) → 밑단(무게 1)으로 미리 곱해 둠, 두 다리는 뺌
      B 옷가지: 머리 리본 꼬리 · 허리 흰 리본 꼬리 · 허벅지 리본 — 매단 곳(0) → 끝(1)
  그리고 확정 시안의 소품 11장(output/maid-bold-prop-assets-20261005/png) → assets/vfx/maid_props/ 복사

실행: python -X utf8 tools/cutin_mint_maid.py   (좌표는 원화 1122×1402 픽셀)
"""
import os
import shutil

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "output", "mint-maid-cutout-20261006", "mint_maid_transparent.png")
OUT = os.path.join(ROOT, "assets", "portraits", "mint_maid")
PROPS_SRC = os.path.join(ROOT, "output", "maid-bold-prop-assets-20261005", "png")
PROPS_OUT = os.path.join(ROOT, "assets", "vfx", "maid_props")
MASK = 256

# 치마 윤곽 (허리 → 밑단) · 빼는 두 다리 · 옷가지 영역 [(다각형, 매단 y, 끝 y)]
SKIRT = [(330, 585), (560, 575), (790, 590), (850, 700), (880, 880), (800, 915), (640, 905), (520, 880), (400, 905), (300, 860), (290, 700)]
WAIST_Y, HEM_Y = 600.0, 905.0
LEGS = [[(445, 735), (548, 728), (560, 1010), (432, 1010)], [(578, 820), (700, 812), (705, 1010), (585, 1010)]]
CLOTH = [
    ([(690, 95), (850, 120), (860, 300), (845, 460), (770, 470), (700, 300)], 140.0, 460.0),   # 머리 리본 + 꼬리
    ([(222, 635), (350, 640), (345, 900), (300, 905), (225, 820)], 650.0, 900.0),              # 허리 흰 리본 꼬리
    ([(410, 785), (490, 785), (490, 845), (410, 845)], 790.0, 845.0),                          # 허벅지 리본 (왼)
    ([(650, 855), (720, 855), (720, 915), (650, 915)], 860.0, 915.0),                          # 허벅지 리본 (오)
]


def poly_mask(size, pts):
    img = Image.new("L", size, 0)
    ImageDraw.Draw(img).polygon(pts, fill=255)
    return np.asarray(img) > 0


def ramp(h, w, y0, y1):
    y = np.arange(h, dtype=np.float32)[:, None]
    k = np.clip((y - y0) / (y1 - y0), 0.0, 1.0)
    return np.broadcast_to(k * k * (3.0 - 2.0 * k), (h, w))


def soft(m, grow, blur):
    img = Image.fromarray((np.clip(m, 0, 1) * 255).astype(np.uint8), "L")
    img = img.filter(ImageFilter.MaxFilter(grow))                 # 윤곽 밖으로 넓혀 가장자리도 같이 움직이게
    img = img.resize((MASK, MASK), Image.LANCZOS)
    return np.asarray(img.filter(ImageFilter.GaussianBlur(blur))).astype(np.float32) / 255.0


def main():
    im = Image.open(SRC).convert("RGBA")
    w, h = im.size
    side = max(w, h)
    ox = (side - w) // 2
    sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    sq.paste(im, (ox, 0))
    os.makedirs(OUT, exist_ok=True)
    sq.save(os.path.join(OUT, "mint-maid-docking.png"), optimize=True)

    a = np.asarray(sq).astype(np.int32)
    r, g, b, al = a[..., 0], a[..., 1], a[..., 2], a[..., 3]
    hair = (al > 128) & (g > r + 18) & (g > b - 4) & (g > 90)
    size = (side, side)
    sh = lambda pts: [(x + ox, y) for x, y in pts]
    skirt = poly_mask(size, sh(SKIRT)) & (al > 0) & ~hair
    for leg in LEGS:
        skirt &= ~poly_mask(size, sh(leg))
    skirt_w = skirt * ramp(side, side, WAIST_Y, HEM_Y)
    cloth_w = np.zeros((side, side), np.float32)
    for pts, y0, y1 in CLOTH:
        m = poly_mask(size, sh(pts)) & (al > 0) & ~hair
        cloth_w = np.maximum(cloth_w, m * ramp(side, side, y0, y1))
    rgb = np.dstack([soft(hair, 13, 3.0), soft(skirt_w, 15, 3.5), soft(cloth_w, 11, 2.5)])
    Image.fromarray((rgb * 255).round().astype(np.uint8), "RGB").save(os.path.join(OUT, "mint-maid-motionmask.png"))

    # 확인용: 원화 위에 마스크 색 겹침 (git 제외 출력 폴더)
    dbg = Image.fromarray((rgb * 255).astype(np.uint8)).resize(size, Image.BILINEAR)
    base = sq.copy()
    over = Image.new("RGBA", size, (0, 0, 0, 0))
    over.putalpha(110)
    over.paste(dbg, (0, 0))
    over.putalpha(140)
    view = Image.alpha_composite(Image.alpha_composite(Image.new("RGBA", size, (30, 30, 40, 255)), base), over)
    view.convert("RGB").resize((side // 2, side // 2)).save(os.path.join(ROOT, "output", "mint-maid-cutout-20261006", "motionmask_check.png"))

    os.makedirs(PROPS_OUT, exist_ok=True)
    for f in sorted(os.listdir(PROPS_SRC)):
        if f.endswith(".png"):
            shutil.copyfile(os.path.join(PROPS_SRC, f), os.path.join(PROPS_OUT, f))
    print("ok", size, "offset x", ox, "hair px", int(hair.sum()), "skirt px", int(skirt.sum()))


if __name__ == "__main__":
    main()
