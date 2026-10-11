const fs = require('fs');
const cp = require('child_process');
const crypto = require('crypto');
const folder = 'output/cutin-restored-20261011/';
const hash = p => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const assets = JSON.parse(fs.readFileSync(folder+'restored-assets.json','utf8'));
const assetsIdentical = assets.every(row => hash(row.path) === row.sha256);
const scriptsIdentical = ['scripts/drone/diagonal_docking_cutin.gd','scripts/drone/cockpit_cutin.gd','tests/diagonal_cutin_check.gd'].every(p => fs.readFileSync(p).equals(cp.execFileSync('git',['show','HEAD:'+p])));
const logs = ['import','diagonal','cockpit','training-bot'].map(name => {
  const data = fs.readFileSync(folder+name+'.log','utf8');
  return {name, errors:(data.match(/(?:^|\n)\s*(?:SCRIPT ERROR|ERROR):/g)||[]).length};
});
const all = fs.readFileSync(folder+'full_tests.log','utf8');
const retry = fs.readFileSync(folder+'shared-retry.log','utf8');
const retryPassed = /ALL 4 TESTS PASSED/.test(retry) && !/SCRIPT ERROR/.test(retry);
const failedNames = ((all.match(/^FAILED: (.+)$/m)||[])[1]||'').trim().split(/,\s*/).filter(Boolean);
const retryNames = ['mammoth_ingame_check','mech_player_check','missile_check','moco_vfx_check'];
const remainingFailures = failedNames.filter(n => !(retryPassed && retryNames.includes(n)));
const testCount = (all.match(/^=== /gm)||[]).length;
const result = {
  scope:'Restore fusion cutins only; retain new dialogue cast, protagonist portrait, blink and idle motion',
  restoredAssetFiles:assets.length, archivedBytesIdentical:assetsIdentical,
  cutinScriptsAndTestsEqualGitHEAD:scriptsIdentical,
  runtimeLogs:logs,
  regression:{completedTests:testCount, passed:testCount-remainingFailures.length, remainingFailures, sharedImportRetryPassed:retryPassed, retryErrors:(retry.match(/(?:^|\n)\s*(?:SCRIPT ERROR|ERROR):/g)||[]).length, knownPriorFailure:'diagonal_cutin_check: right exit x=1271 versus 1280; also documented before this task in AGENTS.md', initialRunErrors:(all.match(/(?:^|\n)\s*(?:SCRIPT ERROR|ERROR):/g)||[]).length},
  visualInspection:['diagonal.png: original mint maid, props and diagonal DOCKING','cockpit.png: original purple cockpit pilot'],
  preserved:'Dialogue owner/worker/partner/me, six closed-eye frames, idle motion; unrelated workspace changes',
  capturedAt:new Date().toISOString()
};
fs.writeFileSync(folder+'validation.json',JSON.stringify(result,null,2));
console.log(JSON.stringify(result));
if (!assetsIdentical || !scriptsIdentical || logs.some(row=>row.errors) || !retryPassed || remainingFailures.some(n => n !== 'diagonal_cutin_check')) process.exitCode=1;
