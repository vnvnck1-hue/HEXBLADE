import hashlib, json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

root=Path(__file__).resolve().parent
project=root.parent.parent
paths=[root/'current_effective.png', project/'output/substance-painter-floor-20261006/floor_4m_chunky_groove.png']
labels=['현재 게임 바닥 · 셰이더 반영', '최신 시안 · 굵은 붓 + 홈 1개']
size,gap,pad,header,footer=1000,24,20,76,48
canvas=Image.new('RGB',(size*2+gap+pad*2,size+header+footer),(25,26,38))
draw=ImageDraw.Draw(canvas)
font=ImageFont.truetype(r'C:\Windows\Fonts\malgun.ttf',30)
small=ImageFont.truetype(r'C:\Windows\Fonts\malgun.ttf',23)
records=[]
for i,path in enumerate(paths):
    source=Image.open(path); source.load()
    assert source.width==source.height
    preview=source.convert('RGB').resize((size,size),Image.Resampling.LANCZOS)
    x=pad+i*(size+gap)
    canvas.paste(preview,(x,header))
    draw.text((x,19),labels[i],font=font,fill=(238,238,246))
    records.append(dict(source=str(path),native_size=list(source.size),sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
    # Pixel colours are copied directly from the uniformly resized source; no recolouring or repainting.
    assert canvas.crop((x,header,x+size,header+size)).tobytes()==preview.tobytes()
draw.text((pad,header+size+10),'동일한 4m 영역 · 조명/그림자 제외 · 비교용 크기만 통일',font=small,fill=(178,181,202))
out=root/'comparison.png'
canvas.save(out)
Image.open(out).verify()
report=dict(file=out.name,size=list(canvas.size),layout='left=current effective ALBEDO, right=latest texture illustration',color_edit=False,inputs=records,pixel_layout_verified=True)
(root/'validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(report,ensure_ascii=False))
