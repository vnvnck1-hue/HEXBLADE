import hashlib, json
from pathlib import Path
from PIL import Image
import numpy as np

root = Path(__file__).resolve().parent
original = Path(r'C:\Users\Loadcomplete\.codex\generated_images\01a10f3b-ca50-7d30-a074-786eade5dbac\exec-90a14cb8-b941-4c3c-b8f2-bb4ea4870009.png')
final = root / 'floor_4m_chunky.png'
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
sources = json.loads((root/'research/images.json').read_text(encoding='utf-8-sig'))
for item in sources:
    path = root/'research/images'/item['file']
    assert inspect(path)['sha256'] == item['sha256']
report = dict(generator='built-in imagegen', file=final.name, unchanged_original=True,
    source=str(original), generated=out, reference=ref,
    delta_v=out['mean_hsv_value']-ref['mean_hsv_value'],
    delta_s=out['mean_hsv_saturation']-ref['mean_hsv_saturation'],
    research_images_decoded_and_hash_verified=len(sources), research_before_generation=True,
    visual_review='2x2 indigo steel plates with visibly wider blunt brush swaths, blocky shaded fasteners and interrupted rough bevel planes; no words/margins. Fine bristle lines remain within some broad strokes.',
    actual_painter_project=False, pbr_channel_set=False, game_applied=False,
    model_render_verified=False, pixel_seam_verified=False)
(root/'validation_chunky.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(report,ensure_ascii=False))
