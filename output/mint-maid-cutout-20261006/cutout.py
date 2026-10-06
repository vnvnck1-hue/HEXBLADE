# 민트 메이드 원화의 보라 배경(바닥 그림자 포함)을 지워 투명 PNG 로 만든다. numpy + Pillow 만 사용.
# 실행: python output/mint-maid-cutout-20261006/cutout.py
#  1) 배경과 같은 계열(같은 색 방향 · 배경 밝기의 0.4~1.12배)인 픽셀을 테두리에서부터 이어진 만큼 지움 (외곽선이 막아 줌)
#  2) 테두리와 안 이어진 갇힌 배경 구멍(팔 · 머리카락 사이)은 배경색에 아주 가깝고 일정 크기 이상일 때만 지움
#  3) 경계 2px 는 "검정 외곽선 + 그 자리 배경" 섞임으로 보고 알파를 풀어 보라 테를 없앰
from collections import deque
from pathlib import Path
import json

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "assets/캐릭터/ChatGPT 이미지 2026년 10월 2일 오후 11_20_41.png"
OUT = Path(__file__).resolve().parent

img = np.asarray(Image.open(SRC).convert("RGB")).astype(np.float32)
H, W, _ = img.shape
B = np.median(np.concatenate([img[:8].reshape(-1, 3), img[-8:].reshape(-1, 3), img[:, :8].reshape(-1, 3), img[:, -8:].reshape(-1, 3)]), axis=0)
INK = np.array([8.0, 8.0, 20.0])

lum = img.sum(2) / B.sum()
dirn = img / np.maximum(img.sum(2, keepdims=True), 1.0)
bdir = B / B.sum()
cand = (np.abs(dirn - bdir).sum(2) < 0.035) & (lum > 0.40) & (lum < 1.12)


def reconstruct(seed, mask):
    cur = seed & mask
    while True:
        g = cur.copy()
        g[1:] |= cur[:-1]; g[:-1] |= cur[1:]; g[:, 1:] |= cur[:, :-1]; g[:, :-1] |= cur[:, 1:]
        g &= mask
        if (g == cur).all():
            return cur
        cur = g


border = np.zeros_like(cand)
border[0] = border[-1] = True
border[:, 0] = border[:, -1] = True
bg = reconstruct(border, cand)

# 갇힌 구멍
strict = cand & ~bg & (np.abs(img - B).max(2) < 14)
seen = np.zeros_like(strict)
holes = 0
for y, x in zip(*np.nonzero(strict)):
    if seen[y, x]:
        continue
    comp = []
    q = deque([(y, x)]); seen[y, x] = True
    while q:
        cy, cx = q.popleft(); comp.append((cy, cx))
        for ny, nx in ((cy + 1, cx), (cy - 1, cx), (cy, cx + 1), (cy, cx - 1)):
            if 0 <= ny < H and 0 <= nx < W and strict[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True; q.append((ny, nx))
    if len(comp) >= 150:
        holes += 1
        ys, xs = zip(*comp)
        grow = np.zeros_like(cand); grow[list(ys), list(xs)] = True
        bg |= reconstruct(grow, cand)



# 남은 조각 중 작은 것(바닥 그림자 가장자리 부스러기)은 배경으로: 남길 픽셀의 연결 덩어리 크기를 잼
def components(mask):
    lab = np.zeros(mask.shape, np.int32)
    sizes = []
    for y, x in zip(*np.nonzero(mask)):
        if lab[y, x]:
            continue
        n = len(sizes) + 1
        cnt = 0
        q = deque([(y, x)]); lab[y, x] = n
        while q:
            cy, cx = q.popleft(); cnt += 1
            for ny in (cy - 1, cy, cy + 1):
                for nx in (cx - 1, cx, cx + 1):
                    if 0 <= ny < H and 0 <= nx < W and mask[ny, nx] and not lab[ny, nx]:
                        lab[ny, nx] = n; q.append((ny, nx))
        sizes.append(cnt)
    return lab, sizes


lab, sizes = components(~bg)
SPECK = 1500
big = [i + 1 for i, s in enumerate(sizes) if s >= SPECK]
print("kept pieces:", sorted((s for s in sizes if s >= 40), reverse=True)[:12], "· specks removed:", sum(1 for s in sizes if s < SPECK))
bg |= ~np.isin(lab, big)


def box(a, r):
    c = np.pad(a, ((r + 1, r), (r + 1, r)), mode="edge").cumsum(0).cumsum(1)
    return c[2 * r + 1:, 2 * r + 1:] - c[:-2 * r - 1, 2 * r + 1:] - c[2 * r + 1:, :-2 * r - 1] + c[:-2 * r - 1, :-2 * r - 1]


def dilate(m, n):
    for _ in range(n):
        g = m.copy()
        g[1:] |= m[:-1]; g[:-1] |= m[1:]; g[:, 1:] |= m[:, :-1]; g[:, :-1] |= m[:, 1:]
        m = g
    return m


# 그 자리 배경색 (그림자 위면 어두운 보라): 지운 픽셀만 평균
w = bg.astype(np.float32)
den = np.maximum(box(w, 7), 1e-3)
local_bg = np.stack([box(img[..., c] * w, 7) / den for c in range(3)], 2)
local_bg[den < 0.5] = B

alpha = np.where(bg, 0.0, 1.0).astype(np.float32)
band = dilate(bg, 2) & dilate(~bg, 2)
# p = a*INK + (1-a)*bg  →  a = |p-bg| / |INK-bg| (bg→INK 방향 투영)
d = INK - local_bg
a = ((img - local_bg) * d).sum(2) / np.maximum((d * d).sum(2), 1.0)
alpha[band] = np.clip(a[band], 0.0, 1.0)
alpha[~dilate(bg, 2)] = 1.0
alpha[bg & ~band] = 0.0

rgb = img.copy()
m = band & (alpha > 0.02)
am = alpha[m][:, None]
rgb[m] = np.clip((img[m] - (1 - am) * local_bg[m]) / am, 0, 255)
rgb[alpha <= 0.02] = 0
out = np.dstack([rgb, alpha * 255]).round().astype(np.uint8)
Image.fromarray(out, "RGBA").save(OUT / "mint_maid_transparent.png")

# 확인용: 밝은 · 어두운 · 체크 배경 위 합성
prev = []
for bgc in ((255, 255, 255), (28, 32, 49)):
    canvas = np.empty_like(img); canvas[:] = bgc
    prev.append(img * 0 + rgb * alpha[..., None] + canvas * (1 - alpha[..., None]))
yy, xx = np.mgrid[0:H, 0:W]
chk = np.where(((yy // 24 + xx // 24) % 2)[..., None] == 0, 200.0, 140.0) * np.ones(3)
chk[..., 1] = np.where(chk[..., 0] == 200, 60, 230)  # 마젠타/초록 체크라 남은 보라 테가 잘 보인다
prev.append(rgb * alpha[..., None] + chk * (1 - alpha[..., None]))
sheet = np.concatenate(prev, 1).astype(np.uint8)
Image.fromarray(sheet).resize((W * 3 // 2, H // 2)).save(OUT / "preview.png")

info = {"source": str(SRC.relative_to(ROOT)), "size": [W, H], "bg_rgb": B.round().tolist(),
        "transparent_px": int((alpha == 0).sum()), "partial_px": int(((alpha > 0) & (alpha < 1)).sum()),
        "enclosed_holes_removed": holes,
        "edge_alpha0": bool((alpha[0] == 0).all() and (alpha[-1] == 0).all() and (alpha[:, 0] == 0).all() and (alpha[:, -1] == 0).all())}
(OUT / "validation.json").write_text(json.dumps(info, ensure_ascii=False, indent=1), encoding="utf-8")
print(info)
