"""Read-only image measurements; does not edit any raster asset."""
from pathlib import Path
import json
import numpy as np
from PIL import Image

folder = Path(__file__).resolve().parent
def pixels(name):
    return np.asarray(Image.open(folder / name).convert('RGB'), dtype=float) / 255

bright = pixels('15_previous_bright_floor_wall.png')
muted = pixels('10_floor_wall_only.png')
mask = bright.max(axis=2) > .22
def metrics(values):
    rgb = values[mask]
    mx, mn = rgb.max(axis=1), rgb.min(axis=1)
    return dict(mean_display_rgb_luma=float((rgb @ [.2126, .7152, .0722]).mean()),
                mean_hsv_saturation=float(((mx - mn) / np.maximum(mx, 1e-8)).mean()))
old, new = metrics(bright), metrics(muted)
vivid_mech = pixels('16_previous_bright_mech_markers.png')
muted_mech = pixels('13_static_mech_markers.png')
# Saturated green pixels in the stationary mech's bounding region.
region = np.zeros(bright.shape[:2], dtype=bool)
region[400:554, 725:840] = True
green = region & (vivid_mech[:,:,1] > vivid_mech[:,:,0] * 1.03) & (vivid_mech[:,:,1] > vivid_mech[:,:,2] * 1.2) & (vivid_mech[:,:,1] > .3)
report = dict(measurement='Identical camera and lighting. Floor/wall only, pixels of bright version with max RGB > .22. Luma measured in display RGB, not linear photometric luminance.',
              sampled_pixels=int(mask.sum()), before=old, after=new,
              luma_ratio=new['mean_display_rgb_luma']/old['mean_display_rgb_luma'],
              saturation_ratio=new['mean_hsv_saturation']/old['mean_hsv_saturation'],
              stationary_mech_green_pixels=int(green.sum()),
              stationary_mech_region_includes_edge_and_floor_pixels=True,
              stationary_mech_green_max_rgb_change=float(np.abs(vivid_mech[green] - muted_mech[green]).max()),
              stationary_mech_green_median_rgb_change=float(np.median(np.abs(vivid_mech[green] - muted_mech[green]))))
(folder / 'palette_metrics.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
print(json.dumps(report, indent=2))
