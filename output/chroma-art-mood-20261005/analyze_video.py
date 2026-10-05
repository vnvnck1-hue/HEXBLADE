import sys
from pathlib import Path
import subprocess
import json
import hashlib

sys.path.insert(0, r'C:\Users\vnvnc\.codex\visualizations\2026\10\05\01a10ae6-d7e8-7f80-bc83-c2c82b6e87bc\video_deps')
import imageio_ffmpeg
from PIL import Image, ImageDraw, ImageChops, ImageStat

OUT = Path(__file__).resolve().parent
VIDEO = Path(r'C:\Users\vnvnc\Downloads\chroma-inventory-2160p.mp4')
EXE = imageio_ffmpeg.get_ffmpeg_exe()
proc = subprocess.run([EXE, '-hide_banner', '-i', str(VIDEO), '-vf', 'scale=640:360', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-'], capture_output=True, check=True)
raw = proc.stdout
size = 640 * 360 * 3
count = len(raw) // size
frames = [Image.frombytes('RGB', (640, 360), raw[i * size:(i + 1) * size]) for i in range(count)]
sheet = Image.new('RGB', (2560, 1152), '#171421')
draw = ImageDraw.Draw(sheet)
for cell, index in enumerate(range(0, count, 10)):
    x, y = (cell % 4) * 640, (cell // 4) * 384
    sheet.paste(frames[index], (x, y))
    draw.text((x + 10, y + 363), f'{index / 30:.2f}s / frame {index}', fill='white')
sheet.save(OUT / 'video_contact.jpg', quality=94)
subprocess.run([EXE, '-hide_banner', '-loglevel', 'error', '-i', str(VIDEO), '-frames:v', '1', '-update', '1', '-y', str(OUT / 'video_reference.png')], check=True)
diff = ImageChops.difference(frames[0], frames[-1])
regions = {'top_navigation': (0, 0, 640, 35), 'equipment_hero': (200, 35, 640, 242), 'left_description': (0, 45, 175, 235), 'bottom_cards': (0, 250, 640, 360)}
stats = {name: [round(v, 3) for v in ImageStat.Stat(diff.crop(rect)).mean] for name, rect in regions.items()}
data = {'source': str(VIDEO), 'source_sha256': hashlib.sha256(VIDEO.read_bytes()).hexdigest(), 'width': 1920, 'height': 1080, 'fps': 30, 'duration_seconds': 4, 'decoded_frames': count, 'contact_interval_frames': 10, 'first_last_difference_rgb_at_640': stats, 'audio_stream': False}
(OUT / 'video_validation.json').write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
(OUT / 'video_metadata.txt').write_text(proc.stderr.decode('utf-8', errors='replace'), encoding='utf-8')
print(json.dumps(data, ensure_ascii=True, indent=2))
