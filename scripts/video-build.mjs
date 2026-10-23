/**
 * Build the silent MP4 (no voice, no subtitles) from the existing HTML prototype (macOS).
 * Requirements: Node, Playwright, Chrome, Swift/AVFoundation.
 * PLAYWRIGHT_PATH may point to an existing playwright or playwright-core module.
 * Run: node scripts/video-build.mjs
 * All intermediate frames stay in the OS temporary directory.
 * Scene texts and durations live in scripts/video-story.json (`seconds` per scene).
 */
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { tmpdir } from 'node:os';
import { execFileSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';

const require = createRequire(import.meta.url);
const root = resolve(import.meta.dirname, '..');
const out = join(root, 'assets/video');
const work = process.env.VIDEO_WORK_DIR || join(tmpdir(), 'trimodos-video-build');
mkdirSync(out, { recursive: true }); mkdirSync(work, { recursive: true });
const scenes = JSON.parse(readFileSync(join(root, 'scripts/video-story.json'), 'utf8'));
const fps = 10;
let position = 0;
for (const scene of scenes) {
  Object.assign(scene, { start: position, duration: scene.seconds });
  position += scene.duration;
}
const chapters = scenes.filter(s => s.chapter).map(({ chapter: title, start }) => ({ title, start }));
writeFileSync(join(out, 'chapters.json'), JSON.stringify({ duration: position, chapters }, null, 2) + '\n');
// The guide page lists the chapters so viewers can jump to each part.
const guideJs = join(root, 'assets/js/guia-conductores.js');
const js = readFileSync(guideJs, 'utf8');
const chapterLine = /const chapterData = .*; \/\/ VIDEO_CHAPTERS/;
if (!chapterLine.test(js)) throw new Error('VIDEO_CHAPTERS marker not found in assets/js/guia-conductores.js');
writeFileSync(guideJs, js.replace(chapterLine, `const chapterData = ${JSON.stringify(chapters)}; // VIDEO_CHAPTERS`));
let playwright;
for (const candidate of [process.env.PLAYWRIGHT_PATH, 'playwright', 'playwright-core', '/Users/felixortuno/.npm/_npx/9833c18b2d85bc59/node_modules/playwright-core'].filter(Boolean)) {
  try { playwright = require(candidate); break; } catch {}
}
if (!playwright) throw new Error('Set PLAYWRIGHT_PATH to an installed Playwright module.');
const browser = await playwright.chromium.launch({ executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', headless: true, args: ['--disable-gpu', '--allow-file-access-from-files'] });
const page = await browser.newPage({ viewport: { width: 1280, height: 720 }, deviceScaleFactor: 1 });
await page.goto(pathToFileURL(join(root, 'propuesta-app-conductores-trimodos.html')).href);
await page.evaluate(() => document.fonts.ready);
await page.addStyleTag({ content: readFileSync(join(root, 'scripts/video-stage.css'), 'utf8') });
await page.evaluate(() => {
  const logo = document.querySelector('img[alt="Grupo Trimodos"]').src;
  document.body.innerHTML = `<main id="videoStage"><div class="video-brand"><img src="${logo}" alt="Grupo Trimodos" width="150" height="34"></div><div class="video-label">Demostración del prototipo · Datos de ejemplo</div><div class="video-copy"><p class="video-chapter"></p><h1></h1><p class="video-detail"></p><div class="video-rule"></div><div class="video-note"></div></div><div class="phone" id="videoPhone"></div><div id="videoPointer"></div><div class="video-footer"><strong>APP PARA CONDUCTORES</strong><span>Gestiones con el vehículo detenido</span></div><div class="video-progress"></div><svg width="0" height="0"><defs><linearGradient id="steel"><stop stop-color="#e0bb00"/><stop offset="1" stop-color="#fdda00"/></linearGradient><linearGradient id="mtl"><stop stop-color="#fdda00"/><stop offset="1" stop-color="#fdda00"/></linearGradient></defs></svg></main>`;
  window.renderVideo = (scene, relative, total, chapter) => {
    const p = relative / scene.duration;
    const switched = scene.next && p > (scene.nextAt || .5);
    const screen = switched ? scene.next : scene.screen;
    let segs = scene.twoTrucks && (screen !== 'detect') ? [[6.75,11.5,'4521 LKM'],[11.5,null,'7832 MHT']] : [[6.75,null,'4521 LKM']];
    if (screen === 'end') segs = [[6.75,11.5,'4521 LKM'],[11.5,14,'7832 MHT']];
    const state = V({ screen, segs, clock: scene.screen === 'login' || scene.screen === 'detect' ? '06:45' : '13:20', mode: scene.mode || 'start', svc: scene.serviceIncrement && p < .35 ? 2 : 3, tickets: [TK], full: scene.full ?? null, adr: scene.adr || false, trl: 'R-4410', tk: scene.scanTicket && p < .3 ? 1 : 2, tm: scene.taller && p > .25 ? 'Avería' : null, tf: !!scene.taller && p > .5, to: !!scene.taller && p > .65 });
    if (scene.pin) state.pin = '1984'.slice(0, Math.min(4, Math.floor(p * 8)));
    document.querySelector('.video-chapter').textContent = chapter;
    document.querySelector('.video-copy h1').textContent = scene.title;
    document.querySelector('.video-detail').textContent = scene.detail;
    document.querySelector('.video-note').textContent = scene.note || '';
    const host = document.querySelector('#videoPhone'); host.innerHTML = rDriver(state);
    // Explicit demo wording avoids presenting the DECA integration as already live here.
    if (screen === 'deca') {
      host.querySelector('.a-top-t small').textContent = 'DECA · acceso previsto desde esta app';
      host.querySelectorAll('.a-info')[1].innerHTML = `${I.shield}<span>Demostración del acceso a DECA. Aquí no se guardan datos ni se descarga una orden real.</span>`;
    }
    const scroll = switched ? (scene.nextScroll || 0) : (scene.scroll || 0) + ((scene.scrollTo ?? scene.scroll ?? 0) - (scene.scroll || 0)) * Math.max(0, Math.min(1, (p - .18) / .55));
    const body = host.querySelector('.a-body'); if (body) body.scrollTop = scroll;
    const target = switched ? (scene.nextTarget || '') : scene.taller && p > .7 ? scene.nextTarget : scene.target;
    const focus = target && host.querySelector(`[data-v="${target}"]`);
    const pointer = document.querySelector('#videoPointer'); pointer.style.opacity = '0';
    if (focus && p > .1) {
      const r = focus.getBoundingClientRect(), phone = host.getBoundingClientRect();
      if (r.top > phone.top + 42 && r.bottom < phone.bottom - 8) {
        focus.dataset.videoFocus = 'true';
        pointer.style.opacity = '.9'; pointer.style.left = `${r.right - Math.min(r.width / 2, 29) - 14}px`; pointer.style.top = `${r.top + r.height / 2 - 14}px`;
        pointer.style.transform = `scale(${p % .3 < .04 ? .75 : 1})`;
      }
    }
    const current = scene.start + relative;
    document.querySelector('.video-progress').style.width = `${current / total * 100}%`;
  };
});
const frames = [];
let chapter = '', chapterNo = 0;
for (let i = 0; i < scenes.length; i++) {
  const scene = scenes[i];
  if (scene.chapter) chapter = `${String(++chapterNo).padStart(2, '0')} · ${scene.chapter}`;
  console.log(`Capturing ${i + 1}/${scenes.length}: ${scene.title} (${scene.duration.toFixed(1)}s)`);
  for (let f = 0; f < scene.duration * fps; f++) {
    await page.evaluate(({ scene, relative, total, chapter }) => window.renderVideo(scene, relative, total, chapter), { scene, relative: f / fps, total: position, chapter });
    const file = join(work, `frame-${String(frames.length).padStart(5, '0')}.png`);
    await page.screenshot({ path: file }); frames.push(file);
    if (i === 0 && f === fps * 2) await page.screenshot({ path: join(out, 'demo-conductores-poster.jpg'), type: 'jpeg', quality: 90 });
  }
}
await browser.close();
writeFileSync(join(work, 'manifest.json'), JSON.stringify({ fps, width: 1280, height: 720, duration: position, frames, audio: [], output: join(out, 'demo-conductores.mp4') }));
execFileSync('/usr/bin/swift', ['-module-cache-path', join(work, 'swift-cache'), join(root, 'scripts/video-encode.swift'), join(work, 'manifest.json')], { stdio: 'inherit' });
console.log(`Completed ${position.toFixed(2)}s: ${join(out, 'demo-conductores.mp4')}`);
