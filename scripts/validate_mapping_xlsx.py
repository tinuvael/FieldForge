#!/usr/bin/env python3
"""Independent ZIP/OOXML + openpyxl validation of the synthetic P5.2 fixture.

P52_EXPORT_FIXTURE_DIR=/tmp/p52 swift test --filter MappingXLSXExportTests
python3 scripts/validate_mapping_xlsx.py /tmp/p52
Requires openpyxl for read-only validation; not an application dependency.
"""
import json
import posixpath
import sys
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET
import openpyxl

root = Path(sys.argv[1])
expected = json.loads((root / 'expected.json').read_text())
path = root / 'FieldForge-Mapping.xlsx'
ns = {'s': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
with zipfile.ZipFile(path) as archive:
    assert archive.testzip() is None, 'ZIP CRC mismatch'
    names = archive.namelist()
    assert len(names) == len(set(names)) == 22
    assert not any('externalLink' in n or 'vba' in n for n in names)
    parts = {name: ET.fromstring(archive.read(name)) for name in names}
    for name, part in parts.items():
        assert not part.findall('.//s:f', ns), name
        if name.endswith('.rels'):
            base = '' if name == '_rels/.rels' else posixpath.dirname(posixpath.dirname(name))
            ids = set()
            for rel in part:
                assert rel.attrib['Id'] not in ids
                ids.add(rel.attrib['Id'])
                assert rel.attrib.get('TargetMode') != 'External'
                target = posixpath.normpath(posixpath.join(base, rel.attrib['Target']))
                assert target in names, (name, target)
    for child in parts['[Content_Types].xml']:
        if child.tag.endswith('Override'):
            assert child.attrib['PartName'].lstrip('/') in names
    for name in names:
        if name.startswith('xl/worksheets/'):
            sheet = parts[name]
            assert sheet.find('s:sheetViews/s:sheetView/s:pane', ns).attrib['state'] == 'frozen'
            assert sheet.find('s:mergeCells', ns) is None
            for cell in sheet.findall('.//s:c', ns):
                assert int(cell.attrib['s']) < 3
                assert cell.attrib.get('t') in (None, 'inlineStr', 'n')

book = openpyxl.load_workbook(path, data_only=False, keep_links=False)
assert book.sheetnames == ['Сводка', 'projects', 'horizons', 'excavations', 'excavation_horizons', 'plans', 'points', 'photo_point_contexts', 'measurements', 'joint_sets', 'interpretation_evidence', 'tectonic_structures', 'assessments', 'photos', 'photo_attachments']
checked = 0
for name, table in expected.items():
    sheet = book[name]
    assert sheet.freeze_panes == 'A2'
    assert sheet.max_row == len(table['rows']) + 1
    assert sheet.max_column == len(table['columns'])
    assert [c.value for c in sheet[1]] == table['columns']
    assert sheet.auto_filter.ref == sheet.calculate_dimension()
    assert not sheet.merged_cells
    assert sheet['A1'].font.bold and sheet['A1'].fill.fgColor.rgb == 'FF243746'
    for i, row in enumerate(table['rows'], 2):
        for j, expected_cell in enumerate(row, 1):
            cell = sheet.cell(i, j)
            if expected_cell['type'] == 'blank':
                assert cell.value is None, (name, cell.coordinate, cell.value)
            else:
                assert cell.data_type == expected_cell['type'], (name, cell.coordinate, cell.data_type)
                assert cell.value == expected_cell['value'], (name, cell.coordinate, cell.value, expected_cell)
            checked += 1
        if i % 2 == 1:
            assert sheet.cell(i, 1).fill.fgColor.rgb == 'FFF0F5F7'

def records(name):
    sheet = book[name]
    values = list(sheet.values)
    return [dict(zip(values[0], row)) for row in values[1:]]

tables = {name: records(name) for name in expected}
def keys(name, column):
    values = [r[column] for r in tables[name]]
    assert len(values) == len(set(values)), (name, column, 'duplicate key')
    return set(values)

projects = keys('projects', 'project_id')
horizons = keys('horizons', 'horizon_id')
excavations = keys('excavations', 'excavation_id')
plans = keys('plans', 'plan_id')
points = keys('points', 'point_id')
measurements = keys('measurements', 'measurement_id')
sets = keys('joint_sets', 'joint_set_id')
attachments = keys('photo_attachments', 'attachment_id')
contexts = keys('photo_point_contexts', 'revision_id')
for table in ['horizons', 'excavations', 'points', 'photo_point_contexts', 'photos']:
    assert all(r['project_id'] in projects for r in tables[table])
for table in ['plans', 'points', 'photos', 'photo_point_contexts', 'excavation_horizons']:
    assert all(r['horizon_id'] in horizons for r in tables[table])
for table in ['points', 'photo_point_contexts', 'photos', 'excavation_horizons']:
    assert all(r['excavation_id'] in excavations for r in tables[table])
for table in ['measurements', 'joint_sets', 'tectonic_structures', 'assessments', 'photos', 'interpretation_evidence', 'photo_point_contexts']:
    assert all(r['point_id'] in points for r in tables[table])
for table in ['points', 'photo_point_contexts']:
    assert all(r['plan_id'] is None or r['plan_id'] in plans for r in tables[table])
membership = {(r['excavation_id'], r['horizon_id']) for r in tables['excavation_horizons']}
for table in ['points', 'photo_point_contexts', 'photos']:
    assert all((r['excavation_id'], r['horizon_id']) in membership for r in tables[table])
set_rows = {r['joint_set_id']: r for r in tables['joint_sets']}
measurement_rows = {r['measurement_id']: r for r in tables['measurements']}
context_rows = {r['revision_id']: r for r in tables['photo_point_contexts']}
plan_rows = {r['plan_id']: r for r in tables['plans']}
for table in ['points', 'photo_point_contexts']:
    assert all(r['plan_id'] is None or plan_rows[r['plan_id']]['horizon_id'] == r['horizon_id'] for r in tables[table])
assessment_keys = [(r['point_id'], r['kind']) for r in tables['assessments']]
assert len(assessment_keys) == len(set(assessment_keys))
for row in tables['interpretation_evidence']:
    assert row['measurement_id'] in measurements and row['joint_set_id'] in sets
    assert row['point_id'] == set_rows[row['joint_set_id']]['point_id'] == measurement_rows[row['measurement_id']]['point_id']
    assert row['joint_set_revision'] == set_rows[row['joint_set_id']]['revision']
for row in tables['photos']:
    assert row['attachment_id'] in attachments and row['context_revision_id'] in contexts
    context = context_rows[row['context_revision_id']]
    assert all(context[key] == row[key] for key in ['point_id', 'project_id', 'horizon_id', 'excavation_id'])
    assert context['version'] == row['context_point_version']
    assert row['captured_at_utc'] is None and row['capture_location_basis'] == 'unknownBeforeFirstSave'
    assert row['original_integrity'] == 'notChecked; originalsNotIncluded'
assert len(points) == 1 and len(measurements) == 2 and len(sets) == 2
assert book['points'].cell(2, 20).data_type == 's'  # exact long decimal X
assert tables['photos'][0]['name'] == '=1+1'
assert all(r['stored_q'] is None for r in tables['assessments'] if r['kind'] == 'RMR89-input-only')
print(f'PASS: ZIP CRC, 22 XML/relationship parts, 15 sheets, {checked} typed data cells, UUID joins, styles, nulls, formula safety and exact precision (openpyxl {openpyxl.__version__}).')
