"""Package only this task's kit + handoff, with project-relative paths."""
from pathlib import Path
import hashlib
import json
import re
import zipfile

KIT=Path(__file__).resolve().parent
PROJECT=KIT.parent.parent
HANDOFF=PROJECT/'docs/lobby-upgrade-claude-handoff.md'
OUTPUT=KIT/'lobby_upgrade_kit.zip'
validation_path=KIT/'validation.json'
v=json.loads(validation_path.read_text(encoding='utf-8'))
log_bytes=(KIT/'engine_stdout.log').read_bytes()
log=log_bytes.decode('utf-16' if log_bytes.startswith(b'\xff\xfe') else 'utf-8-sig')
log=re.sub(r'\r+\n','\n',log).replace('\r','\n')
(KIT/'engine_stdout.log').write_text(log,encoding='utf-8',newline='\n')
v['engine_import']={'method':'Image.load original PNG/SVG through pinned tools/godot.ps1; no import of asset copies','version':'4.7.2-stable','assets_loaded':38,'assets_failed':0,'exit_code':0,'script_error_count':log.count('SCRIPT ERROR'),'startup_environment_error_count':log.count('ERROR:'),'log':'engine_stdout.log'}
v['visual_review']={'static':'reviewed','layered':'reviewed; minor AI design differences, vector banner differs from painted reference','drawer':'reviewed; long Korean text wraps and list scrolls','source_pngs_preserved':True}
sources={s['id']:s for s in json.loads((KIT/'sources.json').read_text(encoding='utf-8'))}
copies=[]
for asset,source in [('01_keyart_clean.png','01_keyart_clean'),('02_hangar_plate.png','02_hangar_plate'),('03_mech_cutout.png','03_mech_cutout'),('04_drone_cutout.png','04_drone_cutout')]:
    original=Path(re.search(r' as (.+?) by default\.',sources[source]['output_hint']).group(1))
    same=hashlib.sha256(original.read_bytes()).digest()==hashlib.sha256((KIT/'png'/asset).read_bytes()).digest()
    copies.append({'file':'png/'+asset,'source_id':source,'sha256_identical':same})
    assert same
v['source_copy_checks']=copies
assert 'LOBBY_ASSETS_CHECK: 38 loaded, 0 failed' in log
assert v['all_asset_checks_pass'] and v['preview_checks_pass']
validation_path.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
prompts=json.loads((KIT/'prompts.json').read_text(encoding='utf-8'))
for p in prompts:
    (KIT/'prompts'/f"{p['id']}.txt").write_text(p['prompt']+'\n',encoding='utf-8')
files=sorted(p for p in KIT.rglob('*') if p.is_file() and p.suffix!='.zip' and p.name!='zip_validation.json' and '__pycache__' not in p.parts)
files.append(HANDOFF)
with zipfile.ZipFile(OUTPUT,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as archive:
    for p in files:
        archive.write(p,p.relative_to(PROJECT).as_posix())
with zipfile.ZipFile(OUTPUT) as archive:
    assert archive.testzip() is None
    names=archive.namelist()
    pngs=[s for s in names if '/png/' in s and s.endswith('.png')]
    svgs=[s for s in names if '/ui/' in s and s.endswith('.svg')]
    variants=[s for s in names if '/ui_png/' in s and s.endswith('.png')]
    assert len(pngs)==4 and len(svgs)==17 and len(variants)==17
    assert 'docs/lobby-upgrade-claude-handoff.md' in names
report={'zip':OUTPUT.name,'bytes':OUTPUT.stat().st_size,'sha256':hashlib.sha256(OUTPUT.read_bytes()).hexdigest(),'file_count':len(names),'generated_png':len(pngs),'native_svg':len(svgs),'native_png_variants':len(variants),'crc_check':True,'handoff_included':True}
(KIT/'zip_validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps(report,ensure_ascii=False,indent=2))
