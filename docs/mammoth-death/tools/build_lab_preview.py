"""Package actual Godot frame captures for review (Pillow; no rendered artwork)."""
from pathlib import Path
import argparse
from PIL import Image, ImageDraw, ImageFont

parser = argparse.ArgumentParser()
parser.add_argument("capture", type=Path)
parser.add_argument("output", type=Path)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
frames = sorted(args.capture.glob("frame_*.png"))
assert frames, "No engine captures"
font = ImageFont.truetype("C:/Windows/Fonts/malgun.ttf", 20)
sheet = Image.new("RGB", (1280, 1296), "#080913")
selected = [48, 108, 164, 196, 224, 336]
labels = ["01 궤도 파손", "02 미끄러짐 → 기울기", "03 무게 중심 붕괴", "04 지면 충돌 직전", "05 2차 폭발 / 포탑 분리", "06 잔해 통과 / 카메라 복귀"]
for i, (number, label) in enumerate(zip(selected, labels)):
    source = args.capture / f"frame_{number:05d}.png"
    with Image.open(source) as frame:
        thumb = frame.convert("RGB").resize((640, 400), Image.Resampling.LANCZOS)
    x, y = (i % 2) * 640, (i // 2) * 432
    sheet.paste(thumb, (x, y))
    ImageDraw.Draw(sheet).text((x + 16, y + 405), label, font=font, fill="#e4efff")
sheet.save(args.output / "engine-contact-sheet.jpg", quality=94)
animated = []
for source in frames:
    with Image.open(source) as frame:
        animated.append(frame.convert("RGB").resize((768, 480), Image.Resampling.LANCZOS).quantize(colors=128))
animated[0].save(args.output / "engine-preview.gif", save_all=True, append_images=animated[1:], duration=67, loop=0, optimize=False)
for source, dest in [("frame_00224.png", "engine-blast.png"), ("frame_00360.png", "engine-final.png")]:
    with Image.open(args.capture / source) as frame:
        frame.save(args.output / dest)
print(f"Packaged {len(frames)} actual Godot frames into {args.output}")
