const fs = require('fs');
const path = require('path');
const cp = require('child_process');
const crypto = require('crypto');
const root = process.cwd();
const archive = 'output/retired-characters-20261011';
const out = 'output/cutin-restored-20261011';
function safe(p) {
  const abs = path.resolve(root, p);
  if (!abs.startsWith(root + path.sep)) throw Error('Outside workspace: ' + abs);
  return abs;
}
function edit(p, fn) { const target = safe(p); fs.writeFileSync(target, fn(fs.readFileSync(target, 'utf8'))); }
const restored = [];
function copyTree(rel) {
  const src = safe(archive + '/' + rel), dst = safe(rel);
  if (fs.statSync(src).isDirectory()) {
    fs.mkdirSync(dst, {recursive:true});
    for (const name of fs.readdirSync(src)) copyTree(rel + '/' + name);
  } else {
    const bytes = fs.readFileSync(src);
    if (fs.existsSync(dst) && !fs.readFileSync(dst).equals(bytes)) throw Error('Existing changed file: ' + rel);
    fs.mkdirSync(path.dirname(dst), {recursive:true});
    fs.writeFileSync(dst, bytes);
    restored.push({path:rel, sha256:crypto.createHash('sha256').update(bytes).digest('hex')});
  }
}
for (const rel of ['assets/portraits/purple_worker','assets/portraits/green_maid','assets/portraits/mint_maid','assets/vfx/drone_cutin/cockpit_plate.png','assets/vfx/drone_cutin/cockpit_plate.png.import','assets/vfx/drone_cutin/cockpit_plate_clipped.png','assets/vfx/drone_cutin/cockpit_plate_clipped.png.import','_capture/drone_cutin_pack_preview.gd']) copyTree(rel);
for (const rel of ['scripts/drone/diagonal_docking_cutin.gd','scripts/drone/cockpit_cutin.gd','tests/diagonal_cutin_check.gd']) {
  const dst = safe(rel);
  const backup = safe(out + '/before/' + rel);
  fs.mkdirSync(path.dirname(backup), {recursive:true});
  fs.copyFileSync(dst, backup);
  fs.writeFileSync(dst, cp.execFileSync('git', ['show', 'HEAD:' + rel]));
}
edit('scripts/drone/partner_drone.gd', s => s.replace('## 청소 파트너 컷인으로 합체했으면', '## 민트 메이드 컷인으로 합체했으면'));
edit('scripts/training/training_main.gd', s => s.replace('## 사선 컷인 캐릭터: 번갈아 → 사장 → 정비사 → 청소 파트너 (바꾸면 바로 미리보기)', '## 사선 컷인 캐릭터: 번갈아 → 보라 정비사 고정 → 초록 메이드 고정 → … (바꾸면 바로 미리보기)'));
const ignore = safe('assets/캐릭터/.gdignore');
if (fs.existsSync(ignore)) {fs.copyFileSync(ignore, safe(out + '/before-character-gdignore.txt')); fs.unlinkSync(ignore);}
edit('tests/dialogue_blink_check.gd', s => s.replace(/\tfor cfg in DiagonalDockingCutin.CHARACTERS:[\s\S]*?\tprint\("RESULT dialogue_blink_check:/, '\tcheck(DiagonalDockingCutin.CHARACTERS.map(func(cfg): return cfg.id) == ["purple", "green", "mint"], "합체 캐릭터는 기존 세 명 유지, 대화 캐스트와 분리")\n\tcheck(CockpitCutin.PLATE.resource_path == "res://assets/vfx/drone_cutin/cockpit_plate_clipped.png", "조종석 합체 원본 유지")\n\tprint("RESULT dialogue_blink_check:'));
edit('README.md', s => s.replace('이전 여성 캐릭터는 게임에서 제외했습니다.', '이전 여성 대화 캐릭터는 대화 씬에서 제외했습니다. 합체 연출의 기존 캐릭터와 포즈는 유지합니다.'));
edit('docs/dialogue.md', s => s.replace(/현재 출연진은[^\r\n]+/, '현재 출연진은 **사장(owner) · 정비사(worker) · 청소 파트너(partner) · 남주(me)**다. 사용자가 남주 포트레이트 유지로 확정했다. 이전 여성 캐릭터의 대화 등록과 대본만 제거했다. **정리 범위는 대화 씬에 한정한다. 합체 연출은 기존 민트 메이드(5포즈)·보라 정비사·초록 메이드 및 조종석 원화와 마스크·소품을 유지한다.** 사선 컷인의 이전 기본 선택/숨김 설정도 유지한다. 구 대화 사장 원화와 역사 자료는 `output/retired-characters-20261011/`에 보관한다.'));
edit(out + '/../portrait-blink-20261011/README.md', s => s.replace(/구 여성 캐릭터의 등록\/대본\/컷인 사용을 제거했다[^\r\n]+/, '2026-10-11 범위 정정: 구 여성 캐릭터의 **대화 등록과 대본만** 제거했다. 합체 연출에 대한 교체는 사용자의 정정 요청으로 원복했다. 기존 민트 메이드 5포즈·보라 정비사·초록 메이드·조종석 원화 및 마스크/소품을 복구했으며, 대화의 새 세 여성/남주와 눈 깜빡임은 유지한다. 후속 기록: `output/cutin-restored-20261011/`. 아래 기존 검증 자료는 원복 이전 상태의 역사 기록이다.'));
fs.writeFileSync(safe(archive + '/README.md'), '# 대화 캐릭터 역사 자료\n\n2026-10-11 사용자 정정: 캐릭터 정리는 대화 씬만 해당한다. 합체 연출에 사용하는 기존 캐릭터는 삭제 대상이 아니다.\n\n`cleaning_owner`는 구 대화 사장 원화 보관본이다. `purple_worker`, `green_maid`, `mint_maid`, 조종석 PNG와 미리보기 도구는 원래 리소스 경로로 복구했고, 이 폴더의 복사본은 원본 보존을 위해 남겼다. 이 폴더 전체는 `.gdignore`로 임포트 제외다. 현재 대화 캐스트는 owner/worker/partner/me이며 합체 캐릭터 설정과 독립적이다.\n');
fs.writeFileSync(safe(out + '/restored-assets.json'), JSON.stringify(restored, null, 2));
fs.writeFileSync(safe(out + '/README.md'), '# 합체 캐릭터 원복 — 2026-10-11\n\n사용자가 캐릭터 정리 범위를 대화 씬으로 정정했다. 합체 컷인 스크립트와 전용 검사는 변경 전 Git HEAD 내용으로 복구하고, 보관한 이미지/마스크/소품과 조종석 PNG/임포트 파일을 동일 바이트로 원래 경로에 복사했다. 민트 메이드 5포즈와 기존 캐릭터 선택/숨김 설정도 복구했다.\n\n대화 씬의 새 세 여성·남주 포트레이트·눈 깜빡임·아이들링은 유지한다. 공유 셰이더의 사선 클립 기본값은 기존 1이며 대화에서만 끈다. 다른 작업자의 전투/훈련 씬 변경은 보존했다. 커밋·푸시는 하지 않았다.\n');
console.log('Restored exact archived assets:', restored.length);
