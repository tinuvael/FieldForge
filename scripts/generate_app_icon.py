#!/usr/bin/env python3
"""Export the approved opaque square artwork to the iOS 1024px AppIcon.

Requires native macOS sips. This is asset preparation only, not a runtime dependency.
The source is preserved byte-for-byte; no crop, redesign or extra mask is applied.
"""
from pathlib import Path
import json
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "branding/FieldForge-AppIcon-master.png"
ASSET = ROOT / "FieldForge/Resources/Assets.xcassets/AppIcon.appiconset"


def png_header(path):
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        raise ValueError(f"Expected a PNG: {path}")
    return struct.unpack(">IIBB", data[16:26])


def main():
    width, height, depth, color = png_header(SOURCE)
    if width != height or width < 1024 or depth != 8 or color != 2:
        raise ValueError("Expected a square, opaque 8-bit RGB master at least 1024px")
    contents = json.loads((ASSET / "Contents.json").read_text())
    if contents["images"] != [{"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}]:
        raise ValueError("Review changed AppIcon asset references before generation")
    subprocess.run(["/usr/bin/sips", "--setProperty", "format", "png", "--resampleHeightWidth", "1024", "1024",
                    str(SOURCE), "--out", str(ASSET / "AppIcon.png")], check=True)
    if png_header(ASSET / "AppIcon.png") != (1024, 1024, 8, 2):
        raise ValueError("Invalid generated AppIcon")
    print("Generated AppIcon.png: 1024 × 1024, opaque RGB; full source composition retained")


if __name__ == "__main__":
    main()
