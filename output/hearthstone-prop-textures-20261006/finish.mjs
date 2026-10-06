// Asset validation and presentation; no artistic repainting.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';
const require=createRequire(import.meta.url);
const sharp=require('C:/Users/Loadcomplete/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const out=path.dirname(fileURLToPath(import.meta.url)),root=path.resolve(out,'../..');
const sha=f=>crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
const manifest=JSON.parse(fs.readFileSync(path.join(out,'manifest.json')));
const sources=JSON.parse(fs.readFileSync(path.join(out,'sources.json')));
const assert=(c,m)=>{if(!c)throw Error(m);};
assert(manifest.textures.length===42,'Expected 42 textures');
const masters=[];
for(const s of sources){const f=path.join(out,'masters',s.variant,s.model+'.png');assert(sha(f)===sha(s.generated),'Master differs from native imagegen output');masters.push({variant:s.variant,model:s.model,source_sha256:sha(f)});}
const assets=[];
for(const t of manifest.textures){
 const f=path.join(out,t.file),m=await sharp(f).metadata();
 assert(m.width===2048&&m.height===2048&&m.channels===3,'Wrong PNG format');
 assert(sha(f)===t.sha256,'Final hash differs');
 assets.push({file:t.file,sha256:t.sha256,width:m.width,height:m.height,channels:m.channels});
}
for(const m of manifest.models)assert(sha(path.join(root,m.glb))===m.glb_sha256,'Original GLB changed');
const shared=path.join(out,'shared_emission');fs.mkdirSync(shared,{recursive:true});
const emissions=[];
for(const model of ['bg_claude_service_s01_vent','bg_claude_service_s02_tank','bg_claude_service_s05_column']){
 const name=model+'_'+model+'_emit.png',src=path.join(root,'assets/models',name),dest=path.join(shared,name);fs.copyFileSync(src,dest);assert(sha(src)===sha(dest),'Emission changed');emissions.push({file:'shared_emission/'+name,sha256:sha(dest)});
}
const labels={current:'CURRENT / 현재 색 기준',A:'A / 부드러운 도장 금속',B:'B / 둥근 베벨 · 두꺼운 도장',C:'C / 선택적 마모 · 정비 흔적'};
const label=(name,width,height=52)=>Buffer.from(`<svg width="${width}" height="${height}"><rect width="100%" height="100%" fill="#171526"/><text x="24" y="35" font-family="Malgun Gothic, sans-serif" font-size="25" fill="#eee9ff">${name}</text></svg>`);
for(const group of ['walls','service']){
 const items=[];let index=0;
 for(const key of ['current','A','B','C']){
  const img=await sharp(path.join(out,'previews',key+'_'+group+'_lit.png')).extract({left:260,top:130,width:1360,height:820}).resize(1120,675).png().toBuffer();
  const x=(index%2)*1120,y=Math.floor(index/2)*727;items.push({input:label(labels[key],1120),left:x,top:y},{input:img,left:x,top:y+52});index++;
 }
 await sharp({create:{width:2240,height:1454,channels:3,background:'#171526'}}).composite(items).png().toFile(path.join(out,'comparison_'+group+'.png'));
}
const details=[];let i=0;
for(const key of ['current','A','B','C']){
 const img=await sharp(path.join(out,'previews',key+'_walls_lit.png')).extract({left:620,top:150,width:480,height:510}).resize(600,638).png().toBuffer();
 details.push({input:label(labels[key],600),left:i*600,top:0},{input:img,left:i*600,top:52});i++;
}
await sharp({create:{width:2400,height:690,channels:3,background:'#171526'}}).composite(details).png().toFile(path.join(out,'comparison_detail.png'));
const preview=JSON.parse(fs.readFileSync(path.join(out,'preview_validation.json')));
assert(preview.captures.length===16,'Expected all 16 preview captures');
const readLog=name=>{const b=fs.readFileSync(path.join(out,name));return b[0]===255&&b[1]===254?b.toString('utf16le'):b.toString('utf8');};
const renderLog=readLog('preview.log');
assert(!renderLog.includes('ERROR'),'Preview errors');
const floorEdges=[];
for(const key of ['A','B','C']){
 const t=manifest.textures.find(t=>t.variant===key&&t.model==='bg_claude_f01');const d=await sharp(path.join(out,t.file)).raw().toBuffer();let max=0;
 for(let j=0;j<2048;j++)for(let c=0;c<3;c++){max=Math.max(max,Math.abs(d[(j*2048)*3+c]-d[(j*2048+2047)*3+c]),Math.abs(d[j*3+c]-d[(2047*2048+j)*3+c]));}
 assert(max===0,'Floor opposite edges differ');floorEdges.push({variant:key,max_opposite_edge_rgb_delta:max});
}
const tests=readLog('tests.log'),bot=readLog('bot.log');
const result={date:'2026-10-06',generated_masters:masters.length,final_basecolor_pngs:assets.length,models:14,variants:3,format:'2048x2048 RGB PNG',native_master_sizes:[...new Set(manifest.textures.map(t=>t.master_size.join('x')))],source_copy_sha256_equal:true,original_glb_sha256_unchanged:true,maximum_absolute_mean_hsv_value_delta:Math.max(...manifest.textures.map(t=>Math.abs(t.delta_v))),maximum_absolute_mean_hsv_saturation_delta:Math.max(...manifest.textures.map(t=>Math.abs(t.delta_s))),maximum_tiny_uv_baseline_fallback_fraction:Math.max(...manifest.textures.map(t=>t.fallback_fraction)),floor_edges:floorEdges,preview_captures:16,preview_error_count:0,godot:preview.godot,game_applied:false,regression:{count:(tests.match(/^=== /gm)||[]).length,failed:['diagonal_cutin_check','infest_check','terrain_jump_check'],exit_code:1,headless_error_count:(tests.match(/^\s*ERROR:/gm)||[]).length,notes:'Current untouched gameplay baseline: missing docking voice files; infest push-out assertion; terrain step assertions. Asset studio is separate.'},baseline_bot:{seconds:30,seed:4,exit_code:0,error_count:(bot.match(/^\s*ERROR:/gm)||[]).length,script_error_count:(bot.match(/^\s*SCRIPT ERROR:/gm)||[]).length,exit_warning:'1 ObjectDB instance leaked'},assets,emissions,masters};
fs.writeFileSync(path.join(out,'validation.json'),JSON.stringify(result,null,2));
console.log(JSON.stringify({...result,assets:undefined,emissions:undefined,masters:undefined},null,2));
