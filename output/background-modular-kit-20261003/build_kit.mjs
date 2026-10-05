// Reproducible design-only checks and catalog. Run: node build_kit.mjs
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.dirname(fileURLToPath(import.meta.url));
const read=n=>fs.readFileSync(path.join(root,n),'utf8').replace(/^\uFEFF/,'');
const save=(n,s)=>fs.writeFileSync(path.join(root,n),s,'utf8');
const json=(n,o)=>save(n,JSON.stringify(o,null,2)+'\n');
const m=JSON.parse(read('kit_manifest.json')), c=JSON.parse(read('kit_contracts.json'));
const latest={F04:2,D02:2,W02:2,W04:2,P01:2,R02:2,R03:2,A02:2,A04:2,I01:2,I02:2,I03:3};
const notes={
 F03:'슬롯은 평면에서만 보임. 측벽은 매립/평면 처리.',F04:'5×5 돌기. 상면 돌출 20mm, 충돌은 Y=0.',
 D01:'투명 캐리어. 실제 안전선 폭 .25m.',D02:'원점 중심 r=.5m. 그림의 반경 화살표보다 보조도 좌표 우선.',D03:'얇은 데칼. 두께는 띄움 거리.',
 W02:'벽 이음에 덧씌움; 건축 폭에 더하지 않음.',W03:'L 단면 .08m. 코너 이중 벽 제거.',W04:'개구부 3.5×2.5m. PNG 비율 아닌 보조도 치수 사용. 기둥 내부 문 이동 슬릿 필수.',W05:'2장 조립. 반대손 파생형을 제작하고 음수 스케일 금지.',W07:'내부 폭 .25m, 날개 .05m.',
 P01:'직선 길이2m, 외경 .25m. FRONT/TOP 직각 투영 교정.',P02:'중심선 r=.5m. 곡선 접점/법선은 보조도 우선.',P03:'±X와 +Z 세 소켓. 원형 단면 .25m.',P04:'관통 내경 .252m, 연결부당 하나.',P05:'막힌 끝에만 배치.',
 R01:'높이 .25/.95m. 기둥 별도.',R02:'.5×.5m는 예약 공간, 실제 곡선 범위 .29m.',R03:'높이차 .70m. 로컬 Z 소켓, X 난간에는 90도 회전. 중간 기둥은 관통형 파생.',
 A02:'평면 손잡이를 정면과 같은 면으로 교정.',A04:'판/훅/공구3개 하위 메시. 별도 전기함 제거.',A09:'피벗 예외: 천이 접히는 선의 중앙.',
 I01:'금속 연결구 없음. 양끝 목 Ø.12m.',I02:'.5×.5m 예약 공간. 목 Ø.12m/중심선 r=.25m는 보조도 우선.',I03:'±X/+Z T분기. 양끝 .08m 구간은 Ø.12m 고정. 그림의 목 굵기를 역측정하지 않음.',I04:'표면에 5–15mm 띄워 밀착. 반복 기본 재질과 분리.',I06:'X=0 연결목 / X=.5 봉합된 끝. 목쪽 단면은 보조도 우선.'
};
for(const p of m.parts){if(latest[p.id])p.sheet=`sheets/${p.id}_v${latest[p.id]}.png`;p.status='concept_reviewed_with_numeric_contract';p.modeling_note=notes[p.id]||'컬러 외관 가이드. 피벗/실측 규격은 DESIGN.txt 참조.';}
m.version=3;m.delivery='42 color three-view sheets + dimensional assembly contract; not CAD or game meshes';
m.parts.find(p=>p.id==='W05').design=m.parts.find(p=>p.id==='W05').design.replace('copy and rotate around Y for opposing leaf','derive an opposite-handed leaf with the same front face');
m.parts.find(p=>p.id==='I03').design='Organic T-branch: sockets (-.5,.06,0),(.5,.06,0),(0,.06,.4), diameter .12. Wine-purple painted flesh; no hardware.';
json('kit_manifest.json',m);
const by=Object.fromEntries(m.parts.map(p=>[p.id,p])),dim=id=>by[id].dimensions_m;
const checks=[];const test=(name,ok,detail)=>{checks.push({name,pass:!!ok,detail});};const near=(a,b)=>Math.abs(a-b)<1e-8;
test('42 unique parts',m.parts.length===42&&Object.keys(by).length===42,m.parts.length);
for(const p of m.parts){const b=fs.readFileSync(path.join(root,p.sheet));test(p.id+' PNG',b.subarray(1,4).toString()==='PNG'&&b.readUInt32BE(16)>=1024&&b.readUInt32BE(20)>=1024,{file:p.sheet,width:b.readUInt32BE(16),height:b.readUInt32BE(20)});}
const floor=[];const add=(id,x,z)=>floor.push({id,x,z,w:dim(id).x,d:dim(id).z});
for(let x=0;x<6;x+=2)for(let z=0;z<8;z+=2)add('F01',x,z);
for(let z=0;z<2;z++)add('F02',6,z);
for(let z=2;z<4;z+=.5)add('F03',6,z);
for(let x=6;x<8;x++)for(let z=4;z<6;z++)add('F04',x,z);
for(let z=6;z<8;z+=.25)add('F05',6,z);
let overlap=0;for(let i=0;i<floor.length;i++)for(let j=i+1;j<floor.length;j++){const a=floor[i],b=floor[j];overlap+=Math.max(0,Math.min(a.x+a.w,b.x+b.w)-Math.max(a.x,b.x))*Math.max(0,Math.min(a.z+a.d,b.z+b.d)-Math.max(a.z,b.z));}
const area=floor.reduce((n,r)=>n+r.w*r.d,0),inbounds=floor.every(r=>r.x>=0&&r.z>=0&&r.x+r.w<=8&&r.z+r.d<=8);
test('8x8 floor exact coverage',near(area,64)&&near(overlap,0)&&inbounds,{tiles:floor.length,area_m2:area,overlap_m2:overlap,uncovered_m2:64-area});
test('floor top/thickness',m.parts.filter(p=>p.group==='floor').every(p=>near(p.dimensions_m.y,.2)),{top_y:0,bottom_y:-.2,stud_relief:.02});
const d=c.door,doorW=dim('W04').x-2*d.jamb,doorH=dim('W04').y-d.header,l=dim('W05');
test('closed door clearances',near(doorW,2*l.x+2*d.side_gap+d.center_gap)&&near(doorH,l.y+2*d.vertical_gap),{opening:[doorW,doorH],center_gap:d.center_gap,side_gap:d.side_gap});
const left0=d.jamb+d.side_gap,left1=left0+l.x,right0=left1+d.center_gap,right1=right0+l.x;
test('door open and inside side pockets',left1-d.travel<=d.jamb&&right0+d.travel>=dim('W04').x-d.jamb&&left0-d.travel>=-dim('W01').x&&right1+d.travel<=dim('W04').x+dim('W01').x,{left:[left0-d.travel,left1-d.travel],right:[right0+d.travel,right1+d.travel]});
test('door depth inside pocket and wall',d.leaf_z>d.pocket_z[0]&&d.leaf_z+l.z<d.pocket_z[1]&&d.pocket_z[1]<dim('W01').z,{front_clearance:d.leaf_z-d.pocket_z[0],rear_clearance:d.pocket_z[1]-d.leaf_z-l.z,jamb_slit_required:true});
const rot=(v,degrees)=>{const a=degrees*Math.PI/180;return [v[0]*Math.cos(a)+v[2]*Math.sin(a),v[1],-v[0]*Math.sin(a)+v[2]*Math.cos(a)];};
for(const [i,q] of c.connections.entries()){const a=c.sockets[q.a][q.a_socket],b=c.sockets[q.b][q.b_socket],ap=rot(a.p,q.a_yaw).map((v,j)=>v+q.a_pos[j]),bp=rot(b.p,q.b_yaw).map((v,j)=>v+q.b_pos[j]),an=rot(a.n,q.a_yaw),bn=rot(b.n,q.b_yaw);test('socket pair '+(i+1)+' '+q.a+'/'+q.b,ap.every((v,j)=>near(v,bp[j]))&&an.every((v,j)=>near(v,-bn[j])),{position:ap,normal_a:an,normal_b:bn});}
test('pipe bore and wall clearance',c.pipe.bore>c.pipe.outer&&c.pipe.wall_offset>dim('P04').y/2,{radial_fit:(c.pipe.bore-c.pipe.outer)/2,wall_clearance:c.pipe.wall_offset-dim('P04').y/2});
test('pipe dimensions match connectors',near(dim('P01').y,c.pipe.outer)&&near(dim('P02').x,.5+c.pipe.outer/2)&&near(dim('P03').z,.5+c.pipe.outer/2),{diameter:c.pipe.outer});
const posts=[0,2,4,6];test('rail shared posts / vertical span',new Set(posts).size===4&&near(dim('R01').y,c.rail.heights[1]-c.rail.heights[0]+c.rail.diameter),{three_spans:3,posts,heights:c.rail.heights,corner_straight_variant:dim('R01').x-c.rail.corner_radius});
test('organic neck fits height',near(c.organic.neck_y,c.organic.neck_diameter/2)&&['I01','I02','I03','I06'].every(id=>dim(id).y>=c.organic.neck_diameter),{neck:c.organic.neck_diameter});
test('wall cap clearance',near(dim('W07').z,dim('W01').z+.1),{overhang:.05});
test('texture period / trim sum',near(c.texture.resolution,c.texture.period_m*c.texture.density_px_m)&&near(c.texture.trim_widths_m.reduce((a,b)=>a+b,0),c.texture.period_m),{trim_pixels:c.texture.trim_widths_m.map(x=>x*c.texture.density_px_m)});
const report={scope:'Numeric design contract only. No mesh, UV seam, texture baking or engine test.',pass:checks.every(t=>t.pass),checks};json('validation.json',report);json('assembly_instances.json',{floor,connections:c.connections,door:{left_closed:[left0,left1],right_closed:[right0,right1],travel:d.travel}});
const esc=s=>String(s).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('"','&quot;');
const text=(x,y,s,size=18)=>`<text x="${x}" y="${y}" font-size="${size}" fill="#e6dfeb">${esc(s)}</text>`;
const rect=(x,y,w,h,fill,stroke='#b9a7c8')=>`<rect x="${x}" y="${y}" width="${w}" height="${h}" fill="${fill}" stroke="${stroke}"/>`;
let svg=`<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="1610" viewBox="0 0 1200 1610"><title>HEXBLADE numeric assembly guide</title><rect width="1200" height="1610" fill="#252033"/><g font-family="Arial, Malgun Gothic, sans-serif">`;
svg+=text(40,45,'HEXBLADE / 조립 치수 보조도',28)+text(40,77,'단위 m · PNG 컬러 시트의 보조 자료 · 좌표/치수 우선, 실제 메시 검증 아님',16);
svg+=text(40,125,'A. 8×8 바닥 대체 슬롯 / 총 30장, 64m²',21);
const colors={F01:'#56438A',F02:'#6E4382',F03:'#423665',F04:'#68577b',F05:'#CE5F54'};
for(const r of floor){const x=40+r.x*58,y=155+(8-r.z-r.d)*58;svg+=rect(x,y,r.w*58,r.d*58,colors[r.id]);if(r.id!=='F05')svg+=text(x+7,y+r.d*29+5,r.id,15);}
svg+=text(40,645,'+X → / +Z ↑ · F05 8장 = 오른쪽 위 2×2 대체 슬롯',16);
svg+=text(550,125,'B. 벽 정면 조립 / 동일 팔레트',21);
svg+=rect(550,165,600,225,'#8c819f');
for(let i=1;i<4;i++)svg+=rect(550+i*150-5,165,10,225,'#423665');
svg+=rect(550,381,600,9,'#423665')+rect(550,161,600,9,'#56438A');
// A01 bench at wall x0..2; A04 above it, A10 above; A02, A03, A11 and hose.
svg+=rect(570,315,150,10,'#CE5F54')+rect(575,325,40,65,'#56438A')+rect(675,325,40,65,'#56438A');
svg+=rect(588,224,112.5,56.25,'#ac9caf')+text(598,258,'A04',18);
svg+=rect(608,195,75,11.25,'#AC41A6')+text(691,206,'A10',15);
svg+=rect(751,240,75,150,'#56438A')+text(765,310,'A02',18);
svg+=rect(865,227,75,112.5,'#68577b')+text(878,280,'A03',18);
svg+=rect(960,285,15,37.5,'#AC41A6')+text(978,303,'A11',15);
svg+='<ellipse cx="1080" cy="278" rx="19" ry="23" fill="none" stroke="#423665" stroke-width="7"/>'+text(1056,325,'A13',15);
svg+=text(580,418,'A01 상면 Y=1 / A04 중심 Y=1.8 / A10 중심 Y=2.5',16);
svg+=text(550,461,'작업대 뒤 간격 .05 · 벽 덮개는 폭에 더하지 않음',16);
svg+=text(550,495,'A05·A08은 상판 위 / A09는 앞 모서리',16);
svg+=text(550,529,'주 배관 Ø.25 / A12 도관 Ø.08 — 직접 접속 금지',16);
svg+=text(550,563,'중앙 전투 바닥은 비움 · 감염은 가장자리에서 확장',16);
svg+=text(40,704,'C. 문 정면 / 닫힘과 열림 (배치 개념도)',21);
// full assembly -2..6, scale130; y0..3 scale90, x40..1080
const dx=x=>300+x*130,dy=y=>1020-y*90;
svg+=rect(dx(-2),dy(3),260,270,'#6b5c7a')+rect(dx(4),dy(3),260,270,'#6b5c7a');
svg+=rect(dx(0),dy(3),520,45,'#423665')+rect(dx(0),dy(2.5),32.5,225,'#423665')+rect(dx(3.75),dy(2.5),32.5,225,'#423665');
svg+=rect(dx(left0),dy(2.49),l.x*130,l.y*90,'#56438A')+rect(dx(right0),dy(2.49),l.x*130,l.y*90,'#56438A');
svg+=text(440,895,'W05 ×2 / 1.74 × 2.48',20)+text(438,928,'중앙 .01 / 측면 .005',17)+text(405,782,'W04 4 × 3 / 통로 3.5 × 2.5',19);
for(const a of [[left0-d.travel,left1-d.travel],[right0+d.travel,right1+d.travel]])svg+=`<rect x="${dx(a[0])}" y="${dy(2.49)}" width="${l.x*130}" height="${l.y*90}" fill="none" stroke="#CE5F54" stroke-width="3" stroke-dasharray="8 5"/>`;
svg+=text(62,866,'포켓 W01',19)+text(884,866,'포켓 W01',19)+text(62,899,'← 이동 1.75',17)+text(884,899,'이동 1.75 →',17);
svg+=text(40,1056,'깊이: 벽 Z 0~.25 / 빈 포켓 .04~.20 / 문짝 .06~.18 / 기둥에도 같은 슬릿',18);
svg+=text(40,1111,'D. 곡선 접속 / TOP (+X →, +Z ↑)',21);
const families=[['D02',.5,.25,'#CE5F54'],['P02',.5,.25,'#56438A'],['R02',.25,.08,'#CE5F54'],['I02',.25,.12,'#6E4382']];
for(let i=0;i<families.length;i++){const [id,r,w,col]=families[i],ox=55+i*285,oy=1400,s=270;svg+=text(ox,1150,`${id} / r=${r}, Ø/폭=${w}`,16);svg+=`<path d="M ${ox+r*s} ${oy} A ${r*s} ${r*s} 0 0 0 ${ox} ${oy-r*s}" fill="none" stroke="${col}" stroke-width="${w*s}"/><path d="M ${ox+220} ${oy} H ${ox} V ${oy-210}" fill="none" stroke="#b9a7c8" stroke-width="1"/>`;svg+=text(ox,oy+25,'(0,0)',14)+text(ox+115,oy+25,`(${r},0)`,14)+text(ox+5,oy-r*s-25,`(0,${r})`,14);}
svg+=text(40,1475,'배관/줄기: 끝 중심 일치 + 법선 반대. 링은 접속마다 1개. 줄기는 금속 링 없이 목 Ø.12.',18);
svg+=text(40,1510,'I03 T분기: (-.5,.06,0) / (.5,.06,0) / (0,.06,.4). R 바 높이 .25/.95, 간격 .70.',18);
svg+=text(40,1550,'공통 512px/m · 2048px = 4m · BASE / TRIM / PROP / ORGANIC 분리',18)+'</g></svg>';
save('assembly.svg',svg);
const groupNames={floor:'바닥 5종',decal:'표식 3종',wall:'벽·문 7종',pipe:'배관 5종',rail:'난간 3종',prop:'프랍 13종',infection:'감염 6종'};
const style=`body{margin:0;background:#252033;color:#e6dfeb;font-family:Arial,'Malgun Gothic',sans-serif}header,main{max-width:1500px;margin:auto;padding:28px}a{color:#eaa99f}nav{display:flex;gap:16px;flex-wrap:wrap}section{margin:36px 0}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(410px,1fr));gap:24px}article{background:#342c47;padding:18px;border-radius:10px}img{width:100%;border-radius:5px}p{line-height:1.7}.note{color:#dacbdf;font-size:14px} .swatches{display:flex;gap:12px;flex-wrap:wrap}.swatches span{padding:16px;border:1px solid #a091b0}.assembly{max-width:1200px}@media(max-width:550px){.grid{grid-template-columns:1fr}header,main{padding:16px}}`;
let html=`<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>HEXBLADE 배경 42종 · 모델링 인수 도감</title><style>${style}</style><header><h1>HEXBLADE · 배경 모듈 42종</h1><p>정면 · 우측면 · 평면 / 승인된 보라·코랄 핸드페인팅 컨셉</p><p>모델링 착수용 컬러 도면과 조립 규격입니다. PNG는 CAD 실측 투영이 아닙니다. 치수·소켓은 수치 보조도와 설계서를 우선하며, 실제 모델·타일 텍스처·게임 적용은 별도 단계입니다.</p><nav><a href="DESIGN.txt">조립·텍스처 설계</a><a href="assembly.svg">조립 보조도 원본</a><a href="kit_manifest.json">42종 치수 목록</a><a href="kit_contracts.json">접속 규격</a><a href="validation.json">수치 검사 결과</a><a href="generation_log.txt">생성 프롬프트</a><a href="revision_prompts.txt">교정 프롬프트</a></nav><p>검증: ${checks.filter(t=>t.pass).length}/${checks.length} 파일·설계 검사 통과. 메시 조립·UV 이음 검증이 아닙니다.</p><div class="swatches">${c.palette.map(x=>`<span style="background:${x}">${x}</span>`).join('')}</div><p>기본 세계 재질 + 독립 감염 레이어. 코랄은 경계·손잡이, 마젠타는 작은 조명, 민트는 제한된 상태색.</p><nav>${Object.entries(groupNames).map(([g,n])=>`<a href="#${g}">${n}</a>`).join('')}</nav></header><main><section><h2>조립 예시와 연결 치수</h2><a href="assembly.svg"><img class="assembly" src="assembly.svg" alt="8x8 바닥, 벽과 소품, 문 포켓, 곡선 소켓의 수치 조립도"></a></section>`;
for(const [g,n] of Object.entries(groupNames)){html+=`<section id="${g}"><h2>${n}</h2><div class="grid">`;for(const p of m.parts.filter(p=>p.group===g)){const d=p.dimensions_m;html+=`<article id="${p.id}"><h3>${p.id} · ${esc(p.name)}</h3><a href="${p.sheet}"><img loading="lazy" src="${p.sheet}" alt="${esc(p.name)} 정면 우측면 평면"></a><p>X ${d.x} × Y ${d.y} × Z ${d.z} m / 피벗 ${p.pivot}</p><p class="note">${esc(p.modeling_note)}</p></article>`;}html+='</div></section>';}
save('index.html',html+'</main></html>');
json('review.json',{status:'modeling_concept_handoff',parts_reviewed:42,three_views_per_part:true,method:'Image outputs visually reviewed; obvious feature/projection errors revised. Numerical assembly checked separately.',corrections:latest,notes,limitations:['PNG painted proportions are not CAD projections.','Exact sockets, radius, widths and door aperture use assembly.svg / kit_contracts.json.','GLB fit, UV seams, mip padding and in-game readability await actual model production.'],numeric_validation_pass:report.pass});
console.log(JSON.stringify({pass:report.pass,checks:checks.length,failed:checks.filter(t=>!t.pass),parts:m.parts.length,floor_tiles:floor.length},null,2));
if(!report.pass)process.exitCode=1;
