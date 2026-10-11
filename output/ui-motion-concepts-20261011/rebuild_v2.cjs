const fs=require('fs'),p=__dirname+'/';
const h=fs.readFileSync(p+'index_v2.template.html','utf8');
const d=JSON.parse(fs.readFileSync(p+'motion_v2_data.json','utf8'));
fs.writeFileSync(p+'index.html',h.replace('__DATA__',JSON.stringify(d)));

