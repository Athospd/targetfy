"""Builds demo/walkthrough-v2/targetfy-v2-walkthrough.mp4: a ~45 s tour of
what's new in targetfy v2, made from REAL runs on the test fixtures.

- The notebook and the Pipeline shown are tests/fixtures/realworld/project
  (inst/tuning.Rmd and targets_tuning.R), read from disk.
- The terminal lines summarise the real read.R and check.R results on that
  project and on tests/fixtures/hidden/project (the Invalidation Check).

    python demo/walkthrough-v2/make-walkthrough-v2.py [--preview t1 t2 ...]
"""
import importlib.util
import pathlib
import shutil
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw
from pygments.lexers import SLexer

HERE = pathlib.Path(__file__).parent
ROOT = HERE.parent.parent
RW = ROOT / "tests/fixtures/realworld/project"

spec = importlib.util.spec_from_file_location("walk1", HERE.parent / "walkthrough" / "make-walkthrough.py")
V1 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(V1)
P = V1.P

W, H, FPS = P.W, P.H, P.FPS
TEAL, INK, MUTED, AMBER, PINK, CARD = P.TEAL, P.INK, P.MUTED, P.AMBER, P.PINK, P.CARD
clamp, prog, ease, ease_out, back_out, mix = P.clamp, P.prog, P.ease, P.ease_out, P.back_out, P.mix
CONTENT, LINE_H = V1.CONTENT, V1.LINE_H
F_CODE, F_TERM = V1.F_CODE, V1.F_TERM
F_PILL = P.sans(24, 600)
F_TITLE = P.sans(110, 700)
F_SUB = P.sans(46, 500)
F_FEAT = P.sans(42, 600)
F_FEAT2 = P.mono(26)

SCENES = [
    (0.0, 4.0, "title", {}),
    (4.0, 11.5, "notebook", dict(step=1, label="Notebooks are Source Scripts now",
                                 file="inst/tuning.Rmd")),
    (11.5, 18.5, "terminal", dict(step=2, label="It reads the flow before converting",
                                  term="scan")),
    (18.5, 23.5, "code", dict(step=3, label="One Target per version",
                              file="targets_tuning.R")),
    (23.5, 28.5, "terminal", dict(step=4, label="Checked: same results as the notebook",
                                  term="check")),
    (28.5, 36.0, "terminal", dict(step=5, label="Change one input, compare what reruns",
                                  term="invalidation")),
    (36.0, 41.5, "features", dict(step=6, label="And more targets tools")),
    (41.5, 45.0, "end", {}),
]
DUR = SCENES[-1][1]
N = int(DUR * FPS)
FADE = V1.FADE

# ---------------------------------------------------------------------------
# Notebook rendering: prose muted, chunk code coloured as R
# ---------------------------------------------------------------------------

PROSE = (150, 165, 190)

def r_line(text):
    toks = [t for t in SLexer().get_tokens(text) if t[1] != "\n"]
    out = []
    for i, (tt, v) in enumerate(toks):
        nxt = next((v2 for _, v2 in toks[i + 1:] if v2.strip()), "")
        out.append((v, V1.colour_for(tt, v, nxt)))
    return out

def rmd_lines(path):
    lines, in_chunk = [], False
    for raw in path.read_text(encoding="utf-8").splitlines():
        if raw.startswith("```"):
            in_chunk = not in_chunk and raw.startswith("```{")
            lines.append([(raw, (104, 122, 150))])
        elif in_chunk:
            lines.append(r_line(raw))
        elif raw.startswith("#"):
            lines.append([(raw, INK)])
        elif "`r " in raw:
            a, rest = raw.split("`r ", 1)
            b, c = rest.split("`", 1)
            lines.append([(a, PROSE), ("`r " + b + "`", AMBER), (c, PROSE)])
        else:
            lines.append([(raw, PROSE)])
    return lines

NOTEBOOK = rmd_lines(RW / "inst/tuning.Rmd")
PIPELINE = V1.code_lines(RW / "targets_tuning.R")

# (line, colour, tag): what read.R found, on the notebook's own lines
NB_PILLS = [
    (14, MUTED, "label parsed: none (was a v1 bug)"),
    (15, MUTED, "display only"),
    (20, AMBER, "cache = TRUE: first Targets to make"),
    (21, PINK, "grid, version 1"),
    (26, MUTED, "inline code: prose only"),
    (31, PINK, "grid, version 2: reads best"),
    (38, MUTED, "display only"),
    (39, PINK, "console leftover: fails"),
]
PL_PILLS = [
    (8, PINK, "grid, version 1"),
    (11, PINK, "grid, version 2"),
    (14, TEAL, "d: the last version, mapped"),
]

def draw_pill(d, x, y, colour, text, a):
    tw = d.textlength(text, font=F_PILL)
    d.rounded_rectangle([x, y + 3, x + tw + 32, y + 39], 18,
                        fill=mix(tuple(int(c * 0.25) for c in colour), a),
                        outline=mix(colour, a), width=2)
    d.text((x + 16, y + 7), text, font=F_PILL, fill=mix(colour, a))

def draw_annotated(layer, lines, pills, scroll, t, alpha, pill_x=1080):
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
    view_h = y1 - y0
    for ln, col, tag in pills:
        y = top + (ln - 1) * LINE_H
        # a pill appears once its line has scrolled into the lower 80 %
        on = clamp((view_h * 0.85 - y) / 120)
        if on <= 0 or y < -LINE_H or y > view_h:
            continue
        vd.rectangle([92, y + 2, 96, y + LINE_H - 4], fill=mix(col, alpha * on))
        draw_pill(vd, pill_x, y, col, tag, alpha * ease_out(on))
    V1.place(layer, view, fade_edges=True)

# ---------------------------------------------------------------------------
# Terminal scripts (summaries of the real results)
# ---------------------------------------------------------------------------

TERMS = {
    "scan": ("/targetfy inst/tuning.Rmd", [
        (0.9, "info", "Preflight: R 4.4.1; targets, tarchetypes, callr, jsonlite load"),
        (1.5, "info", "_targets.R exists, so I'm creating targets_tuning.R"),
        (2.1, "info", "tuning.Rmd: 6 R chunks; prose and 1 inline expression dropped"),
        (2.8, "warn", "grid, fits, best, d are changed after use: 2 versions each"),
        (3.5, "warn", "2 chunks have cache = TRUE: they become their own Targets"),
        (4.2, "info", "4 lines only display something: left out of the Pipeline"),
        (4.9, "info", "Wrote targets_tuning.R, R_targets/tuning_functions.R"),
    ]),
    "check": ("Rscript scripts/check.R ... --scripts inst/tuning.Rmd", [
        (0.4, "run", "Running the notebook and the Pipeline in throwaway copies"),
        (1.9, "ok", "equivalent: d, grid, fits, best match (4/4)"),
        (2.5, "warn", "tuning.Rmd:39 leftover_from_the_console() failed"),
        (2.5, "cont", "it only displays: skipped and reported, the rest compared"),
        (3.2, "info", "knitting the notebook itself would stop at that line"),
    ]),
    "invalidation": ("/targetfy taxes.R", [
        (0.4, "run", "Outputs match. Now changing each input file, one at a time"),
        (1.8, "ok", "data/sales.csv: the same Targets change as in the script"),
        (2.3, "info", "data/notes.txt: read by nothing"),
        (2.9, "fail", "data/rates.csv: changes sales and total in the script,"),
        (2.9, "cont", "but the Pipeline thinks they're up to date"),
        (3.6, "fail", "hidden dependency: a file read through a variable path"),
        (4.4, "info", "Fix: track it with tar_file_read(), then check again"),
        (5.4, "ok", "equivalent, and all 3 inputs pass"),
    ]),
}

def draw_terminal(layer, d, t, alpha, command, lines):
    x0, y0, x1, y1 = CONTENT
    x, y = x0 + 44, y0 + 40
    typed = command[: int(len(command) * prog(t, 0.05, 0.35))]
    d.text((x, y), ">", font=F_TERM, fill=mix(TEAL, alpha))
    d.text((x + 40, y), typed, font=F_TERM, fill=mix(INK, alpha))
    y += 80
    run_end = next((t_on for t_on, k, _ in lines if k in ("ok", "fail")), 99)
    for t_on, kind, text in lines:
        a = ease_out(prog(t, t_on, t_on + 0.25)) * alpha
        if a <= 0:
            if kind != "cont":
                y += 62
            else:
                y += 50
            continue
        bx, by = x + 14, y + 18
        col = INK
        if kind == "ok":
            d.line([(bx - 10, by), (bx - 3, by + 8), (bx + 12, by - 9)], fill=mix(TEAL, a), width=5, joint="curve")
            col = TEAL
        elif kind == "fail":
            d.line([(bx - 8, by - 8), (bx + 8, by + 8)], fill=mix(PINK, a), width=5)
            d.line([(bx - 8, by + 8), (bx + 8, by - 8)], fill=mix(PINK, a), width=5)
            col = PINK
        elif kind == "warn":
            d.text((bx - 5, y), "!", font=F_TERM, fill=mix(AMBER, a))
            col = AMBER
        elif kind == "cont":
            col = MUTED
            y -= 12
        elif kind == "run":
            if t >= run_end - 0.1:
                d.ellipse([bx - 7, by - 7, bx + 7, by + 7], fill=mix(MUTED, a))
            else:
                import math
                for k in range(8):
                    ang = (k / 8) * 2 * math.pi + t * 9
                    rr = 3 + 2 * ((k + int(t * 12)) % 8) / 8
                    d.ellipse([bx + 11 * math.cos(ang) - rr, by + 11 * math.sin(ang) - rr,
                               bx + 11 * math.cos(ang) + rr, by + 11 * math.sin(ang) + rr],
                              fill=mix(TEAL, a * (0.3 + 0.7 * k / 8)))
        else:
            d.ellipse([bx - 7, by - 7, bx + 7, by + 7], fill=mix(MUTED, a))
        d.text((x + 48, y), text, font=F_TERM, fill=mix(col, a))
        y += 62

# ---------------------------------------------------------------------------
# Title and feature cards
# ---------------------------------------------------------------------------

def draw_title(img, t, alpha):
    s = back_out(prog(t, 0.2, 0.8), 1.4)
    if s > 0:
        h = int(300 * s)
        w = int(h * P.LOGO.width / P.LOGO.height)
        if h > 4:
            lg = P.LOGO.resize((w, h), Image.LANCZOS)
            lg.putalpha(lg.getchannel("A").point(lambda v: int(v * alpha)))
            img.alpha_composite(lg, (W // 2 - w // 2, 330 - h // 2))
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    ta = ease_out(prog(t, 0.7, 1.2)) * alpha
    P.text_center(d, (W / 2, 560 + 20 * (1 - ta)), "targetfy v2", F_TITLE, mix(INK, ta))
    ua = ease_out(prog(t, 1.2, 1.7)) * alpha
    P.text_center(d, (W / 2, 720), "What's new", F_SUB, mix(TEAL, ua))
    img.alpha_composite(layer)

FEATURES = [
    ("Scripts that aren't DAGs", "versions, files overwritten in place, carried loops"),
    ("Pipeline setup from script code", "tar_source(), tar_option_set(seed, memory, error)"),
    ("Branching that fits the loop", "pattern = map(), tar_map(), tar_group_by(), tar_rep()"),
    ("Objects RDS can't store", 'tar_format() for torch and keras, format = "url"'),
    ("Files that are already targets", "pipelines and tar_read() reports are recognised"),
]

def draw_features(d, t, alpha):
    x, y = 260, 210
    for k, (head, sub) in enumerate(FEATURES):
        a = ease_out(prog(t, 0.4 + 0.55 * k, 0.8 + 0.55 * k)) * alpha
        if a > 0:
            dx = 30 * (1 - a)
            d.ellipse([x + dx, y + 18, x + dx + 22, y + 40], fill=mix(TEAL, a))
            d.text((x + 50 + dx, y), head, font=F_FEAT, fill=mix(INK, a))
            d.text((x + 52 + dx, y + 60), sub, font=F_FEAT2, fill=mix(MUTED, a))
        y += 150

# ---------------------------------------------------------------------------
# Frame
# ---------------------------------------------------------------------------

def scroll_to(t, t0, t1, lines, hold_start=0.8, hold_end=1.0):
    return V1.scroll_for(t, t0, t1, lines, hold_start, hold_end)

def frame(i):
    t = i / FPS
    img = P.BG.copy()
    for k, (t0, t1, kind, args) in enumerate(SCENES):
        if not (t0 - 0.01 <= t <= t1 + 0.01):
            continue
        lt = t - t0
        a = V1.scene_alpha(t, t0, t1, first=(k == 0), last=(kind == "end"))
        if a <= 0:
            continue
        if kind == "end":
            P.draw_end(img, 6.9 + lt * (3.1 / (t1 - t0)))
            continue
        if kind == "title":
            draw_title(img, lt, a)
            continue
        layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        V1.draw_step(d, args["step"], args["label"], a)
        if kind == "notebook":
            V1.draw_window(d, args["file"] + "  —  editor", a)
            draw_annotated(layer, NOTEBOOK, NB_PILLS, scroll_to(t, t0, t1, NOTEBOOK), lt, a)
        elif kind == "code":
            V1.draw_window(d, args["file"] + "  —  editor", a)
            draw_annotated(layer, PIPELINE, PL_PILLS, scroll_to(t, t0, t1, PIPELINE), lt, a,
                           pill_x=1240)
        elif kind == "terminal":
            V1.draw_window(d, "terminal  —  claude", a, body=(16, 22, 34))
            cmd, lines = TERMS[args["term"]]
            draw_terminal(layer, d, lt, a, cmd, lines)
        elif kind == "features":
            draw_features(d, lt, a)
        slide = 30 * (1 - ease_out(prog(t, t0, t0 + FADE)))
        if slide:
            shifted = Image.new("RGBA", (W, H), (0, 0, 0, 0))
            shifted.alpha_composite(layer, (0, int(slide)))
            layer = shifted
        img.alpha_composite(layer)
    fi = ease_out(prog(t, 0, 0.35))
    if fi < 1:
        img = Image.blend(Image.new("RGBA", (W, H), (0, 0, 0, 255)), img, fi)
    return img.convert("RGB")

def music():
    # the v1 walkthrough's bed, stretched to this timeline
    V1.DUR, V1.SCENES = DUR, SCENES
    return V1.music()

def main(preview_times=None):
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="targetfy-walk2-"))
    try:
        if preview_times:
            for t in preview_times:
                frame(int(t * FPS)).save(HERE / f"preview-{t:05.1f}.png")
            return
        for i in range(N):
            frame(i).save(tmp / f"f{i:04d}.png")
        P.write_wav(tmp / "music.wav", music())
        out = (HERE / "targetfy-v2-walkthrough.mp4").as_posix()
        r = (f"f <- sort(list.files('{tmp.as_posix()}', '^f\\\\d+\\\\.png$', full.names = TRUE)); "
             f"av::av_encode_video(f, output = '{out}', framerate = {FPS}, "
             f"vfilter = 'format=yuv420p', codec = 'libx264', "
             f"audio = '{(tmp / 'music.wav').as_posix()}', verbose = FALSE)")
        subprocess.run(["Rscript", "-e", r], check=True)
        frame(int(2.5 * FPS)).save(HERE / "thumbnail.png")
        print(out)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--preview":
        main([float(x) for x in sys.argv[2:]])
    else:
        main()
