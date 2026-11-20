"""Генерує іконки та графіку інсталерів Optimizator.
Запуск: python3 tools/make_assets.py  (потрібен Pillow)
"""
import math
import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WIN = os.path.join(ROOT, "Windows", "Assets")
MAC = os.path.join(ROOT, "macOS", "Assets")
INST = os.path.join(ROOT, "Windows", "installer")
PKG = os.path.join(ROOT, "macOS", "packaging", "resources")
for d in (WIN, MAC, INST, PKG):
    os.makedirs(d, exist_ok=True)

ACCENT_A = (167, 139, 250)   # #A78BFA
ACCENT_B = (124, 58, 237)    # #7C3AED
BG_TOP = (36, 30, 52)
BG_BOT = (12, 12, 17)
S = 4  # суперсемплінг


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def vgradient(w, h, top, bot):
    g = Image.new("RGB", (1, h))
    for y in range(h):
        g.putpixel((0, y), lerp(top, bot, y / max(1, h - 1)))
    return g.resize((w, h))


def dgradient(w, h, a, b):
    """Діагональний градієнт (зліва-зверху -> справа-знизу)."""
    small = Image.new("RGB", (64, 64))
    for y in range(64):
        for x in range(64):
            small.putpixel((x, y), lerp(a, b, (x + y) / 126))
    return small.resize((w, h), Image.BICUBIC)


def logo(size, pad_ratio=0.0, radius_ratio=0.225, shadow=False):
    """Квадрат із заокругленими кутами, кільце-градієнт і блискавка."""
    W = size * S
    img = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    pad = int(W * pad_ratio)
    box = W - 2 * pad
    r = int(box * radius_ratio)

    if shadow:
        sh = Image.new("RGBA", (W, W), (0, 0, 0, 0))
        ImageDraw.Draw(sh).rounded_rectangle(
            [pad, pad + int(W * 0.012), pad + box, pad + box + int(W * 0.012)], r, fill=(0, 0, 0, 150))
        sh = sh.filter(ImageFilter.GaussianBlur(W * 0.018))
        img.alpha_composite(sh)

    mask = Image.new("L", (W, W), 0)
    ImageDraw.Draw(mask).rounded_rectangle([pad, pad, pad + box, pad + box], r, fill=255)
    bg = vgradient(W, W, BG_TOP, BG_BOT).convert("RGBA")
    img.paste(bg, (0, 0), mask)

    # тонка світла обводка
    edge = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ImageDraw.Draw(edge).rounded_rectangle([pad, pad, pad + box, pad + box], r,
                                           outline=(255, 255, 255, 28), width=max(1, int(W * 0.004)))
    img.alpha_composite(edge)

    cx = cy = W / 2
    # м'яке світіння
    glow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    gr = box * 0.34
    ImageDraw.Draw(glow).ellipse([cx - gr, cy - gr, cx + gr, cy + gr], fill=ACCENT_B + (110,))
    glow = glow.filter(ImageFilter.GaussianBlur(box * 0.09))
    glow_masked = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    glow_masked.paste(glow, (0, 0), mask)
    img.alpha_composite(glow_masked)

    # кільце
    ro, ri = box * 0.33, box * 0.255
    ring = Image.new("L", (W, W), 0)
    d = ImageDraw.Draw(ring)
    d.ellipse([cx - ro, cy - ro, cx + ro, cy + ro], fill=255)
    d.ellipse([cx - ri, cy - ri, cx + ri, cy + ri], fill=0)
    img.paste(dgradient(W, W, ACCENT_A, ACCENT_B).convert("RGBA"), (0, 0), ring)

    # блискавка
    pts = [(0.20, -1.0), (-0.60, 0.15), (-0.02, 0.15), (-0.22, 1.0), (0.60, -0.22), (0.04, -0.22), (0.36, -1.0)]
    sx, sy = box * 0.155, box * 0.205
    poly = [(cx + x * sx, cy + y * sy) for x, y in pts]
    bm = Image.new("L", (W, W), 0)
    ImageDraw.Draw(bm).polygon(poly, fill=255)
    bolt = vgradient(W, W, (255, 255, 255), (221, 214, 254)).convert("RGBA")
    img.paste(bolt, (0, 0), bm)

    return img.resize((size, size), Image.LANCZOS)


def font(px, bold=True):
    for p in ["/usr/share/fonts/opentype/inter/Inter-SemiBold.otf" if bold else "/usr/share/fonts/opentype/inter/Inter-Regular.otf",
              "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"]:
        if os.path.exists(p):
            return ImageFont.truetype(p, px)
    return ImageFont.load_default()


# ---------- macOS: 1024 з відступом за сіткою Apple ----------
mac = logo(1024, pad_ratio=0.098, radius_ratio=0.225, shadow=True)
mac.save(os.path.join(MAC, "icon-1024.png"))

# ---------- Windows: .ico ----------
win = logo(256, pad_ratio=0.02, radius_ratio=0.22)
win.save(os.path.join(WIN, "app.ico"), sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
win.save(os.path.join(WIN, "app-256.png"))


# ---------- Inno Setup: бокова картинка майстра ----------
def wizard_large(w, h):
    im = vgradient(w, h, BG_TOP, BG_BOT).convert("RGBA")
    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([-w * 0.4, h * 0.15, w * 1.4, h * 0.75], fill=ACCENT_B + (70,))
    im.alpha_composite(glow.filter(ImageFilter.GaussianBlur(w * 0.25)))
    ls = int(w * 0.56)
    im.alpha_composite(logo(ls, pad_ratio=0.0), (int((w - ls) / 2), int(h * 0.26)))
    d = ImageDraw.Draw(im)
    f1, f2 = font(int(w * 0.13)), font(int(w * 0.068), bold=False)
    t1, t2 = "Optimizator", "FPS optimizer"
    y = int(h * 0.26) + ls + int(h * 0.05)
    d.text(((w - d.textlength(t1, font=f1)) / 2, y), t1, font=f1, fill=(237, 237, 242))
    d.text(((w - d.textlength(t2, font=f2)) / 2, y + int(w * 0.17)), t2, font=f2, fill=(160, 150, 190))
    return im.convert("RGB")


wizard_large(164, 314).save(os.path.join(INST, "wizard-large-100.bmp"))
wizard_large(328, 628).save(os.path.join(INST, "wizard-large-200.bmp"))


def wizard_small(w, h):
    im = Image.new("RGBA", (w, h), (255, 255, 255, 255))
    s = int(min(w, h) * 0.92)
    im.alpha_composite(logo(s, pad_ratio=0.0), ((w - s) // 2, (h - s) // 2))
    return im.convert("RGB")


wizard_small(55, 55).save(os.path.join(INST, "wizard-small-100.bmp"))
wizard_small(110, 106).save(os.path.join(INST, "wizard-small-200.bmp"))

# ---------- macOS Installer: фон (лого внизу ліворуч, напівпрозоре) ----------
bgp = Image.new("RGBA", (620, 418), (0, 0, 0, 0))
lg = logo(190, pad_ratio=0.0)
lg.putalpha(lg.getchannel("A").point(lambda a: int(a * 0.35)))
bgp.alpha_composite(lg, (-30, 418 - 190 + 30))
bgp.save(os.path.join(PKG, "background.png"))

print("assets ok")
