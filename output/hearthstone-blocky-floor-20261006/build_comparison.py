import hashlib, json
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import numpy as np

root=Path(__file__).resolve().parent
project=root.parent.parent
source=Path(r'C:\Users\Loadcomplete\.codex\generated_images\01a10f3b-ca50-7d30-a074-786eade5dbac\exec-6a26a0cd-37b0-4478-a4e0-92f032fd9b6a.png')
final=root/'floor_4m_final.png'
assert source.read_bytes()==final.read_bytes()
paths=[root/'current_effective.png',project/'output/substance-painter-floor-20261006/floor_4m_chunky_groove.png',final]
labels=['현재 게임 바닥','직전 시안 · 굵은 붓 + 홈','새 시안 · 하스스톤풍']
size,gap,pad,header,footer=800,24,20,76,48
canvas=Image.new('RGB',(size*3+gap*2+pad*2,size+header+footer),(25,26,38))
draw=ImageDraw.Draw(canvas)
font=ImageFont.truetype(r'C:\Windows\Fonts\malgun.ttf',30)
small=ImageFont.truetype(r'C:\Windows\Fonts\malgun.ttf',23)
records=[]
for i,path in enumerate(paths):
    im=Image.open(path); im.load()
    assert im.width==im.height
    if i==2:
        assert im.size==(1254,1254)
        assert 'A' not in im.getbands() or im.getchannel('A').getextrema()==(255,255)
    rgb=np.asarray(im.convert('RGB'),dtype=np.float64)/255
    high,low=rgb.max(axis=2),rgb.min(axis=2)
    preview=im.convert('RGB').resize((size,size),Image.Resampling.LANCZOS)
    x=pad+i*(size+gap)
    canvas.paste(preview,(x,header))
    draw.text((x,19),labels[i],font=font,fill=(238,238,246))
    assert canvas.crop((x,header,x+size,header+size)).tobytes()==preview.tobytes()
    records.append(dict(source=str(path),native_size=list(im.size),mode=im.mode,sha256=hashlib.sha256(path.read_bytes()).hexdigest(),mean_v=float(high.mean()),mean_s=float(((high-low)/np.maximum(high,1e-9)).mean())))
draw.text((pad,header+size+10),'동일한 4m 영역 · 조명/그림자 제외 · 비교용 크기만 통일',font=small,fill=(178,181,202))
out=root/'comparison_three.png'
canvas.save(out)
Image.open(out).verify()
ref=root/'reference_user.png'
Image.open(ref).verify()
report=dict(generator='built-in imagegen',file=final.name,original_copy_equal=True,comparison_size=list(canvas.size),comparison_color_edit=False,pixel_layout_verified=True,inputs=records,user_reference_sha256=hashlib.sha256(ref.read_bytes()).hexdigest(),visual_review='Hearthstone-like broad blue-purple facets, thick uneven chamfers and rounded dimples; exact 2x2 plates with four corner bolts each; no fine-brush blanket, words or margins.',game_applied=False,pixel_repeat_seam_verified=False,model_render_verified=False)
(root/'validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(report,ensure_ascii=True))
