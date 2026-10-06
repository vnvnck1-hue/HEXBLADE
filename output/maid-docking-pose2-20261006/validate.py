"""Validate the saved image without editing its pixels."""
from pathlib import Path
import hashlib
import json
from PIL import Image

folder = Path(__file__).resolve().parent
final = folder / 'mint_maid_docking_pose2.png'
master = Path(r'C:\Users\vnvnc\.codex\generated_images\01a11195-3978-7991-a030-d6230c8f07ab\exec-dddf4d35-c75d-4f97-9044-b64fdcd6edb7.png')
with Image.open(final) as check:
    check.verify()
with Image.open(final) as im:
    alpha = im.getchannel('A')
    report = {
        'file': final.name,
        'size': list(im.size),
        'mode': im.mode,
        'alpha_extrema': list(alpha.getextrema()),
        'alpha_bbox': list(alpha.getbbox()),
        'corner_alpha': [alpha.getpixel(xy) for xy in [(0, 0), (im.width-1, 0), (0, im.height-1), (im.width-1, im.height-1)]],
        'sha256': hashlib.sha256(final.read_bytes()).hexdigest(),
        'master_copy_identical': final.read_bytes() == master.read_bytes(),
        'game_capture': {'engine': '4.7.2.stable.official.ed1daf0bf', 'renderer': 'Forward+', 'scene': 'res://scenes/training.tscn', 'trigger': 'PartnerDrone.whirl_link() (Q fusion)', 'frames': 80, 'dock_time': 0.233, 'exit_code': 0, 'script_errors': 0, 'environment_errors': ['user log rotation access', 'user log file write access', 'Windows root certificate store access']},
        'visual_check': 'Same mint maid identity and costume; both open hands have five fingers; two legs/shoes visible; dynamic twist/jump and spread-arm silhouette differs from original tray pose; no props or trails drawn.',
        'integration': 'Artwork only; new pose not connected to runtime portrait, layout, or motion masks.'
    }
    assert im.mode == 'RGBA'
    assert report['alpha_extrema'] == [0, 255]
    assert report['corner_alpha'] == [0, 0, 0, 0]
    assert report['master_copy_identical']
(folder / 'validation.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps(report, ensure_ascii=False, indent=2))
