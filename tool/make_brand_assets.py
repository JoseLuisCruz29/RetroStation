"""Genera el logo y los iconos de RetroStation a partir del logo del autor.

Uso (desde la raíz del proyecto):
    python tool/make_brand_assets.py assets/brand/source/retrostation_logo.jpg

La imagen de origen tiene el símbolo (tren sobre un mando) encima del nombre,
sobre un fondo claro liso. El script:
  1. Recorta el símbolo (sin el texto) y quita el fondo con bordes suaves.
  2. Crea la versión "loseta" (símbolo sobre un cuadrado claro redondeado), que
     es la que se ve bien tanto en fondos oscuros como claros.
  3. Genera los iconos de Android (clásico, adaptativo, monocromo), la pantalla
     de carga y los iconos de iOS.
"""
import re
import sys
from collections import deque
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
TILE = (243, 245, 246)        # fondo claro de la loseta y del icono
INK = (11, 10, 20)            # fondo oscuro de la marca (BrandColors.ink)


def dist(a, b):
    return max(abs(a[0] - b[0]), abs(a[1] - b[1]), abs(a[2] - b[2]))


def border_color(img):
    w, h = img.size
    px = img.load()
    samples = [px[x, 0] for x in range(0, w, 7)] + [px[x, h - 1] for x in range(0, w, 7)]
    samples += [px[0, y] for y in range(0, h, 7)] + [px[w - 1, y] for y in range(0, h, 7)]
    return tuple(sorted(c[i] for c in samples)[len(samples) // 2] for i in range(3))


def symbol_box(img, bg, thr=40):
    """Caja del símbolo: el primer bloque de filas con contenido (el texto va debajo)."""
    w, h = img.size
    px = img.load()
    rows = [any(dist(px[x, y], bg) > thr for x in range(0, w, 2)) for y in range(h)]
    blocks, start = [], None
    for y, filled in enumerate(rows + [False]):
        if filled and start is None:
            start = y
        elif not filled and start is not None:
            if y - start > 4:
                blocks.append((start, y))
            start = None
    top, bottom = blocks[0]
    cols = [x for x in range(w) if any(dist(px[x, y], bg) > thr for y in range(top, bottom, 2))]
    return cols[0], top, cols[-1] + 1, bottom


def cut_out(img, bg, hard=10, soft=70):
    """Fondo transparente: relleno desde los bordes por los píxeles parecidos al
    fondo, con alfa gradual en los bordes y el color de fondo descontado."""
    img = img.convert('RGB')
    w, h = img.size
    px = img.load()
    out = Image.new('RGBA', (w, h))
    op = out.load()
    seen = bytearray(w * h)
    queue = deque()
    for x in range(w):
        queue.extend([(x, 0), (x, h - 1)])
    for y in range(h):
        queue.extend([(0, y), (w - 1, y)])
    background = bytearray(w * h)
    while queue:
        x, y = queue.popleft()
        i = y * w + x
        if seen[i]:
            continue
        seen[i] = 1
        if dist(px[x, y], bg) >= soft:
            continue
        background[i] = 1
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < w and 0 <= ny < h and not seen[ny * w + nx]:
                queue.append((nx, ny))
    for y in range(h):
        for x in range(w):
            c = px[x, y]
            if not background[y * w + x]:
                op[x, y] = (*c, 255)
                continue
            d = dist(c, bg)
            a = 0.0 if d <= hard else min(1.0, (d - hard) / (soft - hard))
            if a <= 0:
                op[x, y] = (0, 0, 0, 0)
                continue
            # Quita la mezcla con el fondo para que el borde no deje halo claro.
            rgb = tuple(max(0, min(255, round((c[k] - bg[k] * (1 - a)) / a))) for k in range(3))
            op[x, y] = (*rgb, round(a * 255))
    return out


def square(symbol, size, scale):
    """Centra el símbolo en un lienzo transparente cuadrado; [scale] es la
    fracción del lado que ocupa su dimensión mayor."""
    canvas = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    w, h = symbol.size
    f = size * scale / max(w, h)
    s = symbol.resize((max(1, round(w * f)), max(1, round(h * f))), Image.LANCZOS)
    canvas.alpha_composite(s, ((size - s.width) // 2, (size - s.height) // 2))
    return canvas


def tile(symbol, size, scale=0.74, radius=0.22, full_bleed=False, color=TILE):
    base = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    mask = Image.new('L', (size, size), 0)
    d = ImageDraw.Draw(mask)
    if full_bleed:
        d.rectangle([0, 0, size, size], fill=255)
    else:
        d.rounded_rectangle([0, 0, size - 1, size - 1], radius=round(size * radius), fill=255)
    base.paste(Image.new('RGBA', (size, size), (*color, 255)), (0, 0), mask)
    base.alpha_composite(square(symbol, size, scale))
    return base


def silhouette(symbol_sq, rgb=(255, 255, 255)):
    alpha = symbol_sq.getchannel('A')
    out = Image.new('RGBA', symbol_sq.size, (*rgb, 0))
    out.putalpha(alpha)
    return out


def save(img, rel, size=None):
    path = ROOT / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    if size and img.size != (size, size):
        img = img.resize((size, size), Image.LANCZOS)
    img.save(path, optimize=True)


def main(source):
    src = Image.open(source).convert('RGB')
    bg = border_color(src)
    x0, y0, x1, y1 = symbol_box(src, bg)
    pad = 12
    crop = src.crop((max(0, x0 - pad), max(0, y0 - pad), min(src.width, x1 + pad), min(src.height, y1 + pad)))
    symbol = cut_out(crop, bg)
    symbol = symbol.crop(symbol.getbbox())
    print(f'Fondo {bg}, símbolo {symbol.size}')

    # Recursos de la app.
    symbol_sq = square(symbol, 1024, 0.96)
    save(symbol_sq, 'assets/brand/logo_symbol.png')
    save(tile(symbol, 1024), 'assets/brand/logo_tile.png')
    save(silhouette(symbol_sq), 'assets/brand/logo_symbol_white.png')
    save(tile(symbol, 1024), 'assets/brand/app_icon.png')

    res = 'android/app/src/main/res'
    for d, f in {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}.items():
        legacy = round(48 * f)
        save(tile(symbol, 1024, scale=0.76), f'{res}/mipmap-{d}/ic_launcher.png', legacy)
        adaptive = round(108 * f)
        # Zona segura del icono adaptativo: 66 dp centrales de 108.
        fg = square(symbol, 1024, 60 / 108)
        save(fg, f'{res}/mipmap-{d}/ic_launcher_foreground.png', adaptive)
        save(silhouette(fg), f'{res}/mipmap-{d}/ic_launcher_monochrome.png', adaptive)
    # Pantalla de carga: antes de Android 12, loseta de 160 dp sobre el fondo
    # oscuro; en Android 12+ el sistema pone el círculo claro (ver values-v31).
    save(tile(symbol, 1024), f'{res}/drawable-xxxhdpi/splash_logo.png', 640)
    save(square(symbol, 1152, 170 / 288), f'{res}/drawable-xxxhdpi/splash_icon.png')

    ios = ROOT / 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
    for f in ios.glob('Icon-App-*.png'):
        m = re.search(r'Icon-App-([\d.]+)x[\d.]+@(\d)x\.png$', f.name)
        if m:
            px = round(float(m[1]) * int(m[2]))
            # iOS no admite transparencia y redondea las esquinas él mismo.
            icon = tile(symbol, 1024, scale=0.76, full_bleed=True).convert('RGB')
            icon.resize((px, px), Image.LANCZOS).save(f, optimize=True)
    print('Recursos generados.')


if __name__ == '__main__':
    main(sys.argv[1])
