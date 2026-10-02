"""Compose captured Godot frames into a still, a pose sheet and a GIF. Pillow only."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "output/insects-20261002"
frames = sorted((OUT / "studio_frames").glob("f_*.png"))
font = ImageFont.truetype("C:/Windows/Fonts/arialbd.ttf", 24)
small = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 18)
Image.open(frames[8]).save(OUT / "concepts-ingame.png")
names = ["IDLE / FEELERS", "WALK / TRIPOD + INCHING", "WINDUP / JAWS OPEN", "ATTACK / LUNGE", "RECOVER", "HURT / RECOIL", "STAGGER", "DEATH / LEG CURL", "EMERGE"]
sheet = Image.new("RGB", (1440, 1170), "#1b1826")
for i, name in enumerate(names):
    idx = min(len(frames)-1, i*13+8)
    tile = Image.open(frames[idx]).convert("RGB").crop((190,165,910,585)).resize((480,280), Image.Resampling.LANCZOS)
    x,y = (i%3)*480,(i//3)*390
    sheet.paste(tile,(x,y+45))
    ImageDraw.Draw(sheet).text((x+14,y+10), name, font=small, fill="#ffe2ab")
sheet.save(OUT / "animation-sheet.png")
gif=[]
for i, path in enumerate(frames):
    f=Image.open(path).convert("RGB").resize((770,518),Image.Resampling.LANCZOS)
    draw=ImageDraw.Draw(f)
    draw.rectangle((0,0,770,36),fill="#1b1826")
    label=names[min(8,int((i+1)*0.2/2.6))]
    draw.text((14,5),label,font=font,fill="#ffe2ab")
    gif.append(f)
gif[0].save(OUT / "insect-animation.gif",save_all=True,append_images=gif[1:],duration=200,loop=0,optimize=False)
print("saved concepts-ingame.png, animation-sheet.png, insect-animation.gif")
