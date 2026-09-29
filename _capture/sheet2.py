import sys, glob
from PIL import Image, ImageDraw
# usage: sheet2.py dir out cols scale f1 f2 ...   (frame numbers; label = frame)
d, out, cols, sc = sys.argv[1], sys.argv[2], int(sys.argv[3]), float(sys.argv[4])
fr = [int(x) for x in sys.argv[5:]]
w, h = int(1280 * sc), int(800 * sc)
rows = (len(fr) + cols - 1) // cols
sheet = Image.new("RGB", (w * cols, h * rows))
dr = ImageDraw.Draw(sheet)
for i, f in enumerate(fr):
    im = Image.open("%s/f_%04d.png" % (d, f)).convert("RGB").resize((w, h))
    sheet.paste(im, ((i % cols) * w, (i // cols) * h))
    dr.text(((i % cols) * w + 6, (i // cols) * h + 4), str(f), fill=(255, 255, 0))
sheet.save(out)
