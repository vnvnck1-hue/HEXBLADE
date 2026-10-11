// Imagegen drew each eyelid. Only its eye patches are composited; every other
// original RGBA byte, including hair boundaries and the alpha channel, is kept.
const sharp=require('C:/Users/vnvnc/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const fs=require('fs'),path=require('path'),crypto=require('crypto');
const regions={
 owner_welcome:[[[476,362],[532,377],[607,402],[646,431],[635,473],[583,493],[532,488],[501,455]],[[676,463],[729,466],[792,480],[831,505],[818,547],[773,568],[718,558],[678,534]]],
 owner_briefing:[[[453,522],[495,516],[548,526],[596,548],[582,590],[540,615],[491,613],[446,580]],[[624,448],[670,439],[746,412],[795,415],[789,465],[765,514],[718,552],[667,550],[639,516]]],
 owner_encouragement:[[[445,520],[490,516],[535,524],[576,547],[569,588],[523,610],[476,608],[440,576]],[[602,444],[652,420],[728,392],[765,394],[752,440],[729,487],[686,523],[645,528],[607,507]]],
 worker_introduction:[[[410,478],[450,455],[497,445],[549,450],[583,490],[570,532],[526,557],[474,553],[430,534]],[[631,384],[678,354],[733,333],[808,314],[805,355],[790,410],[760,458],[710,474],[654,450]]],
 worker_cheerful:[[[425,492],[472,461],[521,446],[568,468],[582,494],[566,536],[522,559],[470,559],[428,541]],[[631,393],[679,359],[739,333],[805,313],[806,351],[790,406],[767,457],[714,471],[662,450]]],
 partner_greeting:[[[513,343],[546,311],[598,290],[666,295],[681,318],[668,372],[641,420],[587,440],[547,420],[520,384]]],
};
// Enclose the union of the original lash/iris and the generated closed lash.
const boxes={owner_welcome:[[470,350,662,502],[667,453,853,577]],owner_briefing:[[432,475,607,618],[616,393,807,560]],owner_encouragement:[[426,470,587,615],[584,362,780,535]],worker_introduction:[[397,429,590,568],[620,308,835,483]],worker_cheerful:[[410,434,594,570],[620,306,837,485]],partner_greeting:[[507,282,690,446]]};
for(const id in boxes)regions[id]=boxes[id].map(([x,y,r,b])=>[[x,y],[r,y],[r,b],[x,b]]);
regions.owner_encouragement[1]=[[584,441],[634,408],[695,386],[733,372],[780,369],[780,535],[584,535]];
const inside=(x,y,p)=>{let hit=false;for(let i=0,j=p.length-1;i<p.length;j=i++)if((p[i][1]>y)!=(p[j][1]>y)&&x<(p[j][0]-p[i][0])*(y-p[i][1])/(p[j][1]-p[i][1])+p[i][0])hit=!hit;return hit;};
const distance=(x,y,p)=>Math.min(...p.map((a,i)=>{const b=p[(i+1)%p.length],dx=b[0]-a[0],dy=b[1]-a[1],t=Math.max(0,Math.min(1,((x-a[0])*dx+(y-a[1])*dy)/(dx*dx+dy*dy)));return Math.hypot(x-a[0]-t*dx,y-a[1]-t*dy);}));
const hair=(b,i,id)=>id.startsWith('owner')?b[i]>b[i+1]*1.04&&b[i+1]-b[i+2]>38:id.startsWith('worker')?b[i+2]>80&&b[i]>b[i+1]*1.25&&b[i+2]>b[i+1]*1.25:b[i+1]>90&&b[i+1]>b[i]*1.02&&b[i+1]>b[i+2]*1.02;
(async()=>{
const jobs=JSON.parse(fs.readFileSync(__dirname+'/prompts.json'));fs.mkdirSync(__dirname+'/masters',{recursive:true});let report=[];
for(const j of jobs){
 const original=await sharp(j.target).ensureAlpha().raw().toBuffer(),gen=await sharp(j.source).ensureAlpha().raw().toBuffer(),out=Buffer.from(original);
 const polys=regions[j.id];let changes=0,alphaChanges=0,outsideChanges=0;
 for(let y=0;y<1254;y++)for(let x=0;x<1254;x++){
  const i=(y*1254+x)*4,p=polys.find(p=>inside(x+.5,y+.5,p));if(!p||hair(original,i,j.id)&&(j.id.startsWith('worker')||j.id.startsWith('partner')||hair(gen,i,j.id)))continue;
  const w=Math.min(1,distance(x+.5,y+.5,p)/3);
  for(let c=0;c<3;c++)out[i+c]=Math.round(original[i+c]*(1-w)+gen[i+c]*w);
 }
 for(let y=0;y<1254;y++)for(let x=0;x<1254;x++){const i=(y*1254+x)*4;if(!out.subarray(i,i+4).equals(original.subarray(i,i+4))){changes++;if(!polys.some(p=>inside(x+.5,y+.5,p)))outsideChanges++;}if(out[i+3]!==original[i+3])alphaChanges++;}
 const dest=j.target.replace(/\.png$/,'_closed.png');await sharp(out,{raw:{width:1254,height:1254,channels:4}}).png().toFile(dest);
 fs.copyFileSync(j.source,__dirname+'/masters/'+j.id+'.png');
 report.push({id:j.id,open:j.target,closed:dest,regions:polys,changedPixels:changes,outsideEyeChangedPixels:outsideChanges,alphaChangedPixels:alphaChanges,sha256:crypto.createHash('sha256').update(fs.readFileSync(dest)).digest('hex')});
}
fs.writeFileSync(__dirname+'/asset_validation.json',JSON.stringify(report,null,2));console.log(report.map(x=>({id:x.id,changed:x.changedPixels,outside:x.outsideEyeChangedPixels,alpha:x.alphaChangedPixels})));
})();
