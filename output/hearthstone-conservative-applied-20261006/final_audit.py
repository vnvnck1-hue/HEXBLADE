from pathlib import Path
import hashlib, json, re

folder=Path(__file__).resolve().parent
repo=folder.parents[1]
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
asset=repo/'assets/textures/handpaint_blue/floor_hearthstone.png'
source=folder.parent/'hearthstone-conservative-floor-20261006/floor_4m_final.png'
tone=json.loads((folder/'tone_validation.json').read_text(encoding='utf-8'))
suite=(folder/'tests.log').read_text(encoding='utf-8-sig',errors='replace')
assert 'FAILED:' in suite or 'TESTS PASSED' in suite
sections=re.split(r'^=== (\w+)\s*$',suite,flags=re.M)
checks={sections[i]:sections[i+1] for i in range(1,len(sections)-1,2)}
fail_names=[name for name,log in checks.items() if re.search(r'^\s*FAIL\b|SCRIPT ERROR',log,re.M)]
relevant=('blue_handpaint_check','brawl_look_check','ground_break_check')
assert all(name in checks and name not in fail_names for name in relevant)
runtime_names=('import','game_compare','flat_before','flat_after','bot_main','bot_run')
runtime={}
for name in runtime_names:
    log=(folder/(name+'.log')).read_text(encoding='utf-8-sig',errors='replace')
    runtime[name]=dict(error_count=len(re.findall(r'(?m)^ERROR:|^SCRIPT ERROR:',log)))
    assert runtime[name]['error_count']==0
assert 'bot=true' in (folder/'game_compare.log').read_text(encoding='utf-8-sig')
assert 'ROOM_CLEAR' in (folder/'bot_main.log').read_text(encoding='utf-8-sig')
assert 'RUN_ENTER' in (folder/'bot_run.log').read_text(encoding='utf-8-sig')
assert sha(asset)==sha(source)=='95f43d022a1e0e6c91f4650dc11aab8c9dfdb2f73c9582865ea2c7776f2dfd58'
assert sha(folder/'before_effective.png')=='1c5b3564c04571029cf1be2564e26ad30e8a28c49ff87bfa529912bb277bc980'
core=(repo/'scripts/claude_background/blue_handpaint.gd').read_text(encoding='utf-8-sig')
assert 'const FLOOR_LIFT := 1.18' in core and 'floor_hearthstone.png' in core
floor_shader=(repo/'scripts/claude_background/blue_handpaint_floor.gdshaderinc').read_text(encoding='utf-8-sig')
assert 'if (floor_direct)' in floor_shader and 'textureGrad(paint_tex, uv, dFdx(uv), dFdy(uv)).rgb' in floor_shader
import_settings=(repo/'assets/textures/handpaint_blue/floor_hearthstone.png.import').read_text(encoding='utf-8-sig')
assert 'mipmaps/generate=true' in import_settings and 'compress/high_quality=true' in import_settings
assert sha(repo/'assets/textures/handpaint_blue/wall_brush.png')=='67b5987ca9cc821ddc262d0b9bbdd2ef0a4d00cecedccf59ce60f33e3eb8a0dd'
for name in ('flat_albedo','game_0090','game_0120'):
    value=tone[name]
    assert abs(value['v_delta_percentage_points'])<1
    assert abs(value['s_delta_percentage_points'])<2
    assert abs(value['hue_of_mean_rgb_delta_degrees'])<2
result=dict(game_applied=True,asset_sha256=sha(asset),approved_png_byte_identical=True,
    sampling='direct 4m world XZ, no brush blending or procedural damage',floor_linear_lift=1.18,
    prior_floor_render_sha_identical=True,wall_png_sha_unchanged=True,
    tone=tone,checks_run=len(checks),checks_failed=fail_names,
    relevant_checks_passed=list(relevant),runtime=runtime,
    validation_scope='Default current game material; same paused scene/camera/lighting at two gameplay positions plus entire 4m shader albedo. Separate 30 game-second main/run bot processes exited 0.',
    note='Full suite exceptions are reported rather than hidden. No commit/push; other authors changes preserved.')
recheck=(folder/'lancaster_final_recheck.log').read_text(encoding='utf-8-sig',errors='replace')
previous=(folder/'lancaster_previous.log').read_text(encoding='utf-8-sig',errors='replace')
result['lancaster_recheck']=dict(current_floor_passed='RESULT OK (0 fails)' in recheck,
    previous_floor_passed='RESULT OK (0 fails)' in previous,
    note='Initial full suite foot-contact failure is retained; both isolated rechecks passed. Logs also contain an existing ObjectDB cleanup warning.')
(folder/'validation.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(dict(checks_run=len(checks),failed=fail_names,asset_sha256=sha(asset),game_applied=True),ensure_ascii=True))
