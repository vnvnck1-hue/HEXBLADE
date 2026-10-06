import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';
const require=createRequire(import.meta.url);
const sharp=require('C:/Users/Loadcomplete/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const out=path.dirname(fileURLToPath(import.meta.url));
const read=f=>JSON.parse(fs.readFileSync(path.join(out,f),'utf8').replace(/^\uFEFF/,''));
const groups=read('sources.json'),downloads=read('download_manifest.json');
const records=[];
for(const d of downloads){
 if(d.status!=='ok')throw Error('Missing '+d.url);
 const file=path.join(out,d.file),meta=await sharp(file).metadata();
 const hash=crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
 if(hash!==d.sha256||!meta.width||!meta.height)throw Error('Invalid image '+file);
 records.push({...d,width:meta.width,height:meta.height,format:meta.format,bytes:fs.statSync(file).size});
}
const text=(s,w,h=44)=>Buffer.from(`<svg width="${w}" height="${h}"><rect width="100%" height="100%" fill="#222230"/><text x="16" y="29" font-size="20" font-family="Malgun Gothic, sans-serif" fill="white">${s}</text></svg>`);
async function board(name,items,cols,w,h){const layers=[];let i=0;for(const [file,label] of items){const x=(i%cols)*w,y=Math.floor(i/cols)*(h+44);const b=await sharp(path.join(out,'images',file)).resize(w,h,{fit:'contain',background:'#161620'}).png().toBuffer();layers.push({input:text(label,w),left:x,top:y},{input:b,left:x,top:y+44});i++;}await sharp({create:{width:cols*w,height:Math.ceil(i/cols)*(h+44),channels:3,background:'#161620'}}).composite(layers).png().toFile(path.join(out,name));}
await board('reference_board.png',[
 ['01_tinker_01.jpg','01 / Tiffany Chiu · Tinker Tavern'],
 ['02_box_04.jpg','02 / Ben Thompson · Hearthstone Box'],
 ['03_scholomance_01.jpg','03 / Jay Axer · Scholomance Board'],
 ['04_zuldazar_05.jpg','04 / Izzy Hoover · 실제 벽 텍스처'],
 ['05_nathria_03.jpg','05 / Christopher Hayes · Nathria'],
 ['06_mechagon_15.jpg','06 / Ryan Cooper · 실제 공업 텍스처']
],3,900,620);
await board('texture_sheets.png',[
 ['04_zuldazar_01.jpg','Zuldazar / Texture Sheet 01'],
 ['04_zuldazar_02.jpg','Zuldazar / Texture Sheet 02'],
 ['04_zuldazar_05.jpg','Zuldazar / Wall Textures'],
 ['06_mechagon_15.jpg','Mechagon / Industrial Texture Sheet']
],2,1050,790);
await board('mechagon_context.png',Array.from({length:6},(_,i)=>['06_mechagon_'+String(i+1).padStart(2,'0')+'.jpg','Mechagon / '+String(i+1)]),3,760,500);
await board('all_images_index.png',records.map(r=>[path.basename(r.file),path.basename(r.file)]),5,430,300);
const escape=s=>String(s).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('"','&quot;');
const sections=groups.map(g=>`<section id="${g.id}"><h2>${escape(g.title)}</h2><p>${escape(g.artist)} · ${escape(g.kind)} · <a href="${g.page}" target="_blank">작가 원문</a></p><div class="grid">${records.filter(r=>r.group===g.id).map(r=>`<figure><a href="${r.file}" target="_blank"><img loading="lazy" src="${r.file}"></a><figcaption>${escape(path.basename(r.file))} · ${r.width}×${r.height}<br><a href="${escape(r.url)}" target="_blank">공개 원본</a></figcaption></figure>`).join('')}</div></section>`).join('');
fs.writeFileSync(path.join(out,'gallery.html'),`<!doctype html><html lang="ko"><meta charset="utf-8"><title>Blizzard 배경 텍스처 리서치</title><style>body{background:#181822;color:#ecebf4;font:16px Malgun Gothic,sans-serif;max-width:1600px;margin:30px auto;padding:20px}a{color:#a9baff}.grid{display:grid;grid-template-columns:repeat(3,1fr);gap:16px}figure{margin:0;background:#252530;padding:12px}img{width:100%;height:340px;object-fit:contain}figcaption{font-size:13px;line-height:1.8}section{margin:40px 0}nav a{margin:10px}h1{font-size:28px}</style><h1>Blizzard 배경 텍스처 · 실제 작가 자료 30장</h1><p>원본 이미지를 클릭하면 확대됩니다. 리서치 참고 자료이며 게임 적용 에셋과 구분합니다. 분석은 README.md를 참조합니다.</p><nav>${groups.map(g=>`<a href="#${g.id}">${g.id}</a>`).join('')}</nav>${sections}</html>`);
fs.writeFileSync(path.join(out,'image_manifest.json'),JSON.stringify({date:'2026-10-06',sources:groups.length,images:records.length,records},null,2));
fs.mkdirSync(path.join(out,'crops'),{recursive:true});
const cropSpecs=[
 {id:'metal_plate',file:'06_mechagon_15.jpg',box:{left:735,top:723,width:317,height:275},label:'Mechagon / 판금 · 큰 반사 면'},
 {id:'rivets',file:'06_mechagon_15.jpg',box:{left:1063,top:723,width:306,height:275},label:'Mechagon / 볼트 · 접합부 · 마모'},
 {id:'holes',file:'06_mechagon_15.jpg',box:{left:1392,top:722,width:308,height:276},label:'Mechagon / 구멍의 안쪽 깊이'},
 {id:'box_bevel',file:'02_box_02.jpg',box:{left:710,top:100,width:740,height:540},label:'Hearthstone / 베벨의 밝고 어두운 면'}
];
for(const c of cropSpecs)await sharp(path.join(out,'images',c.file)).extract(c.box).png().toFile(path.join(out,'crops',c.id+'.png'));
const closeLayers=[];
for(let j=0;j<cropSpecs.length;j++){const c=cropSpecs[j],x=(j%2)*900,y=Math.floor(j/2)*644;const b=await sharp(path.join(out,'crops',c.id+'.png')).resize(900,600,{fit:'contain',background:'#161620'}).png().toBuffer();closeLayers.push({input:text(c.label,900),left:x,top:y},{input:b,left:x,top:y+44});}
await sharp({create:{width:1800,height:1288,channels:3,background:'#161620'}}).composite(closeLayers).png().toFile(path.join(out,'material_closeups.png'));
fs.writeFileSync(path.join(out,'crop_manifest.json'),JSON.stringify(cropSpecs,null,2));
console.log(JSON.stringify({sources:groups.length,images:records.length,bytes:records.reduce((a,r)=>a+r.bytes,0),formats:[...new Set(records.map(r=>r.format))]}));
