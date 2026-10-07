// Rasterize our native SVG resources and capture the local HTML composition.
// This never edits AI paintings. Requires bundled Node, sharp and Playwright.
const fs=require('fs');const path=require('path');const {pathToFileURL}=require('url');
const deps=process.env.LOBBY_NODE_MODULES || 'C:/Users/Loadcomplete/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules';
const sharp=require(path.join(deps,'sharp'));const {chromium}=require(path.join(deps,'playwright'));
const root=__dirname;
(async()=>{
 const out=path.join(root,'ui_png');fs.mkdirSync(out,{recursive:true});
 for(const file of fs.readdirSync(path.join(root,'ui')).filter(s=>s.endsWith('.svg'))){await sharp(path.join(root,'ui',file)).png().toFile(path.join(out,file.replace('.svg','.png')))}
 const candidates=[process.env.LOBBY_CHROME_EXE,chromium.executablePath(),'C:/Program Files/Google/Chrome/Application/chrome.exe','C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'].filter(Boolean);
 const executablePath=candidates.find(p=>fs.existsSync(p));
 if(!executablePath)throw new Error('No installed Chromium browser found; set LOBBY_CHROME_EXE. No automatic installation.');
 const browser=await chromium.launch({headless:true,executablePath});
 const checks=[];
 for(const config of [
  {name:'preview_static_1920x1080.png',width:1920,height:1080,mode:'static'},
  {name:'preview_layered_1920x1080.png',width:1920,height:1080,mode:'layered'},
  {name:'preview_static_1280x800.png',width:1280,height:800,mode:'static'},
  {name:'preview_static_1280x720.png',width:1280,height:720,mode:'static'},
  {name:'preview_static_1920x800.png',width:1920,height:800,mode:'static'},
  {name:'preview_test_drawer.png',width:1920,height:1080,mode:'static',drawer:true},
 ]){
  const page=await browser.newPage({viewport:{width:config.width,height:config.height},deviceScaleFactor:1});
  const errors=[];page.on('pageerror',e=>errors.push(String(e)));
  await page.goto(pathToFileURL(path.join(root,'preview.html')).href+'?export=1&mode='+config.mode+(config.drawer?'&drawer=1':''));
  await page.evaluate(async()=>{await document.fonts.ready;await Promise.all([...document.images].map(im=>im.decode()))});
  const check=await page.evaluate(()=>{const r=document.querySelector('#stage').getBoundingClientRect();const menus=[...document.querySelectorAll('.menu')].map(b=>{const q=b.getBoundingClientRect();return {id:b.dataset.id,in_view:q.left>=0&&q.top>=0&&q.right<=innerWidth+.5&&q.bottom<=innerHeight+.5}});return {stage:{x:r.x,y:r.y,width:r.width,height:r.height},menus,image_count:document.images.length,all_images_loaded:[...document.images].every(im=>im.complete&&im.naturalWidth>0),drawer_rows:document.querySelectorAll('.drawerrow').length}});
  if(!config.drawer){await page.keyboard.press('ArrowDown');const active=await page.locator('.menu.hot').getAttribute('data-id');check.keyboard_down=active==='death_test';await page.keyboard.press('ArrowUp');check.keyboard_up=await page.locator('.menu.hot').getAttribute('data-id')==='sector_run';}
  await page.screenshot({path:path.join(root,config.name)});checks.push({name:config.name,...check,errors});await page.close();
 }
 await browser.close();
 const crypto=require('crypto');const manifestPath=path.join(root,'manifest.json');const manifest=JSON.parse(fs.readFileSync(manifestPath,'utf8'));manifest.native_png_variant_count=fs.readdirSync(out).length;
 manifest.files=manifest.files.filter(f=>!f.path.startsWith('ui_png/'));
 for(const file of fs.readdirSync(out).filter(s=>s.endsWith('.png'))){const full=path.join(out,file);const meta=await sharp(full).metadata();manifest.files.push({path:'ui_png/'+file,format:'PNG',size:[meta.width,meta.height],sha256:crypto.createHash('sha256').update(fs.readFileSync(full)).digest('hex'),source:'ui/'+file.replace('.png','.svg')})}
 fs.writeFileSync(manifestPath,JSON.stringify(manifest,null,2)+'\n');
 const v=JSON.parse(fs.readFileSync(path.join(root,'validation.json'),'utf8'));v.preview_checks=checks;v.svg_rasterization={tool:'sharp',count:manifest.native_png_variant_count};v.preview_checks_pass=checks.every(c=>c.errors.length===0&&c.all_images_loaded&&c.menus.every(m=>m.in_view)&&c.drawer_rows===13&&(c.keyboard_down===undefined||c.keyboard_down)&&(c.keyboard_up===undefined||c.keyboard_up));fs.writeFileSync(path.join(root,'validation.json'),JSON.stringify(v,null,2)+'\n');
 console.log(JSON.stringify({preview_checks_pass:v.preview_checks_pass,checks},null,2));if(!v.preview_checks_pass)process.exitCode=1;
})().catch(e=>{console.error(e);process.exit(1)});
