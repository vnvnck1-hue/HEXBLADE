"""Godot 실제 캡처 프레임을 공유용 GIF로 포장한다. 게임 원화는 수정하지 않는다."""
from pathlib import Path
import json
from PIL import Image

root = Path(__file__).resolve().parent
names = ["owner", "worker", "partner", "mira", "sena", "noa", "eirin"]
results = []


def encode(prefix, target, size=None, crop=None):
    frames = []
    for path in sorted((root / "frames").glob(f"{prefix}_*.png")):
        with Image.open(path) as source:
            frame = source.convert("RGB")
            if crop:
                frame = frame.crop(crop)
            if size:
                frame = frame.resize(size, Image.Resampling.LANCZOS)
            frames.append(frame)
    if not frames:
        raise ValueError(f"No frames for {prefix}")
    atlas = Image.new("RGB", (320, 200 * 4))
    for row, index in enumerate([0, len(frames)//3, 2*len(frames)//3, len(frames)-1]):
        atlas.paste(frames[index].resize((320, 200)), (0, row * 200))
    palette = atlas.quantize(colors=256)
    quantized = [frame.quantize(palette=palette, dither=Image.Dither.NONE) for frame in frames]
    output = root / target
    quantized[0].save(output, save_all=True, append_images=quantized[1:], duration=67, loop=0, optimize=True)
    with Image.open(output) as gif:
        result = {"file": target, "size": list(gif.size), "frames": gif.n_frames, "bytes": output.stat().st_size}
        assert gif.n_frames == len(frames), result
        results.append(result)


for prefix in ["gallery", "mechanic", "partner"]:
    encode(prefix, f"{prefix}.gif", (960, 600))
for i, name in enumerate(names):
    x, y = (23 + i * 320, 112) if i < 4 else (183 + (i - 4) * 320, 461)
    encode("gallery", f"{i+1:02}_{name}.gif", crop=(x-10, y-32, x+286, y+286))
(root / "preview_validation.json").write_text(json.dumps(results, indent=2), encoding="utf-8")
print(json.dumps(results, indent=2))
