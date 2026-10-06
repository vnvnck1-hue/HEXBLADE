"""Verify generated files, transparency and source copies without changing pixels."""
from pathlib import Path
import hashlib
import json
from PIL import Image

folder = Path(__file__).resolve().parent
sources = json.loads((folder / 'sources.json').read_text(encoding='utf-8'))
reports = []
for entry in sources:
    path = folder / entry['file']
    master = Path(entry['source'])
    with Image.open(path) as check:
        check.verify()
    with Image.open(path) as im:
        alpha = im.getchannel('A')
        report = {
            'file': path.name,
            'size': list(im.size),
            'mode': im.mode,
            'alpha_extrema': list(alpha.getextrema()),
            'alpha_bbox': list(alpha.getbbox()),
            'opaque_content_bbox': list(alpha.point(lambda v: 255 if v >= 250 else 0).getbbox()),
            'outside_sample_alpha': [alpha.getpixel(xy) for xy in [(100, 100), (200, 100), (400, 10), (30, 700)]],
            'corner_alpha': [alpha.getpixel(xy) for xy in [(0, 0), (im.width-1, 0), (0, im.height-1), (im.width-1, im.height-1)]],
            'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
            'master_copy_identical': path.read_bytes() == master.read_bytes()
        }
        assert im.mode == 'RGBA'
        assert report['alpha_extrema'][0] == 0 and report['alpha_extrema'][1] >= 250
        assert report['corner_alpha'] == [0, 0, 0, 0]
        assert report['outside_sample_alpha'] == [0, 0, 0, 0]
        assert report['master_copy_identical']
        reports.append(report)
assert len(reports) == 3
(folder / 'validation.json').write_text(json.dumps(reports, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps(reports, ensure_ascii=False, indent=2))
