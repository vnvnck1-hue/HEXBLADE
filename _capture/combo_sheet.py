import sys, os
from PIL import Image, ImageDraw
# usage: combo_sheet.py dir out first last [step] [cols] [cx cy w h]
d, out = sys.argv[1], sys.argv[2]
a, b = int(sys.argv[3]), int(sys.argv[4])
st = int(sys.argv[5]) if len(sys.argv) > 5 else 1
cols = int(sys.argv[6]) if len(sys.argv) > 6 else 6
cx, cy, w, h = (int(x) for x in sys.argv[7:11]) if len(sys.argv) > 10 else (640, 380, 560, 400)
fr = [i for i in range(a, b + 1, st) if os.path.exists(f"{d}/f_{i:04d}.png")]
tw, th = 400, int(400 * h / w)
rows = (len(fr) + cols - 1) // cols
sheet = Image.new("RGB", (tw * cols, th * rows))
dr = ImageDraw.Draw(sheet)
for k, i in enumerate(fr):
    im = Image.open(f"{d}/f_{i:04d}.png").convert("RGB")
    im = im.crop((cx - w // 2, cy - h // 2, cx + w // 2, cy + h // 2)).resize((tw, th))
    x, y = (k % cols) * tw, (k // cols) * th
    sheet.paste(im, (x, y))
    dr.text((x + 6, y + 4), str(i), fill=(255, 255, 0))
sheet.save(out)
print(len(fr))
