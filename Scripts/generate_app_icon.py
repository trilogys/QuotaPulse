import json
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "QuotaPulseApp" / "Assets.xcassets"
CANVAS = 2048

OUTPUTS = {
    "AppIcon-20x20@1x.png": 20,
    "AppIcon-20x20@2x.png": 40,
    "AppIcon-20x20@3x.png": 60,
    "AppIcon-29x29@1x.png": 29,
    "AppIcon-29x29@2x.png": 58,
    "AppIcon-29x29@3x.png": 87,
    "AppIcon-40x40@1x.png": 40,
    "AppIcon-40x40@2x.png": 80,
    "AppIcon-40x40@3x.png": 120,
    "AppIcon-60x60@2x.png": 120,
    "AppIcon-60x60@3x.png": 180,
    "AppIcon-76x76@1x.png": 76,
    "AppIcon-76x76@2x.png": 152,
    "AppIcon-83.5x83.5@2x.png": 167,
    "AppIcon-1024x1024@1x.png": 1024,
}

CONTENTS_IMAGES = [
    ("AppIcon-20x20@2x.png", "iphone", "2x", "20x20"),
    ("AppIcon-20x20@3x.png", "iphone", "3x", "20x20"),
    ("AppIcon-29x29@2x.png", "iphone", "2x", "29x29"),
    ("AppIcon-29x29@3x.png", "iphone", "3x", "29x29"),
    ("AppIcon-40x40@2x.png", "iphone", "2x", "40x40"),
    ("AppIcon-40x40@3x.png", "iphone", "3x", "40x40"),
    ("AppIcon-60x60@2x.png", "iphone", "2x", "60x60"),
    ("AppIcon-60x60@3x.png", "iphone", "3x", "60x60"),
    ("AppIcon-20x20@1x.png", "ipad", "1x", "20x20"),
    ("AppIcon-20x20@2x.png", "ipad", "2x", "20x20"),
    ("AppIcon-29x29@1x.png", "ipad", "1x", "29x29"),
    ("AppIcon-29x29@2x.png", "ipad", "2x", "29x29"),
    ("AppIcon-40x40@1x.png", "ipad", "1x", "40x40"),
    ("AppIcon-40x40@2x.png", "ipad", "2x", "40x40"),
    ("AppIcon-76x76@1x.png", "ipad", "1x", "76x76"),
    ("AppIcon-76x76@2x.png", "ipad", "2x", "76x76"),
    ("AppIcon-83.5x83.5@2x.png", "ipad", "2x", "83.5x83.5"),
    ("AppIcon-1024x1024@1x.png", "ios-marketing", "1x", "1024x1024"),
]


def rounded_line(draw, points, fill, width):
    draw.line(points, fill=fill, width=width, joint="curve")
    radius = width // 2
    for x, y in (points[0], points[-1]):
        draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=fill)


def light_background():
    image = Image.new("RGB", (CANVAS, CANVAS), "#F7FBF9")
    glow = Image.new("RGBA", image.size, (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    glow_draw.ellipse((180, 100, 1740, 1660), fill=(104, 224, 174, 24))
    glow = glow.filter(ImageFilter.GaussianBlur(260))
    return Image.alpha_composite(image.convert("RGBA"), glow)


def dark_background():
    image = Image.new("RGB", (CANVAS, CANVAS), "#0A0D12")
    pixels = image.load()
    for y in range(CANVAS):
        for x in range(CANVAS):
            dx = (x - CANVAS * 0.42) / CANVAS
            dy = (y - CANVAS * 0.30) / CANVAS
            glow = max(0.0, 1.0 - math.sqrt(dx * dx + dy * dy) * 1.65)
            pixels[x, y] = (
                int(10 + 9 * glow),
                int(13 + 12 * glow),
                int(18 + 17 * glow),
            )
    return image.convert("RGBA")


def add_shadow(image, ring_box, ring_width, tail, tail_width, full_ring):
    shadow = Image.new("RGBA", image.size, (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    if full_ring:
        shadow_draw.ellipse(ring_box, outline=(0, 35, 24, 70), width=ring_width)
    else:
        shadow_draw.arc(ring_box, start=72, end=342, fill=(0, 35, 24, 70), width=ring_width)
    rounded_line(shadow_draw, tail, (0, 35, 24, 70), tail_width)
    shadow = shadow.filter(ImageFilter.GaussianBlur(34))
    return Image.alpha_composite(image, shadow)


def draw_current():
    ring_box = (430, 390, 1618, 1578)
    tail = [(1190, 1165), (1400, 1375)]
    image = add_shadow(light_background(), ring_box, 184, tail, 142, False)
    draw = ImageDraw.Draw(image)

    draw.ellipse(ring_box, outline="#DCEFE7", width=164)
    draw.arc(ring_box, start=72, end=342, fill="#0B6B50", width=164)
    draw.arc(ring_box, start=205, end=292, fill="#4FD39A", width=164)
    rounded_line(draw, tail, "#0B6B50", 142)
    rounded_line(draw, tail, "#4FD39A", 54)

    pulse = [
        (650, 1000),
        (820, 1000),
        (910, 850),
        (1010, 1152),
        (1112, 928),
        (1190, 1000),
        (1380, 1000),
    ]
    rounded_line(draw, pulse, "#155E4B", 60)
    rounded_line(draw, [(1010, 1152), (1112, 928)], "#4FD39A", 34)
    return image


def draw_classic():
    ring_box = (430, 390, 1618, 1578)
    tail = [(1198, 1180), (1510, 1492)]
    image = add_shadow(light_background(), ring_box, 184, tail, 154, True)
    draw = ImageDraw.Draw(image)

    draw.ellipse(ring_box, outline="#0E6B50", width=164)
    draw.arc(ring_box, start=205, end=305, fill="#55DCA4", width=164)
    rounded_line(draw, tail, "#55DCA4", 154)
    pulse = [
        (650, 1000),
        (820, 1000),
        (910, 850),
        (1010, 1152),
        (1112, 928),
        (1190, 1000),
        (1380, 1000),
    ]
    rounded_line(draw, pulse, "#0E6B50", 64)
    return image


def draw_night():
    ring_box = (430, 390, 1618, 1578)
    tail = [(1198, 1180), (1510, 1492)]
    image = add_shadow(dark_background(), ring_box, 190, tail, 190, True)
    draw = ImageDraw.Draw(image)

    draw.ellipse(ring_box, outline="#F5F2EA", width=164)
    draw.arc(ring_box, start=205, end=305, fill="#55E6B1", width=164)
    rounded_line(draw, tail, "#55E6B1", 154)
    pulse = [
        (650, 1000),
        (820, 1000),
        (910, 850),
        (1010, 1152),
        (1112, 928),
        (1190, 1000),
        (1380, 1000),
    ]
    rounded_line(draw, pulse, "#F5F2EA", 64)
    return image


def write_appiconset(name, image):
    output = ASSETS / f"{name}.appiconset"
    output.mkdir(parents=True, exist_ok=True)
    master = image.convert("RGB").resize((1024, 1024), Image.Resampling.LANCZOS)
    for filename, size in OUTPUTS.items():
        master.resize((size, size), Image.Resampling.LANCZOS).save(
            output / filename,
            format="PNG",
            optimize=True,
        )

    contents = {
        "images": [
            {"filename": filename, "idiom": idiom, "scale": scale, "size": size}
            for filename, idiom, scale, size in CONTENTS_IMAGES
        ],
        "info": {"author": "xcode", "version": 1},
    }
    (output / "Contents.json").write_text(
        json.dumps(contents, indent=2, ensure_ascii=True) + "\n",
        encoding="utf-8",
    )
    return master


def write_preview(name, master):
    output = ASSETS / f"{name}.imageset"
    output.mkdir(parents=True, exist_ok=True)
    master.resize((180, 180), Image.Resampling.LANCZOS).save(
        output / "preview.png",
        format="PNG",
        optimize=True,
    )
    contents = {
        "images": [
            {"filename": "preview.png", "idiom": "universal", "scale": "1x"},
            {"idiom": "universal", "scale": "2x"},
            {"idiom": "universal", "scale": "3x"},
        ],
        "info": {"author": "xcode", "version": 1},
    }
    (output / "Contents.json").write_text(
        json.dumps(contents, indent=2, ensure_ascii=True) + "\n",
        encoding="utf-8",
    )


def main():
    variants = [
        ("AppIcon", "AppIconClassicPreview", draw_classic()),
        ("AppIconClassic", "AppIconCurrentPreview", draw_current()),
        ("AppIconNight", "AppIconNightPreview", draw_night()),
    ]
    for icon_name, preview_name, image in variants:
        master = write_appiconset(icon_name, image)
        write_preview(preview_name, master)
    print("Generated 3 app icon sets and 3 Settings previews")


if __name__ == "__main__":
    main()
