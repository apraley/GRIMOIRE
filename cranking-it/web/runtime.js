// CRANKING IT web player: a browser implementation of the Playdate runtime
// pieces the game uses. Lua runs in wasmoon (Lua 5.4 on WebAssembly); this
// file provides the 1-bit framebuffer, drawing primitives, bitmap fonts,
// synthesized sound, saves, input and the 30 fps frame loop.
// The Lua side of the API lives in playdate_web.lua.
(function () {
  "use strict";
  const W = 400, H = 240;
  const BLACK = 0, WHITE = 1, CLEAR = 2, XOR = 3;

  // ------------------------------------------------------------------
  // images: pix 1 = white, 0 = black; mask 1 = opaque
  // ------------------------------------------------------------------
  const images = [];
  const freeIds = [];
  function makeImage(w, h, bg) {
    w = Math.max(1, Math.floor(w)); h = Math.max(1, Math.floor(h));
    const n = w * h;
    const img = { w, h, pix: new Uint8Array(n), mask: new Uint8Array(n) };
    if (bg === BLACK) img.mask.fill(1);
    else if (bg === WHITE) { img.pix.fill(1); img.mask.fill(1); }
    else img.pix.fill(1);
    return img;
  }
  function addImage(img) {
    const id = freeIds.length ? freeIds.pop() : images.length;
    images[id] = img;
    return id;
  }
  const screen = makeImage(W, H, WHITE);
  images[0] = screen;

  // ------------------------------------------------------------------
  // drawing context
  // ------------------------------------------------------------------
  function newCtx(t) {
    return { t, color: BLACK, pat: null, dither: -1, lw: 1, ox: 0, oy: 0, clip: null, mode: 0, bg: WHITE };
  }
  let ctx = newCtx(screen);
  const stack = [];

  const BAYER = [
    0, 32, 8, 40, 2, 34, 10, 42, 48, 16, 56, 24, 50, 18, 58, 26,
    12, 44, 4, 36, 14, 46, 6, 38, 60, 28, 52, 20, 62, 30, 54, 22,
    3, 35, 11, 43, 1, 33, 9, 41, 51, 19, 59, 27, 49, 17, 57, 25,
    15, 47, 7, 39, 13, 45, 5, 37, 63, 31, 55, 23, 61, 29, 53, 21,
  ];

  function plot(x, y, force) {
    x = Math.floor(x); y = Math.floor(y);
    const t = ctx.t;
    if (x < 0 || y < 0 || x >= t.w || y >= t.h) return;
    const c = ctx.clip;
    if (c && (x < c[0] || y < c[1] || x >= c[0] + c[2] || y >= c[1] + c[3])) return;
    let color = force === undefined ? ctx.color : force;
    if (force === undefined) {
      const p = ctx.pat;
      if (p) {
        const bit = (p[y & 7] >> (7 - (x & 7))) & 1;
        if (p.length === 16 && ((p[8 + (y & 7)] >> (7 - (x & 7))) & 1) === 0) return;
        color = bit ? WHITE : BLACK;
      } else if (ctx.dither >= 0) {
        const th = (BAYER[((y & 7) << 3) | (x & 7)] + 0.5) / 64;
        if (ctx.color === WHITE) { if (th < ctx.dither) return; color = WHITE; }
        else { if (th >= ctx.dither) return; color = BLACK; }
      }
    }
    const i = y * t.w + x;
    if (color === CLEAR) { t.mask[i] = 0; return; }
    if (color === XOR) { t.pix[i] ^= 1; t.mask[i] = 1; return; }
    t.pix[i] = color === BLACK ? 0 : 1;
    t.mask[i] = 1;
  }

  function hspan(x0, x1, y) {
    if (x1 < x0) { const s = x0; x0 = x1; x1 = s; }
    x0 = Math.ceil(x0 - 0.0001); x1 = Math.floor(x1);
    const t = ctx.t;
    if (y < 0 || y >= t.h) return;
    if (x0 < 0) x0 = 0;
    if (x1 >= t.w) x1 = t.w - 1;
    for (let x = x0; x <= x1; x++) plot(x, y);
  }

  function solidFast() { return !ctx.pat && ctx.dither < 0 && (ctx.color === BLACK || ctx.color === WHITE); }

  function fillRectAbs(x, y, w, h) {
    x = Math.floor(x); y = Math.floor(y); w = Math.floor(w); h = Math.floor(h);
    if (w < 0) { x += w; w = -w; }
    if (h < 0) { y += h; h = -h; }
    const t = ctx.t;
    let x0 = Math.max(0, x), x1 = Math.min(t.w - 1, x + w - 1);
    let y0 = Math.max(0, y), y1 = Math.min(t.h - 1, y + h - 1);
    const c = ctx.clip;
    if (c) { x0 = Math.max(x0, c[0]); y0 = Math.max(y0, c[1]); x1 = Math.min(x1, c[0] + c[2] - 1); y1 = Math.min(y1, c[1] + c[3] - 1); }
    if (x1 < x0 || y1 < y0) return;
    if (solidFast()) {
      const v = ctx.color === BLACK ? 0 : 1;
      for (let yy = y0; yy <= y1; yy++) {
        const row = yy * t.w;
        t.pix.fill(v, row + x0, row + x1 + 1);
        t.mask.fill(1, row + x0, row + x1 + 1);
      }
      return;
    }
    for (let yy = y0; yy <= y1; yy++) for (let xx = x0; xx <= x1; xx++) plot(xx, yy);
  }

  function stamp(x, y, lw) {
    if (lw <= 1) { plot(x, y); return; }
    const r = lw / 2;
    for (let yy = Math.floor(y - r + 0.5); yy <= Math.floor(y + r - 0.5); yy++)
      for (let xx = Math.floor(x - r + 0.5); xx <= Math.floor(x + r - 0.5); xx++) plot(xx, yy);
  }

  function lineAbs(x1, y1, x2, y2) {
    const lw = Math.max(1, Math.floor(ctx.lw));
    const dx = x2 - x1, dy = y2 - y1;
    let n = Math.min(Math.ceil(Math.max(Math.abs(dx), Math.abs(dy))), 2000);
    if (n === 0) { stamp(Math.floor(x1 + 0.5), Math.floor(y1 + 0.5), lw); return; }
    for (let i = 0; i <= n; i++) stamp(Math.floor(x1 + dx * i / n + 0.5), Math.floor(y1 + dy * i / n + 0.5), lw);
  }

  const xs = new Float64Array(256);
  function fillPolyAbs(pts) {
    const n = pts.length >> 1;
    if (n < 3) return;
    let miny = Infinity, maxy = -Infinity;
    for (let i = 0; i < n; i++) { const y = pts[i * 2 + 1]; if (y < miny) miny = y; if (y > maxy) maxy = y; }
    const t = ctx.t;
    miny = Math.max(0, Math.floor(miny)); maxy = Math.min(t.h - 1, Math.ceil(maxy));
    for (let y = miny; y <= maxy; y++) {
      const sy = y + 0.5;
      let cnt = 0;
      for (let i = 0; i < n; i++) {
        const ax = pts[i * 2], ay = pts[i * 2 + 1];
        const j = (i + 1) % n;
        const bx = pts[j * 2], by = pts[j * 2 + 1];
        if ((ay <= sy && by > sy) || (by <= sy && ay > sy)) {
          if (cnt < 256) xs[cnt++] = ax + (sy - ay) / (by - ay) * (bx - ax);
        }
      }
      const arr = Array.prototype.slice.call(xs, 0, cnt).sort((a, b) => a - b);
      for (let k = 0; k + 1 < cnt; k += 2) hspan(arr[k], arr[k + 1] - 0.5, y);
    }
  }

  function ellipseFill(cx, cy, rx, ry, a0, a1) {
    if (rx <= 0 || ry <= 0) return;
    const t = ctx.t;
    const hasArc = a0 !== undefined && a0 !== null;
    for (let y = Math.floor(cy - ry); y <= Math.ceil(cy + ry); y++) {
      if (y < 0 || y >= t.h) continue;
      const dy = (y + 0.5 - cy) / ry;
      if (dy < -1 || dy > 1) continue;
      const span = rx * Math.sqrt(1 - dy * dy);
      if (!hasArc) { hspan(cx - span, cx + span - 0.5, y); continue; }
      // sector test with cross products (angles: 0 = up, clockwise)
      const s = ((a0 % 360) + 360) % 360, e = ((a1 % 360) + 360) % 360;
      const sweep = s <= e ? e - s : e + 360 - s;
      const ax = Math.sin(s * Math.PI / 180), ay = -Math.cos(s * Math.PI / 180);
      const bx = Math.sin(e * Math.PI / 180), by = -Math.cos(e * Math.PI / 180);
      const py = y + 0.5 - cy;
      const xa = Math.floor(cx - span), xb = Math.ceil(cx + span);
      for (let x = xa; x <= xb; x++) {
        const px = x + 0.5 - cx;
        const ddx = px / rx;
        if (ddx * ddx + dy * dy > 1) continue;
        const c1 = ax * py - ay * px;   // >= 0: P is clockwise of A
        const c2 = px * by - py * bx;   // >= 0: B is clockwise of P
        const inside = sweep <= 180 ? (c1 >= 0 && c2 >= 0) : !(c1 < 0 && c2 < 0);
        if (inside) plot(x, y);
      }
    }
  }

  function ellipseStroke(cx, cy, rx, ry, a0, a1) {
    const lw = Math.max(1, Math.floor(ctx.lw));
    const steps = Math.max(16, Math.floor((rx + ry) * 3));
    let s = 0, e = 360;
    if (a0 !== undefined && a0 !== null) { s = a0; e = a1; if (e < s) e += 360; }
    for (let i = 0; i <= steps; i++) {
      const a = (s + (e - s) * i / steps) * Math.PI / 180;
      stamp(Math.floor(cx + Math.sin(a) * rx), Math.floor(cy - Math.cos(a) * ry), lw);
    }
  }

  function modeColor(v) {
    switch (ctx.mode) {
      case 0: return v;
      case 1: return v === 0 ? 0 : -1;          // white transparent
      case 2: return v === 1 ? 1 : -1;          // black transparent
      case 3: return WHITE;                     // fill white
      case 4: return BLACK;                     // fill black
      case 5: return v === 1 ? XOR : -1;        // XOR
      case 6: return v === 0 ? XOR : -1;        // NXOR
      case 7: return 1 - v;                     // inverted
      default: return v;
    }
  }

  function blit(img, dx, dy, flip, sx0, sy0, sw, sh, alpha) {
    dx = Math.floor(dx + ctx.ox); dy = Math.floor(dy + ctx.oy);
    sx0 = sx0 || 0; sy0 = sy0 || 0;
    sw = sw || img.w; sh = sh || img.h;
    const fx = flip === 1 || flip === 3, fy = flip === 2 || flip === 3;
    const t = ctx.t;
    for (let y = 0; y < sh; y++) {
      const ty = dy + y;
      if (ty < 0 || ty >= t.h) continue;
      const iy = fy ? sy0 + sh - 1 - y : sy0 + y;
      if (iy < 0 || iy >= img.h) continue;
      for (let x = 0; x < sw; x++) {
        const tx = dx + x;
        if (tx < 0 || tx >= t.w) continue;
        const ix = fx ? sx0 + sw - 1 - x : sx0 + x;
        if (ix < 0 || ix >= img.w) continue;
        const i = iy * img.w + ix;
        if (!img.mask[i]) continue;
        if (alpha !== undefined && (BAYER[((ty & 7) << 3) | (tx & 7)] + 0.5) / 64 >= alpha) continue;
        const c = modeColor(img.pix[i]);
        if (c < 0) continue;
        plot(tx, ty, c);
      }
    }
  }

  // ------------------------------------------------------------------
  // fonts (pre-rendered 1-bit atlas, see make_font.py)
  // ------------------------------------------------------------------
  const FONT = window.CRANK_FONT;
  const fonts = FONT.fonts.map((f) => {
    const g = [];
    for (let c = 32; c < 127; c++) g[c] = f[c];
    return g;
  });
  const FONT_H = FONT.height;
  function glyph(fid, code) { const g = fonts[fid][code]; return g || fonts[fid][63]; }
  function textWidth(fid, s, tracking) {
    let maxw = 0, w = 0;
    for (let i = 0; i < s.length; i++) {
      const code = s.charCodeAt(i);
      if (code === 10) { if (w > maxw) maxw = w; w = 0; continue; }
      w += glyph(fid, code)[0] + tracking;
    }
    return Math.max(maxw, w);
  }
  function drawText(fid, s, x, y, tracking, leading) {
    let color;
    const m = ctx.mode;
    if (m === 3 || m === 7) color = WHITE; else if (m === 5 || m === 6) color = XOR; else color = BLACK;
    let cx = x, cy = y;
    const ox = ctx.ox, oy = ctx.oy;
    for (let i = 0; i < s.length; i++) {
      const code = s.charCodeAt(i);
      if (code === 10) { cx = x; cy += FONT_H + leading; continue; }
      const g = glyph(fid, code);
      const rows = g[2], w = g[1];
      for (let r = 0; r < FONT_H; r++) {
        const bits = rows[r];
        if (!bits) continue;
        for (let k = 0; k < w; k++) if ((bits >> k) & 1) plot(cx + k + ox, cy + r + oy, color);
      }
      cx += g[0] + tracking;
    }
    return cx - x;
  }

  // ------------------------------------------------------------------
  // sound: each Lua synth is a voice slot; notes are short-lived nodes
  // ------------------------------------------------------------------
  let actx = null, master = null, noiseBuf = null;
  const synths = [];
  function audioReady() {
    if (actx) return true;
    return false;
  }
  function startAudio() {
    if (actx) { if (actx.state === "suspended") actx.resume(); return; }
    try {
      actx = new (window.AudioContext || window.webkitAudioContext)();
      master = actx.createGain();
      master.gain.value = 0.35;
      master.connect(actx.destination);
      noiseBuf = actx.createBuffer(1, actx.sampleRate, actx.sampleRate);
      const d = noiseBuf.getChannelData(0);
      for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
    } catch (e) { actx = null; }
  }
  const WAVES = ["square", "triangle", "sine", "noise", "sawtooth"];
  function voiceStop(v, at) {
    if (!v) return;
    const s = v.synth;
    const t = Math.max(at, actx.currentTime);
    try {
      v.gain.gain.cancelScheduledValues(t);
      v.gain.gain.setValueAtTime(v.gain.gain.value, t);
      v.gain.gain.linearRampToValueAtTime(0, t + Math.max(0.005, s.r));
      v.src.stop(t + Math.max(0.005, s.r) + 0.02);
    } catch (e) {}
  }
  function playNote(id, freq, vol, len, when) {
    const s = synths[id];
    if (!s || !actx || muted) return;
    const now = actx.currentTime;
    const t0 = when > 0 ? Math.max(now, when) : now;
    vol = Math.max(0, Math.min(1, vol));
    // legato: glide the held note instead of retriggering
    if (s.legato && s.held && len < 0) {
      try {
        if (s.held.osc) s.held.osc.frequency.setTargetAtTime(freq, t0, 0.01);
        if (s.held.filter) s.held.filter.frequency.setTargetAtTime(Math.min(18000, freq * 2), t0, 0.01);
        s.held.gain.gain.setTargetAtTime(vol * s.vol * s.sus, t0, 0.02);
      } catch (e) {}
      return;
    }
    if (s.held) { voiceStop(s.held, t0); s.held = null; }
    const gain = actx.createGain();
    gain.gain.value = 0;
    let src, osc = null, filter = null;
    if (s.wave === 3) {
      src = actx.createBufferSource();
      src.buffer = noiseBuf;
      src.loop = true;
      filter = actx.createBiquadFilter();
      filter.type = "lowpass";
      filter.frequency.value = Math.min(18000, Math.max(80, freq * 2));
      src.connect(filter); filter.connect(gain);
    } else {
      osc = actx.createOscillator();
      osc.type = WAVES[s.wave] || "square";
      osc.frequency.value = Math.max(1, freq);
      src = osc;
      src.connect(gain);
    }
    gain.connect(master);
    const peak = vol * s.vol * (s.wave === 0 || s.wave === 4 ? 0.5 : 1);
    const a = Math.max(0.001, s.a), d = Math.max(0.001, s.d);
    const g = gain.gain;
    g.setValueAtTime(0, t0);
    g.linearRampToValueAtTime(peak, t0 + a);
    g.linearRampToValueAtTime(peak * s.sus, t0 + a + d);
    src.start(t0);
    const v = { src, gain, osc, filter, synth: s };
    if (len >= 0) {
      const end = t0 + Math.max(len, a + 0.001);
      g.setValueAtTime(peak * s.sus, end);
      g.linearRampToValueAtTime(0, end + Math.max(0.005, s.r));
      src.stop(end + Math.max(0.005, s.r) + 0.05);
    } else {
      s.held = v;
    }
  }

  // ------------------------------------------------------------------
  // input state
  // ------------------------------------------------------------------
  const input = {
    held: 0, prev: 0, cur: 0, pressed: 0, released: 0, downLatch: 0,
    crankAcc: 0, crankChange: 0, crankPos: 0, docked: false,
    keyCrank: 0,
  };
  let muted = false;

  // ------------------------------------------------------------------
  // the Lua-facing API (all arguments and results are plain values)
  // ------------------------------------------------------------------
  const api = {
    R_newImage: (w, h, bg) => addImage(makeImage(w, h, bg)),
    R_free: (id) => { if (id > 0 && images[id]) { images[id] = null; freeIds.push(id); } },
    R_imgW: (id) => images[id].w,
    R_imgH: (id) => images[id].h,
    R_copy: (id) => {
      const s = images[id];
      const c = { w: s.w, h: s.h, pix: s.pix.slice(), mask: s.mask.slice() };
      return addImage(c);
    },
    R_imgClear: (id, c) => {
      const t = images[id];
      if (c === CLEAR) { t.mask.fill(0); return; }
      t.pix.fill(c === BLACK ? 0 : 1); t.mask.fill(1);
    },
    R_sample: (id, x, y) => {
      const t = images[id];
      if (x < 0 || y < 0 || x >= t.w || y >= t.h) return CLEAR;
      const i = y * t.w + x;
      if (!t.mask[i]) return CLEAR;
      return t.pix[i] ? WHITE : BLACK;
    },
    R_invert: (id) => { const t = images[id]; for (let i = 0; i < t.pix.length; i++) t.pix[i] ^= 1; },
    R_removeMask: (id) => images[id].mask.fill(1),
    R_scaled: (id, s, sy) => {
      const src = images[id];
      const nw = Math.max(1, Math.floor(src.w * s)), nh = Math.max(1, Math.floor(src.h * sy));
      const c = makeImage(nw, nh, CLEAR);
      for (let y = 0; y < nh; y++) for (let x = 0; x < nw; x++) {
        const i = Math.floor(y / sy) * src.w + Math.floor(x / s);
        c.pix[y * nw + x] = src.pix[i]; c.mask[y * nw + x] = src.mask[i];
      }
      return addImage(c);
    },
    R_draw: (id, x, y, flip, sx, sy, sw, sh) => blit(images[id], x, y, flip || 0, sx, sy, sw, sh),
    R_drawFaded: (id, x, y, alpha, flip) => blit(images[id], x, y, flip || 0, 0, 0, 0, 0, alpha),
    R_drawScaled: (id, x, y, s, sy) => {
      const img = images[id];
      const nw = Math.floor(img.w * s), nh = Math.floor(img.h * sy);
      x = Math.floor(x + ctx.ox); y = Math.floor(y + ctx.oy);
      for (let yy = 0; yy < nh; yy++) for (let xx = 0; xx < nw; xx++) {
        const i = Math.floor(yy / sy) * img.w + Math.floor(xx / s);
        if (!img.mask[i]) continue;
        const c = modeColor(img.pix[i]);
        if (c >= 0) plot(x + xx, y + yy, c);
      }
    },
    R_drawRotated: (id, x, y, angle, s, sy) => {
      const img = images[id];
      const a = angle * Math.PI / 180, ca = Math.cos(a), sa = Math.sin(a);
      const rad = Math.ceil(Math.sqrt(img.w * img.w * s * s + img.h * img.h * sy * sy) / 2) + 1;
      const cx = x + ctx.ox, cy = y + ctx.oy;
      for (let yy = -rad; yy <= rad; yy++) for (let xx = -rad; xx <= rad; xx++) {
        const u = (ca * xx + sa * yy) / s + img.w / 2;
        const v = (-sa * xx + ca * yy) / sy + img.h / 2;
        const iu = Math.floor(u), iv = Math.floor(v);
        if (iu < 0 || iv < 0 || iu >= img.w || iv >= img.h) continue;
        const i = iv * img.w + iu;
        if (!img.mask[i]) continue;
        const c = modeColor(img.pix[i]);
        if (c >= 0) plot(Math.floor(cx + xx), Math.floor(cy + yy), c);
      }
    },

    R_push: (id) => { stack.push(ctx); const n = newCtx(id >= 0 ? images[id] : ctx.t); if (id < 0) Object.assign(n, ctx); ctx = n; },
    R_pop: () => { if (stack.length) ctx = stack.pop(); },
    R_depth: () => stack.length,

    R_setColor: (c) => { ctx.color = c; ctx.pat = null; ctx.dither = -1; },
    R_getColor: () => ctx.color,
    R_setPattern: function () { const p = new Uint8Array(arguments.length); for (let i = 0; i < arguments.length; i++) p[i] = arguments[i]; ctx.pat = p; ctx.dither = -1; },
    R_setDither: (a) => { ctx.dither = a; ctx.pat = null; },
    R_setLW: (w) => { ctx.lw = w; },
    R_getLW: () => ctx.lw,
    R_setOffset: (x, y) => { ctx.ox = x; ctx.oy = y; },
    R_getOX: () => ctx.ox,
    R_getOY: () => ctx.oy,
    R_setClip: (x, y, w, h) => { ctx.clip = [Math.floor(x + ctx.ox), Math.floor(y + ctx.oy), Math.floor(w), Math.floor(h)]; },
    R_setScreenClip: (x, y, w, h) => { ctx.clip = [Math.floor(x), Math.floor(y), Math.floor(w), Math.floor(h)]; },
    R_clearClip: () => { ctx.clip = null; },
    R_getClip: (i) => ctx.clip ? ctx.clip[i] : [0, 0, ctx.t.w, ctx.t.h][i],
    R_setMode: (m) => { ctx.mode = m; },
    R_getMode: () => ctx.mode,
    R_setBG: (c) => { ctx.bg = c; },
    R_getBG: () => ctx.bg,

    R_clear: (c) => {
      const t = ctx.t;
      if (c === undefined || c === null) c = ctx.bg;
      if (c === CLEAR) t.mask.fill(0); else { t.pix.fill(c === BLACK ? 0 : 1); t.mask.fill(1); }
    },
    R_fillRect: (x, y, w, h) => fillRectAbs(x + ctx.ox, y + ctx.oy, w, h),
    R_drawRect: (x, y, w, h) => {
      const lw = Math.max(1, Math.floor(ctx.lw));
      const fx = x + ctx.ox, fy = y + ctx.oy;
      fillRectAbs(fx, fy, w, lw); fillRectAbs(fx, fy + h - lw, w, lw);
      fillRectAbs(fx, fy, lw, h); fillRectAbs(fx + w - lw, fy, lw, h);
    },
    R_drawLine: (x1, y1, x2, y2) => lineAbs(x1 + ctx.ox, y1 + ctx.oy, x2 + ctx.ox, y2 + ctx.oy),
    R_drawPixel: (x, y) => plot(x + ctx.ox, y + ctx.oy),
    R_fillPoly: function () {
      const n = arguments.length;
      const pts = new Array(n);
      for (let i = 0; i < n; i += 2) { pts[i] = arguments[i] + ctx.ox; pts[i + 1] = arguments[i + 1] + ctx.oy; }
      fillPolyAbs(pts);
    },
    R_drawPoly: function () {
      const n = arguments.length >> 1;
      for (let i = 0; i < n; i++) {
        const j = (i + 1) % n;
        lineAbs(arguments[i * 2] + ctx.ox, arguments[i * 2 + 1] + ctx.oy, arguments[j * 2] + ctx.ox, arguments[j * 2 + 1] + ctx.oy);
      }
    },
    R_ellipseFill: (cx, cy, rx, ry, a0, a1) => ellipseFill(cx + ctx.ox, cy + ctx.oy, rx, ry, a0, a1),
    R_ellipseStroke: (cx, cy, rx, ry, a0, a1) => ellipseStroke(cx + ctx.ox, cy + ctx.oy, rx, ry, a0, a1),
    R_fillRoundRect: (x, y, w, h, r) => {
      x += ctx.ox; y += ctx.oy;
      r = Math.min(r, w / 2, h / 2);
      for (let yy = Math.floor(y); yy <= Math.floor(y + h - 1); yy++) {
        let inset = 0, dy = -1;
        if (yy < y + r) dy = y + r - yy - 0.5; else if (yy > y + h - r - 1) dy = yy - (y + h - r - 1) - 0.5;
        if (dy > 0) inset = r - Math.sqrt(Math.max(0, r * r - dy * dy));
        hspan(x + inset, x + w - 1 - inset, yy);
      }
    },
    R_drawRoundRect: (x, y, w, h, r) => {
      const ox = ctx.ox, oy = ctx.oy;
      r = Math.min(r, w / 2, h / 2);
      lineAbs(x + r + ox, y + oy, x + w - 1 - r + ox, y + oy);
      lineAbs(x + r + ox, y + h - 1 + oy, x + w - 1 - r + ox, y + h - 1 + oy);
      lineAbs(x + ox, y + r + oy, x + ox, y + h - 1 - r + oy);
      lineAbs(x + w - 1 + ox, y + r + oy, x + w - 1 + ox, y + h - 1 - r + oy);
      const lw = Math.max(1, Math.floor(ctx.lw));
      const corner = (cx, cy, s) => {
        for (let i = 0; i <= 12; i++) {
          const a = (s + 90 * i / 12) * Math.PI / 180;
          stamp(Math.floor(cx + ox + Math.sin(a) * r + 0.5), Math.floor(cy + oy - Math.cos(a) * r + 0.5), lw);
        }
      };
      corner(x + r, y + r, 270); corner(x + w - 1 - r, y + r, 0);
      corner(x + w - 1 - r, y + h - 1 - r, 90); corner(x + r, y + h - 1 - r, 180);
    },

    R_fontH: () => FONT_H,
    R_textW: (fid, s, tracking) => textWidth(fid, String(s), tracking || 0),
    R_drawText: (fid, s, x, y, tracking, leading) => drawText(fid, String(s), x, y, tracking || 0, leading || 0),

    R_setInverted: (b) => { display.inverted = !!b; },
    R_setDisplayOffset: (x, y) => { display.ox = x; display.oy = y; },
    R_setFPS: (r) => { display.fps = r > 0 ? r : 30; },
    R_menuImage: (id) => { display.menuImage = id >= 0 ? api.R_copy(id) : -1; },

    R_btn: (k) => (k === 0 ? input.cur : k === 1 ? input.pressed : input.released),
    R_crankChange: () => input.crankChange,
    R_crankPos: () => input.crankPos,
    R_docked: () => input.docked,

    R_ms: () => Math.floor(performance.now() - bootTime),
    R_epoch: () => Math.floor(Date.now() / 1000) - 946684800,
    R_date: () => {
      const d = new Date();
      return [d.getFullYear(), d.getMonth() + 1, d.getDate(), ((d.getDay() + 6) % 7) + 1, d.getHours(), d.getMinutes(), d.getSeconds(), d.getMilliseconds()].join(",");
    },

    R_storeWrite: (name, s) => { try { localStorage.setItem("crankingit:" + name, s); return true; } catch (e) { return false; } },
    R_storeRead: (name) => { try { const v = localStorage.getItem("crankingit:" + name); return v === null ? undefined : v; } catch (e) { return undefined; } },
    R_storeDelete: (name) => { try { localStorage.removeItem("crankingit:" + name); return true; } catch (e) { return false; } },

    R_source: (path) => {
      const s = window.CRANK_SOURCES[path];
      return s === undefined ? undefined : s;
    },
    R_print: (s) => console.log("[lua]", s),

    A_new: (wave) => { synths.push({ wave: wave || 0, a: 0.002, d: 0.08, sus: 0, r: 0.05, vol: 1, legato: false, held: null }); return synths.length - 1; },
    A_play: (id, freq, vol, len, when) => playNote(id, freq, vol, len, when),
    A_off: (id) => { const s = synths[id]; if (s && s.held && actx) { voiceStop(s.held, actx.currentTime); s.held = null; } },
    A_adsr: (id, a, d, s, r) => { const v = synths[id]; if (v) { v.a = a; v.d = d; v.sus = s; v.r = r; } },
    A_vol: (id, v) => { const s = synths[id]; if (s) s.vol = v; },
    A_legato: (id, b) => { const s = synths[id]; if (s) s.legato = !!b; },
    A_time: () => (actx ? actx.currentTime : performance.now() / 1000),
    A_playing: (id) => { const s = synths[id]; return !!(s && s.held); },
  };

  // ------------------------------------------------------------------
  // presentation
  // ------------------------------------------------------------------
  const display = { inverted: false, ox: 0, oy: 0, fps: 30, menuImage: -1 };
  let bootTime = performance.now();

  function present(canvas, palette) {
    const g = canvas.getContext("2d");
    if (!present.data || present.canvas !== canvas) {
      present.data = g.createImageData(W, H);
      present.canvas = canvas;
    }
    const data = present.data.data;
    const [lr, lg, lb] = palette.light, [dr, dg, db] = palette.dark;
    const inv = display.inverted ? 1 : 0;
    const ox = Math.round(display.ox), oy = Math.round(display.oy);
    for (let y = 0; y < H; y++) {
      const sy = y - oy;
      for (let x = 0; x < W; x++) {
        const sx = x - ox;
        let v = 1;
        if (sx >= 0 && sy >= 0 && sx < W && sy < H) v = screen.pix[sy * W + sx];
        v ^= inv;
        const o = (y * W + x) * 4;
        if (v) { data[o] = lr; data[o + 1] = lg; data[o + 2] = lb; }
        else { data[o] = dr; data[o + 1] = dg; data[o + 2] = db; }
        data[o + 3] = 255;
      }
    }
    g.putImageData(present.data, 0, 0);
  }

  function imageToCanvas(id, canvas, palette) {
    const img = images[id];
    if (!img) return;
    const g = canvas.getContext("2d");
    const d = g.createImageData(img.w, img.h);
    const [lr, lg, lb] = palette.light, [dr, dg, db] = palette.dark;
    for (let i = 0; i < img.w * img.h; i++) {
      const v = img.mask[i] ? img.pix[i] : 1;
      d.data[i * 4] = v ? lr : dr; d.data[i * 4 + 1] = v ? lg : dg; d.data[i * 4 + 2] = v ? lb : db; d.data[i * 4 + 3] = 255;
    }
    g.putImageData(d, 0, 0);
  }

  // ------------------------------------------------------------------
  // boot
  // ------------------------------------------------------------------
  async function boot(opts) {
    const factory = new wasmoon.LuaFactory(opts.wasmUri);
    const lua = await factory.createEngine({ injectObjects: false, enableProxy: false });
    for (const k in api) lua.global.set(k, api[k]);
    await lua.doString(window.CRANK_SOURCES["__playdate_web"]);
    await lua.doString('import("main")');
    const update = await lua.doString("return playdate.update");
    const callbacks = await lua.doString("return __callbacks");
    bootTime = performance.now() - 0;
    return { lua, update, callbacks };
  }

  window.CrankRuntime = {
    W, H, api, input, display, boot, present, imageToCanvas, startAudio,
    setMuted: (m) => { muted = !!m; if (m) for (const s of synths) if (s.held && actx) { voiceStop(s.held, actx.currentTime); s.held = null; } },
    // a tap that starts and ends between two frames still counts as a press
    press: (b) => { input.held |= b; input.downLatch |= b; },
    release: (b) => { input.held &= ~b; },
    beginFrame: () => {
      const cur = input.held | input.downLatch;
      input.pressed = cur & ~input.prev;
      input.released = input.prev & ~cur;
      input.cur = cur;
      input.downLatch = 0;
      input.crankChange = input.crankAcc;
      input.crankAcc = 0;
    },
    endFrame: () => { input.prev = input.cur; },
    stackDepth: () => stack.length,
    resetStack: () => { while (stack.length) ctx = stack.pop(); },
  };
})();
