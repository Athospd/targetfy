"""Builds demo/targetfy-demo.mp4: a 10-second, voiceless promo with an
original synthesized soundtrack and the logo at the end.

    python demo/make-demo.py

Frames are drawn with Pillow, the music is synthesized with numpy, and R's
{av} package (bundled ffmpeg) encodes H.264 + AAC.
"""
import math
import pathlib
import shutil
import subprocess
import tempfile
import wave

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = pathlib.Path(__file__).parent
ROOT = HERE.parent
W, H, FPS, DUR = 1920, 1080, 30, 10.0
N = int(FPS * DUR)

BG_TOP, BG_BOTTOM = (34, 48, 74), (14, 20, 32)
TEAL = (60, 200, 180)
INK = (238, 243, 249)
MUTED = (116, 137, 168)
CARD = (24, 33, 50)
AMBER = (240, 190, 110)
PINK = (230, 140, 170)

FONTS = "C:/Windows/Fonts/"
mono = lambda s: ImageFont.truetype(FONTS + "CascadiaMono.ttf", s)
def sans(s, weight=600):
    f = ImageFont.truetype(FONTS + "bahnschrift.ttf", s)
    try:
        f.set_variation_by_axes([weight, 100])
    except Exception:
        pass
    return f

F_CODE, F_TAB, F_LABEL_2X = mono(34), mono(24), mono(52)
F_CAPTION, F_BADGE, F_TAG, F_URL = sans(64), sans(34, 500), sans(46, 500), mono(30)

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

def clamp(x, a=0.0, b=1.0):
    return max(a, min(b, x))

def prog(t, t0, t1):
    return clamp((t - t0) / (t1 - t0))

def ease(x):  # easeInOutCubic
    return 4 * x ** 3 if x < 0.5 else 1 - (-2 * x + 2) ** 3 / 2

def ease_out(x):
    return 1 - (1 - x) ** 3

def back_out(x, s=1.7):
    x -= 1
    return 1 + (s + 1) * x ** 3 + s * x ** 2

def mix(c, a):  # colour with alpha
    return (*c, int(255 * clamp(a)))

def background():
    g = np.linspace(0, 1, H)[:, None, None]
    top, bot = np.array(BG_TOP), np.array(BG_BOTTOM)
    img = (top * (1 - g) + bot * g).repeat(W, axis=1).astype(np.uint8)
    base = Image.fromarray(img, "RGB").convert("RGBA")
    # faint dot grid: the "technical" texture
    dots = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(dots)
    for x in range(40, W, 48):
        for y in range(40, H, 48):
            d.ellipse([x - 1.5, y - 1.5, x + 1.5, y + 1.5], fill=(255, 255, 255, 14))
    return Image.alpha_composite(base, dots)

BG = background()

def glow(size, colour, radius, alpha):
    g = Image.new("RGBA", size, (0, 0, 0, 0))
    ImageDraw.Draw(g).ellipse([radius, radius, size[0] - radius, size[1] - radius],
                              fill=mix(colour, alpha))
    return g.filter(ImageFilter.GaussianBlur(radius / 2))

GLOW = glow((1400, 900), TEAL, 260, 0.20)

def text_center(d, xy, s, font, fill):
    w = d.textlength(s, font=font)
    d.text((xy[0] - w / 2, xy[1]), s, font=font, fill=fill)

# ---------------------------------------------------------------------------
# scene content
# ---------------------------------------------------------------------------

CODE = [
    [("library", TEAL), ("(tidyverse)", INK)],
    [("sales ", INK), ("<-", MUTED), (" read_csv(", INK), ('"data/sales.csv"', AMBER), (")", INK)],
    [("sales ", INK), ("<-", MUTED), (" sales |> ", INK), ("filter", TEAL), ("(year > ", INK), ("2020", PINK), (")", INK)],
    [("model ", INK), ("<-", MUTED), (" ", INK), ("lm", TEAL), ("(revenue ~ region, sales)", INK)],
    [("plot  ", INK), ("<-", MUTED), (" ", INK), ("ggplot", TEAL), ("(sales, aes(region, revenue))", INK)],
    [("coefs ", INK), ("<-", MUTED), (" broom::", INK), ("tidy", TEAL), ("(model)", INK)],
    [("write_csv", TEAL), ("(coefs, ", INK), ('"out/coefs.csv"', AMBER), (")", INK)],
]
CODE_CHARS = sum(len(s) for line in CODE for s, _ in line)
COMMAND = "/targetfy analysis.R"

# DAG: name, x, y   (left to right, branching after sales_clean)
NODES = {
    "sales_file":  (300, 560),
    "sales":       (520, 560),
    "sales_clean": (740, 560),
    "model":       (980, 450),
    "plot":        (980, 680),
    "coefs":       (1200, 450),
    "coefs_file":  (1420, 450),
}
EDGES = [("sales_file", "sales"), ("sales", "sales_clean"),
         ("sales_clean", "model"), ("sales_clean", "plot"),
         ("model", "coefs"), ("coefs", "coefs_file")]
ORDER = list(NODES)
DAG_DX = 110  # shift the whole DAG right to centre it

def bezier(p0, p1, k):
    (x0, y0), (x1, y1) = p0, p1
    c0, c1 = (x0 + (x1 - x0) * 0.5, y0), (x0 + (x1 - x0) * 0.5, y1)
    pts = []
    for i in range(k + 1):
        u = i / k
        x = (1-u)**3*x0 + 3*(1-u)**2*u*c0[0] + 3*(1-u)*u**2*c1[0] + u**3*x1
        y = (1-u)**3*y0 + 3*(1-u)**2*u*c0[1] + 3*(1-u)*u**2*c1[1] + u**3*y1
        pts.append((x, y))
    return pts

LOGO = Image.open(ROOT / "man/figures/logo.png").convert("RGBA")

# ---------------------------------------------------------------------------
# frames
# ---------------------------------------------------------------------------

def draw_code_card(img, t):
    # in: 0.0-0.5 ; out: 3.4-4.0 (slides left and fades)
    a_in = ease_out(prog(t, 0.0, 0.5))
    a_out = ease(prog(t, 3.4, 4.0))
    alpha = a_in * (1 - a_out)
    if alpha <= 0:
        return
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    x0 = 300 - 120 * a_out + 40 * (1 - a_in)
    y0, cw, ch = 250, 1320, 560
    d.rounded_rectangle([x0, y0, x0 + cw, y0 + ch], 22, fill=mix(CARD, 0.96 * alpha),
                        outline=mix((255, 255, 255), 0.10 * alpha), width=2)
    for i, c in enumerate([(232, 106, 94), (240, 190, 90), (98, 196, 120)]):
        d.ellipse([x0 + 28 + i * 30, y0 + 24, x0 + 44 + i * 30, y0 + 40], fill=mix(c, alpha))
    d.text((x0 + 140, y0 + 18), "analysis.R", font=F_TAB, fill=mix(MUTED, alpha))
    d.line([x0, y0 + 62, x0 + cw, y0 + 62], fill=mix((255, 255, 255), 0.07 * alpha), width=2)

    # typing: 0.4-2.3 s
    shown = int(CODE_CHARS * ease_out(prog(t, 0.4, 2.3)))
    y, left = y0 + 92, shown
    for n, line in enumerate(CODE):
        x = x0 + 40
        d.text((x, y), f"{n + 1}", font=F_CODE, fill=mix((80, 96, 122), alpha))
        x += 60
        for s, col in line:
            part = s[:max(0, left)]
            left -= len(s)
            if part:
                d.text((x, y), part, font=F_CODE, fill=mix(col, alpha))
            x += d.textlength(s, font=F_CODE)
        y += 52

    # command bar: typed 2.5-3.2, flash at 3.25
    cp = prog(t, 2.45, 3.15)
    if cp > 0:
        by = y0 + ch + 34
        flash = math.exp(-max(0, t - 3.25) * 8) if t >= 3.25 else 0
        d.rounded_rectangle([x0, by, x0 + cw, by + 78], 16,
                            fill=mix(tuple(int(CARD[i] + (TEAL[i] - CARD[i]) * 0.35 * flash) for i in range(3)), alpha),
                            outline=mix(TEAL, (0.5 + 0.5 * flash) * alpha), width=2)
        typed = COMMAND[:int(len(COMMAND) * cp)]
        d.text((x0 + 34, by + 20), ">", font=F_CODE, fill=mix(TEAL, alpha))
        d.text((x0 + 80, by + 20), typed, font=F_CODE, fill=mix(INK, alpha))
        if cp < 1 and int(t * 4) % 2 == 0:
            cx = x0 + 80 + d.textlength(typed, font=F_CODE) + 4
            d.rectangle([cx, by + 22, cx + 16, by + 58], fill=mix(INK, alpha))
    img.alpha_composite(layer)

def draw_dag(img, t):
    if t < 3.5:
        return
    fade = 1 - ease(prog(t, 6.75, 7.15))
    if fade <= 0:
        return
    SS = 2  # drawn at 2x, then scaled down: smooth curves and circles
    layer = Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    start, step = 3.7, 0.32
    appear = {n: start + i * step for i, n in enumerate(ORDER)}
    pos = {n: ((x + DAG_DX) * SS, y * SS) for n, (x, y) in NODES.items()}
    # edges draw after their source node appears
    for a, b in EDGES:
        p = ease(prog(t, appear[a] + 0.08, appear[b] + 0.05))
        if p <= 0:
            continue
        if pos[a][1] == pos[b][1]:  # straight edge: one segment, no seams
            (x0, y0), (x1, _) = pos[a], pos[b]
            pts = [(x0, y0), (x0 + (x1 - x0) * p, y0)]
            k = 2
        else:
            pts = bezier(pos[a], pos[b], 80)
            k = max(2, int(len(pts) * p))
        d.line(pts[:k], fill=mix(INK, 0.85 * fade), width=6 * SS, joint="curve")
    for n in ORDER:
        p = prog(t, appear[n], appear[n] + 0.35)
        if p <= 0:
            continue
        s = back_out(p)
        x, y = pos[n]
        r = 26 * s * SS
        halo = 1 - p
        if halo > 0:
            g = 18 * p * SS
            d.ellipse([x - r - g, y - r - g, x + r + g, y + r + g],
                      outline=mix(TEAL, 0.6 * halo * fade), width=3 * SS)
        d.ellipse([x - r, y - r, x + r, y + r], fill=mix(TEAL, fade),
                  outline=mix(INK, fade), width=6 * SS)
        la = ease_out(prog(t, appear[n] + 0.1, appear[n] + 0.4)) * fade
        lw = d.textlength(n, font=F_LABEL_2X)
        ly = y - 84 * SS if n in ("model", "coefs", "coefs_file") else y + 48 * SS
        d.text((x - lw / 2, ly), n, font=F_LABEL_2X, fill=mix(INK, 0.9 * la))
    layer = layer.resize((W, H), Image.LANCZOS)
    d = ImageDraw.Draw(layer)
    # badge, with the check mark drawn (Bahnschrift has no check glyph)
    ba = ease_out(prog(t, 5.9, 6.3)) * fade
    if ba > 0:
        msg = "same results as your script  \u00b7  checked"
        tw = d.textlength(msg, font=F_BADGE) + 52
        bx, by = W / 2 - tw / 2 - 34, 870 + 20 * (1 - ba)
        d.rounded_rectangle([bx, by, bx + tw + 68, by + 70], 35, fill=mix((22, 60, 62), 0.95 * ba),
                            outline=mix(TEAL, ba), width=2)
        cx, cy = bx + 40, by + 35
        d.line([(cx, cy + 1), (cx + 10, cy + 11), (cx + 28, cy - 11)],
               fill=mix(TEAL, ba), width=6, joint="curve")
        d.text((bx + 34 + 52, by + 14), msg, font=F_BADGE, fill=mix(INK, ba))
    img.alpha_composite(layer)

def draw_captions(img, t):
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    a1 = ease_out(prog(t, 0.2, 0.7)) * (1 - ease(prog(t, 3.3, 3.7)))
    if a1 > 0:
        text_center(d, (W / 2, 120 - 14 * (1 - a1)), "Your R script.", F_CAPTION, mix(INK, a1))
    a2 = ease_out(prog(t, 3.7, 4.2)) * (1 - ease(prog(t, 6.75, 7.1)))
    if a2 > 0:
        s1, s2 = "Now a ", "{targets}"
        s3 = " pipeline."
        full = s1 + s2 + s3
        w = d.textlength(full, font=F_CAPTION)
        x, y = W / 2 - w / 2, 150 - 14 * (1 - a2)
        d.text((x, y), s1, font=F_CAPTION, fill=mix(INK, a2))
        x += d.textlength(s1, font=F_CAPTION)
        d.text((x, y), s2, font=F_CAPTION, fill=mix(TEAL, a2))
        x += d.textlength(s2, font=F_CAPTION)
        d.text((x, y), s3, font=F_CAPTION, fill=mix(INK, a2))
    img.alpha_composite(layer)

def draw_end(img, t):
    if t < 6.9:
        return
    p = prog(t, 7.0, 7.55)
    s = back_out(p, 1.4) if p > 0 else 0
    out = 1 - ease(prog(t, 9.6, 10.0))
    # glow behind logo
    ga = ease_out(prog(t, 6.9, 7.6)) * out
    if ga > 0:
        g = GLOW.copy()
        g.putalpha(g.getchannel("A").point(lambda v: int(v * ga)))
        img.alpha_composite(g, (W // 2 - 700, 420 - 450))
    if s > 0:
        h = int(520 * s)
        w = int(h * LOGO.width / LOGO.height)
        if h > 4:
            lg = LOGO.resize((w, h), Image.LANCZOS)
            if out < 1:
                lg.putalpha(lg.getchannel("A").point(lambda v: int(v * out)))
            img.alpha_composite(lg, (W // 2 - w // 2, 410 - h // 2))
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    ta = ease_out(prog(t, 7.5, 8.0)) * out
    if ta > 0:
        # the arrow is drawn: Bahnschrift has no arrow glyph
        a, b, gap = "R scripts", "{targets} pipelines. Verified.", 84
        wa, wb = d.textlength(a, font=F_TAG), d.textlength(b, font=F_TAG)
        x = W / 2 - (wa + gap + wb) / 2
        y = 720 + 16 * (1 - ta)
        d.text((x, y), a, font=F_TAG, fill=mix(INK, ta))
        ax0, ax1, ay = x + wa + 20, x + wa + gap - 20, y + 23
        d.line([(ax0, ay), (ax1, ay)], fill=mix(TEAL, ta), width=5)
        d.line([(ax1 - 12, ay - 11), (ax1, ay), (ax1 - 12, ay + 11)],
               fill=mix(TEAL, ta), width=5, joint="curve")
        d.text((x + wa + gap, y), b, font=F_TAG, fill=mix(INK, ta))
    ua = ease_out(prog(t, 7.9, 8.4)) * out
    if ua > 0:
        text_center(d, (W / 2, 800), "github.com/Athospd/targetfy", F_URL, mix(TEAL, ua))
    img.alpha_composite(layer)

def frame(i):
    t = i / FPS
    img = BG.copy()
    draw_code_card(img, t)
    draw_dag(img, t)
    draw_captions(img, t)
    draw_end(img, t)
    # global fade in from black
    fi = ease_out(prog(t, 0, 0.35))
    if fi < 1:
        img = Image.blend(Image.new("RGBA", (W, H), (0, 0, 0, 255)), img, fi)
    return img.convert("RGB")

# ---------------------------------------------------------------------------
# music: original, synthesized. 120 BPM, A minor: Am | F | C | G | Am
# ---------------------------------------------------------------------------

SR = 44100
BPM = 120
BEAT = 60 / BPM

def note(n):  # MIDI to Hz
    return 440.0 * 2 ** ((n - 69) / 12)

def env(n, a, d_):
    t = np.arange(n) / SR
    e = np.minimum(1, t / max(a, 1e-4)) * np.exp(-t / d_)
    return e

def add(buf, start, sig):
    i = int(start * SR)
    j = min(len(buf), i + len(sig))
    if i < len(buf):
        buf[i:j] += sig[: j - i]

def music():
    n = int(SR * DUR)
    L = np.zeros(n)
    R = np.zeros(n)
    rng = np.random.default_rng(7)
    chords = [(57, 60, 64), (53, 57, 60), (48, 52, 55), (55, 59, 62), (57, 60, 64)]
    roots = [33, 29, 36, 31, 33]
    bar = 4 * BEAT
    for b, (ch, root) in enumerate(zip(chords, roots)):
        t0 = b * bar
        # pad: detuned sines, slow attack, stereo
        k = int(bar * SR) + SR // 2
        tt = np.arange(k) / SR
        pe = np.minimum(1, tt / 0.6) * np.exp(-tt / 3.0)
        for m in ch:
            f = note(m)
            L_ = np.sin(2 * np.pi * f * 0.997 * tt) + 0.3 * np.sin(2 * np.pi * 2 * f * tt)
            R_ = np.sin(2 * np.pi * f * 1.003 * tt) + 0.3 * np.sin(2 * np.pi * 2 * f * tt)
            add(L, t0, 0.045 * pe * L_)
            add(R, t0, 0.045 * pe * R_)
        # bass: 8th notes, rounded saw
        for e8 in range(8):
            if b == 4 and e8 > 1:
                break
            st = t0 + e8 * BEAT / 2
            k = int(BEAT / 2 * SR)
            tt = np.arange(k) / SR
            f = note(root + (12 if e8 % 4 == 3 else 0))
            saw = sum(np.sin(2 * np.pi * f * h * tt) / h for h in range(1, 6))
            sig = 0.11 * saw * env(k, 0.005, 0.16)
            add(L, st, sig)
            add(R, st, sig)
        # arpeggio from bar 1 (scene 2 energy), 16ths
        if 1 <= b <= 3:
            seq = [ch[0], ch[1], ch[2], ch[1] + 12, ch[2], ch[1], ch[0] + 12, ch[2]]
            for s16 in range(16):
                st = t0 + s16 * BEAT / 4
                k = int(0.22 * SR)
                tt = np.arange(k) / SR
                f = note(seq[s16 % 8] + 12)
                sig = (np.sin(2 * np.pi * f * tt) + 0.25 * np.sin(4 * np.pi * f * tt)) * env(k, 0.002, 0.07)
                pan = 0.5 + 0.35 * math.sin(s16 * 0.9)
                add(L, st, 0.05 * sig * (1 - pan) * 2)
                add(R, st, 0.05 * sig * pan * 2)
    beats = int(DUR / BEAT)
    for bt in range(beats):
        st = bt * BEAT
        # kick: from beat 2, pause before the drop, back on the logo
        if 2 <= bt < 13 or bt >= 14:
            if bt <= 18:
                k = int(0.35 * SR)
                tt = np.arange(k) / SR
                f = 45 + 95 * np.exp(-tt * 28)
                ph = 2 * np.pi * np.cumsum(f) / SR
                sig = 0.55 * np.sin(ph) * np.exp(-tt * 9)
                add(L, st, sig)
                add(R, st, sig)
        # hats on the off-beats
        if 1 <= bt < 13 or 14 <= bt <= 18:
            k = int(0.05 * SR)
            nz = np.diff(rng.standard_normal(k + 1))
            sig = 0.05 * nz * env(k, 0.001, 0.012)
            add(L, st + BEAT / 2, sig)
            add(R, st + BEAT / 2, sig * 0.8)
        # clap on 2 and 4
        if bt % 2 == 1 and 3 <= bt < 13:
            k = int(0.12 * SR)
            nz = rng.standard_normal(k)
            sig = 0.12 * np.convolve(nz, np.ones(6) / 6, "same") * env(k, 0.001, 0.035)
            add(L, st, sig)
            add(R, st, sig)
    # riser into the logo (6.0 -> 7.0) and impact at 7.0
    k = int(1.0 * SR)
    tt = np.arange(k) / SR
    nz = rng.standard_normal(k)
    hp = np.diff(np.concatenate([[0], nz]))
    riser = (tt / 1.0) ** 2 * (0.6 * hp + 0.4 * nz) * 0.07
    sweep = 0.05 * np.sin(2 * np.pi * np.cumsum(200 + 1400 * (tt / 1.0) ** 2) / SR) * (tt / 1.0) ** 2
    add(L, 6.0, riser + sweep)
    add(R, 6.0, riser * 0.9 + sweep)
    k = int(2.6 * SR)
    tt = np.arange(k) / SR
    boom_f = 38 + 60 * np.exp(-tt * 10)
    boom = 0.7 * np.sin(2 * np.pi * np.cumsum(boom_f) / SR) * np.exp(-tt * 2.2)
    crash = 0.09 * rng.standard_normal(k) * np.exp(-tt * 1.6)
    crash = np.diff(np.concatenate([[0], crash]))
    add(L, 7.0, boom + crash)
    add(R, 7.0, boom + crash * 0.9)
    # end chord: A minor add9, rings out
    k = int(3.0 * SR)
    tt = np.arange(k) / SR
    for m in (57, 64, 69, 71, 72):
        f = note(m)
        e = np.minimum(1, tt / 0.02) * np.exp(-tt / 1.6)
        add(L, 7.0, 0.05 * e * np.sin(2 * np.pi * f * 0.998 * tt))
        add(R, 7.0, 0.05 * e * np.sin(2 * np.pi * f * 1.002 * tt))
    # master: fade in/out, soft clip, normalise
    t_all = np.arange(n) / SR
    fade = np.minimum(1, t_all / 0.15) * np.clip((DUR - t_all) / 0.6, 0, 1)
    out = np.stack([L, R], axis=1) * fade[:, None]
    out = np.tanh(out * 1.4)
    out /= np.max(np.abs(out)) + 1e-9
    out *= 0.89
    return (out * 32767).astype(np.int16)

def write_wav(path, data):
    with wave.open(str(path), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())

# ---------------------------------------------------------------------------

def main(only_frames=None):
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="targetfy-demo-"))
    try:
        frames = only_frames or range(N)
        for i in frames:
            frame(i).save(tmp / f"f{i:04d}.png")
        if only_frames:
            for i in only_frames:
                shutil.copy(tmp / f"f{i:04d}.png", HERE / f"preview-{i:04d}.png")
            return
        write_wav(tmp / "music.wav", music())
        out = (HERE / "targetfy-demo.mp4").as_posix()
        r = (f"f <- sort(list.files('{tmp.as_posix()}', '^f\\\\d+\\\\.png$', full.names = TRUE)); "
             f"av::av_encode_video(f, output = '{out}', framerate = {FPS}, "
             f"vfilter = 'format=yuv420p', codec = 'libx264', "
             f"audio = '{(tmp / 'music.wav').as_posix()}', verbose = FALSE)")
        subprocess.run(["Rscript", "-e", r], check=True)
        print(out)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

if __name__ == "__main__":
    import sys
    if len(sys.argv) > 1 and sys.argv[1] == "--preview":
        main(only_frames=[int(x) for x in sys.argv[2:]])
    else:
        main()
