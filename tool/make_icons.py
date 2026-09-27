"""Build every app-icon variant from the new secretary-bird artwork.

Input: a small screenshot of a rounded-square icon on a white background.
Outputs (1024 px unless noted), written to OUT:
  icon.png             rounded tile, transparent corners (launcher legacy,
                       Windows .ico, favicon, in-app logo)
  icon_foreground.png  Android adaptive foreground: the full-bleed tile scaled
                       into the 72/108 visible viewport on a transparent layer
  maskable_512.png / maskable_192.png   web maskable icons (tile inside the
                       80% safe circle on the tile's own edge colour)
  edge_color.txt       hex of the tile background, for the adaptive background
"""
import sys
from collections import deque
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

SRC = Path(sys.argv[1])
OUT = Path(sys.argv[2])
OUT.mkdir(parents=True, exist_ok=True)

SIZE = 1024
SS = 4  # supersampling for smooth mask edges

src = Image.open(SRC).convert("RGB")
w, h = src.size


def is_background(px):
    r, g, b = px
    return r > 225 and g > 225 and b > 225


def dark(p):
    return sum(p) / 3 < 150


# --- 1. find the tile: bounding box of its dark body (ignores the light
#        anti-aliased rim and any drop shadow the screenshot picked up) --------
xs, ys = [], []
for y in range(h):
    for x in range(w):
        if dark(src.getpixel((x, y))):
            xs.append(x)
            ys.append(y)
left, right, top, bottom = min(xs), max(xs), min(ys), max(ys)
tile = src.crop((left, top, right + 1, bottom + 1))
tw, th = tile.size
side = max(tw, th)

# --- 2. corner radius: on the top row of the body, the first dark pixel sits
#        roughly one radius in from the left edge of a rounded rectangle. ------
row = [tile.getpixel((x, 0)) for x in range(tw)]
first_dark = next((i for i, p in enumerate(row) if dark(p)), int(side * 0.2))
radius_ratio = min(max(first_dark / side, 0.12), 0.28)

# --- 3. tile edge colour (sampled just inside the left edge, mid height) -----
samples = [tile.getpixel((int(tw * 0.04), int(th * f))) for f in (0.45, 0.5, 0.55)]
edge = tuple(sum(c[i] for c in samples) // len(samples) for i in range(3))

# Paint the white corners with the edge colour so upscaling never blends white
# into the tile's rim. Flood-fill from the outer corners only: the bird's white
# feathers and the ring's highlight are also near-white and must be kept.
square = Image.new("RGB", (side, side), edge)
square.paste(tile, ((side - tw) // 2, (side - th) // 2))
px = square.load()


def light(p):  # background white plus its anti-aliased grey fringe
    return sum(p) / 3 > 150


queue = deque([(0, 0), (side - 1, 0), (0, side - 1), (side - 1, side - 1)])
seen = set()
while queue:
    x, y = queue.popleft()
    if (x, y) in seen or not (0 <= x < side and 0 <= y < side):
        continue
    seen.add((x, y))
    if not light(px[x, y]):
        continue
    px[x, y] = edge
    queue.extend(((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)))

# --- 4. upscale with light sharpening ----------------------------------------
big = square.resize((SIZE, SIZE), Image.LANCZOS)
big = big.filter(ImageFilter.UnsharpMask(radius=2.2, percent=70, threshold=2))
fullbleed = big.copy()  # corners filled with the edge colour


def rounded_mask(size, ratio):
    m = Image.new("L", (size * SS, size * SS), 0)
    ImageDraw.Draw(m).rounded_rectangle(
        (0, 0, size * SS - 1, size * SS - 1), radius=int(size * SS * ratio), fill=255
    )
    return m.resize((size, size), Image.LANCZOS)


# --- 5. rounded icon with transparent corners --------------------------------
icon = fullbleed.convert("RGBA")
icon.putalpha(rounded_mask(SIZE, radius_ratio))
icon.save(OUT / "icon.png")

# --- 6. Android adaptive foreground ------------------------------------------
# ic_launcher.xml insets the foreground by 16% per side, which maps the image
# onto the 72dp visible viewport. So the foreground is the full tile, trimmed
# 2% per side: the artwork's bevelled edge then falls just outside the mask,
# while the gold ring (~81% of the tile) stays well inside it.
trim = round(SIZE * 0.02)
foreground = fullbleed.crop((trim, trim, SIZE - trim, SIZE - trim)).resize(
    (SIZE, SIZE), Image.LANCZOS
)
foreground.save(OUT / "icon_foreground.png")

hex_edge = "#{:02X}{:02X}{:02X}".format(*edge)
(OUT / "edge_color.txt").write_text(hex_edge)

# --- 7. platform files, laid out like the Flutter project --------------------
P = OUT / "platform"


def save(img, rel, size):
    path = P / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    img.resize((size, size), Image.LANCZOS).save(path, optimize=True)


densities = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
res = "android/app/src/main/res"
for name, scale in densities.items():
    save(icon, f"{res}/mipmap-{name}/ic_launcher.png", round(48 * scale))
    save(foreground, f"{res}/drawable-{name}/ic_launcher_foreground.png", round(108 * scale))
(P / f"{res}/values").mkdir(parents=True, exist_ok=True)
(P / f"{res}/values/colors.xml").write_text(
    '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
    f'    <color name="ic_launcher_background">{hex_edge}</color>\n</resources>\n'
)

# Web: plain icons keep the rounded tile; maskable icons sit the ring inside
# the 80% safe circle on the tile colour.
save(icon, "web/icons/Icon-192.png", 192)
save(icon, "web/icons/Icon-512.png", 512)
save(icon, "web/favicon.png", 32)
for px_size in (512, 192):
    canvas = Image.new("RGB", (px_size, px_size), edge)
    inner = round(px_size * 0.95)
    canvas.paste(fullbleed.resize((inner, inner), Image.LANCZOS), ((px_size - inner) // 2,) * 2)
    path = P / f"web/icons/Icon-maskable-{px_size}.png"
    canvas.save(path, optimize=True)

# Windows: multi-resolution .ico.
ico = P / "windows/runner/resources/app_icon.ico"
ico.parent.mkdir(parents=True, exist_ok=True)
icon.save(ico, sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])

print(f"tile {tw}x{th} at ({left},{top}); radius ratio {radius_ratio:.3f}; edge {hex_edge}")
