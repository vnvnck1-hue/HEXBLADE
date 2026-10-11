const fs=require('fs'),path=require('path'),crypto=require('crypto');
const sharp=require('C:/Users/vnvnc/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
(async()=>{
const rows=JSON.parse(fs.readFileSync(__dirname+'/asset_validation.json'));
const originals=JSON.parse(fs.readFileSync(__dirname+'/original_hash_check.json','utf8').replace(/^\uFEFF/,''));
let assets=[];
for(const row of rows){const actual=crypto.createHash('sha256').update(fs.readFileSync(row.closed)).digest('hex');const m=await sharp(row.closed).metadata();assets.push({id:row.id,hashMatches:actual===row.sha256,dimensions:[m.width,m.height],rgba:m.hasAlpha&&m.channels===4,importExists:fs.existsSync(row.closed+'.import'),outsideEyeChangedPixels:row.outsideEyeChangedPixels,alphaChangedPixels:row.alphaChangedPixels});}
const preview=await sharp(__dirname+'/blink_preview.gif',{animated:true}).metadata();
const retired=['cleaning_owner','purple_worker','green_maid','mint_maid'].map(d=>({name:d,absentFromGame:!fs.existsSync('assets/portraits/'+d),archiveExists:fs.existsSync('output/retired-characters-20261011/assets/portraits/'+d)}));
const result={tool:'built-in imagegen, 6 independent edits',originals,assets,preview:{width:preview.width,pageHeight:preview.pageHeight,frames:preview.pages,loop:preview.loop},retired};
fs.writeFileSync(__dirname+'/delivery_checks.json',JSON.stringify(result,null,2));console.log(JSON.stringify({assetsOK:assets.every(a=>a.hashMatches&&a.rgba&&a.importExists&&!a.outsideEyeChangedPixels&&!a.alphaChangedPixels),originalsUnchanged:originals.every(x=>x.unchanged),retiredOK:retired.every(x=>x.absentFromGame&&x.archiveExists),preview:result.preview}));
})();
