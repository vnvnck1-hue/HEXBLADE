const $=s=>document.querySelector(s),ticket=$('#ticket'),slider=$('#timeline');
const designs=JSON.parse(document.querySelector('#design-data').textContent);
const names={lead:'선행 칼집',panel:'먹색 패널',border:'아이보리 테두리',dots:'망점',slash0:'장식 1',slash1:'장식 2',slash2:'장식 3',word:'제목 단어',number:'번호·강조어',sub:'한국어 설명',receipt:'영수증 판',receiptText:'영수증 문구',burst:'임팩트 조각',stat0:'점수 숫자',stat1:'처치 숫자',stat2:'콤보 숫자',stat3:'시간',action0:'재출격',action1:'로비'};
const delays={
stage:[0,18,40,58,64,78,90,74,96,132,150,170,108],
wave:[0,8,26,42,47,58,69,48,67,102,114,134,82],
clear:[0,12,34,46,56,68,80,60,86,126,144,164,94],
boss:[0,20,40,56,66,80,94,86,106,148,164,188,126],
combat:[0,0,12,18,24,32,40,22,36,58,70,84,54],
support:[0,6,22,34,44,55,66,42,64,94,114,136,78],
equipment:[0,8,22,36,44,54,64,40,60,90,108,128,72],
danger:[0,0,18,34,40,50,60,0,0,0,88,114,38],
result:[0,18,38,58,68,80,92,76,104,140,164,188,124],
route:[0,6,18,28,34,44,54,32,48,78,98,116,62]};
const tones={lime:'#a4ff45',mint:'#70e6b5',coral:'#ff556f',amber:'#ffb451'};
names.badge='분류 스탬프';const layerOrder=['lead','panel','border','dots','slash0','slash1','slash2','word','number','sub','receipt','receiptText','burst','badge'];
let chosen=0,tracks=[],playing=false,raf=0,start=0,base=0,exitPreview=false,disabled=new Set();
function frame(track,d,reduced){
const special=(d.type==='danger'&&['word','number','sub'].includes(track.id));
const out=d.duration-d.exit+track.exitOrder*9,cut=Math.min(d.duration,out+track.exitDur),persist=d.persistent&&!exitPreview;
if(reduced){if(track.id==='burst'||track.id==='lead')return [{opacity:0,offset:0},{opacity:0,offset:1}];return [{opacity:special?1:0,offset:0},{opacity:1,offset:Math.min((special?1:80)/d.duration,.2)},{opacity:1,offset:out/d.duration},{opacity:persist?1:0,offset:cut/d.duration},{opacity:persist?1:0,offset:1}];}
const size=Math.min(ticket.clientWidth*.5,300),flow=d.type==='equipment'?-1:1;
let from='translate('+(-size*flow)+'px,0) scale(.55,1.18)',hit='translate(10px,0) scale(1.15,.85)',end='translate('+size+'px,-12px) scale(1.12,.7)';
if(track.id==='border'){from='translate('+size*.65+'px,0) scale(.9,1)';hit='translate(-5px,0) scale(1.03,1.08)';end='translate(-'+size+'px,0) scale(.7,1)';}
if(track.id==='dots'){from='translate(0,-36px) scale(1.2,.4)';hit='translate(0,2px) scale(1)';end='translate(0,-40px) scale(1,.3)';}
if(track.id.startsWith('slash')){from='translate(65px,-28px) scale(.4,1.5)';hit='translate(-3px,1px) scale(1.2,.9)';end='translate(90px,-35px) scale(.3,1.4)';}
if(track.id==='word'){from='translate(-70px,18px) scale(1.45,.28) skewX(-12deg)';hit='translate(3px,-2px) scale(1.13,1.13) skewX(1deg)';end='translate(-140px,-4px) scale(1.08,.72) skewX(-9deg)';}
if(track.id==='number'){from='translate(8px,-78px) scale(.6,1.9)';hit='translate(0,4px) scale(1.25,.76)';end='translate(34px,-95px) scale(.7,1.5)';}
if(track.id==='sub'||track.id==='receiptText'){from='translate(0,24px) scale(1,.5)';hit='translate(0,-2px) scale(1,1.02)';end='translate(0,22px) scale(1,.65)';}
if(track.id==='receipt'){from='translate(100px,0) scale(.12,1.5)';hit='translate(-7px,0) scale(1.12,.82)';end='translate(140px,0) scale(.08,1.3)';}
if(track.id.startsWith('stat')){from='translate(0,-34px) scale(.7,1.6)';hit='translate(0,3px) scale(1.15,.84)';end='translate(0,28px) scale(.8,.6)';}
if(track.id.startsWith('action')){from='translate(40px,0) scale(.8,1)';hit='translate(-4px,0) scale(1.03,1)';end='translate(0,28px) scale(.8,.6)';}
const f=[];const add=(time,values,easing='linear')=>f.push({...values,offset:Math.max(0,Math.min(1,time/d.duration)),easing});
if(track.id==='lead'||track.id==='burst'){add(0,{opacity:0,transform:from});if(track.delay>0)add(track.delay,{opacity:0,transform:from});add(track.delay+track.attack,{opacity:track.id==='burst'?.65:1,transform:track.id==='burst'?'scale(1.13)':hit},'cubic-bezier(.08,.9,.16,1)');add(track.delay+track.attack+50,{opacity:0,transform:track.id==='burst'?'scale(1.6)':'translate('+size+'px,0) scale(1.4,.07)'},'ease-out');add(d.duration,{opacity:0,transform:'scale(1)'});return f;}
if(special){add(0,{opacity:1,transform:'scale(1.08,.96)'});add(45,{opacity:1,transform:'none'},'ease-out');}
else{add(0,{opacity:0,transform:from});if(track.delay>0)add(track.delay,{opacity:0,transform:from});add(track.delay+track.attack,{opacity:1,transform:hit},'cubic-bezier(.04,.95,.12,1)');add(track.delay+track.attack+track.settle,{opacity:1,transform:'none'},'cubic-bezier(.12,.8,.18,1)');}
add(out,{opacity:1,transform:'none'},'cubic-bezier(.8,0,.98,.2)');add(cut,{opacity:persist?1:0,transform:persist?'none':end});if(cut<d.duration)add(d.duration,{opacity:persist?1:0,transform:persist?'none':end});return f;
}
function make(){
tracks.forEach(t=>t.animation?.cancel());let d=designs[chosen];ticket.className=d.type;ticket.style.setProperty('--tone',tones[d.accent]);$('#word').textContent=d.words[0];$('#number').textContent=d.words[1];$('#sub').textContent=d.sub;$('#receiptText').textContent=d.receipt;$('#badge').textContent=d.badge;
tracks=layerOrder.map((id,i)=>({id,name:names[id],delay:i===13?delays[d.type][3]+8:delays[d.type][i],attack:['word','number'].includes(id)?(d.type==='combat'?23:34):id==='panel'?34:28,settle:['word','number','panel','receipt'].includes(id)?48:24,exitOrder:[6,5,4,3,2,1,0,8,7,9,11,10,0,2][i],exitDur:id==='word'?62:48}));
if(d.type==='result')for(let i=0;i<4;i++)tracks.push({id:'stat'+i,name:names['stat'+i],delay:178+i*24,attack:26,settle:40,exitOrder:9+i,exitDur:36});
if(d.type==='result')for(let i=0;i<4;i++)tracks.push({id:'statLabel'+i,name:['점수 라벨','처치 라벨','콤보 라벨','시간 라벨'][i],delay:154+i*18,attack:22,settle:18,exitOrder:4+i,exitDur:36});
if(d.type==='result')tracks.push({id:'statsRule',name:'정산 구분선',delay:144,attack:24,settle:20,exitOrder:3,exitDur:40});
if(d.type==='result')for(let i=0;i<2;i++)tracks.push({id:'action'+i,name:names['action'+i],delay:300+i*30,attack:30,settle:32,exitOrder:13+i,exitDur:36});
const reduced=$('#reduce').checked;tracks.forEach(t=>{let el=$('#'+t.id);t.animation=el.animate(frame(t,d,reduced),{duration:d.duration,fill:'both'});t.animation.pause();el.style.visibility=disabled.has(t.id)?'hidden':'visible';});
slider.max=d.duration;slider.value=0;renderLanes();setTime(0);
$('#note').textContent=d.note+' '+(d.persistent&&!exitPreview?'상태 종료 전까지 유지합니다. 퇴장 미리보기 버튼으로 분해 퇴장을 볼 수 있습니다.':'각 레이어는 따로 퇴장하며 정보는 읽기 구간에서 고정됩니다.');
$('#exit').textContent=exitPreview?'상태 유지 보기':'퇴장 미리보기';
}
function renderLanes(){let d=designs[chosen];$('#lanes').innerHTML='';tracks.forEach(t=>{const row=document.createElement('div');row.className='lane';row.dataset.track=t.id;const b=document.createElement('button');b.textContent=t.name;b.setAttribute('aria-pressed',String(!disabled.has(t.id)));b.onclick=()=>{disabled.has(t.id)?disabled.delete(t.id):disabled.add(t.id);$('#'+t.id).style.visibility=disabled.has(t.id)?'hidden':'visible';b.setAttribute('aria-pressed',String(!disabled.has(t.id)))};const area=document.createElement('div');area.className='lane-track';area.innerHTML='<i style="left:'+t.delay/d.duration*100+'%;width:'+(t.attack+t.settle)/d.duration*100+'%"></i><span>'+t.delay+' ms</span>';row.append(b,area);$('#lanes').append(row)});}
function setTime(time){const d=designs[chosen],t=Math.max(0,Math.min(time,d.duration));tracks.forEach(tr=>{tr.animation.currentTime=t;const row=document.querySelector('[data-track="'+tr.id+'"]');if(row)row.classList.toggle('active',t>=tr.delay&&t<=tr.delay+tr.attack+tr.settle)});slider.value=t;$('#clock').textContent=Math.round(t)+' ms';$('#state').textContent=t<d.build?'LAYER BUILD':t<d.duration-d.exit?'READ HOLD':d.persistent&&!exitPreview?'STATE HOLD':'SPLIT EXIT';}
function stop(){playing=false;cancelAnimationFrame(raf)}
function run(){stop();const d=designs[chosen];base=Number(slider.value)>=d.duration?0:Number(slider.value);start=performance.now();playing=true;function step(now){if(!playing)return;let t=base+(now-start)*Number($('#speed').value);setTime(t);if(t<d.duration)raf=requestAnimationFrame(step);else playing=false;}raf=requestAnimationFrame(step)}
function choose(i){stop();chosen=(i+designs.length)%designs.length;exitPreview=false;disabled.clear();$('#picker').querySelectorAll('button').forEach((b,j)=>{b.classList.toggle('active',j===chosen);b.setAttribute('aria-pressed',String(j===chosen))});make();}
function dismiss(){stop();exitPreview=!exitPreview;make();run();}
const query=new URLSearchParams(location.search),embed=query.has('embed');
designs.forEach((d,i)=>{const b=document.createElement('button');b.textContent=String(i+1).padStart(2,'0')+' · '+d.title;b.onclick=()=>{choose(i);run()};$('#picker').append(b);if(!embed){let c=document.createElement('article');c.className='card';c.innerHTML='<h2>'+String(i+1).padStart(2,'0')+' · '+d.title+'</h2><a href="v2/'+d.id+'_layered.png" target="_blank" rel="noopener"><img src="v2/'+d.id+'_layered.png" alt="'+d.title+' 독립 레이어 리듬 보드"></a><p>'+d.note+'</p><a href="'+d.id+'.png">기존 정지 디자인 참고</a>';$('#boards').append(c)}});
$('#play').onclick=run;$('#pause').onclick=stop;$('#reset').onclick=()=>{stop();setTime(0)};$('#exit').onclick=dismiss;slider.oninput=()=>{stop();setTime(Number(slider.value))};$('#reduce').checked=!embed&&matchMedia('(prefers-reduced-motion:reduce)').matches;$('#reduce').onchange=()=>{stop();make()};$('#speed').onchange=()=>{if(playing)run()};document.addEventListener('keydown',e=>{if(e.target.matches('input,select'))return;if(e.key==='ArrowRight'){e.preventDefault();choose(chosen+1)}if(e.key==='ArrowLeft'){e.preventDefault();choose(chosen-1)}if(e.key===' '){e.preventDefault();playing?stop():run()}});document.addEventListener('visibilitychange',()=>{if(document.hidden)stop()});
choose(Number(query.get('type')||0));if(embed){document.body.classList.add('embed');setTime(Number(query.get('t')||0));if(query.has('exit')){exitPreview=true;make();setTime(Number(query.get('t')||0))}}
window.motionConcept={designs,choose,setTime,run,stop,dismiss,get chosen(){return chosen},get tracks(){return tracks},get exitPreview(){return exitPreview}};

