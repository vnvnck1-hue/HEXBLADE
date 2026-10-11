const sourceMap={
  "01_stage_start": "C:\\Users\\vnvnc\\.codex\\generated_images\\01a12b49-aeca-7763-a498-39bb532d1c27\\exec-0d8f7d18-5585-4eb4-abd9-0cf91f0488a2.png",
  "02_wave_elite": "C:\\Users\\vnvnc\\.codex\\generated_images\\01a12b49-aeca-7763-a498-39bb532d1c27\\exec-a599b766-09b6-462e-a8d3-8ed5b0946d38.png",
  "03_area_clear": "C:\\Users\\vnvnc\\.codex\\generated_images\\01a12b49-aeca-7763-a498-39bb532d1c27\\exec-dd6df825-f194-4dde-8709-bacf5f8c0114.png",
  "04_boss_alert": "C:\\Users\\vnvnc\\.codex\\generated_images\\01a12b49-aeca-7763-a498-39bb532d1c27\\exec-56e9f4ef-945d-4663-aa85-2e6c5f7e3910.png",
  "05_combat_feedback": "C:\\Users\\vnvnc\\.codex\\generated_images\\01a12b49-aeca-7763-a498-39bb532d1c27\\exec-845f227d-1fdb-4c44-9a4d-7e7317572d56.png",
  "06_support_docking": "C:\\Users\\vnvnc\\.codex\\generated_images\\01a12b49-aeca-7763-a498-39bb532d1c27\\exec-7e969f1f-0a8a-4fc1-9d7f-9b8d85193748.png",
  "07_equipment_resources": "C:\\Users\\vnvnc\\.codex\\generated_images\\01a12b49-aeca-7763-a498-39bb532d1c27\\exec-5a9bd513-d8e7-4252-82c6-a815b37e3478.png",
  "08_hazards_gimmicks": "C:\\Users\\vnvnc\\.codex\\generated_images\\01a12b49-aeca-7763-a498-39bb532d1c27\\exec-d1378183-cb7d-45af-90db-cd32879841b8.png",
  "09_results": "C:\\Users\\vnvnc\\.codex\\generated_images\\01a12b49-aeca-7763-a498-39bb532d1c27\\exec-9bb2b5e1-b5fb-4ea8-8eae-96bfd5d50553.png",
  "10_route_dialogue_system": "C:\\Users\\vnvnc\\.codex\\generated_images\\01a12b49-aeca-7763-a498-39bb532d1c27\\exec-6b2a3224-ad4d-4efd-b298-d3e09ef8ef45.png"
};
const visualReviews=[
  {
    "id": "01_stage_start",
    "title": "출격·스테이지 시작",
    "reviewed": true,
    "style": "navy/ivory clipped panels, lime halftone, short kinetic accents",
    "notes": "Concept text/scene is not live state proof"
  },
  {
    "id": "02_wave_elite",
    "title": "웨이브·정예·진행",
    "reviewed": true,
    "style": "navy/ivory clipped panels, lime halftone, short kinetic accents",
    "notes": "Concept text/scene is not live state proof"
  },
  {
    "id": "03_area_clear",
    "title": "청소·구역 완료·보상",
    "reviewed": true,
    "style": "navy/ivory clipped panels, lime halftone, short kinetic accents",
    "notes": "Illustrative clear state; receipt should be smaller than picture if action resumes"
  },
  {
    "id": "04_boss_alert",
    "title": "보스 등장·페이즈·약점",
    "reviewed": true,
    "style": "navy/ivory clipped panels, lime halftone, short kinetic accents",
    "notes": "Boss geometry is AI reinterpretation; name treatment only, not model approval"
  },
  {
    "id": "05_combat_feedback",
    "title": "정밀회피·타격·콤보",
    "reviewed": true,
    "style": "navy/ivory clipped panels, lime halftone, short kinetic accents",
    "notes": "Six text feedback variants and timestamp labels rather than three separate motion frames"
  },
  {
    "id": "06_support_docking",
    "title": "드론 지원·합체·청소",
    "reviewed": true,
    "style": "navy/ivory clipped panels, lime halftone, short kinetic accents",
    "notes": "X meter threshold50 is represented; existing Q DOCK art labeling differs from actual Q whirlwind30, use MD"
  },
  {
    "id": "07_equipment_resources",
    "title": "장비·재장전·자원",
    "reviewed": true,
    "style": "navy/ivory clipped panels, lime halftone, short kinetic accents",
    "notes": "Equipment icon correction inspected; lower storyboard ammo17/30 is fixed illustration, real reload must finish30/30"
  },
  {
    "id": "08_hazards_gimmicks",
    "title": "위험·상태·상호작용",
    "reviewed": true,
    "style": "navy/ivory clipped panels, lime halftone, short kinetic accents",
    "notes": "Attack-blocked sample uses combat backdrop, not live attack-state proof; warnings stay until source hazard ends"
  },
  {
    "id": "09_results",
    "title": "승리·실패·무한 모드 기록",
    "reviewed": true,
    "style": "navy/ivory clipped panels, lime halftone, short kinetic accents",
    "notes": "Concept text/scene is not live state proof"
  },
  {
    "id": "10_route_dialogue_system",
    "title": "포탈·대화·시스템 알림",
    "reviewed": true,
    "style": "navy/ivory clipped panels, lime halftone, short kinetic accents",
    "notes": "Route icons and confirmation dialogue are conceptual reinterpretations; existing four node types/scripts preserved; SAVED optional"
  }
];
const fs=require('fs'),path=require('path'),crypto=require('crypto'),{pathToFileURL}=require('url');
const dep='C:/Users/vnvnc/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules';
const sharp=require(path.join(dep,'sharp')),{chromium}=require(path.join(dep,'playwright'));
const root=__dirname,project=path.resolve(root,'../..'),hash=p=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const prompts=JSON.parse(fs.readFileSync(path.join(root,'prompts.json'),'utf8'));
(async()=>{const checks=[],sources=[];
for(const b of prompts.boards){const local=path.join(root,b.id+'.png');const meta=await sharp(local).metadata();await sharp(local).raw().toBuffer();const gen=sourceMap[b.id];const same=hash(local)===hash(gen);checks.push({kind:'png',id:b.id,width:meta.width,height:meta.height,format:meta.format,decoded:true,original_copy_same:same,pass:same&&meta.width>1000&&meta.height>700});sources.push({id:b.id,path:b.id+'.png',generated_source:gen,sha256:hash(local),size:[meta.width,meta.height]});}
const refs=prompts.references.map(p=>({path:path.relative(project,p).replaceAll('\\','/'),sha256:hash(p),role:'adopted UI/world style reference; no new human character generation'}));
fs.writeFileSync(path.join(root,'sources.json'),JSON.stringify({mode:'built-in image_gen',date:'2026-10-11',references:refs,images:sources},null,2)+'\n');
const document=fs.readFileSync(path.join(project,'docs/ui-notification-motion-concepts.md'),'utf8');
if(!fs.existsSync(path.join(root,'validation.json')))fs.writeFileSync(path.join(root,'validation.json'),JSON.stringify({status:'verification_running'}));
const links=[...document.matchAll(/\]\(([^)]+)\)/g)].map(m=>m[1]);const missing=links.filter(p=>!fs.existsSync(path.resolve(project,'docs',p)));checks.push({kind:'document',inventory_rows:(document.match(/\| A\d\d \|/g)||[]).length,local_links:links.length,missing_links:missing,pass:missing.length===0&&(document.match(/\| A\d\d \|/g)||[]).length===58});
const before=JSON.parse(fs.readFileSync(path.join(root,'runtime-before.json'),'utf8').replace(/^\uFEFF/,''));checks.push({kind:'monitored_runtime_hashes',files:before.map(x=>({path:path.relative(project,x.Path),same:hash(x.Path).toUpperCase()===x.Hash})),pass:before.every(x=>hash(x.Path).toUpperCase()===x.Hash)});
const execs=[chromium.executablePath(),'C:/Program Files/Google/Chrome/Application/chrome.exe','C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'].find(fs.existsSync);if(!execs)throw new Error('Installed browser missing');
const browser=await chromium.launch({headless:true,executablePath:execs}),errors=[];
const page=await browser.newPage({viewport:{width:1440,height:1080}});page.on('pageerror',e=>errors.push(String(e)));await page.goto(pathToFileURL(path.join(root,'index_v1.html')).href);await page.evaluate(async()=>{await document.fonts.ready;await Promise.all([...document.images].map(im=>im.decode()));});
checks.push({kind:'gallery_load',images:await page.locator('.card img').count(),pass:await page.locator('.card img').count()===10});
checks.push({kind:'motion_overlay_single_background',pass:await page.evaluate(()=>getComputedStyle(document.querySelector('#ticket')).backgroundImage==='none')});
for(let i=0;i<10;i++){const state=await page.evaluate(i=>{window.motionConcept.choose(i);const d=window.motionConcept.designs[i];window.motionConcept.setTime(d.entry+d.settle+10);const r=document.querySelector('#ticket').getBoundingClientRect(),s=document.querySelector('#stage').getBoundingClientRect();return {i,title:d.title,inStage:r.left>=s.left&&r.right<=s.right&&r.top>=s.top&&r.bottom<=s.bottom,head:document.querySelector('#head').textContent,time:Number(document.querySelector('#timeline').value),duration:d.duration};},i);checks.push({kind:'sample',...state,pass:state.inStage});}
await page.setViewportSize({width:1440,height:1440});await page.evaluate(()=>{motionConcept.choose(0);motionConcept.setTime(300)});await page.screenshot({path:path.join(root,'motion_preview.png'),fullPage:false});
await page.locator('#play').click();await page.waitForTimeout(220);let progressed=await page.locator('#timeline').inputValue();await page.locator('#pause').click();let stopped=await page.locator('#timeline').inputValue();await page.waitForTimeout(100);checks.push({kind:'play_pause',progressed:Number(progressed)>300,paused:stopped===await page.locator('#timeline').inputValue(),pass:Number(progressed)>300&&stopped===await page.locator('#timeline').inputValue()});
await page.locator('#reset').click();checks.push({kind:'reset',pass:await page.locator('#timeline').inputValue()==='0'});
await page.locator('#reduce').check();let reduced=await page.evaluate(()=>{motionConcept.setTime(100);return getComputedStyle(document.querySelector('#ticket')).transform});checks.push({kind:'reduced_motion',transform:reduced,pass:reduced==='none'||reduced==='matrix(1, 0, 0, 1, 0, 0)'});
await page.evaluate(()=>document.activeElement.blur());await page.keyboard.press('ArrowRight');checks.push({kind:'keyboard',pass:await page.evaluate(()=>motionConcept.chosen===1)});
for(const cfg of [{width:1280,height:720},{width:1280,height:800},{width:1920,height:800},{width:390,height:844}]){await page.setViewportSize(cfg);const layout=await page.evaluate(()=>({scrollWidth:document.documentElement.scrollWidth,viewWidth:innerWidth,buttons:[...document.querySelectorAll('#picker button')].every(b=>{const q=b.getBoundingClientRect();return q.left>=0&&q.right<=innerWidth})}));checks.push({kind:'responsive',...cfg,...layout,pass:layout.scrollWidth<=cfg.width&&layout.buttons});}
await page.setViewportSize({width:1600,height:1080});await page.goto(pathToFileURL(path.join(root,'contact_sheet.html')).href);await page.evaluate(async()=>{await document.fonts.ready;await Promise.all([...document.images].map(im=>im.decode()))});await page.screenshot({path:path.join(root,'contact_sheet.png'),fullPage:true});await browser.close();checks.push({kind:'browser_js',errors,pass:errors.length===0});
const v={date:'2026-10-11',scope:'concept PNGs, independent HTML timing preview and MD only; no Godot gameplay integration',boards:10,events:58,checks,all_pass:checks.every(c=>c.pass),visual_review:visualReviews,limitations:['AI concept boards reinterpret backdrop/models; no model change approval','Generated Korean and schematic timing are concept-only; MD is authoritative','Extra state swatches are alternatives, not simultaneous alerts','Native HTML geometry demonstrates timing and is not an animation of AI bitmap layers','SAVED, NEW OBJECTIVE, PAUSE and general persistence systems are future proposals']};
fs.writeFileSync(path.join(root,'validation.json'),JSON.stringify(v,null,2)+'\n');console.log(JSON.stringify({all_pass:v.all_pass,checks},null,2));if(!v.all_pass)process.exitCode=1;
})().catch(e=>{console.error(e);process.exit(1)});

