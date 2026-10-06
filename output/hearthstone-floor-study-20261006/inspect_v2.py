import hashlib, json
from pathlib import Path
from PIL import Image
import numpy as np

root = Path(__file__).resolve().parent
original = Path(r'C:\Users\Loadcomplete\.codex\generated_images\01a10f3b-ca50-7d30-a074-786eade5dbac\exec-26938424-9157-456e-9212-3a97cbfdd36c.png')
final = root / 'floor_4m_v2.png'
reference = root.parent / 'hearthstone-prop-textures-20261006/references/bg_claude_f01_current.png'
def inspect(path):
    im = Image.open(path)
    im.load()
    rgb = np.asarray(im.convert('RGB'), dtype=np.float64) / 255
    maximum, minimum = rgb.max(axis=2), rgb.min(axis=2)
    return dict(size=list(im.size), mode=im.mode,
        sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
        mean_hsv_value=float(maximum.mean()),
        mean_hsv_saturation=float(((maximum-minimum)/np.maximum(maximum,1e-9)).mean()),
        alpha_extrema=im.getchannel('A').getextrema() if 'A' in im.getbands() else None)

src, out, ref = inspect(original), inspect(final), inspect(reference)
assert src['sha256'] == out['sha256']
assert out['size'][0] == out['size'][1]
assert out['alpha_extrema'] in (None, (255,255))
report = dict(generator='built-in imagegen', file=final.name, unchanged_original=True,
    source=str(original), generated=out, reference=ref,
    delta_v=out['mean_hsv_value']-ref['mean_hsv_value'],
    delta_s=out['mean_hsv_saturation']-ref['mean_hsv_saturation'],
    visual_review='Large broad painted swaths; fewer fine marks; 2x2 panels and corner bolts preserved; indigo-blue palette, no text/margins.',
    game_applied=False, model_render_verified=False, pixel_seam_verified=False)
(root/'validation_v2.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(report,ensure_ascii=False))
