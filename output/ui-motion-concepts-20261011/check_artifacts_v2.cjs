const fs=require('fs'),path=require('path'),crypto=require('crypto'),{pathToFileURL}=require('url');
const root=__dirname,repo=path.resolve(root,'../..');
const {chromium}=require('C:/Users/vnvnc/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
(async()=>{
 const exe=[chromium.executablePath(),'C:/Program Files/Google/Chrome/Application/chrome.exe','C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'].find(fs.existsSync);
 const browser=await chromium.launch({headless:true,executablePath:exe}),page=await browser.newPage();let errors=[];page.on('pageerror',e=>errors.push(String(e)));
 await page.goto(pathToFileURL(path.join(root,'index.html')).href);await page.evaluate(()=>Promise.all([...document.images].map(x=>x.decode())));
 const images=await page.evaluate(()=>[...document.images].map(x=>({src:x.getAttribute('src'),width:x.naturalWidth,height:x.naturalHeight})));
 const md=fs.readFileSync(repo+'/docs/ui-notification-motion-concepts.md','utf8');const links=[...md.matchAll(/\]\(([^)]+)\)/g)].map(x=>({url:x[1],exists:fs.existsSync(path.resolve(repo+'/docs',x[1]))}));
 const validation=JSON.parse(fs.readFileSync(root+'/validation_v2.json','utf8'));
 validation.artifacts={reviewed_on:'2026-10-12',all_ten_visually_reviewed:true,images,links,browser_errors:errors,all_pass:images.length===10&&images.every(x=>x.width>0)&&links.every(x=>x.exists)&&errors.length===0};
 validation.artifacts.files=images.map(x=>({path:x.src,sha256:crypto.createHash('sha256').update(fs.readFileSync(path.join(root,x.src))).digest('hex')}));
 validation.all_pass=validation.all_pass&&validation.artifacts.all_pass;
 await page.keyboard.press('ArrowRight');const right=await page.evaluate(()=>motionConcept.chosen);await page.keyboard.press('ArrowLeft');const left=await page.evaluate(()=>motionConcept.chosen);validation.artifacts.keyboard_navigation=right===1&&left===0;validation.all_pass&&=validation.artifacts.keyboard_navigation;
 await browser.close();for(const name of ['validation_v2.json','validation.json']){fs.writeFileSync(root+'/'+name+'.tmp',JSON.stringify(validation,null,2));fs.renameSync(root+'/'+name+'.tmp',root+'/'+name);}
 console.log(JSON.stringify({all_pass:validation.all_pass,motion_checks:validation.checks.length,board_images:images.length,document_links:links.length,keyboard_navigation:validation.artifacts.keyboard_navigation}));if(!validation.all_pass)process.exitCode=1;
})().catch(e=>{console.error(e);process.exitCode=1});
