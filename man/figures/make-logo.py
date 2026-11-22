"""Builds the targetfy hex sticker: logo.svg (text as outlines), then
logo.png (518x600) and logo@2x.png via R's rsvg.

    python man/figures/make-logo.py

Needs fontTools and the Bahnschrift font (ships with Windows 10+).
"""
import math
import pathlib
import subprocess

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

HERE = pathlib.Path(__file__).parent
W, H = 518, 600
CX, CY = W / 2, H / 2

NAVY_TOP, NAVY_BOTTOM = "#26354F", "#141C2B"
TEAL = "#3CC8B4"
INK = "#EEF3F9"
MUTED = "#7489A8"


def hexagon(r):
    """Pointy-top hexagon around the centre, as SVG points."""
    pts = []
    for k in range(6):
        a = math.radians(-90 + 60 * k)
        pts.append(f"{CX + r * math.cos(a):.2f},{CY + r * math.sin(a):.2f}")
    return " ".join(pts)


def text_path(text, font_file, size, baseline, weight=600, tracking=0.0):
    """The text as one SVG path, centred on CX. tracking is in em."""
    font = TTFont(font_file)
    if "fvar" in font:
        font = instancer.instantiateVariableFont(font, {"wght": weight})
    upem = font["head"].unitsPerEm
    scale = size / upem
    cmap = font.getBestCmap()
    glyphs = font.getGlyphSet()
    hmtx = font["hmtx"]
    names = [cmap[ord(c)] for c in text]
    advance = sum(hmtx[n][0] for n in names) + tracking * upem * (len(names) - 1)
    x = CX / scale - advance / 2
    parts = []
    for n in names:
        pen = SVGPathPen(glyphs)
        # Font units are y-up: flip, then place on the baseline.
        tpen = TransformPen(pen, (scale, 0, 0, -scale, x * scale, baseline))
        glyphs[n].draw(tpen)
        parts.append(pen.getCommands())
        x += hmtx[n][0] + tracking * upem
    return " ".join(parts)


def build():
    outer = hexagon(282)
    inner = hexagon(262)
    name = text_path("targetfy", "C:/Windows/Fonts/bahnschrift.ttf",
                     size=74, baseline=414, weight=600, tracking=0.02)

    # Motif, centred on y = 250.
    y = 250
    # DAG: root A forks to B (up) and C (down), with curved edges.
    ax, bx = 312, 418
    by, cy = y - 44, y + 44
    edge = lambda y2: (f"M{ax},{y} C{ax + 52},{y} {bx - 52},{y2} {bx},{y2}")

    svg = f"""<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0.35" y2="1">
      <stop offset="0" stop-color="{NAVY_TOP}"/>
      <stop offset="1" stop-color="{NAVY_BOTTOM}"/>
    </linearGradient>
    <radialGradient id="glow" cx="0.5" cy="0.4" r="0.55">
      <stop offset="0" stop-color="{TEAL}" stop-opacity="0.16"/>
      <stop offset="1" stop-color="{TEAL}" stop-opacity="0"/>
    </radialGradient>
  </defs>

  <!-- Hexagon: gradient body, soft glow behind the motif, teal rim and a
       faint inner hairline. -->
  <polygon points="{outer}" fill="url(#bg)" stroke="{TEAL}" stroke-width="16" stroke-linejoin="round"/>
  <polygon points="{inner}" fill="url(#glow)"/>
  <polygon points="{inner}" fill="none" stroke="#FFFFFF" stroke-opacity="0.09" stroke-width="2" stroke-linejoin="round"/>

  <!-- </> : the code -->
  <g fill="none" stroke="{INK}" stroke-width="11" stroke-linecap="round" stroke-linejoin="round">
    <polyline points="114,{y - 34} 80,{y} 114,{y + 34}"/>
    <line x1="132" y1="{y + 42}" x2="156" y2="{y - 42}"/>
    <polyline points="174,{y - 34} 208,{y} 174,{y + 34}"/>
  </g>

  <!-- dashed arrow: the transmutation -->
  <g fill="none" stroke="{MUTED}" stroke-width="7" stroke-linecap="round" stroke-linejoin="round">
    <line x1="229" y1="{y}" x2="235" y2="{y}"/>
    <line x1="245" y1="{y}" x2="251" y2="{y}"/>
    <polyline points="261,{y - 11} 272,{y} 261,{y + 11}"/>
  </g>

  <!-- O< : the DAG -->
  <g fill="none" stroke="{INK}" stroke-width="7" stroke-linecap="round">
    <path d="{edge(by)}"/>
    <path d="{edge(cy)}"/>
  </g>
  <g fill="{TEAL}" stroke="{INK}" stroke-width="6">
    <circle cx="{ax}" cy="{y}" r="17"/>
    <circle cx="{bx}" cy="{by}" r="17"/>
    <circle cx="{bx}" cy="{cy}" r="17"/>
  </g>

  <!-- name, as outlines (Bahnschrift SemiBold) -->
  <path d="{name}" fill="{INK}"/>
</svg>
"""
    (HERE / "logo.svg").write_text(svg, encoding="utf-8")


def render():
    r = ("rsvg::rsvg_png('logo.svg', 'logo.png', width = 518, height = 600); "
         "rsvg::rsvg_png('logo.svg', 'logo@2x.png', width = 1036, height = 1200)")
    subprocess.run(["Rscript", "-e", r], cwd=HERE, check=True)


if __name__ == "__main__":
    build()
    render()
