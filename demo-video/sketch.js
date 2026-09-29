/* =====================================================================
   Buildify — GitHub README brief  (REAL-FOOTAGE compositor)
   ~1280x720 · 30fps · loops · your real app recordings + screenshots
   framed in the brand motion (title cards, captions, particles, fades).

   Grounded sources (all real):
     clips/01-new-service.mp4    dashboard + "+ new service" (both paths)
     clips/02-model-download.mp4 model catalog -> CONTINUE -> download
     clips/03-start-online.mp4   START AI SERVER -> ONLINE + IP/port
     clips/05a-endpoints.jpg     network/tunnels/endpoints screenshot
     clips/05b-logs.jpg          runtime logs (tunnel active) screenshot
     clips/06-host-project.mp4   host-a-project wizard
   clip 4 (laptop terminal) is drawn in code, grounded in the real values
   from the screenshots (tailscale 100.90.69.71:8080, tinyllama, tunnel).
   Video segments auto-fit to the real clip length on load.
   ===================================================================== */

const W = 1280, H = 720, FPS = 30;

// ---- brand palette --------------------------------------------------
const WEB_BG = "#0a0a0f", TXT = "#E5E2E0", DIM = "#8E9192", WHITE = "#FFFFFF";
const CYAN = "#9ADFFF", VIOLET = "#A78BFA", EMERALD = "#5FF2B3", GREEN = "#10B981", AMBER = "#F5B451";

// ---- grounded values (from the real app / screenshots) --------------
const TAILSCALE = "100.90.69.71:8080";
const TUNNEL = "ending-carmen-performer-jungle.trycloudflare.com";
const MODEL = "tinyllama-1.1b-q4";

// ---- segment timeline (video durations auto-fit on load) ------------
// frame: 'title' | 'phone' | 'window' | 'outro'
// source: clip (video) | img [{src,fy}] (screenshots, ken-burns) | none (custom)
const SEG = [
  { id: "intro", dur: 3.5, frame: "title" },
  { id: "new-service",    dur: 5.5, trim: 3.0, frame: "phone",  clip: "clips/01-new-service.mp4", tag: "buildify",
    cap: ["One app.", "Host anything."], sub: "+ new service · run an AI model / host a project", note: "Dashboard → + new service" },
  { id: "model-download", dur: 6.0, trim: 4.5, frame: "phone",  clip: "clips/02-model-download.mp4", tag: "tinyllama · GGUF",
    cap: ["Pick an open model."], sub: "TinyLlama · Qwen2 · Phi-3 — quantized GGUF", note: "Model catalog → download" },
  { id: "start-online",   dur: 6.0, trim: 4.0, frame: "phone",  clip: "clips/03-start-online.mp4", tag: "ONLINE · :8080", tagDot: true,
    cap: ["Tap start.", "Your phone is a server."], sub: "0.0.0.0:8080 · OpenAI-compatible", note: "START AI SERVER → ONLINE" },
  { id: "call-it",        dur: 7.0, frame: "window", /* code terminal */
    cap: ["Call it from anywhere."], sub: "curl · Python & TypeScript SDKs · your phone answers", note: "laptop terminal (grounded)" },
  { id: "tunnel",         dur: 6.5, frame: "phone",  img: [{ src: "clips/05a-endpoints.jpg", fy: 0.47 }, { src: "clips/05b-logs.jpg", fy: 0.63 }], tag: "tunnel active", tagDot: true,
    cap: ["Go public — or stay private."], sub: "local · tailscale mesh · cloudflare public tunnel", note: "endpoints + tunnel" },
  { id: "host-project",   dur: 6.0, trim: 1.5, frame: "phone",  clip: "clips/06-host-project.mp4", tag: "LIVE endpoint", tagDot: true,
    cap: ["Or host your whole project."], sub: "GitHub / upload → build → live endpoint", note: "host-a-project wizard" },
  { id: "outro", dur: 3.0, frame: "outro" },
];

// ---- state ----------------------------------------------------------
let particles = [];
let videos = {};   // seg.id -> {el, ok}
let imgs = {};     // src -> {el, ok}
let canvasEl = null;
let clock0 = 0, paused = false, pauseAcc = 0, pausedAt = 0;
let curIdx = -1;
let fontsReady = false;
let muted = true, audioStarted = false;
let rec = null, recChunks = [], recording = false, recStop = 0;

// =====================================================================
function setup() {
  const c = createCanvas(W, H); c.parent("stage"); canvasEl = c.elt;
  frameRate(FPS); pixelDensity(1);

  for (let i = 0; i < 90; i++) particles.push({
    x: random(W), y: random(H), amp: random(6, 26), spd: floor(random(1, 4)),
    phase: random(TWO_PI), r: random(0.6, 2.2), a: random(30, 120),
  });

  for (const s of SEG) {
    if (s.clip) {
      const v = document.createElement("video");
      v.src = s.clip; v.muted = true; v.playsInline = true; v.preload = "auto";
      v.style.display = "none"; document.body.appendChild(v);
      const rec = { el: v, ok: false };
      v.addEventListener("loadeddata", () => (rec.ok = true));
      v.addEventListener("loadedmetadata", () => { if (isFinite(v.duration)) s.dur = Math.min(s.dur, Math.max(1, v.duration - (s.trim || 0) - 0.05)); });
      v.addEventListener("error", () => (rec.ok = false));
      videos[s.id] = rec;
    }
    if (s.img) for (const it of s.img) if (!imgs[it.src]) {
      const im = new Image(); const rec = { el: im, ok: false };
      im.onload = () => (rec.ok = true); im.onerror = () => (rec.ok = false); im.src = it.src;
      imgs[it.src] = rec;
    }
  }

  document.fonts.ready.then(() => (fontsReady = true));
  clock0 = performance.now();

  select("#play").mousePressed(togglePause);
  select("#restart").mousePressed(() => { setClock(0); curIdx = -1; });
  select("#mute").mousePressed(toggleMute);
  select("#rec").mousePressed(startRecording);
  setupAudio();
}

function keyPressed() {
  if (key === " ") togglePause();
  if (key === "r" || key === "R") startRecording();
  if (key === "m" || key === "M") toggleMute();
}

// ---- timeline (recomputed each frame so clip auto-fit reflows) ------
function timeline() { let starts = [], t = 0; for (const s of SEG) { starts.push(t); t += s.dur; } return { starts, total: t }; }

// ---- master clock ---------------------------------------------------
function now() { return (performance.now() - clock0 - pauseAcc) / 1000; }
function setClock(sec) { clock0 = performance.now() - sec * 1000 - pauseAcc; }
function togglePause() {
  paused = !paused;
  if (paused) { pausedAt = performance.now(); for (const k in videos) videos[k].el.pause(); }
  else { pauseAcc += performance.now() - pausedAt; }
  select("#play").html(paused ? "▶ play" : "⏸ pause");
}

// =====================================================================
function draw() {
  if (!fontsReady) { background(WEB_BG); fill(DIM); textAlign(CENTER, CENTER); textSize(16); textFont("monospace"); text("loading fonts…", W / 2, H / 2); return; }

  const { starts, total } = timeline();
  const t = now() % total;
  background(WEB_BG);
  drawParticles(t, total);

  let idx = 0; for (let i = 0; i < SEG.length; i++) if (t >= starts[i]) idx = i;
  const seg = SEG[idx], lt = t - starts[idx];
  if (idx !== curIdx) { curIdx = idx; onEnterSegment(seg); }

  try { drawSegment(seg, lt); }
  catch (err) {
    ga(1); console.error("draw error @ " + seg.id, err);
    fill("#ff5f57"); noStroke(); textFont("monospace"); textSize(15); textAlign(LEFT, TOP);
    text("error @ " + seg.id + ": " + (err && err.message), 30, 30, W - 60);
  }

  if (recording && performance.now() >= recStop) stopRecording();
}

function onEnterSegment(seg) {
  for (const k in videos) videos[k].el.pause();
  if (seg.clip && videos[seg.id] && videos[seg.id].ok) {
    const v = videos[seg.id].el;
    try { v.currentTime = seg.trim || 0; if (!paused) v.play().catch(() => {}); } catch (e) {}
  }
  if (!muted && audioStarted) cueAudioForSegment(seg.id);
}

// =====================================================================
function drawSegment(seg, lt) {
  const fin = easeOut(constrain(lt / 0.4, 0, 1));
  const fout = easeIn(1 - constrain((seg.dur - lt) / 0.4, 0, 1));
  const alpha = fin * (1 - fout);

  if (seg.frame === "title") { drawTitle(lt); return; }
  if (seg.frame === "outro") { drawOutro(lt); return; }

  ga(alpha);
  if (seg.frame === "phone")  drawPhoneSeg(seg, lt);
  if (seg.frame === "window") drawWindowSeg(seg, lt);
  drawCaption(seg, lt);
  ga(1);
}

// ---- intro / outro --------------------------------------------------
function drawTitle(lt) {
  const s = SEG[0];
  const inn = easeOut(constrain(lt / 0.6, 0, 1));
  const out = easeIn(1 - constrain((s.dur - lt) / 0.5, 0, 1));
  ga(inn * (1 - out));
  const t = now() / 40;
  textAlign(CENTER, CENTER);
  textFont("Geist Mono"); textSize(15);
  const pw = 300, px = W / 2 - pw / 2, py = H / 2 - 118;
  fill(255, 255, 255, 8); stroke(255, 255, 255, 28); strokeWeight(1); rr(px, py, pw, 34, 17); noStroke();
  fill(CYAN); circle(px + 22, py + 17, 7); fill(DIM); text("Open source · Private by design", W / 2 + 8, py + 18);
  textFont("Geist"); textStyle(BOLD); textSize(62);
  auroraText("Host anything —", W / 2, H / 2 - 26, t);
  fill(TXT); text("your AI, or your project.", W / 2, H / 2 + 40);
  textStyle(NORMAL); ga(1);
}

function drawOutro(lt) {
  const s = SEG[SEG.length - 1];
  const inn = easeOut(constrain(lt / 0.6, 0, 1));
  const out = easeIn(1 - constrain((s.dur - lt) / 0.4, 0, 1));
  ga(inn * (1 - out));
  textAlign(CENTER, CENTER);
  const mx = W / 2, my = H / 2 - 66;
  const g = drawingContext.createLinearGradient(mx - 34, my - 34, mx + 34, my + 34);
  g.addColorStop(0, CYAN); g.addColorStop(0.5, VIOLET); g.addColorStop(1, EMERALD);
  drawingContext.fillStyle = g; rectMode(CENTER); rr(mx, my, 68, 68, 18); rectMode(CORNER);
  fill(WEB_BG); rr(mx - 29, my - 29, 58, 58, 14);
  drawingContext.fillStyle = g; textFont("Geist"); textStyle(BOLD); textSize(46); text("B", mx, my + 2);
  fill(TXT); textSize(30); text("On your own device.", W / 2, H / 2 + 26);
  auroraText("Private by design.", W / 2, H / 2 + 70, now() / 40);
  textStyle(NORMAL); fill(DIM); textFont("Geist Mono"); textSize(16);
  text("Free · Open source · github.com/NavadeepDj/Buildify", W / 2, H / 2 + 130);
  ga(1);
}

// ---- phone-framed footage / screenshots + brand framing ------------
function drawPhoneSeg(seg, lt) {
  const pw = 300, ph = 640, px = 300, py = H / 2 - ph / 2;

  drawPhoneGlow(px, py, pw, ph);                         // soft animated cyan halo
  push(); fill("#050505"); stroke(255, 255, 255, 18); strokeWeight(1.5);
  rr(px - 6, py - 6, pw + 12, ph + 12, 34); noStroke(); pop();

  let drew = false;
  if (seg.clip) drew = drawVideoCover(seg, px, py, pw, ph, 26);
  else if (seg.img) drew = drawScreens(seg, lt, px, py, pw, ph, 26);
  if (!drew) placeholder(px, py, pw, ph, 26, seg);
  else drawScreenFx(px, py, pw, ph, 26);                 // vignette + scan sweep

  fill("#050505"); rr(px + pw / 2 - 34, py + 4, 68, 14, 7); // notch
  if (drew) drawCornerTag(px, py, pw, ph, seg);          // grounded status pill
}

// soft, slowly pulsing brand glow behind the phone
function drawPhoneGlow(px, py, pw, ph) {
  const pulse = 0.5 + 0.5 * sin(now() * 1.1);
  push(); const ctx = drawingContext; ctx.save();
  ctx.shadowColor = "rgba(154,223,255," + (0.30 + 0.14 * pulse) + ")";
  ctx.shadowBlur = 42 + 16 * pulse;
  noStroke(); fill(WEB_BG); rr(px - 6, py - 6, pw + 12, ph + 12, 34);
  ctx.restore(); pop();
}

// gentle vignette + a slow cyan light sweep, clipped to the screen
function drawScreenFx(x, y, w, h, r) {
  const ctx = drawingContext; ctx.save(); clipRoundRect(x, y, w, h, r);
  const vg = ctx.createRadialGradient(x + w / 2, y + h / 2, h * 0.24, x + w / 2, y + h / 2, h * 0.62);
  vg.addColorStop(0, "rgba(0,0,0,0)"); vg.addColorStop(1, "rgba(0,0,0,0.26)");
  ctx.fillStyle = vg; ctx.fillRect(x, y, w, h);
  const sy = y + ((now() * 0.10) % 1) * h;               // slow downward sweep
  const sg = ctx.createLinearGradient(0, sy - 46, 0, sy + 46);
  sg.addColorStop(0, "rgba(154,223,255,0)"); sg.addColorStop(0.5, "rgba(154,223,255,0.05)"); sg.addColorStop(1, "rgba(154,223,255,0)");
  ctx.fillStyle = sg; ctx.fillRect(x, sy - 46, w, 92);
  ctx.restore();
}

// small grounded status pill, bottom-left of the screen
function drawCornerTag(x, y, w, h, seg) {
  if (!seg.tag) return;
  push(); textFont("Geist Mono"); textSize(11); textAlign(LEFT, CENTER);
  const tw = textWidth(seg.tag) + (seg.tagDot ? 30 : 18);
  const bx = x + 12, by = y + h - 34;
  fill(10, 10, 15, 190); stroke(154, 223, 255, 70); strokeWeight(1); rr(bx, by, tw, 22, 11); noStroke();
  let tx = bx + 10;
  if (seg.tagDot) {
    const p = 3 + sin(now() * TWO_PI * 1.4) * 1.5;
    fill(16, 185, 129, 60); circle(bx + 13, by + 11, 12 + p); fill(GREEN); circle(bx + 13, by + 11, 7);
    tx = bx + 24;
  }
  fill(230); text(seg.tag, tx, by + 11);
  pop();
}

// ---- call-it scene: coded live phone (left) + terminal (right) ------
function drawWindowSeg(seg, lt) {
  // phone (coded, live, grounded)
  const px = 48, pw = 240, ph = 520, py = 100;
  push(); fill("#050505"); stroke(255, 255, 255, 18); strokeWeight(1.5);
  rr(px - 6, py - 6, pw + 12, ph + 12, 30); noStroke(); pop();
  push(); clipRoundRect(px, py, pw, ph, 24); drawCallPhone(px, py, pw, ph, lt); pop();
  fill("#050505"); rr(px + pw / 2 - 28, py + 3, 56, 12, 6); // notch

  // terminal window
  const tx = 372, ty = 104, tw = W - tx - 56, th = 432;
  push(); fill("#0E0E0D"); stroke(255, 255, 255, 16); strokeWeight(1); rr(tx, ty, tw, th, 14);
  fill("#2A2A29"); rr(tx, ty, tw, 34, 14); fill("#0E0E0D"); rect(tx, ty + 24, tw, 12);
  fill("#ff5f57"); circle(tx + 20, ty + 17, 11); fill("#febc2e"); circle(tx + 40, ty + 17, 11); fill("#28c840"); circle(tx + 60, ty + 17, 11);
  fill(DIM); textFont("Geist Mono"); textSize(12); textAlign(CENTER, CENTER); text("laptop — zsh", tx + tw / 2, ty + 17); pop();
  drawGroundedTerminal(tx, ty + 36, tw, th - 38, lt);

  // beam phone -> terminal
  drawBeam(px + pw + 2, py + 230, tx, ty + 130, now() / 40);
}

// a rich, animated Buildify "server running" screen (all values grounded)
function drawCallPhone(x, y, w, h, lt) {
  const t = now();
  noStroke(); fill("#131312"); rect(x, y, w, h);
  const pad = 12, ix = x + pad, iw = w - pad * 2;

  // top bar
  fill(TXT); textFont("Space Mono"); textStyle(BOLD); textSize(13); textAlign(LEFT, CENTER);
  text("buildify", ix + 14, y + 22);
  // compass-ish mark
  push(); stroke(TXT); strokeWeight(1.4); noFill();
  line(ix + 2, y + 27, ix + 6, y + 17); line(ix + 6, y + 17, ix + 10, y + 27); pop();
  textStyle(NORMAL); fill(DIM); textSize(9); textAlign(RIGHT, CENTER); text("edge server", x + w - 12, y + 22);

  // status card
  const c1 = y + 40, ch1 = 60;
  fill("#20201F"); rr(ix, c1, iw, ch1, 10);
  const pulse = 4 + sin(t * TWO_PI * 1.4) * 2;
  fill(16, 185, 129, 60); circle(ix + 22, c1 + 24, 20 + pulse);
  fill(GREEN); circle(ix + 22, c1 + 24, 10 + pulse * 0.5);
  fill(TXT); textFont("Space Mono"); textStyle(BOLD); textSize(12); textAlign(LEFT, CENTER);
  text("ONLINE", ix + 40, c1 + 20);
  // LIVE badge
  fill("#0e2a20"); rr(ix + iw - 52, c1 + 12, 44, 16, 8); fill(EMERALD); textSize(8); textAlign(CENTER, CENTER); text("LIVE", ix + iw - 30, c1 + 20);
  textStyle(NORMAL); fill(DIM); textSize(9.5); textAlign(LEFT, CENTER);
  text("model: tinyllama 1.1b q4", ix + 40, c1 + 38);
  text("0.0.0.0:8080", ix + 14, c1 + 52);

  // system status card
  const c2 = c1 + ch1 + 10, ch2 = 92;
  fill("#20201F"); rr(ix, c2, iw, ch2, 10);
  fill(DIM); textFont("Space Mono"); textSize(9); textAlign(LEFT, TOP); text("SYSTEM", ix + 12, c2 + 10);
  fill(TXT); textSize(11); text("8-core arm", ix + 12, c2 + 24);
  fill(GREEN); textAlign(RIGHT, TOP); textSize(10); text("⚡ 66%", ix + iw - 12, c2 + 10);
  // cpu bar (animated jitter)
  const cpu = 0.02 + 0.03 * (0.5 + 0.5 * sin(t * 5.0)) + 0.02 * (0.5 + 0.5 * sin(t * 11.0));
  bar(ix + 12, c2 + 44, iw - 24, "cpu", cpu, Math.round(cpu * 100) + "%");
  bar(ix + 12, c2 + 66, iw - 24, "ram", 6.5 / 11, "6.5 / 11 GB");

  // requests card (live counter + tok/s)
  const c3 = c2 + ch2 + 10, ch3 = 64;
  fill("#20201F"); rr(ix, c3, iw, ch3, 10);
  const reqs = 128 + floor(lt * 3) + (lt > 3 ? 14 : 0) + (lt > 5.6 ? 9 : 0);
  fill(CYAN); textFont("Space Mono"); textStyle(BOLD); textSize(24); textAlign(LEFT, TOP); text(reqs, ix + 12, c3 + 10);
  textStyle(NORMAL); fill(DIM); textSize(8.5); text("requests served", ix + 12, c3 + 40);
  fill(EMERALD); textFont("Space Mono"); textSize(16); textAlign(RIGHT, TOP); text("14.8", ix + iw - 12, c3 + 12);
  fill(DIM); textSize(8.5); text("tok/s", ix + iw - 12, c3 + 34);

  // mini live logs (append in step with the terminal calls)
  const c4 = c3 + ch3 + 10, ch4 = y + h - c4 - 12;
  fill("#0E0E0D"); rr(ix, c4, iw, ch4, 10);
  const logs = [
    [0.0, "listening 0.0.0.0:8080", DIM],
    [3.0, "POST /v1/chat/completions 200", GREEN],
    [3.4, "84 tok · 14.8 tok/s", DIM],
    [5.7, "discover ✓ 100.90.69.71", CYAN],
  ];
  textFont("Space Mono"); textSize(8.5); textAlign(LEFT, TOP);
  let ly = c4 + 10;
  for (const [tt, msg, col] of logs) {
    if (lt < tt) continue;
    const app = constrain((lt - tt) / 0.3, 0, 1);
    push(); ga(drawingContext.globalAlpha * app);
    fill(DIM); text("[buildify]", ix + 10, ly);
    fill(col); text(msg, ix + 10, ly + 11, iw - 20);
    pop();
    ly += 30;
  }
}

function bar(x, y, w, label, frac, valStr) {
  fill(DIM); textFont("Space Mono"); textSize(8.5); textAlign(LEFT, TOP); text(label, x, y);
  fill(TXT); textAlign(RIGHT, TOP); text(valStr, x + w, y);
  fill("#2A2A29"); rr(x, y + 12, w, 4, 2);
  fill(frac > 0.85 ? AMBER : WHITE); rr(x, y + 12, w * constrain(frac, 0, 1), 4, 2);
}

function drawGroundedTerminal(x, y, w, h, lt) {
  const cx = x + 22, cy = y + 24, lh = 23; let ln = 0;
  textAlign(LEFT, TOP); textFont("Geist Mono"); textSize(14);
  const put = (s, col) => { fill(col); text(s, cx, cy + ln * lh, w - 44); ln++; };
  const tw = (s, p) => { const n = floor(p * s.length); const car = p < 1 && frameCount % 16 < 8 ? "▌" : ""; return s.substring(0, n) + car; };

  // curl typed against the real tailscale endpoint
  const type = constrain((lt - 0.3) / 1.9, 0, 1);
  fill(EMERALD); text("➜", cx, cy); fill(TXT); text(tw("curl http://" + TAILSCALE + "/v1/chat/completions \\", type), cx + 22, cy, w - 60); ln = 1;
  if (type >= 1) {
    put('     -H "Content-Type: application/json" \\', DIM);
    put(`     -d '{"messages":[{"role":"user","content":"hi"}]}'`, DIM);
  }
  // response
  const resp = constrain((lt - 3.0) / 0.5, 0, 1);
  if (resp > 0) {
    push(); ga(drawingContext.globalAlpha * resp);
    put("", TXT);
    put("{", DIM);
    put('  "model": "' + MODEL + '",', CYAN);
    put('  "choices":[{"message":{"role":"assistant",', DIM);
    put('    "content":"Hi! How can I help you today?"}}],', TXT);
    put('  "timings":{"predicted_per_second":14.8}', DIM);
    put("}", DIM);
    pop();
  }
  // SDK auto-discovery
  const py = constrain((lt - 5.6) / 1.4, 0, 1);
  if (py > 0) {
    push(); ga(drawingContext.globalAlpha * min(1, py * 2));
    put("", TXT);
    fill(EMERALD); text("➜", cx, cy + ln * lh); fill(TXT); text(tw("python  # buildify-ai SDK: Buildify.discover()", py), cx + 22, cy + ln * lh, w - 60); ln++;
    if (py >= 1) put("→ connected: http://" + TAILSCALE + "  ✓", GREEN);
    pop();
  }
}

// ---- media helpers --------------------------------------------------
function drawVideoCover(seg, dx, dy, dw, dh, r) {
  const rec = videos[seg.id]; if (!rec || !rec.ok) return false;
  const v = rec.el; if (!v.videoWidth) return false;
  return blit(v, v.videoWidth, v.videoHeight, dx, dy, dw, dh, r, 1, 0.5, 0.5);
}

function drawScreens(seg, lt, dx, dy, dw, dh, r) {
  // two screenshots, split across the segment with a slow ken-burns push
  const n = seg.img.length, cross = 0.35;
  const frac = constrain(lt / seg.dur, 0, 0.999);
  const which = min(n - 1, floor(frac * n));
  const localStart = (which / n) * seg.dur, localDur = seg.dur / n;
  const lp = constrain((lt - localStart) / localDur, 0, 1);
  const it = seg.img[which], rec = imgs[it.src];
  if (!rec || !rec.ok || !rec.el.naturalWidth) return false;
  const z = lerp(1.18, 1.34, lp);           // slow push-in
  // crossfade from previous image at the boundary
  let a = 1;
  if (which > 0 && lp < cross) {
    a = lp / cross;
    const prev = seg.img[which - 1], prec = imgs[prev.src];
    if (prec && prec.ok && prec.el.naturalWidth) blit(prec.el, prec.el.naturalWidth, prec.el.naturalHeight, dx, dy, dw, dh, r, 1.34, prev.fy, 1);
  }
  return blit(rec.el, rec.el.naturalWidth, rec.el.naturalHeight, dx, dy, dw, dh, r, z, it.fy, a);
}

// draw source with cover + focal zoom; fx/fy focal (0..1), z zoom, a alpha
function blit(el, iw, ih, dx, dy, dw, dh, r, z, fy, a) {
  const scale = Math.max(dw / iw, dh / ih) * z;
  const sw = iw * scale, sh = ih * scale;
  let sx = dx + dw / 2 - 0.5 * iw * scale;          // horizontally centered
  let sy = dy + dh / 2 - (fy == null ? 0.5 : fy) * ih * scale;
  sx = Math.min(dx, Math.max(dx + dw - sw, sx));
  sy = Math.min(dy, Math.max(dy + dh - sh, sy));
  const ctx = drawingContext; ctx.save();
  if (r > 0) clipRoundRect(dx, dy, dw, dh, r); else { ctx.beginPath(); ctx.rect(dx, dy, dw, dh); ctx.clip(); }
  const prevA = ctx.globalAlpha; ctx.globalAlpha = prevA * a;
  try { ctx.drawImage(el, sx, sy, sw, sh); } catch (e) { ctx.restore(); return false; }
  ctx.globalAlpha = prevA; ctx.restore(); return true;
}

function placeholder(x, y, w, h, r, seg) {
  push(); fill("#141416"); if (r > 0) rr(x, y, w, h, r); else rect(x, y, w, h);
  stroke(255, 255, 255, 20); strokeWeight(1); drawingContext.setLineDash([6, 6]); noFill();
  if (r > 0) rr(x + 8, y + 8, w - 16, h - 16, r - 4); else rect(x + 8, y + 8, w - 16, h - 16);
  drawingContext.setLineDash([]); noStroke();
  fill(DIM); textAlign(CENTER, CENTER); textFont("Geist Mono"); textSize(13);
  text("loading: " + (seg.clip || (seg.img && seg.img[0].src) || seg.id), x + w / 2, y + h / 2 - 14, w - 30);
  fill(TXT); textSize(14); text(seg.note || seg.id, x + w / 2, y + h / 2 + 12, w - 30);
  pop();
}

// ---- caption / lower-third ------------------------------------------
function drawCaption(seg, lt) {
  if (!seg.cap) return;
  const a = easeOut(constrain((lt - 0.3) / 0.5, 0, 1)) * (1 - easeIn(1 - constrain((seg.dur - lt) / 0.5, 0, 1)));
  push(); ga(drawingContext.globalAlpha * a);

  if (seg.frame === "window") {
    // centered bottom lower-third (never overlaps the phone / terminal)
    textAlign(CENTER, CENTER); textFont("Geist"); textStyle(BOLD); textSize(34);
    fill(TXT); text(seg.cap.join(" "), W / 2, H - 66);
    textStyle(NORMAL);
    if (seg.sub) { fill(DIM); textFont("Geist Mono"); textSize(15); text(seg.sub, W / 2, H - 34); }
    pop(); return;
  }

  // phone scenes: caption to the right of the bezel
  const cx = 660; let cy = H / 2 - (seg.cap.length * 50) / 2 - 10;
  textAlign(LEFT, CENTER); textFont("Geist"); textStyle(BOLD);
  seg.cap.forEach((line, i) => {
    textSize(42);
    if (i === seg.cap.length - 1 && seg.cap.length > 1) auroraLeft(line, cx, cy + i * 50);
    else { fill(TXT); text(line, cx, cy + i * 50); }
  });
  textStyle(NORMAL);
  if (seg.sub) { fill(DIM); textFont("Geist Mono"); textSize(15); text(seg.sub, cx, cy + seg.cap.length * 50 + 16, 520); }
  pop();
}

// =====================================================================
// small helpers
// =====================================================================
function ga(v) { drawingContext.globalAlpha = v; }
function rr(x, y, w, h, r) { rect(x, y, w, h, r); }
function easeOut(t) { return 1 - pow(1 - t, 3); }
function easeIn(t) { return t * t * t; }
function clipRoundRect(x, y, w, h, r) {
  const c = drawingContext; c.beginPath(); c.moveTo(x + r, y);
  c.arcTo(x + w, y, x + w, y + h, r); c.arcTo(x + w, y + h, x, y + h, r);
  c.arcTo(x, y + h, x, y, r); c.arcTo(x, y, x + w, y, r); c.closePath(); c.clip();
}
function drawParticles(t, total) {
  const tt = t / total; push(); noStroke();
  for (const p of particles) {
    const px = p.x + sin(tt * TWO_PI * p.spd + p.phase) * p.amp;
    const py = p.y + cos(tt * TWO_PI * p.spd + p.phase) * p.amp;
    fill(154, 223, 255, p.a * 0.5); circle(px, py, p.r * 2);
  }
  pop();
}
function auroraText(str, cx, cy, t) {
  push(); const w = textWidth(str);
  const g = drawingContext.createLinearGradient(cx - w / 2, 0, cx + w / 2, 0);
  g.addColorStop(0, CYAN); g.addColorStop(constrain(0.5 + sin(t * TWO_PI) * 0.18, 0.05, 0.95), VIOLET); g.addColorStop(1, EMERALD);
  drawingContext.fillStyle = g; text(str, cx, cy); pop();
}
function auroraLeft(str, x, y) {
  push(); const w = textWidth(str);
  const g = drawingContext.createLinearGradient(x, 0, x + w, 0);
  g.addColorStop(0, CYAN); g.addColorStop(0.5, VIOLET); g.addColorStop(1, EMERALD);
  drawingContext.fillStyle = g; text(str, x, y); pop();
}
function drawBeam(x1, y1, x2, y2, t) {
  push(); const g = drawingContext.createLinearGradient(x1, y1, x2, y2);
  g.addColorStop(0, "rgba(154,223,255,0.15)"); g.addColorStop(1, "rgba(167,139,250,0.15)");
  drawingContext.strokeStyle = g; drawingContext.lineWidth = 1.5;
  drawingContext.beginPath(); drawingContext.moveTo(x1, y1); drawingContext.lineTo(x2, y2); drawingContext.stroke();
  const m = (t * 4) % 1, dx = lerp(x1, x2, m), dy = lerp(y1, y2, m);
  noStroke(); fill(CYAN); circle(dx, dy, 7); fill(154, 223, 255, 80); circle(dx, dy, 16); pop();
}

// =====================================================================
// audio (Tone.js) — live preview only; README export is silent
// =====================================================================
let pad, blip, chime;
function setupAudio() {
  try {
    pad = new Tone.PolySynth(Tone.Synth, { oscillator: { type: "sine" }, envelope: { attack: 1.2, decay: 0.4, sustain: 0.5, release: 2.5 }, volume: -26 }).toDestination();
    blip = new Tone.Synth({ oscillator: { type: "triangle" }, envelope: { attack: 0.001, decay: 0.08, sustain: 0, release: 0.05 }, volume: -20 }).toDestination();
    chime = new Tone.Synth({ oscillator: { type: "sine" }, envelope: { attack: 0.005, decay: 0.5, sustain: 0.1, release: 1.2 }, volume: -14 }).toDestination();
  } catch (e) {}
}
async function toggleMute() {
  muted = !muted; select("#mute").html(muted ? "🔇 sound off" : "🔊 sound on");
  if (!muted && !audioStarted) { try { await Tone.start(); audioStarted = true; } catch (e) {} }
}
function cueAudioForSegment(id) {
  try {
    if (id === "intro") pad && pad.triggerAttackRelease(["C4", "G4", "E5"], "2n");
    else if (id === "start-online") chime && chime.triggerAttackRelease("E6", "8n");
    else if (id === "tunnel") chime && chime.triggerAttackRelease("G6", "8n");
    else if (id === "outro") pad && pad.triggerAttackRelease(["C4", "E4", "G4", "C5"], "1n");
    else blip && blip.triggerAttackRelease("B5", "16n");
  } catch (e) {}
}

// =====================================================================
// recording — MediaRecorder on the canvas stream (captures real video)
// =====================================================================
function startRecording() {
  if (recording || !canvasEl) return;
  const stream = canvasEl.captureStream(FPS);
  const mime = MediaRecorder.isTypeSupported("video/webm;codecs=vp9") ? "video/webm;codecs=vp9" : "video/webm";
  rec = new MediaRecorder(stream, { mimeType: mime, videoBitsPerSecond: 8e6 });
  recChunks = []; rec.ondataavailable = (e) => e.data.size && recChunks.push(e.data);
  rec.onstop = () => {
    const blob = new Blob(recChunks, { type: "video/webm" });
    const url = URL.createObjectURL(blob); const a = document.createElement("a");
    a.href = url; a.download = "buildify-brief.webm"; a.click(); URL.revokeObjectURL(url);
  };
  if (paused) togglePause();
  setClock(0); curIdx = -1;
  const total = timeline().total;
  recording = true; recStop = performance.now() + total * 1000 + 300;
  rec.start(); select("#rec").html("● recording…");
}
function stopRecording() {
  recording = false; try { rec.stop(); } catch (e) {} select("#rec").html("● record webm");
}
