#!/usr/bin/env python3
"""Read-only calibration audit. Usage: python3 scripts/verify_gsi_source.py SOURCE.pdf

Requires pdfplumber (development only). Never copies source artwork into the app.
The source book is owner supplied and deliberately excluded from this repository.
"""
import hashlib
import re
import sys
from pathlib import Path

import pdfplumber

source = Path(sys.argv[1])
expected_hash = "c7af2a3b0e5fdac914414a090c3f273db05b333d97ac941f6c629c5802b43b2a"
assert hashlib.sha256(source.read_bytes()).hexdigest() == expected_hash, "Use the documented source edition/copy"
with pdfplumber.open(source) as book:
    page = book.pages[140]  # Printed page 126, Table 5.34.
    assert (page.width, page.height) == (595, 765)
    paths = []
    for line in page.lines:
        if (line["x0"] > 280 and line["top"] > 260 and line["bottom"] < 530
                and line["width"] > 10 and line["height"] > 10):
            points = tuple(round(value, 7) for point in line["pts"] for value in point)
            if points not in paths:  # The PDF paints the same table twice.
                paths.append(points)
    assert len(paths) == 19
    code = (Path(__file__).resolve().parents[1] / "FieldForge/Services/GSIChart.swift").read_text()
    stored = re.findall(r"Contour\(value: (\d+), ax: ([\d.]+), ay: ([\d.]+), bx: ([\d.]+), by: ([\d.]+)\)", code)
    assert len(stored) == len(paths)
    for index, (entry, points) in enumerate(zip(stored, paths)):
        assert int(entry[0]) == 95 - 5 * index
        assert tuple(float(value) for value in entry[1:]) == points, f"Contour {entry[0]} changed"
    # Separate printed anchors check the five-unit labelling sequence, including intermediate lines.
    words = page.extract_words()
    for label in ["90", "80", "75", "70", "60", "55", "50", "40", "35", "30", "20", "10"]:
        assert any(word["text"] == label and word["x0"] > 280 and 260 < word["top"] < 530 for word in words), label
print("PASS: source fingerprint, PDF page geometry, 19 contour segments and 12 printed numerical anchors")
