from pathlib import Path
import hashlib, json
import numpy as np
from PIL import Image

folder = Path(__file__).resolve().parent
def inspect(path):
    with Image.open(path) as im:
        im.load()
        size, mode = im.size, im.mode
        opaque = im.convert('RGBA').getextrema()[3] == (255, 255)
        rgb = np.asarray(im.convert('RGB'), dtype=np.float64) / 255
    vmax, vmin = rgb.max(2), rgb.min(2)
    sat = np.divide(vmax-vmin, vmax, out=np.zeros_like(vmax), where=vmax>0)
    luma = rgb @ np.array([.2126, .7152, .0722])
    interiors = np.concatenate([luma[y:y+480, x:x+480].ravel()
        for y in (74, 701) for x in (74, 701)])
    return dict(path=str(path), sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
        size=size, mode=mode, opaque=opaque, mean_hsv_v=float(vmax.mean()),
        mean_hsv_s=float(sat.mean()), global_luma_std=float(luma.std()),
        panel_interior_luma_std=float(interiors.std()),
        panel_interior_p95_p05=float(np.percentile(interiors,95)-np.percentile(interiors,5)))

before = inspect(folder/'floor_4m_final.png')
after = inspect(folder/'floor_4m_low_contrast.png')
native = Path(r'C:\Users\Loadcomplete\.codex\generated_images\01a10f3b-ca50-7d30-a074-786eade5dbac\exec-9314d54d-c5be-4844-a259-4bf5dcf1213b.png')
result = dict(before=before, after=after,
    generated_source=str(native), generated_copy_sha_equal=after['sha256']==hashlib.sha256(native.read_bytes()).hexdigest(),
    interior_contrast_reduction_percent=100*(1-after['panel_interior_p95_p05']/before['panel_interior_p95_p05']),
    metric_note='sRGB weighted luma, four 480-square plate interior regions; read-only pixel analysis',
    game_applied=False, model_uv_verified=False, seamless_repeat_verified=False)
assert after['size']==(1254,1254) and after['opaque'] and result['generated_copy_sha_equal']
(folder/'validation_low_contrast.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(result,ensure_ascii=True,indent=2))
