// Encode actual Godot captures; character artwork is not edited here.
const sharp=require('C:/Users/vnvnc/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const fs=require('fs');
(async()=>{
const names=fs.readdirSync(__dirname+'/frames').filter(x=>x.startsWith('blink_')).sort();
const frames=[];
for(const name of names)frames.push(await sharp(__dirname+'/frames/'+name).resize(960,600).ensureAlpha().raw().toBuffer());
await sharp(Buffer.concat(frames),{raw:{width:960,height:600*frames.length,channels:4,pageHeight:600}}).gif({loop:0,delay:50,effort:7,colours:128}).toFile(__dirname+'/blink_preview.gif');
console.log('Encoded '+names.length+' Godot frames');
})();
