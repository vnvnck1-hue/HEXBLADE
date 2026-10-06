# 캡처 폴더의 PNG 를 4열 시트로: python _capture/lancaster_sheet.py <폴더> <출력.png>
import sys, glob, os
from PIL import Image, ImageDraw
d, outp = sys.argv[1], sys.argv[2]
fs = sorted(glob.glob(os.path.join(d, "*.png")))
ims = [Image.open(f).convert("RGB") for f in fs]
w, h = ims[0].size
s = 0.4
tw, th = int(w * s), int(h * s)
cols = 4
rows = (len(ims) + cols - 1) // cols
sheet = Image.new("RGB", (tw * cols, th * rows))
for i, (f, im) in enumerate(zip(fs, ims)):
    im = im.resize((tw, th))
    ImageDraw.Draw(im).text((6, 6), os.path.basename(f), fill=(255, 255, 0))
    sheet.paste(im, ((i % cols) * tw, (i // cols) * th))
sheet.save(outp)
