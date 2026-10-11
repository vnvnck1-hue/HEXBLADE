const sharp=require('C:/Users/vnvnc/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const fs=require('fs');
(async()=>{
const jobs=JSON.parse(fs.readFileSync(__dirname+'/prompts.json'));
let images=[];
for(let i=0;i<jobs.length;i++){
const j=jobs[i];
console.log(j.id,await sharp(j.target).metadata().then(m=>[m.width,m.height]),await sharp(j.source).metadata().then(m=>[m.width,m.height]));
for(let k=0;k<2;k++)images.push({input:await sharp(k?j.target.replace('.png','_closed.png'):j.target).extract({left:400,top:280,width:450,height:330}).png().toBuffer(),left:k*450,top:i*330});
}
await sharp({create:{width:900,height:1980,channels:4,background:'#666666'}}).composite(images).png().toFile(__dirname+'/final_eye_comparison.png');
})();

