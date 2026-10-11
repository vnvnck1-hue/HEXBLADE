// Historical script superseded by the user correction: dialogue changes only; retain original fusion characters.
throw new Error("Do not replay: fusion restoration is recorded in output/cutin-restored-20261011.");
const fs=require('fs');const edit=(p,f)=>fs.writeFileSync(p,f(fs.readFileSync(p,'utf8')).replace(/\r\n/g,'\n'));
edit('scripts/drone/diagonal_docking_cutin.gd',s=>{
const props=s.match(/\t\t"props": \[[\s\S]*?\n\t\t\],\n\t\t"sparkle": [^\n]+/)[0];
const pose=(file,name)=>`{"name": "${name}", "tex": "res://assets/portraits/opening_cast/${file}.png", "face": Vector2(0.50, 0.35)}`;
const cfg=(id,ko,theme,file,poses,extra='')=>`\t{"id": "${id}", "ko": "${ko}", "theme": "${theme}", "art": 1254.0,
\t\t"tex": preload("res://assets/portraits/opening_cast/${file}.png"), "mask": null,
\t\t"anchor": Vector2(0.50, 0.94), "hair_top": 0.0, "hair_screen": 0.04, "side_max_h": 0.92,
\t\t"c_l": Vector2(0.42, 0.68), "c_r": Vector2(0.57, 0.68), "r": 0.10, "tilt": 0.0,
\t\t"bust": false, "motion": true, "hair_root": Vector2(0.48, 0.17), "hair_len": 0.60,
\t\t"face": Vector2(0.50, 0.35), "poses": [${poses.join(',')}],
${extra}\t},`;
const chars=`const CHARACTERS := [\n${cfg('owner','사장','green','owner_welcome',[pose('owner_welcome','환영'),pose('owner_briefing','업무 설명'),pose('owner_encouragement','격려')])}\n${cfg('worker','정비사','purple','worker_cheerful',[pose('worker_introduction','소개'),pose('worker_cheerful','신남')])}\n${cfg('partner','청소 파트너','mint','partner_greeting',[pose('partner_greeting','인사')], '\t\t"shadow": {"off": Vector2(0.032, -0.006), "scale": 0.01},\n'+props+'\n')}\n]\n`;
s=s.replace(/const CHARACTERS := \[[\s\S]*?\n]\n/,chars).replace('static var char_mode := "alt"','static var char_mode := "partner"').replace('static var hidden_chars: Array = ["purple", "green"]','static var hidden_chars: Array = []');
s=s.replace('\tmat.set_shader_parameter("hair_mask", cfg.mask)','\tmat.set_shader_parameter("hair_mask", DialogueIdleMotion.mask_for(cfg.id, cfg.tex))');
return s;
});
edit('scripts/drone/cockpit_cutin.gd',s=>s.replace('res://assets/vfx/drone_cutin/cockpit_plate_clipped.png','res://assets/portraits/opening_cast/partner_greeting.png').replace('const ART := 1024.0','const ART := 1254.0'));
edit('tests/coworker_dialogue_check.gd',s=>s.replace('res://assets/portraits/cleaning_owner/owner-introduction-player.png','res://assets/portraits/opening_cast/owner_welcome.png').replace('res://assets/portraits/purple_worker/purple-worker-introduction-player.png','res://assets/portraits/opening_cast/worker_introduction.png').replace('res://assets/portraits/purple_worker/purple-worker-cheerful-player.png','res://assets/portraits/opening_cast/worker_cheerful.png'));
edit('tests/diagonal_cutin_check.gd',s=>{
s=s.replaceAll('"purple"','"worker"').replaceAll('"green"','"owner"').replaceAll('"mint"','"partner"').replace('DiagonalDockingCutin.char_mode == "alt" and DiagonalDockingCutin.hidden_chars == ["worker", "owner"]','DiagonalDockingCutin.char_mode == "partner" and DiagonalDockingCutin.hidden_chars.is_empty()').replace('pose_seen.size() == poses.size() and repeat == 0','pose_seen.size() == poses.size() and (poses.size() == 1 or repeat == 0)').replace('load(poses[m1.pose_i].mask)','DialogueIdleMotion.mask_for("partner", m1.portrait.texture)').replace('get_width() == 1226','get_width() == 1254');
const a=s.indexOf('\t_check(gjig > 20.0'),b=s.indexOf('\n\tfor x in _of(DiagonalDockingCutin):',a);
s=s.slice(0,a)+`\t_check(green_c.mat.get_shader_parameter("bust") == 0.0, "새 사장 원화의 가슴 모핑 제외")
\t_check(green_c.pops.is_empty() and green_c.papers.is_empty() and purple_c.pops.is_empty() and purple_c.papers.is_empty(), "구 메이드 말풍선과 종이는 새 캐릭터에서 제외")`+s.slice(b);
return s;
});
