from pathlib import Path
import json, hashlib, colorsys
import numpy as np
from PIL import Image, ImageDraw, ImageFont

folder = Path(__file__).resolve().parent
def rgb(path):
    return np.asarray(Image.open(path).convert('RGB'),dtype=np.float64)/255
def stats(a):
    a=a.reshape(-1,3)
    high,low=a.max(1),a.min(1)
    s=np.divide(high-low,high,out=np.zeros_like(high),where=high>0)
    return dict(pixels=len(a), mean_rgb=(a.mean(0)*255).tolist(),
        hue_of_mean_rgb_degrees=360*colorsys.rgb_to_hsv(*a.mean(0))[0],
        mean_hsv_v=float(high.mean()),mean_hsv_s=float(s.mean()),
        mean_srgb_luma=float((a@np.array([.2126,.7152,.0722])).mean()))
def pair(a,b):
    sa,sb=stats(a),stats(b)
    return dict(before=sa,after=sb,
        hue_of_mean_rgb_delta_degrees=(sb['hue_of_mean_rgb_degrees']-sa['hue_of_mean_rgb_degrees']+180)%360-180,
        v_delta_percentage_points=100*(sb['mean_hsv_v']-sa['mean_hsv_v']),
        s_delta_percentage_points=100*(sb['mean_hsv_s']-sa['mean_hsv_s']),
        luma_delta_percent=100*(sb['mean_srgb_luma']/sa['mean_srgb_luma']-1))

result=dict(flat_albedo=pair(rgb(folder/'before_effective.png'),rgb(folder/'after_effective.png')))
for frame in (90,120):
    mask_rgb=rgb(folder/f'game_{frame:04d}_floor_mask.png')
    mask=(mask_rgb[:,:,0]>.65)&(mask_rgb[:,:,2]>.65)&(mask_rgb[:,:,1]<.06)
    # Erode by 2 pixels to reject anti-aliased floor/object boundaries.
    core=mask[2:-2,2:-2].copy()
    for dy in range(-2,3):
        for dx in range(-2,3):
            core &= mask[2+dy:mask.shape[0]-2+dy,2+dx:mask.shape[1]-2+dx]
    mask[:]=False
    mask[2:-2,2:-2]=core
    assert mask.sum()>10000
    before=rgb(folder/f'game_{frame:04d}_before.png')
    after=rgb(folder/f'game_{frame:04d}_after.png')
    result[f'game_{frame:04d}']=pair(before[mask],after[mask])
    Image.fromarray(np.uint8(mask)*255).save(folder/f'game_{frame:04d}_floor_selection.png')
native=folder.parent/'hearthstone-conservative-floor-20261006/floor_4m_final.png'
applied=folder.parents[1]/'assets/textures/handpaint_blue/floor_hearthstone.png'
result['asset_sha256']=hashlib.sha256(applied.read_bytes()).hexdigest()
result['asset_byte_identical_to_approved_png']=native.read_bytes()==applied.read_bytes()
result['method']='Same paused main.tscn snapshots: only floor texture, direct sampling flag, old paint_mean and lift switched. Visible floor selected with magenta shader mask, eroded 2px. Fluid off only for reproducible comparison.'
assert result['asset_byte_identical_to_approved_png']
(folder/'tone_validation.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
font=ImageFont.truetype(r'C:\Windows\Fonts\malgun.ttf',30)
small=ImageFont.truetype(r'C:\Windows\Fonts\malgun.ttf',23)
canvas=Image.new('RGB',(1952,638),(24,27,39))
d=ImageDraw.Draw(canvas)
for i,name in enumerate(('before','after')):
    im=Image.open(folder/f'game_0120_{name}.png').convert('RGB').resize((960,540),Image.Resampling.LANCZOS)
    x=8+i*976
    canvas.paste(im,(x,56))
    d.text((x+8,10),'적용 전 · 기존 바닥' if i==0 else '적용 후 · 표현을 줄인 바닥',font=font,fill='white')
d.text((16,603),'동일 장면 · 동일 카메라와 조명 · 바닥 재질만 전환',font=small,fill=(190,200,218))
canvas.save(folder/'game_comparison.png')
print(json.dumps(result,ensure_ascii=True,indent=2))
