import sys, glob
from PIL import Image

d, out = sys.argv[1], sys.argv[2]
start = int(sys.argv[3]) if len(sys.argv) > 3 else 0
step = int(sys.argv[4]) if len(sys.argv) > 4 else 1
files = sorted(glob.glob(d + "/f_*.png"))[start::step][:12]
w, h = 640, 400
sheet = Image.new("RGB", (w * 3, h * ((len(files) + 2) // 3)))
for i, f in enumerate(files):
    im = Image.open(f).convert("RGB").resize((w, h))
    sheet.paste(im, ((i % 3) * w, (i // 3) * h))
sheet.save(out)
print(len(files))
