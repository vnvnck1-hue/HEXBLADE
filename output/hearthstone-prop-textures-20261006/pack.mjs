// Technical asset packing only: size, original UV coverage, padding, metrics.
// Artistic surface pixels come from imagegen. HSV mean calibration preserves
// current per-island tone; no invented strokes, damage or shader reinterpretation.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
const require=createRequire(import.meta.url);
const sharp=require('C:/Users/Loadcomplete/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const out=path.dirname(fileURLToPath(import.meta.url));
const root=path.resolve(out,'../..');
const N=2048, P=N*N;
const records=JSON.parse(fs.readFileSync(path.join(out,'models.json'),'utf8'));
const sha=f=>crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
async function raw(f){return sharp(f).resize(N,N,{fit:'fill'}).ensureAlpha().raw().toBuffer();}
function stats(data,mask){let n=0,v=0,s=0,y=0;for(let i=0;i<P;i++){if(!mask[i])continue;const o=i*4,r=data[o]/255,g=data[o+1]/255,b=data[o+2]/255,mx=Math.max(r,g,b),mn=Math.min(r,g,b);v+=mx;s+=mx?(mx-mn)/mx:0;y+=.2126*r+.7152*g+.0722*b;n++;}return{pixels:n,mean_hsv_v:v/n,mean_hsv_s:s/n,mean_srgb_luma:y/n};}
function labelsFor(mask,floor){
 const labels=new Int32Array(P);labels.fill(-1);let count=0;
 if(floor){for(let i=0;i<P;i++)if(mask[i])labels[i]=(i%N>=N/2?1:0)+(Math.floor(i/N)>=N/2?2:0);return{labels,count:4};}
 const queue=new Int32Array(P);
 for(let start=0;start<P;start++){
  if(!mask[start]||labels[start]>=0)continue;
  let head=0,tail=0;queue[tail++]=start;labels[start]=count;
  while(head<tail){const i=queue[head++],x=i%N;for(const j of [x?i-1:-1,x<N-1?i+1:-1,i>=N?i-N:-1,i<P-N?i+N:-1])if(j>=0&&mask[j]&&labels[j]<0){labels[j]=count;queue[tail++]=j;}}
  count++;
 }return{labels,count};
}
function calibrate(gen,ref,labels,count){
 const values=Array.from({length:count},()=>({n:0,rv:0,gv:0,rs:0,gs:0}));
 for(let i=0;i<P;i++){
  const label=labels[i];if(label<0)continue;const a=values[label],o=i*4;
  const rmax=Math.max(ref[o],ref[o+1],ref[o+2]),rmin=Math.min(ref[o],ref[o+1],ref[o+2]);
  const gmax=Math.max(gen[o],gen[o+1],gen[o+2]),gmin=Math.min(gen[o],gen[o+1],gen[o+2]);
  a.n++;a.rv+=rmax;a.gv+=gmax;a.rs+=rmax?(rmax-rmin)/rmax:0;a.gs+=gmax?(gmax-gmin)/gmax:0;
 }
 for(let i=0;i<P;i++){
  const label=labels[i];if(label<0)continue;const a=values[label],o=i*4,mx=Math.max(gen[o],gen[o+1],gen[o+2]);
  const value=a.gv?a.rv/a.gv:1,saturation=a.gs?a.rs/a.gs:1;
  for(let c=0;c<3;c++)gen[o+c]=Math.round(Math.max(0,Math.min(255,(mx-(mx-gen[o+c])*saturation)*value)));
 }
 return values.map(a=>({pixels:a.n,value_gain:a.gv?a.rv/a.gv:1,saturation_gain:a.gs?a.rs/a.gs:1}));
}
const validation=[];
const models=[];
for(const r of records){
 const ref=await raw(path.join(out,r.reference));
 const coverage=await raw(path.join(out,'references',r.model+'_coverage.png'));
 const mask=new Uint8Array(P);for(let i=0;i<P;i++)mask[i]=coverage[i*4]>240&&coverage[i*4+3]>200?1:0;
 const baseline=stats(ref,mask);
 const {labels,count}=labelsFor(mask,r.mapping==='world_xz_4m');
 models.push({...r,glb_sha256:sha(path.join(root,r.glb)),source_sha256:sha(path.join(root,r.source_texture.replace('res://',''))),reference_stats:baseline});
 for(const variant of ['A','B','C']){
  const master=path.join(out,'masters',variant,r.model+'.png');if(!fs.existsSync(master))continue;
  const gen=await raw(master);let fallback=0;const rawStats=stats(gen,mask);
  const calibration=calibrate(gen,ref,labels,count);
  calibrate(gen,ref,labels,count);
  if(r.mapping!=='world_xz_4m'){
   for(let i=0;i<P;i++){
    const o=i*4;
    if(mask[i]){
     const rv=Math.max(ref[o],ref[o+1],ref[o+2]);
     const gv=Math.max(gen[o],gen[o+1],gen[o+2]);
     // Tiny source UV islands must not vanish when the master is resampled.
     if(gv<Math.max(5,rv*.25)){gen[o]=ref[o];gen[o+1]=ref[o+1];gen[o+2]=ref[o+2];fallback++;}
    }else{gen[o]=0;gen[o+1]=0;gen[o+2]=0;}
    gen[o+3]=255;
   }
   // Nearest-color dilation into 12-pixel UV gutters; never across covered UVs.
   const dist=new Uint8Array(P);dist.fill(255);
   const queue=new Int32Array(P);let head=0,tail=0;
   for(let i=0;i<P;i++)if(mask[i]){dist[i]=0;queue[tail++]=i;}
   while(head<tail){const i=queue[head++],d=dist[i];if(d>=12)continue;const x=i%N;
    for(const j of [x?i-1:-1,x<N-1?i+1:-1,i>=N?i-N:-1,i<P-N?i+N:-1]){
     if(j<0||dist[j]!==255)continue;
     dist[j]=d+1;queue[tail++]=j;const a=i*4,b=j*4;
     gen[b]=gen[a];gen[b+1]=gen[a+1];gen[b+2]=gen[a+2];
    }
   }
  }else{
   for(let i=0;i<P;i++)gen[i*4+3]=255;
   // Technical wrap repair: match opposite 4m-repeat borders within 8 pixels.
   // Painting inside the plates remains untouched.
   for(let y=0;y<N;y++)for(let d=0;d<8;d++){
    const a=(y*N+d)*4,b=(y*N+N-1-d)*4,t=(1-d/8)**2;
    for(let c=0;c<3;c++){const avg=(gen[a+c]+gen[b+c])/2;gen[a+c]=Math.round(gen[a+c]*(1-t)+avg*t);gen[b+c]=Math.round(gen[b+c]*(1-t)+avg*t);}
   }
   for(let x=0;x<N;x++)for(let d=0;d<8;d++){
    const a=(d*N+x)*4,b=((N-1-d)*N+x)*4,t=(1-d/8)**2;
    for(let c=0;c<3;c++){const avg=(gen[a+c]+gen[b+c])/2;gen[a+c]=Math.round(gen[a+c]*(1-t)+avg*t);gen[b+c]=Math.round(gen[b+c]*(1-t)+avg*t);}
   }
  }
  const dir=path.join(out,'png',variant);fs.mkdirSync(dir,{recursive:true});
  const filename=path.join(dir,path.basename(r.source_texture));
  // UV clip-space capture uses Vulkan's vertical framebuffer convention.
  // Normalize to the original imported model's texture convention once here.
  await sharp(gen,{raw:{width:N,height:N,channels:4}}).flip().removeAlpha().png().toFile(filename);
  const actual=stats(gen,mask),metadata=await sharp(master).metadata();
  const result={variant,model:r.model,file:path.relative(out,filename).replaceAll('\\','/'),size:[N,N],mode:'RGB',uv_orientation:'vertical-normalized from capture space to original model UV',master_size:[metadata.width,metadata.height],master_sha256:sha(master),sha256:sha(filename),fallback_pixels:fallback,fallback_fraction:fallback/baseline.pixels,padding_pixels:r.mapping==='world_xz_4m'?0:12,reference:baseline,raw:rawStats,calibration,actual,delta_v:actual.mean_hsv_v-baseline.mean_hsv_v,delta_s:actual.mean_hsv_s-baseline.mean_hsv_s};
  validation.push(result);
  console.log(variant,r.model,'dV='+result.delta_v.toFixed(4),'dS='+result.delta_s.toFixed(4),'tinyUV='+(100*result.fallback_fraction).toFixed(2)+'%');
 }
}
fs.writeFileSync(path.join(out,'manifest.json'),JSON.stringify({date:'2026-10-06',models,textures:validation,artistic_source:'built-in image_gen',packing:'2048x2048 resampling; HSV mean calibration per original UV island or floor plate; original coverage and 12px padding; tiny missing UV pixels preserve current baseline',floor_mapping:'world XZ/4m, 2x2 plates; all other props use unchanged UVs',game_applied:false},null,2));
