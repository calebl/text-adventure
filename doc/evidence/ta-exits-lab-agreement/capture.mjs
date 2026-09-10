// Direct CDP proof, using Node's built-in WebSocket; no package or app build step.
// Run from the isolated worktree. Only processes started here are stopped here.
import { spawn, execFileSync } from 'node:child_process';
import { writeFileSync, openSync, mkdirSync } from 'node:fs';
import { resolve } from 'node:path';
const root = process.cwd();
if (!root.includes('/.treehouse/')) throw new Error('Evidence requires the disposable worktree');
const evidence = resolve('doc/evidence/ta-exits-lab-agreement');
const port = 3193, debugPort = 9393;
const listeners = execFileSync('ss', ['-ltnp', `sport = :${port} or sport = :${debugPort}`], { encoding: 'utf8' });
if (listeners.trim().split('\n').length !== 1) throw new Error('Evidence ports occupied');
writeFileSync(`${evidence}/ports.txt`, listeners);
mkdirSync('tmp/agreement-chromium', { recursive: true });
execFileSync('python3', ['-c', "import sqlite3; a=sqlite3.connect('storage/development.sqlite3'); b=sqlite3.connect('tmp/agreement-before.sqlite3'); a.backup(b); b.close(); a.close()"]);
const app = spawn('bin/dev', [], { env: { ...process.env, PORT: String(port), TA_DEBUG_VIEW: '1' }, stdio: ['ignore', openSync('tmp/agreement-app.log', 'w'), 'pipe'] });
const browser = spawn('chromium', ['--headless', '--no-sandbox', '--disable-gpu', `--remote-debugging-port=${debugPort}`, `--user-data-dir=${root}/tmp/agreement-chromium`, 'about:blank'], { stdio: ['ignore', openSync('tmp/agreement-chromium.log', 'w'), 'ignore'] });
writeFileSync(`${evidence}/processes.json`, JSON.stringify({ app: app.pid, browser: browser.pid, cwd: root, port, debugPort }, null, 2));
let ws;
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
async function ready(url) {
  for (let attempt = 0; attempt < 100; attempt++) {
    try { const response = await fetch(url); if (response.ok) return response; } catch {}
    await delay(200);
  }
  throw new Error(`Not ready: ${url}`);
}
try {
  await ready(`http://127.0.0.1:${port}/lab/exits`);
  const tabs = await (await ready(`http://127.0.0.1:${debugPort}/json/list`)).json();
  ws = new WebSocket(tabs.find(tab => tab.type === 'page').webSocketDebuggerUrl);
  await new Promise((resolve, reject) => { ws.onopen = resolve; ws.onerror = reject; });
  let serial = 0;
  const pending = new Map();
  ws.onmessage = event => {
    const result = JSON.parse(event.data);
    if (pending.has(result.id)) {
      const [resolve, reject] = pending.get(result.id); pending.delete(result.id);
      result.error ? reject(new Error(JSON.stringify(result.error))) : resolve(result.result);
    }
  };
  const call = (method, params = {}) => new Promise((resolve, reject) => {
    const id = ++serial; pending.set(id, [resolve, reject]); ws.send(JSON.stringify({ id, method, params }));
  });
  await call('Page.enable');
  await call('Emulation.setDeviceMetricsOverride', { width: 1440, height: 1000, deviceScaleFactor: 1, mobile: false });
  const proof = {};
  for (const state of ['empty', 'below', 'established']) {
    execFileSync('bin/rails', ['runner', `${evidence}/seed.rb`], { env: { ...process.env, AGREEMENT_STATE: state }, stdio: 'pipe' });
    await call('Page.navigate', { url: `http://127.0.0.1:${port}/lab/exits` });
    await delay(700);
    const { result } = await call('Runtime.evaluate', { expression: `(() => { const el = document.querySelector('#agreement'); const r = el.getBoundingClientRect(); return { text: el.innerText, links: [...el.querySelectorAll('a')].map(a=>a.href), clip: {x:r.x,y:r.y+scrollY,width:r.width,height:r.height,scale:1} }; })()`, returnByValue: true });
    if (!result.value) throw new Error(JSON.stringify(result));
    const page = result.value;
    if (state === 'empty' && (!page.text.includes('nothing drawn') || page.text.includes('%'))) throw new Error('Empty state failed');
    if (state === 'below' && (!page.text.includes('not established') || page.text.includes('%') || page.links.length < 2)) throw new Error('Below state failed');
    if (state === 'established' && (!page.text.includes('100.0%') || !page.text.includes('held out'))) throw new Error('Established state failed');
    const screenshot = await call('Page.captureScreenshot', { format: 'png', captureBeyondViewport: true, clip: page.clip });
    writeFileSync(`${evidence}/${state}.png`, Buffer.from(screenshot.data, 'base64'));
    writeFileSync(`${evidence}/${state}.txt`, page.text);
    proof[state] = { links: page.links, clip: page.clip, passed: true };
    if (state === 'below') {
      for (const link of page.links) { const response = await fetch(link); if (!response.ok) throw new Error(`Evidence link failed: ${link}`); }
    }
    writeFileSync(`${evidence}/rake-${state}.txt`, execFileSync('bin/rails', ['eval:exits_alignment'], { encoding: 'utf8' }));
  }
  writeFileSync(`${evidence}/browser-checks.json`, JSON.stringify(proof, null, 2));
} finally {
  ws?.close();
  const exited = child => new Promise(resolve => { if (child.exitCode !== null) resolve(); else child.once('exit', resolve); });
  const stops = [exited(app), exited(browser)];
  app.kill('SIGTERM'); browser.kill('SIGTERM');
  await Promise.all(stops);
  execFileSync('python3', ['-c', "import sqlite3; a=sqlite3.connect('tmp/agreement-before.sqlite3'); b=sqlite3.connect('storage/development.sqlite3'); a.backup(b); b.close(); a.close()"]);
}
