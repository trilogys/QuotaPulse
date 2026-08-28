from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "AIQuotaApp" / "Assets.xcassets" / "AppIcon.appiconset"
OUT.mkdir(parents=True, exist_ok=True)

CANVAS = 2048


def rounded_line(draw, points, fill, width):
    draw.line(points, fill=fill, width=width, joint="curve")
    radius = width // 2
    for x, y in (points[0], points[-1]):
        draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=fill)


# A nearly-black neutral background keeps the mark legible across every iOS
# appearance while the warm white and mint prevent the icon feeling monochrome.
image = Image.new("RGB", (CANVAS, CANVAS), "#0A0D12")
pixels = image.load()
for y in range(CANVAS):
    for x in range(CANVAS):
        dx = (x - CANVAS * 0.42) / CANVAS
        dy = (y - CANVAS * 0.30) / CANVAS
        glow = max(0.0, 1.0 - (dx * dx + dy * dy) ** 0.5 * 1.65)
        pixels[x, y] = (
            int(10 + 9 * glow),
            int(13 + 12 * glow),
            int(18 + 17 * glow),
        )

# Use a soft shadow only to preserve the silhouette at small icon sizes.
shadow = Image.new("RGBA", image.size, (0, 0, 0, 0))
shadow_draw = ImageDraw.Draw(shadow)
ring_box = (430, 390, 1618, 1578)
shadow_draw.ellipse(ring_box, outline="#000000", width=190)
rounded_line(shadow_draw, [(1198, 1180), (1510, 1492)], "#000000", 190)
shadow = shadow.filter(ImageFilter.GaussianBlur(36))
image = Image.alpha_composite(image.convert("RGBA"), shadow)

draw = ImageDraw.Draw(image)

# The single ring reads as both a Q and an at-a-glance quota gauge.
draw.ellipse(ring_box, outline="#F5F2EA", width=164)
draw.arc(ring_box, start=205, end=305, fill="#55E6B1", width=164)

# The Q tail shares the progress color and is deliberately separated from the
# pulse so the mark remains clear at 20 pt.
rounded_line(draw, [(1198, 1180), (1510, 1492)], "#55E6B1", 154)

# A compact heartbeat line makes "Pulse" explicit without adding text.
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

master = image.convert("RGB").resize((1024, 1024), Image.Resampling.LANCZOS)

outputs = {
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

for filename, size in outputs.items():
    master.resize((size, size), Image.Resampling.LANCZOS).save(
        OUT / filename,
        format="PNG",
        optimize=True,
    )

print(f"Generated {len(outputs)} app icon images in {OUT}")
