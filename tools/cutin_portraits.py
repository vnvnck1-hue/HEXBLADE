"""사선 DOCKING 컷인용 포트레이트 가공 (docs/diagonal-docking-cutin.md "캐릭터").

- 초록 머리 메이드 원화(투명 PNG, 1226×1672 전신에 가까움) → 위에서부터 원화 너비만큼 잘라 정사각(1226², 아래는 치마 밑에서 잘림)
  → assets/portraits/green_maid/green-maid-docking.png
- 머리카락 마스크(256², 흐림): 흔들림 셰이더가 이 영역의 UV 만 민다
  · 초록: 세이지 그린(G 가 R·B 보다 큼, 채도 낮음) · 보라: 보라 계열 + 재킷과 겹치지 않게 그림 위쪽 37.5% 안만
  → assets/portraits/green_maid/green-maid-hairmask.png · assets/portraits/purple_worker/purple-worker-cheerful-hairmask.png

- 초록 원화 왼쪽의 하트 말풍선 · 반짝이 2개는 따로 떼어(원화에서는 지움) 순서대로 튀어나오게 쓴다:
  green-maid-bubble.png(하트 자리를 흰색으로 메운 말풍선) · green-maid-heart.png · green-maid-sparkle-a/b.png
  위치(원화 1226² 기준 픽셀 중심)는 실행 때 출력 → diagonal_docking_cutin.gd 의 CHARACTERS.green.pops 에 적는다

실행: python tools/cutin_portraits.py <초록 원화 경로>
"""
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MASK = 256


def hair_mask(rgba: np.ndarray, kind: str) -> Image.Image:
    r = rgba[..., 0].astype(np.int32)
    g = rgba[..., 1].astype(np.int32)
    b = rgba[..., 2].astype(np.int32)
    a = rgba[..., 3]
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    if kind == "green":
        m = (a > 128) & (g > r + 2) & (g > b - 7) & (mx > 60) & (mx - mn < 90)   # 회청색 그림자 끝(147,151,154)까지
    else:
        h = rgba.shape[0]
        rows = np.arange(h)[:, None] < int(h * 0.375)
        m = (a > 128) & (b > g + 12) & (r > g + 4) & (mx > 45) & (mx < 200) & rows
    img = Image.fromarray((m * 255).astype(np.uint8), "L")
    img = img.filter(ImageFilter.MinFilter(3))           # 잡티 제거
    img = img.filter(ImageFilter.MaxFilter(13))          # 가장자리 밖으로 조금 넓혀 끝이 잘리지 않게
    img = img.resize((MASK, MASK), Image.LANCZOS)
    return img.filter(ImageFilter.GaussianBlur(3.0))


def main() -> None:
    src = sys.argv[1]
    im = Image.open(src).convert("RGBA")
    w, h = im.size
    side = w                                   # 정사각: 위에서부터 너비만큼 (얼굴이 작아지지 않게 다리는 버린다)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(im.crop((0, 0, w, min(h, side))), (0, 0))
    out_dir = os.path.join(ROOT, "assets", "portraits", "green_maid")
    os.makedirs(out_dir, exist_ok=True)
    # 말풍선 · 반짝이 떼어내기 (원화에서 서로 떨어진 덩어리: 사각 범위 안의 불투명 픽셀)
    arr = np.asarray(canvas).copy()
    pieces = {"bubble": (75, 237, 193, 359), "sparkle-a": (52, 375, 96, 441), "sparkle-b": (102, 446, 127, 480)}
    pad = 4
    for name, (x0, y0, x1, y1) in pieces.items():
        x0, y0, x1, y1 = x0 - pad, y0 - pad, x1 + pad + 1, y1 + pad + 1
        piece = arr[y0:y1, x0:x1].copy()
        arr[y0:y1, x0:x1, 3] = 0
        if name == "bubble":
            r = piece[..., 0].astype(int)
            g = piece[..., 1].astype(int)
            heart = (piece[..., 3] > 0) & (r - g > 45)
            hm = np.asarray(Image.fromarray((heart * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(3))) > 0
            hp = piece.copy()
            hp[~hm, 3] = 0
            Image.fromarray(hp).save(os.path.join(out_dir, "green-maid-heart.png"))
            ys, xs = np.nonzero(hm)
            print("heart center", (x0 + xs.mean(), y0 + ys.mean()), "size", piece.shape[1], piece.shape[0])
            piece[hm, 0:3] = 250                    # 하트 자리는 말풍선 안쪽 흰색으로
        Image.fromarray(piece).save(os.path.join(out_dir, "green-maid-%s.png" % name))
        print(name, "center", ((x0 + x1) / 2.0, (y0 + y1) / 2.0), "size", (x1 - x0, y1 - y0))
    canvas = Image.fromarray(arr)
    canvas.save(os.path.join(out_dir, "green-maid-docking.png"), optimize=True)
    hair_mask(np.asarray(canvas), "green").save(os.path.join(out_dir, "green-maid-hairmask.png"))
    pu = Image.open(os.path.join(ROOT, "assets", "portraits", "purple_worker", "purple-worker-cheerful.png")).convert("RGBA")
    hair_mask(np.asarray(pu), "purple").save(os.path.join(ROOT, "assets", "portraits", "purple_worker", "purple-worker-cheerful-hairmask.png"))
    print("ok", canvas.size)


if __name__ == "__main__":
    main()
