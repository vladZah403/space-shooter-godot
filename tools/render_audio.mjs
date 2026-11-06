// Звук для Godot-версии: эффекты и музыка JS-версии, записанные в WAV.
//
// Запуск (из папки Godot-проекта; нужны Node 22+ и Chrome или Edge):
//     node tools/render_audio.mjs
//
// Берёт ../space-shooter-game/js/audio.js как есть и выполняет его в скрытом браузере:
//  • эффекты — тем же OfflineAudioContext (32 кГц), что и в игре → assets/audio/sfx/<имя>.wav
//  • музыка — тот же секвенсор (_schedule) в оффлайн-контексте: 8 тактов, берутся такты 5–8 — бесшовная
//    петля с хвостами нот; по стилю и интенсивности (0 меню, 1 бой, 2 босс) → assets/audio/music/<стиль>_<0|1|2>.wav
// и пишет assets/audio/audio.json: длительности, пики и громкость (LIMIT) для audio.gd.
// Браузер можно указать явно: CHROME_PATH="C:\...\chrome.exe" node tools/render_audio.mjs
import { spawn } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(fileURLToPath(new URL('..', import.meta.url)));
const SRC = resolve(ROOT, '..', 'space-shooter-game', 'js', 'audio.js');
const OUT = join(ROOT, 'assets', 'audio');
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function findBrowser() {
  const pf = [process.env.PROGRAMFILES, process.env['PROGRAMFILES(X86)'], process.env.LOCALAPPDATA].filter(Boolean);
  const list = [process.env.CHROME_PATH,
    ...pf.map((p) => join(p, 'Google', 'Chrome', 'Application', 'chrome.exe')),
    ...pf.map((p) => join(p, 'Microsoft', 'Edge', 'Application', 'msedge.exe')),
    '/usr/bin/google-chrome', '/usr/bin/chromium'];
  return list.find((p) => p && existsSync(p));
}

async function launch(exe) {
  const profile = mkdtempSync(join(tmpdir(), 'ss-audio-'));
  const proc = spawn(exe, ['--headless=new', '--remote-debugging-port=0', '--user-data-dir=' + profile,
    '--no-first-run', '--no-default-browser-check', '--mute-audio', 'about:blank'], { stdio: 'ignore' });
  const portFile = join(profile, 'DevToolsActivePort');
  for (let i = 0; i < 150 && !existsSync(portFile); i++) await sleep(100);
  if (!existsSync(portFile)) throw new Error('браузер не запустился: ' + exe);
  await sleep(200);
  return { proc, profile, port: readFileSync(portFile, 'utf8').split('\n')[0].trim() };
}

function cdp(wsUrl) {
  const ws = new WebSocket(wsUrl);
  let id = 0;
  const wait = new Map();
  ws.onmessage = (m) => {
    const msg = JSON.parse(m.data);
    if (msg.id && wait.has(msg.id)) { const [res, rej] = wait.get(msg.id); wait.delete(msg.id); msg.error ? rej(new Error(msg.error.message)) : res(msg.result); }
  };
  const ready = new Promise((r, j) => { ws.onopen = r; ws.onerror = j; });
  const send = (method, params = {}) => new Promise((res, rej) => { wait.set(++id, [res, rej]); ws.send(JSON.stringify({ id, method, params })); });
  const evaluate = async (expr) => {
    const r = await send('Runtime.evaluate', { expression: expr, awaitPromise: true, returnByValue: true });
    if (r.exceptionDetails) throw new Error(r.exceptionDetails.exception?.description || r.exceptionDetails.text);
    return r.result.value;
  };
  return { ready, evaluate, close: () => ws.close() };
}

// выполняется в странице: заглушки SS, audio.js, оффлайн-рендер, кодирование WAV в base64
const PAGE = (src) => `(async () => {
  const U = { rand: (a, b) => a + Math.random() * (b - a), clamp: (v, a, b) => Math.max(a, Math.min(b, v)) };
  window.SS = { util: U, store: { s: { settings: { music: 70, sfx: 80 } } }, emit() {}, on() {} };
  ${src}
  const A = SS.audio, M = A.music;
  function wav(samples, rate) {
    const n = samples.length, buf = new ArrayBuffer(44 + n * 2), v = new DataView(buf);
    const str = (o, s) => { for (let i = 0; i < s.length; i++) v.setUint8(o + i, s.charCodeAt(i)); };
    str(0, 'RIFF'); v.setUint32(4, 36 + n * 2, true); str(8, 'WAVE'); str(12, 'fmt ');
    v.setUint32(16, 16, true); v.setUint16(20, 1, true); v.setUint16(22, 1, true); v.setUint32(24, rate, true);
    v.setUint32(28, rate * 2, true); v.setUint16(32, 2, true); v.setUint16(34, 16, true); str(36, 'data'); v.setUint32(40, n * 2, true);
    for (let i = 0; i < n; i++) v.setInt16(44 + i * 2, Math.max(-1, Math.min(1, samples[i])) * 32767, true);
    let s = ''; const b = new Uint8Array(buf);
    for (let i = 0; i < b.length; i += 0x8000) s += String.fromCharCode.apply(null, b.subarray(i, i + 0x8000));
    return btoa(s);
  }
  const peak = (d) => { let p = 0; for (let i = 0; i < d.length; i++) p = Math.max(p, Math.abs(d[i])); return p; };
  const out = { sfx: {}, music: {} };
  // ── эффекты: тот же renderSfx, что в игре ──
  await A.renderSfx();
  for (const name of Object.keys(A.buffers)) {
    const d = A.buffers[name].getChannelData(0);
    // хвост тишины в конце буфера не нужен
    let end = d.length; while (end > 1 && Math.abs(d[end - 1]) < 1e-4) end--;
    const k = peak(d) > 1 ? 1 / peak(d) : 1;
    out.sfx[name] = { wav: wav(d.subarray(0, end).map((x) => x * k), 32000), dur: end / 32000, gain: 1 / k };
  }
  // ── музыка: 8 тактов в оффлайн-контексте, петля — такты 5–8 ──
  const RATE = 32000;
  for (const id of Object.keys(A.styles)) {
    const st = A.styles[id], sd = 60 / st.bpm / 4, bar = sd * 16;
    for (const lv of [0, 1, 2]) {
      const ac = new OfflineAudioContext(1, Math.ceil(bar * 8 * RATE) + RATE, RATE);
      A.ac = ac;
      A.noise = ac.createBuffer(1, ac.sampleRate, ac.sampleRate);
      const nd = A.noise.getChannelData(0); for (let i = 0; i < nd.length; i++) nd[i] = Math.random() * 2 - 1;
      M._bus = ac.createGain(); M._bus.connect(ac.destination);
      M.style = st; M.intensity = lv;
      for (let b = 0; b < 8; b++) for (let s = 0; s < 16; s++) M._schedule(st, s, b, 0.05 + (b * 16 + s) * sd, sd);
      const buf = await ac.startRendering();
      const d = buf.getChannelData(0), from = Math.round((0.05 + bar * 4) * RATE), to = Math.round((0.05 + bar * 8) * RATE);
      const loop = d.slice(from, to), p = peak(loop), k = p > 0.98 ? 0.98 / p : 1;
      out.music[id + '_' + lv] = { wav: wav(loop.map((x) => x * k), RATE), dur: (to - from) / RATE, gain: 1 / k, bpm: st.bpm, name: st.name };
    }
  }
  return out;
})()`;

const exe = findBrowser();
if (!exe) { console.error('Не нашёл Chrome или Edge. Укажите CHROME_PATH'); process.exit(2); }
const { proc, profile, port } = await launch(exe);
try {
  const list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
  const page = list.find((t) => t.type === 'page');
  const c = cdp(page.webSocketDebuggerUrl);
  await c.ready;
  const res = await c.evaluate(PAGE(readFileSync(SRC, 'utf8')));
  c.close();
  mkdirSync(join(OUT, 'sfx'), { recursive: true });
  mkdirSync(join(OUT, 'music'), { recursive: true });
  const meta = { sfx: {}, music: {} };
  let bytes = 0;
  for (const [name, s] of Object.entries(res.sfx)) {
    const b = Buffer.from(s.wav, 'base64'); bytes += b.length;
    writeFileSync(join(OUT, 'sfx', name + '.wav'), b);
    meta.sfx[name] = { dur: +s.dur.toFixed(3), gain: +s.gain.toFixed(3) };
  }
  for (const [name, m] of Object.entries(res.music)) {
    const b = Buffer.from(m.wav, 'base64'); bytes += b.length;
    writeFileSync(join(OUT, 'music', name + '.wav'), b);
    meta.music[name] = { dur: +m.dur.toFixed(4), gain: +m.gain.toFixed(3), bpm: m.bpm, name: m.name };
  }
  writeFileSync(join(OUT, 'audio.json'), JSON.stringify(meta, null, 1));
  console.log(`эффектов: ${Object.keys(meta.sfx).length}, петель музыки: ${Object.keys(meta.music).length}, ${(bytes / 1048576).toFixed(1)} МБ WAV`);
} finally {
  proc.kill();
  await sleep(300);
  try { rmSync(profile, { recursive: true, force: true }); } catch (e) {}
}
