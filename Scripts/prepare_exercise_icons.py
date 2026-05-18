#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = ROOT / "GymTracker" / "IconSource" / "ExerciseIcons"
ASSET_DIR = ROOT / "GymTracker" / "Assets.xcassets" / "ExerciseIcons"

ICON_MAP = {
    "Bicep Curl.png": "icon_exercise_bicep_curl",
    "Chest fly.png": "icon_exercise_chest_fly",
    "Diverging Row.png": "icon_exercise_diverging_row",
    "Dumbel Shoulder Press.png": "icon_exercise_dumbbell_shoulder_press",
    "HackSquat.png": "icon_exercise_hack_squat",
    "Hip Adduction.png": "icon_exercise_hip_adduction",
    "Incline Chest Press.png": "icon_exercise_incline_chest_press",
    "Lat Pulldown.png": "icon_exercise_lat_pulldown",
    "Leg Curl.png": "icon_exercise_leg_curl",
    "Leg Extension.png": "icon_exercise_leg_extension",
    "Leg press.png": "icon_exercise_leg_press",
    "legs.png": "icon_exercise_legs",
    "Push.png": "icon_exercise_generic_push",
    "Pull.png": "icon_exercise_generic_pull",
    "Pull ups.png": "icon_exercise_pull_ups",
    "Standing Calf Raise.png": "icon_exercise_standing_calf_raise",
    "Tricep Push Down.png": "icon_exercise_tricep_push_down",
}

STRICT_ICON_SOURCES = {"Push.png", "Pull.png"}


def is_green_icon_pixel(r: int, g: int, b: int, alpha: int, *, strict: bool = False) -> bool:
    if alpha == 0:
        return False

    brightness = max(r, g, b)
    saturation = brightness - min(r, g, b)

    if strict:
        return (
            g > 155
            and g > r + 22
            and g > b + 35
            and saturation > 55
        )

    return (
        g > 72
        and g > r + 16
        and g > b + 16
        and saturation > 28
    )


def trim_to_square(image: Image.Image, padding_ratio: float = 0.10) -> Image.Image:
    bbox = image.getchannel("A").getbbox()
    if bbox is None:
        return image

    left, top, right, bottom = bbox
    width = right - left
    height = bottom - top
    padding = max(10, int(max(width, height) * padding_ratio))
    side = max(width, height) + padding * 2

    center_x = (left + right) // 2
    center_y = (top + bottom) // 2
    crop_left = center_x - side // 2
    crop_top = center_y - side // 2

    output = Image.new("RGBA", (side, side), (255, 255, 255, 0))
    paste_x = max(0, -crop_left)
    paste_y = max(0, -crop_top)

    source_crop = image.crop((
        max(0, crop_left),
        max(0, crop_top),
        min(image.width, crop_left + side),
        min(image.height, crop_top + side),
    ))
    output.paste(source_crop, (paste_x, paste_y))
    return output


def template_mask(source: Path, *, strict: bool = False, trim: bool = False) -> Image.Image:
    source_image = Image.open(source).convert("RGBA")
    output = Image.new("RGBA", source_image.size, (255, 255, 255, 0))

    source_pixels = source_image.load()
    output_pixels = output.load()

    width, height = source_image.size
    for y in range(height):
        for x in range(width):
            r, g, b, alpha = source_pixels[x, y]
            if not is_green_icon_pixel(r, g, b, alpha, strict=strict):
                continue

            brightness = max(r, g, b)
            saturation = brightness - min(r, g, b)
            edge_alpha = min(255, max(96, int(saturation * 2.2), int((g - max(r, b)) * 4.0)))
            output_pixels[x, y] = (255, 255, 255, edge_alpha)

    if trim:
        return trim_to_square(output, padding_ratio=0.10)

    return output


def write_contents_json(imageset_dir: Path, filename: str) -> None:
    contents = {
        "images": [
            {
                "filename": filename,
                "idiom": "universal",
                "scale": "1x",
            }
        ],
        "info": {
            "author": "xcode",
            "version": 1,
        },
        "properties": {
            "template-rendering-intent": "template",
        },
    }

    with (imageset_dir / "Contents.json").open("w", encoding="utf-8") as file:
        json.dump(contents, file, indent=2)
        file.write("\n")


def prepare_icon(source_name: str, asset_name: str) -> None:
    source = SOURCE_DIR / source_name
    if not source.exists():
        raise FileNotFoundError(source)

    imageset_dir = ASSET_DIR / f"{asset_name}.imageset"
    imageset_dir.mkdir(parents=True, exist_ok=True)

    for child in imageset_dir.iterdir():
        if child.name != "Contents.json":
            child.unlink()

    filename = f"{asset_name}.png"
    use_strict_detection = source_name in STRICT_ICON_SOURCES
    template_mask(source, strict=use_strict_detection, trim=use_strict_detection).save(imageset_dir / filename)
    write_contents_json(imageset_dir, filename)


def main() -> None:
    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    for source_name, asset_name in ICON_MAP.items():
        prepare_icon(source_name, asset_name)
        print(f"{source_name} -> {asset_name}")


if __name__ == "__main__":
    main()
