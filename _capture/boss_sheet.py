import glob
from PIL import Image, ImageDraw, ImageFont
files = sorted(glob.glob("boss/0*.png"))
labels = ["쿼터뷰 (게임 시점)", "정면", "측면", "후방 3/4", "후방", "탑뷰", "로우 앵글", "포탑 클로즈업", "플레이어와 크기 비교"]
w, h = 640, 400
sheet = Image.new("RGB", (w * 3, h * 3), (30, 30, 34))
d = ImageDraw.Draw(sheet)
try: font = ImageFont.truetype("C:/Windows/Fonts/malgunbd.ttf", 22)
except: font = ImageFont.load_default()
for i, f in enumerate(files):
    im = Image.open(f).convert("RGB").resize((w, h), Image.LANCZOS)
    x, y = (i % 3) * w, (i // 3) * h
    sheet.paste(im, (x, y))
    d.rectangle([x, y, x + w - 1, y + h - 1], outline=(20, 20, 24), width=2)
    d.text((x + 14, y + 10), labels[i], font=font, fill=(255, 255, 255), stroke_width=2, stroke_fill=(0, 0, 0))
sheet.save("boss-sheet.png")
print(len(files))
