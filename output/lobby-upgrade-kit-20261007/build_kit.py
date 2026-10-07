"""Build native SVG UI assets and inspect AI PNGs. Never edits the source paintings.
Run with Python + Pillow. Screen composition is rendered separately by render_preview.cjs.
"""
from pathlib import Path
import hashlib
import json
import xml.etree.ElementTree as ET
from PIL import Image

ROOT = Path(__file__).resolve().parent
UI = ROOT / 'ui'
UI.mkdir(exist_ok=True)

def svg(name, w, h, body):
    text = f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}" preserveAspectRatio="none">{body}</svg>\n'
    ET.fromstring(text)
    (UI / name).write_text(text, encoding='utf-8')

# Crisp native geometry, intentionally text-free: real Labels draw all menu text.
mark = '<g fill="#10efd0"><path d="M55 18H108L137 66 115 100 87 99 102 69 83 39H43Z"/><path d="M149 29L177 79 159 126 121 146 93 129 117 106 148 91 131 60Z"/><path d="M112 158H58L18 104 32 66 69 55 88 77 58 88 56 112 85 146Z"/></g>'
svg('01_logo_mark.svg',192,192,mark)

def menu_body(fill, edge, ink, disabled=False):
    body = f'<path d="M30 11L626 8 601 112 5 116Z" fill="{fill}" stroke="{edge}" stroke-width="2"/>'
    body += f'<g fill="{edge}"><path d="M20 21L33 3 94 1 80 8 35 9 23 40Z"/><path d="M601 93L611 66 616 70 611 107 595 124 545 124 559 118 591 117Z"/></g>'
    body += f'<g fill="{ink}" opacity="{0.08 if disabled else 0.12}"><path d="M51 15L63 15 49 30 45 27Z"/><path d="M605 27L619 20 615 28Z"/><path d="M580 109L598 103 591 112Z"/><path d="M14 97L26 77 22 102Z"/><path d="M95 110L136 111 132 114 89 114Z"/></g>'
    return body

svg('02_menu_normal.svg',640,128,menu_body('#191728','#efe8d1','#ffffff'))
svg('03_menu_focus.svg',640,128,'<defs><linearGradient id="g"><stop stop-color="#82ff43"/><stop offset="1" stop-color="#a0ff67"/></linearGradient></defs>'+menu_body('url(#g)','#f8f1db','#102019'))
svg('04_menu_pressed.svg',640,128,menu_body('#62cf31','#eaf1cd','#102019'))
svg('05_menu_disabled.svg',640,128,menu_body('#171623','#635f68','#ddd4c3',True))
svg('06_focus_corners.svg',640,128,'<g fill="#fff5dc"><path d="M18 8H104L92 15H30L22 53 13 59Z"/><path d="M621 70L614 115 597 127H538L549 118H592L605 106 612 72Z"/></g>')
chevron = '<path d="M10 6H25L42 24 25 42H10L26 24Z" fill="{color}"/>'
svg('07_arrow_cream.svg',48,48,chevron.format(color='#cfc8b8'))
svg('08_arrow_ink.svg',48,48,chevron.format(color='#102015'))
banner = '<path d="M690 608L1545 0H1920L1900 175 1305 535 900 890 748 925 1010 668 800 724Z" fill="#78fa43"/><path d="M971 565L1856 52 1740 284 1116 723 1001 842 847 878 1187 553Z" fill="#91ff5c" opacity=".5"/><path d="M1379 115L1483 99 1569 158 1531 240 1451 255 1369 197Z" fill="#386d2a" opacity=".22"/><path d="M1664 0L1689 0 1660 26 1621 29Z" fill="#192631"/><path d="M1619 39L1731 13 1693 74 1584 103Z" fill="#25353e"/>'
# Small deterministic brush-edge speckles: no expensive SVG filters.
for i in range(90):
    x = 704 + (i*73)%540
    y = 587 - (x-704)*.704 + ((i*19)%25)
    banner += f'<rect x="{x}" y="{y:.1f}" width="{1+i%4}" height="{1+(i*3)%5}" fill="#2b4833" opacity=".3"/>'
svg('09_diagonal_backdrop.svg',1920,1080,banner)
svg('10_logo_underline.svg',336,18,'<g fill="#10efd0"><path d="M14 2H105L91 16H0Z"/><path d="M115 2H173L159 16H101Z"/><path d="M183 2H220L206 16H169Z"/></g><path d="M231 2H282L268 16H217Z" fill="#164a45"/><path d="M292 2H336L322 16H278Z" fill="#183431"/>')
svg('11_hint_plate.svg',640,72,'<path d="M19 6L636 3 617 66 0 69Z" fill="#131222" fill-opacity=".94"/>')
svg('12_drawer_panel.svg',760,820,'<path d="M32 12L744 6 726 807 6 812Z" fill="#151323" fill-opacity=".97" stroke="#ece3cb" stroke-width="3"/><path d="M35 16H736L730 24H31Z" fill="#85fb49"/><path d="M719 777L716 798H666L675 805H726L730 768Z" fill="#ece3cb"/>')
svg('13_badge_plate.svg',144,48,'<path d="M12 3H143L132 44H1Z" fill="#252536" stroke="#678488" stroke-width="1"/>')
svg('14_left_readability.svg',1920,1080,'<defs><linearGradient id="shade"><stop stop-color="#090911" stop-opacity=".36"/><stop offset=".32" stop-color="#090911" stop-opacity=".22"/><stop offset=".47" stop-color="#090911" stop-opacity="0"/></linearGradient></defs><rect width="1920" height="1080" fill="url(#shade)"/>')
svg('15_contact_shadow.svg',512,128,'<defs><radialGradient id="s"><stop stop-color="#080916" stop-opacity=".64"/><stop offset=".65" stop-color="#080916" stop-opacity=".28"/><stop offset="1" stop-color="#080916" stop-opacity="0"/></radialGradient></defs><ellipse cx="256" cy="64" rx="240" ry="48" fill="url(#s)"/>')
svg('16_sword_floor_light.svg',512,128,'<defs><radialGradient id="l"><stop stop-color="#ff1d46" stop-opacity=".52"/><stop offset=".5" stop-color="#ff3156" stop-opacity=".18"/><stop offset="1" stop-color="#ff3156" stop-opacity="0"/></radialGradient></defs><ellipse cx="256" cy="64" rx="240" ry="52" fill="url(#l)"/>')

PNG_ROLES = {
 '01_keyart_clean.png': 'Complete static background; mech/drone/banner/reflections already baked in. Do not add cutouts on top.',
 '02_hangar_plate.png': 'Empty environment for optional layered composition; cables/crane foreground are baked in.',
 '03_mech_cutout.png': 'Transparent mech + glowing red sword; framed with padding, re-illustrated. Use manifest bounds, not original canvas placement.',
 '04_drone_cutout.png': 'Transparent single cleaning drone; centered square sprite, re-illustrated.',
}
files=[]
checks=[]
for name, role in PNG_ROLES.items():
    path=ROOT/'png'/name
    with Image.open(path) as im:
        im.load()
        a=im.getchannel('A') if 'A' in im.getbands() else None
        bbox=a.point(lambda p:255 if p>=16 else 0).getbbox() if a else (0,0,*im.size)
        solid=a.point(lambda p:255 if p>=128 else 0).getbbox() if a else bbox
        corners=[a.getpixel(p) for p in [(0,0),(im.width-1,0),(0,im.height-1),(im.width-1,im.height-1)]] if a else None
        boundary_max=max(a.crop((0,0,im.width,1)).getextrema()[1],a.crop((0,im.height-1,im.width,im.height)).getextrema()[1],a.crop((0,0,1,im.height)).getextrema()[1],a.crop((im.width-1,0,im.width,im.height)).getextrema()[1]) if a else None
        transparent='cutout' in name
        # Allow a one-step alpha trace (1/255), but no visible silhouette touching the border.
        ok=(not transparent) or (im.mode=='RGBA' and a.getextrema()==(0,255) and boundary_max<=1)
        checks.append({'file':'png/'+name,'decode':True,'mode':im.mode,'size':list(im.size),'alpha_range':list(a.getextrema()) if a else None,'alpha_corners':corners,'boundary_alpha_max':boundary_max,'pass':ok})
        files.append({'path':'png/'+name,'format':'PNG','size':list(im.size),'mode':im.mode,'bounds_alpha16':list(bbox),'bounds_alpha128':list(solid),'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'role':role})
for path in sorted(UI.glob('*.svg')):
    el=ET.fromstring(path.read_text(encoding='utf-8'))
    files.append({'path':'ui/'+path.name,'format':'SVG','size':[int(el.get('width')),int(el.get('height'))],'text_free':True,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})

def fit_bounds(sprite, target):
    entry=next(f for f in files if f['path']=='png/'+sprite)
    x0,y0,x1,y1=entry['bounds_alpha16']; tx,ty,tw,th=target
    scale=min(tw/(x1-x0),th/(y1-y0))
    px=tx+(tw-(x1-x0)*scale)/2-x0*scale
    py=ty+(th-(y1-y0)*scale)/2-y0*scale
    return {'path':entry['path'],'rect':[round(px,3),round(py,3),round(entry['size'][0]*scale,3),round(entry['size'][1]*scale,3)],'visual_target':target,'scale':round(scale,6),'fit':'alpha16 bounding box, uniform fit'}

layout={
 'design_size':[1920,1080], 'resize':'scale=min(viewport_w/1920,viewport_h/1080); center design canvas; artwork is contained, extra space filled by dark backdrop',
 'logo_mark':[170,74,192,192],'title_wordmark_rect':[375,132,726,86],'title_rect':[377,118,690,110],'title_text':'HEX BLADE','title_font_size':116,'title_italic':True,
 'logo_underline':[375,242,336,18], 'subtitle_rect':[372,282,670,36],'subtitle':'쿼터뷰 3D 액션 로그라이트','subtitle_font_size':27,
 'menus':[
  {'id':'sector_run','rect':[157,344,624,125],'title':'섹터 런','subtitle':'HEX SECTOR RUN','title_font_size':49,'subtitle_font_size':25,'existing_handler':'Lobby._start_run'},
  {'id':'death_test','rect':[157,484,624,125],'title':'연출 테스트','subtitle':'MAMMOTH B','title_font_size':49,'subtitle_font_size':25,'existing_handler':'Lobby._go(Lobby.DEATH_TEST_SCENE)'},
  {'id':'test_scenes','rect':[157,624,624,125],'title':'테스트 씬','subtitle':'','title_font_size':49,'existing_handler':'Lobby._toggle_tests'},
  {'id':'quit','rect':[157,764,540,125],'title':'종료','subtitle':'','title_font_size':49,'existing_handler':'get_tree().quit'},
 ],
 'text_inset':[57,20], 'arrow_inset':[72,38], 'hint_rect':[161,933,600,66],'hint_text':'↑↓ 선택   ENTER 결정','hint_font_size':25,
 'extra_hint_rect':[169,1013,760,34],'extra_hint_text':'게임 중 ESC 로비   ·   F11 전체 화면','extra_hint_font_size':18,
 'drawer_rect':[166,334,760,650],'drawer_title':'테스트 씬','drawer_row_height':70,'drawer_close':'ESC 닫기',
 'layered':{
   'background':{'path':'png/02_hangar_plate.png','rect':[0,0,1920,1080]},
   'banner':{'path':'ui/09_diagonal_backdrop.svg','rect':[0,0,1920,1080]},
   'mech_shadow':{'path':'ui/15_contact_shadow.svg','rect':[865,917,716,86]},
   'sword_reflection':{'path':'ui/16_sword_floor_light.svg','rect':[541,935,324,53]},
   'mech':fit_bounds('03_mech_cutout.png',[619,208,1000,754]),
   'drone_shadow':{'path':'ui/15_contact_shadow.svg','rect':[1511,911,373,48]},
   'drone':fit_bounds('04_drone_cutout.png',[1510,647,371,298]),
   'readability':{'path':'ui/14_left_readability.svg','rect':[0,0,1920,1080]},
 },
 'static':{'path':'png/01_keyart_clean.png','rect':[0,0,1920,1080]},
 'palette':{'lime':'#82ff43','ink':'#102019','cream':'#f5eedb','navy':'#191728','secondary_text':'#a7b8d5','brand_mint':'#10efd0'},
 'motion_suggestion':{'bg_parallax_px':2,'mech_parallax_px':4,'drone_parallax_px':6,'drone_idle_vertical_px':1.5,'drone_idle_period_s':3.0,'menu_focus_duration_s':0.12,'menu_focus_translation_px':6,'reduced_motion':True},
}
(ROOT/'layout.json').write_text(json.dumps(layout,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(ROOT/'layout_data.js').write_text('globalThis.LOBBY_LAYOUT = '+json.dumps(layout,ensure_ascii=False,indent=2)+';\n',encoding='utf-8')
(ROOT/'manifest.json').write_text(json.dumps({'version':1,'generated_png_count':4,'native_svg_count':len(list(UI.glob('*.svg'))),'units':'pixels, bounds exclusive right/bottom','files':files},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(ROOT/'validation.json').write_text(json.dumps({'png_checks':checks,'svg_xml_parse':True,'source_images_edited_by_script':False,'all_asset_checks_pass':all(c['pass'] for c in checks),'engine_import':'not yet checked'},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'checks':checks,'asset_count':len(files),'mech':layout['layered']['mech'],'drone':layout['layered']['drone']},ensure_ascii=False,indent=2))
if not all(c['pass'] for c in checks):
    raise SystemExit('Asset validation failed')
