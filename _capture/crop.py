import sys, re
from PIL import Image, ImageDraw
# crop.py dir log out cols t0 t1 step   -> close-ups around crawler between times
d, log, out, cols = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
t0, t1, step = float(sys.argv[5]), float(sys.argv[6]), int(sys.argv[7])
pos = []
for line in open(log, encoding='utf-8', errors='ignore'):
    m = re.match(r"CPOS (\d+) (-?\d+) (-?\d+) ([\d.]+)", line)
    if m: pos.append((int(m[1]), int(m[2]), int(m[3]), float(m[4])))
sel = [p for p in pos if t0 <= p[3] <= t1][::step]
W, H = 420, 300
rows = (len(sel) + cols - 1) // cols
sheet = Image.new("RGB", (W * cols, H * rows))
dr = ImageDraw.Draw(sheet)
for i, (f, x, y, t) in enumerate(sel):
    im = Image.open("%s/f_%04d.png" % (d, f)).convert("RGB")
    x = max(W // 2, min(im.width - W // 2, x)); y = max(H // 2, min(im.height - H // 2, y))
    c = im.crop((x - W // 2, y - H // 2, x + W // 2, y + H // 2))
    sheet.paste(c, ((i % cols) * W, (i // cols) * H))
    dr.text(((i % cols) * W + 6, (i // cols) * H + 4), "%.3f" % t, fill=(255, 255, 0))
sheet.save(out)
print(len(sel))
