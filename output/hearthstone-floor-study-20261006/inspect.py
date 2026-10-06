import hashlib, json
from pathlib import Path
from PIL import Image
import numpy as np

ROOT = Path(__file__).resolve().parent
PROJECT = ROOT.parent.parent
def inspect(path):
    im = Image.open(path)
    rgb = np.asarray(im.convert('RGB'), dtype=np.float64) / 255.0
    high = rgb.max(axis=2)
    low = rgb.min(axis=2)
    sat = (high - low) / np.maximum(high, 1e-9)
    return dict(size=list(im.size), mode=im.mode,
        sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
        mean_rgb=(rgb.mean(axis=(0,1))*255).tolist(),
        mean_value=float(high.mean()), mean_saturation=float(sat.mean()),
        alpha_extrema=im.getchannel('A').getextrema() if 'A' in im.getbands() else None)

source = Path(r'C:\Users\Loadcomplete\.codex\generated_images\01a10f3b-ca50-7d30-a074-786eade5dbac\exec-371cadc3-4dad-4600-ab6b-8e7e23c456e6.png')
final = ROOT / 'floor_4m.png'
reference = PROJECT / 'output/hearthstone-prop-textures-20261006/references/bg_claude_f01_current.png'
a, b, r = inspect(source), inspect(final), inspect(reference)
assert a['sha256'] == b['sha256'], 'Original copy differs'
assert b['size'][0] == b['size'][1], 'Texture is not square'
assert b['alpha_extrema'] in (None, (255,255)), 'Texture must be opaque'
report = dict(generator='built-in imagegen', game_applied=False,
    texture='floor_4m.png', mapping='world XZ / 4m; 2x2 plates, each 2m',
    original=str(source), unchanged_original=True, generated=b, reference=r,
    delta_value=b['mean_value']-r['mean_value'],
    delta_saturation=b['mean_saturation']-r['mean_saturation'],
    inspected_visuals='2x2 plates, rivets and bevel shading, blue-purple palette; no text or margins',
    limitation='Repeatable grid designed; exact pixel edge seamlessness and in-game model appearance are not verified in this preview step.')
(ROOT/'validation.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps(report, ensure_ascii=False))
