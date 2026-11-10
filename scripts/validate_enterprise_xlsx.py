#!/usr/bin/env python3
"""Check the synthetic Data workbook with openpyxl and the standard-library ZIP reader.

FF_ENTERPRISE_FIXTURE_DIR=/tmp/enterprise swift test --filter EnterpriseGeotechnicalTests/testRegulatoryEffectiveRowsAndLegacyReports
python3 scripts/validate_enterprise_xlsx.py /tmp/enterprise
"""
import sys
from pathlib import Path
from xml.etree import ElementTree as ET
from zipfile import ZipFile

import openpyxl


path = Path(sys.argv[1]) / "FieldForge-Geotechnical.xlsx"
ns = {"s": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
with ZipFile(path) as archive:
    assert archive.testzip() is None
    assert len(archive.namelist()) == 8
    assert [name for name in archive.namelist() if name.startswith("xl/worksheets/")] == [
        "xl/worksheets/sheet1.xml"
    ]
    for name in archive.namelist():
        assert not ET.fromstring(archive.read(name)).findall(".//s:f", ns), "Unexpected formula"

book = openpyxl.load_workbook(path)
assert book.sheetnames == ["Data"]
report = book["Data"]
assert report.sheet_state == "visible"
assert report.calculate_dimension() == "A1:AD8"
assert report.freeze_panes == "A5"
assert report.auto_filter.ref == "A4:AD8"
assert set(str(r) for r in report.merged_cells.ranges) == {
    "A1:AD1", "A2:E2", "F2:H2", "I2:J2", "K2:L2", "M2:R2", "S2:U2", "V2:AC2", "C3:E3"
}

assert [cell.value for cell in report[1] if cell.value is not None] == ["КАРТИРОВАНИЕ ВЫРАБОТОК"]
groups = {
    "A": "Место картирования", "F": "Строение", "I": "Прочность", "K": "Структура",
    "M": "Свойства трещин", "V": "Ориентация трещиноватости", "AD": "Рейтинг массива",
}
assert {cell.column_letter: cell.value for cell in report[2] if cell.value is not None} == groups
descriptions = [
    "Место картирования", "Пикетаж", "Координаты точек замеров", None, None,
    "Сокращенная литология", "Выветривание стенок трещин", "Обводненность",
    "Категория прочности пород", "Прочность породы, МПа", "Качество породы, %",
    "Количество систем трещин", "Шероховатость стенок трещин", "Сцепление стенок трещин",
    "Расстояние между трещинами, м", "Раскрытие трещин", "Свойства трещин", "Длина трещин",
    "Угол падения разлома, ° ", "Азимут падения разлома, °", "Мощность разлома, м",
]
for number in range(1, 5):
    descriptions += [f"Угол падения {number} й системы трещин, °", f"Азимут падения {number} й системы трещин, °"]
assert [cell.value for cell in report[3]] == descriptions + ["GSI"]
keys = "ID PK X Y Z ROCK A45 JW A1 UCS RQD JN JR JA SD A43 JCON76 A42 F_DIP F_AZI F_THI".split()
for number in range(1, 5):
    keys += [f"J_DIP_{number}", f"J_AZI_{number}"]
assert [cell.value for cell in report[4]] == keys + ["GSI"]

widths = [25.7109375, 10.7109375, 10.7109375, 13.28515625, 10.7109375] + [7.7109375] * 25
assert [report.column_dimensions[cell.column_letter].width for cell in report[4]] == widths
assert len(report.column_dimensions) == 30
assert [report.row_dimensions[row].height for row in range(1, 9)] == [15, 15, 193.5] + [14.1] * 5
assert report["V3"].alignment.text_rotation == 90
assert report["V3"].fill.fgColor.rgb == "FFB4C6E7"
assert report["AD2"].alignment.shrink_to_fit
assert report["A1"].border.top.style == "thin" and report["A1"].alignment.vertical == "center"
assert report["A2"].alignment.wrap_text and report["F2"].alignment.wrap_text
assert report["G4"].font.name == "Calibri" and report["G4"].font.sz == 11
assert report["G4"].border.top.color.rgb == "FF000000"
assert report["G4"].border.bottom.style is None
assert all(report[ref].alignment.shrink_to_fit for ref in ("F4", "AC3", "AC4", "C5", "D5", "E5"))
assert report["AC4"].font.sz == 8 and report["AC4"].alignment.horizontal == "left"
assert (report.page_setup.paperSize, report.page_setup.orientation, report.page_setup.scale) == (9, "portrait", 100)
assert report.page_setup.pageOrder == "downThenOver"
assert (report.page_margins.left, report.page_margins.right, report.page_margins.top, report.page_margins.bottom,
        report.page_margins.header, report.page_margins.footer) == (0.7, 0.7, 0.75, 0.75, 0.3, 0.3)
formats = {"C": "0.000", "D": "0.000", "E": "0.000", "O": "0.00", "AD": "0"}
for row in report.iter_rows(min_row=5):
    assert all(cell.number_format == formats.get(cell.column_letter, "General") for cell in row)
    assert all(cell.data_type == ("s" if isinstance(cell.value, str) else "n") for cell in row)

rows = list(report.values)[4:]
prefix = ("Штрек", "ПК 1+5", 1234567.123456789, 0, -14.125, "0001.20", 3, 0.5, None,
          152.125, 5, 9, 3, 2, 0.375, 1, 25, 4)
suffix = (11, 101, 22, 0, 33, 303, 0, None, 41.25)
assert rows[0] == prefix + (32.125, 0, 0) + suffix
assert rows[1] == prefix + (None, 270, 0.875) + suffix
assert rows[2] == ("Штрек", "ПК 2+5") + (None,) * 16 + (48,) + (None,) * 11
assert rows[3] == ("Штрек", "ПК 3+5") + (None,) * 6 + (0, None, 0) + (None,) * 19
print("PASS: one visible Data sheet, 30 columns, four header rows, and four typed report rows")
