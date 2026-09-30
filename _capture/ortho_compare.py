"""3면도 원본과 렌더를 같은 축척으로 겹친다. 원본 중심 x: 정면 372, 옆(발 중심) 925, 뒤 1432.
출력: _capture/ortho_compare.png (위: 원본 | 렌더 | 겹침 50%)"""
from PIL import Image, ImageChops
import sys
sheet = Image.open("_capture/ref/sheet.png").convert("RGB")
centers = {"front": 372, "side": 925, "back": 1432}
rows = []
for k, cx in centers.items():
    r = Image.open(f"_capture/ortho_{k}.png").convert("RGB")
    W, H = r.size
    half = W // 2
    ref = Image.new("RGB", (W, H), (255, 255, 255))
    x0 = cx - half
    crop = sheet.crop((max(0, x0), 0, min(sheet.width, x0 + W), H))
    ref.paste(crop, (max(0, -x0), 0))
    blend = Image.blend(ref, r, 0.5)
    row = Image.new("RGB", (W * 3, H), (255, 255, 255))
    row.paste(ref, (0, 0)); row.paste(r, (W, 0)); row.paste(blend, (W * 2, 0))
    rows.append(row)
    blend.save(f"_capture/ortho_blend_{k}.png")
out = Image.new("RGB", (rows[0].width, sum(r.height for r in rows)))
y = 0
for r in rows:
    out.paste(r, (0, y)); y += r.height
out.save("_capture/ortho_compare.png")
