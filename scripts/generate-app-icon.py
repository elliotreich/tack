#!/usr/bin/env python3

import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw


SIZE = 1024
SCALE = 4


def scaled_box(box):
    return tuple(int(value * SCALE) for value in box)


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: generate-app-icon.py OUTPUT.png")

    output = Path(sys.argv[1])
    high_size = SIZE * SCALE
    base = Image.new("RGB", (SIZE, SIZE))
    pixels = base.load()
    top = (20, 34, 57)
    bottom = (61, 35, 78)
    for y in range(SIZE):
        t = y / (SIZE - 1)
        for x in range(SIZE):
            glow = 0.08 * (1 - math.hypot(x - 700, y - 210) / 900)
            pixels[x, y] = tuple(
                max(0, min(255, int(top[index] * (1 - t) + bottom[index] * t + glow * 255)))
                for index in range(3)
            )

    image = base.resize((high_size, high_size), Image.Resampling.BICUBIC).convert("RGBA")
    texture = Image.new("RGBA", image.size)
    texture_draw = ImageDraw.Draw(texture)
    for x in range(-high_size, high_size * 2, 96):
        texture_draw.line((x, 0, x + high_size, high_size), fill=(255, 255, 255, 10), width=3)
    image = Image.alpha_composite(image, texture)

    card = Image.new("RGBA", (700 * SCALE, 570 * SCALE))
    card_draw = ImageDraw.Draw(card)
    card_draw.rounded_rectangle(
        scaled_box((24, 28, 676, 548)),
        radius=42 * SCALE,
        fill=(0, 0, 0, 95),
    )
    card_draw.rounded_rectangle(
        scaled_box((12, 12, 664, 532)),
        radius=42 * SCALE,
        fill=(250, 246, 229, 255),
        outline=(255, 255, 255, 120),
        width=3 * SCALE,
    )
    card_draw.polygon(
        [
            (664 * SCALE, 12 * SCALE),
            (664 * SCALE, 142 * SCALE),
            (534 * SCALE, 12 * SCALE),
        ],
        fill=(229, 221, 198, 255),
    )
    card_draw.line((534 * SCALE, 12 * SCALE, 664 * SCALE, 142 * SCALE), fill=(203, 193, 166, 190), width=3 * SCALE)

    card_draw.rounded_rectangle(scaled_box((86, 175, 410, 205)), radius=15 * SCALE, fill=(35, 49, 73, 230))
    card_draw.rounded_rectangle(scaled_box((86, 237, 560, 267)), radius=15 * SCALE, fill=(35, 49, 73, 110))
    card_draw.rounded_rectangle(scaled_box((86, 299, 480, 329)), radius=15 * SCALE, fill=(35, 49, 73, 110))
    card_draw.rounded_rectangle(scaled_box((86, 382, 214, 500)), radius=22 * SCALE, fill=(238, 114, 96, 230))
    card_draw.rounded_rectangle(scaled_box((246, 382, 374, 500)), radius=22 * SCALE, fill=(80, 167, 174, 230))
    card_draw.rounded_rectangle(scaled_box((406, 382, 534, 500)), radius=22 * SCALE, fill=(225, 177, 83, 230))

    rotated_card = card.rotate(8, resample=Image.Resampling.BICUBIC, expand=True)
    card_x = (high_size - rotated_card.width) // 2
    card_y = 330 * SCALE - rotated_card.height // 2
    image.alpha_composite(rotated_card, (card_x, card_y))

    pin = Image.new("RGBA", (260 * SCALE, 360 * SCALE))
    pin_draw = ImageDraw.Draw(pin)
    pin_draw.ellipse(scaled_box((48, 34, 214, 200)), fill=(0, 0, 0, 100))
    pin_draw.polygon(
        [
            (112 * SCALE, 160 * SCALE),
            (178 * SCALE, 160 * SCALE),
            (146 * SCALE, 332 * SCALE),
            (124 * SCALE, 332 * SCALE),
        ],
        fill=(169, 60, 59, 255),
    )
    pin_draw.ellipse(scaled_box((34, 20, 206, 192)), fill=(238, 91, 86, 255), outline=(255, 173, 143, 180), width=5 * SCALE)
    pin_draw.ellipse(scaled_box((73, 48, 125, 100)), fill=(255, 205, 178, 200))
    image.alpha_composite(pin, ((high_size - pin.width) // 2, 72 * SCALE))

    final = image.resize((SIZE, SIZE), Image.Resampling.LANCZOS).convert("RGB")
    output.parent.mkdir(parents=True, exist_ok=True)
    final.save(output, format="PNG", optimize=True)


if __name__ == "__main__":
    main()
