#!/usr/bin/env python3
"""Import the pinned Workout Guide SVG collection into an Xcode asset catalog.

The imported SVGs are deliberately kept as upstream vector data.  Peakline
loads these image sets with template rendering, so their white monochrome
paths become the active Peakline accent through ``ExerciseIconView`` in both
light and dark themes.

Example:

    python3 Scripts/import_workout_guide_assets.py \
        --source /path/to/workout-guide \
        --output GymTracker/Assets.xcassets/WorkoutGuide

The source checkout is expected to be at the pinned commit declared below.
The script can also validate an existing import without changing it:

    python3 Scripts/import_workout_guide_assets.py \
        --source /path/to/workout-guide \
        --output GymTracker/Assets.xcassets/WorkoutGuide --check
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ElementTree
from pathlib import Path
from typing import Iterable
from urllib.parse import urlparse
from urllib.request import urlopen


UPSTREAM_REPOSITORY = "https://github.com/bryllim/workout-guide.git"
PINNED_COMMIT = "aac599224bb9780305239607ef98540b7e0ce389"
EXPECTED_EXERCISES = 302
EXPECTED_FRAMES_PER_EXERCISE = 3
EXPECTED_FRAMES = EXPECTED_EXERCISES * EXPECTED_FRAMES_PER_EXERCISE

_SVG_NAMESPACE = "http://www.w3.org/2000/svg"
_SAFE_COLOURS = {"#fff", "#ffffff", "white", "none"}
_COLOUR_ATTRIBUTES = {"color", "fill", "stroke", "stop-color"}
_HEX_COLOUR = re.compile(r"^#[0-9a-fA-F]{3,8}$")
_LOCAL_NAME = re.compile(r"^[a-z0-9]+(?:[-_][a-z0-9]+)*$")


class ImportError(RuntimeError):
    """Raised when the upstream collection is incomplete or not template-safe."""


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source",
        type=Path,
        help=(
            "Workout Guide checkout, package directory, or repository URL. "
            "A URL is cloned at the pinned commit."
        ),
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("GymTracker/Assets.xcassets/WorkoutGuide"),
        help="Destination WorkoutGuide asset group (default: %(default)s)",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Validate source and an existing destination without writing files",
    )
    return parser.parse_args()


def source_asset_root(source: Path) -> Path:
    """Return ``packages/workout-guide/assets`` for any supported checkout path."""

    candidates = (
        source / "packages/workout-guide/assets",
        source / "assets",
        source,
    )
    for candidate in candidates:
        if candidate.is_dir() and any(candidate.glob("*/frame-1.svg")):
            return candidate
    raise ImportError(
        f"Could not find Workout Guide SVG assets below {source}. "
        "Pass the repository checkout or packages/workout-guide directory."
    )


def source_commit(source: Path) -> str | None:
    """Read the checkout commit when the source is a Git repository."""

    for candidate in (source, source / "packages/workout-guide"):
        try:
            completed = subprocess.run(
                ["git", "-C", str(candidate), "rev-parse", "HEAD"],
                check=True,
                capture_output=True,
                text=True,
            )
        except (OSError, subprocess.CalledProcessError):
            continue
        return completed.stdout.strip()
    return None


def resolve_source(source: Path | None) -> tuple[Path, tempfile.TemporaryDirectory[str] | None]:
    """Resolve a local checkout or clone the pinned repository for a URL."""

    if source is None:
        raise ImportError(
            "--source is required. Fetch the pinned repository first with "
            f"git clone {UPSTREAM_REPOSITORY} and checkout {PINNED_COMMIT}."
        )

    parsed = urlparse(str(source))
    if parsed.scheme in {"http", "https", "git", "ssh"}:
        temporary_directory = tempfile.TemporaryDirectory(prefix="workout-guide-")
        checkout = Path(temporary_directory.name) / "source"
        subprocess.run(
            ["git", "clone", "--no-checkout", str(source), str(checkout)],
            check=True,
        )
        subprocess.run(
            ["git", "-C", str(checkout), "checkout", "--detach", PINNED_COMMIT],
            check=True,
        )
        return checkout, temporary_directory

    return source.expanduser().resolve(), None


def slug_to_asset_prefix(slug: str) -> str:
    """Convert a source slug to the stable Swift/Xcode asset prefix."""

    if not _LOCAL_NAME.fullmatch(slug):
        raise ImportError(f"Unsafe or unsupported exercise slug: {slug!r}")
    return "workout_guide_" + slug.replace("-", "_")


def svg_size(root: ElementTree.Element, path: Path) -> tuple[int, int]:
    width = root.attrib.get("width")
    height = root.attrib.get("height")
    view_box = root.attrib.get("viewBox", "").split()
    if width is None or height is None or len(view_box) != 4:
        raise ImportError(f"{path} must declare width, height, and a four-part viewBox")

    def pixel_dimension(value: str) -> int:
        match = re.fullmatch(r"(\d+)(?:px)?", value.strip())
        if not match:
            raise ImportError(f"{path} has unsupported SVG dimension {value!r}")
        return int(match.group(1))

    if pixel_dimension(width) != 512 or pixel_dimension(height) != 512:
        raise ImportError(f"{path} is not a 512 × 512 SVG")

    try:
        view_box_values = tuple(float(value) for value in view_box)
    except ValueError as error:
        raise ImportError(f"{path} has an invalid viewBox") from error
    if view_box_values != (0.0, 0.0, 512.0, 512.0):
        raise ImportError(f"{path} must use viewBox 0 0 512 512")
    return 512, 512


def validate_svg(path: Path) -> tuple[int, int]:
    """Validate one SVG for Xcode template rendering and return its dimensions."""

    try:
        root = ElementTree.parse(path).getroot()
    except (ElementTree.ParseError, OSError) as error:
        raise ImportError(f"Could not parse SVG {path}: {error}") from error

    if root.tag != f"{{{_SVG_NAMESPACE}}}svg":
        raise ImportError(f"{path} does not have an SVG root element")
    width, height = svg_size(root, path)
    path_elements = 0

    for element in root.iter():
        local_tag = element.tag.rsplit("}", 1)[-1]
        if local_tag == "image":
            raise ImportError(f"{path} contains an embedded raster image")
        if local_tag in {"foreignObject", "script", "style"}:
            raise ImportError(f"{path} contains unsupported non-vector SVG content: {local_tag}")
        if local_tag == "path":
            path_elements += 1
        for attribute, value in element.attrib.items():
            local_attribute = attribute.rsplit("}", 1)[-1].lower()
            if local_attribute == "style":
                raise ImportError(f"{path} contains a CSS style declaration")
            if local_attribute not in _COLOUR_ATTRIBUTES:
                continue
            normalized = value.strip().lower()
            if normalized not in _SAFE_COLOURS:
                raise ImportError(
                    f"{path} has non-template colour {value!r}; "
                    "only white/none source fills are allowed"
                )
            if normalized.startswith("#") and not _HEX_COLOUR.fullmatch(normalized):
                raise ImportError(f"{path} has malformed colour {value!r}")

    if path_elements == 0:
        raise ImportError(f"{path} contains no vector paths")
    return width, height


def discover_frames(asset_root: Path) -> list[tuple[str, int, Path]]:
    """Discover and validate every exercise's three ordered SVG frames."""

    frames: list[tuple[str, int, Path]] = []
    exercise_dirs = sorted(path for path in asset_root.iterdir() if path.is_dir())
    if len(exercise_dirs) != EXPECTED_EXERCISES:
        raise ImportError(
            f"Expected {EXPECTED_EXERCISES} exercise directories, found {len(exercise_dirs)}"
        )

    for exercise_dir in exercise_dirs:
        slug = exercise_dir.name
        slug_to_asset_prefix(slug)
        for frame_index in range(1, EXPECTED_FRAMES_PER_EXERCISE + 1):
            frame_path = exercise_dir / f"frame-{frame_index}.svg"
            if not frame_path.is_file():
                raise ImportError(f"Missing frame {frame_index} for {slug}")
            validate_svg(frame_path)
            frames.append((slug, frame_index, frame_path))

        unexpected = sorted(
            path.name
            for path in exercise_dir.iterdir()
            if path.is_file() and path.suffix.lower() == ".svg" and path.name not in {
                f"frame-{index}.svg" for index in range(1, EXPECTED_FRAMES_PER_EXERCISE + 1)
            }
        )
        if unexpected:
            raise ImportError(f"Unexpected SVG frames for {slug}: {', '.join(unexpected)}")

    if len(frames) != EXPECTED_FRAMES:
        raise ImportError(f"Expected {EXPECTED_FRAMES} SVG frames, found {len(frames)}")
    return frames


def contents_json(filename: str) -> dict[str, object]:
    return {
        "images": [{"filename": filename, "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
        "properties": {
            "preserves-vector-representation": True,
            "template-rendering-intent": "template",
        },
    }


def group_contents_json() -> dict[str, object]:
    return {"info": {"author": "xcode", "version": 1}}


def write_json(path: Path, value: dict[str, object]) -> None:
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def expected_assets(frames: Iterable[tuple[str, int, Path]]) -> list[tuple[str, int, Path, str]]:
    return [
        (slug, index, source_path, f"{slug_to_asset_prefix(slug)}_frame_{index}")
        for slug, index, source_path in frames
    ]


def validate_destination(output: Path, frames: Iterable[tuple[str, int, Path]]) -> None:
    if not output.is_dir():
        raise ImportError(f"Destination does not exist: {output}")
    group_contents = output / "Contents.json"
    if not group_contents.is_file():
        raise ImportError(f"Missing asset group metadata: {group_contents}")
    if json.loads(group_contents.read_text(encoding="utf-8")) != group_contents_json():
        raise ImportError(f"Unexpected asset group metadata: {group_contents}")

    expected = expected_assets(frames)
    actual_sets = sorted(path for path in output.glob("*.imageset") if path.is_dir())
    if len(actual_sets) != EXPECTED_FRAMES:
        raise ImportError(f"Expected {EXPECTED_FRAMES} imagesets, found {len(actual_sets)}")

    for _slug, _index, _source_path, asset_name in expected:
        imageset = output / f"{asset_name}.imageset"
        svg = imageset / f"{asset_name}.svg"
        contents = imageset / "Contents.json"
        if not imageset.is_dir() or not svg.is_file() or not contents.is_file():
            raise ImportError(f"Incomplete imageset: {imageset}")
        if json.loads(contents.read_text(encoding="utf-8")) != contents_json(svg.name):
            raise ImportError(f"Unexpected template metadata: {contents}")
        if svg.read_bytes() != _source_path.read_bytes():
            raise ImportError(f"Imported SVG differs from its pinned source: {svg}")
        validate_svg(svg)


def import_assets(source: Path, output: Path, check: bool) -> None:
    asset_root = source_asset_root(source)
    commit = source_commit(source)
    if commit != PINNED_COMMIT:
        raise ImportError(
            f"Source checkout is {commit or 'not a Git checkout'}, expected pinned commit "
            f"{PINNED_COMMIT}"
        )
    frames = discover_frames(asset_root)

    if check:
        validate_destination(output, frames)
        print(f"Validated {EXPECTED_EXERCISES} exercises / {EXPECTED_FRAMES} template SVG frames")
        return

    output.mkdir(parents=True, exist_ok=True)
    write_json(output / "Contents.json", group_contents_json())
    for slug, index, source_path, asset_name in expected_assets(frames):
        imageset = output / f"{asset_name}.imageset"
        imageset.mkdir(exist_ok=True)
        destination_svg = imageset / f"{asset_name}.svg"
        shutil.copyfile(source_path, destination_svg)
        write_json(imageset / "Contents.json", contents_json(destination_svg.name))

    # Avoid silently retaining a stale imageset if a future upstream import has
    # fewer exercises.  This only removes generated ``*.imageset`` directories
    # whose names use this importer prefix; unrelated groups remain untouched.
    expected_names = {asset_name for _slug, _index, _source, asset_name in expected_assets(frames)}
    for imageset in output.glob("workout_guide_*.imageset"):
        if imageset.stem not in expected_names:
            shutil.rmtree(imageset)

    validate_destination(output, frames)
    print(
        f"Imported {EXPECTED_EXERCISES} exercises / {EXPECTED_FRAMES} template SVG frames "
        f"from {PINNED_COMMIT} into {output}"
    )


def main() -> int:
    arguments = parse_arguments()
    source, temporary_directory = resolve_source(arguments.source)
    try:
        import_assets(source, arguments.output, arguments.check)
    except (ImportError, OSError, json.JSONDecodeError, subprocess.CalledProcessError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    finally:
        if temporary_directory is not None:
            temporary_directory.cleanup()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
