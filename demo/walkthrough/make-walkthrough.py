"""Builds demo/walkthrough/targetfy-walkthrough.mp4: a ~34 s screen-style
walkthrough of a REAL targetfy run on project/analysis.R.

Everything shown comes from that run: the script and the Generated Files
are read from project/, the DAG is a headless-browser capture of the real
tar_glimpse() page (captures/dag.png) and the report is a capture of the
real targetfy-report.md (captures/report.png, made by render-report.R).
The terminal lines summarise that run's real results.

    python demo/walkthrough/make-walkthrough.py [--preview t1 t2 ...]
"""
import importlib.util
import math
import pathlib
import shutil
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image, ImageDraw
from pygments.lexers import SLexer
from pygments.token import Comment, Keyword, Name, Number, Operator, String

HERE = pathlib.Path(__file__).parent
PROJECT = HERE / "project"
CAPTURES = HERE / "captures"

spec = importlib.util.spec_from_file_location("promo", HERE.parent / "make-demo.py")
P = importlib.util.module_from_spec(spec)
spec.loader.exec_module(P)

W, H, FPS = P.W, P.H, P.FPS
DUR = 34.0
N = int(DUR * FPS)
TEAL, INK, MUTED, AMBER, PINK, CARD = P.TEAL, P.INK, P.MUTED, P.AMBER, P.PINK, P.CARD
clamp, prog, ease, ease_out, back_out, mix = P.clamp, P.prog, P.ease, P.ease_out, P.back_out, P.mix

F_CODE = P.mono(30)
F_CHROME = P.mono(22)
F_TERM = P.mono(28)
F_STEP = P.sans(40, 600)
F_STEPNUM = P.sans(30, 700)
LINE_H = 44

# Window geometry
WX, WY, WW, WH = 160, 150, 1600, 860
BAR = 54  # title bar height
CONTENT = (WX, WY + BAR, WX + WW, WY + WH)

# ---------------------------------------------------------------------------
# Timeline: (start, end, kind, args)
# ---------------------------------------------------------------------------
SCENES = [
    (0.0, 7.6, "code", dict(file="analysis.R", step=1, label="Your R script")),
    (7.6, 15.2, "terminal", dict(step=2, label="Run /targetfy")),
    (15.2, 20.4, "code", dict(file="_targets.R", step=3, label="The Pipeline: _targets.R")),
    (20.4, 23.2, "code", dict(file="R/analysis_functions.R", step=3, label="Its functions: R/analysis_functions.R")),
    (23.2, 27.4, "dag", dict(step=4, label="The DAG: tar_glimpse()")),
    (27.4, 31.6, "report", dict(step=5, label="The report: targetfy-report.md")),
    (31.6, DUR, "end", {}),
]
FADE = 0.35

def _content_mask(fade_edges):
    x0, y0, x1, y1 = CONTENT
    w, h = x1 - x0, y1 - y0 - 4
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).rounded_rectangle([2, -40, w - 3, h - 1], 18, fill=255)
    if fade_edges:
        a = np.asarray(m).astype(float)
        ramp = np.ones(h)
        k = 34
        ramp[:k] = np.linspace(0, 1, k)
        ramp[-k:] = np.linspace(1, 0, k)
        m = Image.fromarray((a * ramp[:, None]).astype(np.uint8), "L")
    return m

MASK_PLAIN, MASK_FADE = None, None

def place(layer, view, fade_edges=False):
    """Composite a content-sized image into the window, clipped to its
    rounded corners (and faded at the top and bottom for scrolling text)."""
    global MASK_PLAIN, MASK_FADE
    if MASK_PLAIN is None:
        MASK_PLAIN, MASK_FADE = _content_mask(False), _content_mask(True)
    mask = MASK_FADE if fade_edges else MASK_PLAIN
    view = view.crop((0, 0, mask.width, mask.height))
    a = np.asarray(view.getchannel("A")).astype(np.uint16) * np.asarray(mask) // 255
    view.putalpha(Image.fromarray(a.astype(np.uint8), "L"))
    layer.alpha_composite(view, (CONTENT[0], CONTENT[1]))

# ---------------------------------------------------------------------------
# Code rendering (pygments S lexer, our palette)
# ---------------------------------------------------------------------------

def colour_for(ttype, value, next_value):
    if ttype in Comment:
        return (104, 122, 150)
    if ttype in String:
        return AMBER
    if ttype in Number:
        return PINK
    if ttype in Keyword or value in ("TRUE", "FALSE", "NULL", "function"):
        return PINK
    if ttype in Operator or value in ("<-", "|>", "~", "+", "!!"):
        return MUTED
    if ttype in Name and next_value.startswith("("):
        return TEAL
    return INK

def code_lines(path):
    text = path.read_text(encoding="utf-8")
    toks = list(SLexer().get_tokens(text))
    lines, cur = [], []
    for i, (tt, v) in enumerate(toks):
        nxt = ""
        for _, v2 in toks[i + 1:]:
            if v2.strip():
                nxt = v2
                break
        parts = v.split("\n")
        for j, part in enumerate(parts):
            if part:
                cur.append((part, colour_for(tt, part, nxt)))
            if j < len(parts) - 1:
                lines.append(cur)
                cur = []
    if cur:
        lines.append(cur)
    while lines and not lines[-1]:
        lines.pop()
    return lines

CODE = {f: code_lines(PROJECT / f) for f in ("analysis.R", "_targets.R", "R/analysis_functions.R")}

def draw_code(layer, d, lines, scroll, alpha):
    x0, y0, x1, y1 = CONTENT
    view = Image.new("RGBA", (x1 - x0, y1 - y0), (0, 0, 0, 0))
    vd = ImageDraw.Draw(view)
    top = 26 - scroll
    for n, line in enumerate(lines):
        y = top + n * LINE_H
        if y < -LINE_H or y > y1 - y0:
            continue
        vd.text((24, y), f"{n + 1:>2}", font=F_CODE, fill=mix((78, 94, 120), alpha))
        x = 100
        for s, col in line:
            vd.text((x, y), s, font=F_CODE, fill=mix(col, alpha))
            x += vd.textlength(s, font=F_CODE)
    place(layer, view, fade_edges=True)

# ---------------------------------------------------------------------------
# Window chrome and captions
# ---------------------------------------------------------------------------

def draw_window(d, title, alpha, body=(CARD), light=False):
    x0, y0 = WX, WY
    d.rounded_rectangle([x0, y0, x0 + WW, y0 + WH], 20,
                        fill=mix(body if not light else (255, 255, 255), 0.98 * alpha),
                        outline=mix((255, 255, 255), 0.12 * alpha), width=2)
    d.rounded_rectangle([x0, y0, x0 + WW, y0 + BAR], 20, fill=mix((19, 26, 40), alpha))
    d.rectangle([x0, y0 + BAR - 20, x0 + WW, y0 + BAR], fill=mix((19, 26, 40), alpha))
    for i, c in enumerate([(232, 106, 94), (240, 190, 90), (98, 196, 120)]):
        d.ellipse([x0 + 24 + i * 28, y0 + 19, x0 + 40 + i * 28, y0 + 35], fill=mix(c, alpha))
    tw = d.textlength(title, font=F_CHROME)
    d.text((x0 + WW / 2 - tw / 2, y0 + 14), title, font=F_CHROME, fill=mix(MUTED, alpha))

def draw_step(d, num, label, alpha):
    x, y = WX, 62
    r = 26
    d.ellipse([x, y, x + 2 * r, y + 2 * r], fill=mix(TEAL, alpha))
    s = str(num)
    tw = d.textlength(s, font=F_STEPNUM)
    d.text((x + r - tw / 2, y + 8), s, font=F_STEPNUM, fill=mix((16, 24, 36), alpha))
    d.text((x + 2 * r + 20, y + 2), label, font=F_STEP, fill=mix(INK, alpha))

def scroll_for(t, t0, t1, lines, hold_start=0.8, hold_end=0.9):
    total = len(lines) * LINE_H + 40
    view = CONTENT[3] - CONTENT[1]
    max_scroll = max(0, total - view)
    return max_scroll * ease(prog(t, t0 + hold_start, t1 - hold_end))

# ---------------------------------------------------------------------------
# Terminal: the run, summarised from its real results
# ---------------------------------------------------------------------------

TERM = [
    # (time offset, kind, text)
    (0.9, "info", "Preflight: R 4.4.1 (on your PATH): readr, dplyr, ggplot2, broom all load"),
    (1.5, "info", "Read analysis.R: 5 Steps, 1 input file, 2 output files, 3 lines to drop"),
    (2.1, "info", "Wrote _targets.R, R/analysis_functions.R, targetfy-map.json"),
    (2.8, "ask", "Which check?  > Run and compare (recommended)"),
    (3.5, "run", "Running your script and the Pipeline in throwaway copies"),
    (5.0, "ok", "equivalent: 5/5 Targets match, 2/2 files byte-identical"),
    (5.6, "info", "Wrote targetfy-report.md; graph opened in your browser"),
]
COMMAND = "/targetfy analysis.R"

def draw_terminal(layer, d, t, alpha):
    x0, y0, x1, y1 = CONTENT
    x, y = x0 + 44, y0 + 40
    typed = COMMAND[: int(len(COMMAND) * prog(t, 0.2, 0.8))]
    d.text((x, y), ">", font=F_TERM, fill=mix(TEAL, alpha))
    d.text((x + 40, y), typed, font=F_TERM, fill=mix(INK, alpha))
    if t < 0.85 and int(t * 4) % 2 == 0:
        cx = x + 40 + d.textlength(typed, font=F_TERM) + 4
        d.rectangle([cx, y + 2, cx + 15, y + 34], fill=mix(INK, alpha))
    y += 80
    for t_on, kind, text in TERM:
        a = ease_out(prog(t, t_on, t_on + 0.25)) * alpha
        if a <= 0:
            continue
        bx, by = x + 14, y + 18
        if kind == "ok":
            d.line([(bx - 10, by), (bx - 3, by + 8), (bx + 12, by - 9)], fill=mix(TEAL, a), width=5, joint="curve")
            col = TEAL
        elif kind == "ask":
            d.text((bx - 8, y), "?", font=F_TERM, fill=mix(AMBER, a))
            col = INK
        elif kind == "run":
            done = t >= 4.9
            if done:
                d.ellipse([bx - 7, by - 7, bx + 7, by + 7], fill=mix(MUTED, a))
            else:  # spinner
                for k in range(8):
                    ang = (k / 8) * 2 * math.pi + t * 9
                    rr = 3 + 2 * ((k + int(t * 12)) % 8) / 8
                    d.ellipse([bx + 11 * math.cos(ang) - rr, by + 11 * math.sin(ang) - rr,
                               bx + 11 * math.cos(ang) + rr, by + 11 * math.sin(ang) + rr],
                              fill=mix(TEAL, a * (0.3 + 0.7 * k / 8)))
            col = INK
        else:
            d.ellipse([bx - 7, by - 7, bx + 7, by + 7], fill=mix(MUTED, a))
            col = INK
        d.text((x + 48, y), text, font=F_TERM, fill=mix(col, a))
        y += 62

# ---------------------------------------------------------------------------
# Captures
# ---------------------------------------------------------------------------

DAG = Image.open(CAPTURES / "dag.png").convert("RGBA").crop((60, 360, 1990, 800))
REPORT = Image.open(CAPTURES / "report.png").convert("RGBA")
REPORT_END = 2040  # content height in the capture

def draw_dag(layer, t, dur, alpha):
    x0, y0, x1, y1 = CONTENT
    z = 1.0 + 0.06 * ease(prog(t, 0, dur))
    w = int((x1 - x0 - 80) * z)
    h = int(w * DAG.height / DAG.width)
    img = DAG.resize((w, h), Image.LANCZOS)
    if alpha < 1:
        img.putalpha(img.getchannel("A").point(lambda v: int(v * alpha)))
    cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
    view = Image.new("RGBA", (x1 - x0, y1 - y0), (0, 0, 0, 0))
    view.alpha_composite(img, ((x1 - x0) // 2 - w // 2, (y1 - y0) // 2 - h // 2))
    place(layer, view)

def draw_report(layer, t, dur, alpha):
    x0, y0, x1, y1 = CONTENT
    vw, vh = x1 - x0, y1 - y0
    scale = vw / REPORT.width
    max_scroll = REPORT_END * scale - vh
    s = max_scroll * ease(prog(t, 0.7, dur - 0.6))
    src_top = int(s / scale)
    crop = REPORT.crop((0, src_top, REPORT.width, src_top + int(vh / scale)))
    crop = crop.resize((vw, vh), Image.LANCZOS)
    if alpha < 1:
        crop.putalpha(crop.getchannel("A").point(lambda v: int(v * alpha)))
    place(layer, crop)

# ---------------------------------------------------------------------------
# Frame
# ---------------------------------------------------------------------------

def scene_alpha(t, t0, t1, first=False, last=False):
    a_in = 1 if first else ease_out(prog(t, t0, t0 + FADE))
    a_out = 1 if last else 1 - ease(prog(t, t1 - FADE, t1))
    return a_in * a_out

def frame(i):
    t = i / FPS
    img = P.BG.copy()
    for k, (t0, t1, kind, args) in enumerate(SCENES):
        if not (t0 - 0.01 <= t <= t1 + 0.01):
            continue
        lt = t - t0
        a = scene_alpha(t, t0, t1, first=(k == 0), last=(kind == "end"))
        if a <= 0:
            continue
        if kind == "end":
            # replay the promo's end card (6.9 -> 10.0 s) over this scene
            P.draw_end(img, 6.9 + (t - t0) * (3.1 / (t1 - t0)))
            continue
        layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        slide = 30 * (1 - ease_out(prog(t, t0, t0 + FADE))) if k > 0 else 0
        draw_step(d, args["step"], args["label"], a)
        if kind == "code":
            draw_window(d, args["file"] + "  —  editor", a)
            lines = CODE[args["file"]]
            draw_code(layer, d, lines, scroll_for(t, t0, t1, lines), a)
        elif kind == "terminal":
            draw_window(d, "terminal  —  claude", a, body=(16, 22, 34))
            draw_terminal(layer, d, lt, a)
        elif kind == "dag":
            draw_window(d, "_targets-glimpse.html  —  browser", a, light=True)
            draw_dag(layer, lt, t1 - t0, a)
        elif kind == "report":
            draw_window(d, "targetfy-report.md  —  preview", a, body=(15, 21, 32))
            draw_report(layer, lt, t1 - t0, a)
        if slide:
            shifted = Image.new("RGBA", (W, H), (0, 0, 0, 0))
            shifted.alpha_composite(layer, (0, int(slide)))
            layer = shifted
        img.alpha_composite(layer)
    fi = ease_out(prog(t, 0, 0.35))
    if fi < 1:
        img = Image.blend(Image.new("RGBA", (W, H), (0, 0, 0, 255)), img, fi)
    return img.convert("RGB")

# ---------------------------------------------------------------------------
# Music: same palette as the promo, a calmer bed, then the logo hit
# ---------------------------------------------------------------------------

def music():
    SR, BEAT = P.SR, P.BEAT
    n = int(SR * DUR)
    L, R = np.zeros(n), np.zeros(n)
    rng = np.random.default_rng(11)
    note, env, add = P.note, P.env, P.add
    chords = [(57, 60, 64), (53, 57, 60), (48, 52, 55), (55, 59, 62)]
    roots = [33, 29, 36, 31]
    bar = 4 * BEAT
    logo = SCENES[-1][0]
    nbars = int(math.ceil(DUR / bar))
    for b in range(nbars):
        t0 = b * bar
        if t0 >= logo - 0.01:
            break
        ch, root = chords[b % 4], roots[b % 4]
        k = int(bar * SR) + SR // 2
        tt = np.arange(k) / SR
        pe = np.minimum(1, tt / 0.8) * np.exp(-tt / 3.5)
        for m in ch:
            f = note(m)
            add(L, t0, 0.04 * pe * np.sin(2 * np.pi * f * 0.997 * tt))
            add(R, t0, 0.04 * pe * np.sin(2 * np.pi * f * 1.003 * tt))
        for e8 in range(8):
            st = t0 + e8 * BEAT / 2
            if st >= logo - 0.05:
                break
            k = int(BEAT / 2 * SR)
            tt = np.arange(k) / SR
            f = note(root + (12 if e8 % 4 == 3 else 0))
            saw = sum(np.sin(2 * np.pi * f * h * tt) / h for h in range(1, 5))
            sig = 0.08 * saw * env(k, 0.005, 0.15)
            add(L, st, sig)
            add(R, st, sig)
        if b >= 2:  # arpeggio once the run starts
            seq = [ch[0], ch[1], ch[2], ch[1] + 12, ch[2], ch[1], ch[0] + 12, ch[2]]
            for s16 in range(16):
                st = t0 + s16 * BEAT / 4
                if st >= logo - 1.0:
                    break
                k = int(0.2 * SR)
                tt = np.arange(k) / SR
                f = note(seq[s16 % 8] + 12)
                sig = (np.sin(2 * np.pi * f * tt) + 0.25 * np.sin(4 * np.pi * f * tt)) * env(k, 0.002, 0.06)
                pan = 0.5 + 0.35 * math.sin(s16 * 0.9)
                add(L, st, 0.035 * sig * (1 - pan) * 2)
                add(R, st, 0.035 * sig * pan * 2)
    for bt in range(int(DUR / BEAT)):
        st = bt * BEAT
        if st >= logo - 1.0 and st < logo:
            continue  # breath before the logo
        if st >= logo + 2.0:
            break
        if bt >= 2:
            k = int(0.3 * SR)
            tt = np.arange(k) / SR
            f = 45 + 90 * np.exp(-tt * 28)
            sig = 0.38 * np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt * 10)
            add(L, st, sig)
            add(R, st, sig)
        if bt >= 1:
            k = int(0.05 * SR)
            nz = np.diff(rng.standard_normal(k + 1))
            sig = 0.04 * nz * env(k, 0.001, 0.012)
            add(L, st + BEAT / 2, sig)
            add(R, st + BEAT / 2, sig * 0.8)
    # riser and logo hit
    k = int(1.0 * SR)
    tt = np.arange(k) / SR
    nz = rng.standard_normal(k)
    riser = (tt ** 2) * (0.6 * np.diff(np.concatenate([[0], nz])) + 0.4 * nz) * 0.06
    sweep = 0.04 * np.sin(2 * np.pi * np.cumsum(200 + 1400 * tt ** 2) / SR) * tt ** 2
    add(L, logo - 1.0, riser + sweep)
    add(R, logo - 1.0, riser * 0.9 + sweep)
    k = int(2.4 * SR)
    tt = np.arange(k) / SR
    boom = 0.65 * np.sin(2 * np.pi * np.cumsum(38 + 60 * np.exp(-tt * 10)) / SR) * np.exp(-tt * 2.2)
    crash = np.diff(np.concatenate([[0], 0.08 * rng.standard_normal(k) * np.exp(-tt * 1.6)]))
    add(L, logo, boom + crash)
    add(R, logo, boom + crash * 0.9)
    k = int(2.4 * SR)
    tt = np.arange(k) / SR
    for m in (57, 64, 69, 71, 72):
        e = np.minimum(1, tt / 0.02) * np.exp(-tt / 1.5)
        add(L, logo, 0.045 * e * np.sin(2 * np.pi * note(m) * 0.998 * tt))
        add(R, logo, 0.045 * e * np.sin(2 * np.pi * note(m) * 1.002 * tt))
    t_all = np.arange(n) / SR
    fade = np.minimum(1, t_all / 0.3) * np.clip((DUR - t_all) / 0.6, 0, 1)
    out = np.tanh(np.stack([L, R], axis=1) * fade[:, None] * 1.4)
    out /= np.max(np.abs(out)) + 1e-9
    return (out * 0.89 * 32767).astype(np.int16)

# ---------------------------------------------------------------------------

def main(preview_times=None):
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="targetfy-walk-"))
    try:
        if preview_times:
            for t in preview_times:
                frame(int(t * FPS)).save(HERE / f"preview-{t:05.1f}.png")
            return
        for i in range(N):
            frame(i).save(tmp / f"f{i:04d}.png")
        P.write_wav(tmp / "music.wav", music())
        out = (HERE / "targetfy-walkthrough.mp4").as_posix()
        r = (f"f <- sort(list.files('{tmp.as_posix()}', '^f\\\\d+\\\\.png$', full.names = TRUE)); "
             f"av::av_encode_video(f, output = '{out}', framerate = {FPS}, "
             f"vfilter = 'format=yuv420p', codec = 'libx264', "
             f"audio = '{(tmp / 'music.wav').as_posix()}', verbose = FALSE)")
        subprocess.run(["Rscript", "-e", r], check=True)
        print(out)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--preview":
        main([float(x) for x in sys.argv[2:]])
    else:
        main()
