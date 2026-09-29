import sys, os
from PIL import Image
d, out, frames = sys.argv[1], sys.argv[2], [int(x) for x in sys.argv[3].split(",")]
crop = tuple(int(x) for x in sys.argv[4].split(",")) if len(sys.argv) > 4 else None
files = sorted(f for f in os.listdir(d) if f.endswith(".png"))
ims = []
for i in frames:
    im = Image.open(os.path.join(d, files[i])).convert("RGB")
    if crop: im = im.crop(crop)
    ims.append(im)
w, h = ims[0].size
s = 0.5 if w > 700 else 1.0
w2, h2 = int(w*s), int(h*s)
cols = 3
rows = (len(ims)+cols-1)//cols
sheet = Image.new("RGB", (w2*cols, h2*rows))
for k, im in enumerate(ims):
    sheet.paste(im.resize((w2, h2)), ((k%cols)*w2, (k//cols)*h2))
sheet.save(out)
