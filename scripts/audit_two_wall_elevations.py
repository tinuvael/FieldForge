#!/usr/bin/env python3
"""Independent Decimal reference controls from hash-pinned XYZ DXF records.

No FieldForge/generator imports. Explicit fixture layer selection is an oracle,
not the production wall-identification algorithm. --check never writes controls.

Optional developer tool: run only for fixture changes, a specific failure,
or explicitly requested validation; not a routine feature/PR gate.
"""
import argparse
import csv
import io
from decimal import Decimal as D, localcontext
from pathlib import Path
from survey_fixture_directory import survey_fixture_directory

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / 'Tests' / 'Fixtures'


def read_walls(path):
    raw = [s.strip() for s in path.read_text().splitlines()]
    records, kind, fields = [], None, {}
    for code, value in zip(raw[::2], raw[1::2]):
        if code == '0':
            records.append((kind, fields))
            kind, fields = value, {}
        else:
            fields[code] = value
    walls, active = [], None
    for kind, fields in records:
        if kind == 'POLYLINE':
            active = {'handle': fields['5'], 'layer': fields['8'], 'vertices': []}
        elif kind == 'VERTEX' and active is not None:
            active['vertices'].append(tuple(D(fields[c]) for c in ['10', '20', '30']))
        elif kind == 'SEQEND' and active is not None:
            walls.append(active)
            active = None
    return walls


def project(wall, point):
    answers = []
    px, py = point
    for index, (a, b) in enumerate(zip(wall['vertices'], wall['vertices'][1:])):
        ax, ay, az = a
        bx, by, bz = b
        ux, uy = bx - ax, by - ay
        # Independent high precision scalar XY projection and linear wall profile.
        fraction = max(D(0), min(D(1), ((px-ax)*ux+(py-ay)*uy)/(ux*ux+uy*uy)))
        distance = ((px-ax-fraction*ux)**2+(py-ay-fraction*uy)**2).sqrt()
        answers.append((distance, index, fraction, az+fraction*(bz-az)))
    return min(answers)


def generate(dxf_directory):
    output = io.StringIO(newline='')
    writer = csv.writer(output, lineterminator='\n')
    writer.writerow(['level', 'case', 'x', 'y', 'wall1_handle', 'wall1_segment', 'wall1_z', 'wall1_distance',
                     'wall2_handle', 'wall2_segment', 'wall2_z', 'wall2_distance', 'expected_z'])
    for level in [500, 600, 700]:
        walls = read_walls(dxf_directory / f'underground_survey_{level}.dxf')
        controls = list(csv.DictReader((FIXTURES / f'underground_survey_{level}_controls.csv').open()))
        for c in controls:
            if not (c['case'].startswith(('main_', 'ramp_')) or c['case'] == 'wide_main_center'):
                continue
            layer = c['nearest_layer']
            route, side = layer.split('_LEFT')[0], 'LEFT'
            if '_RIGHT' in layer:
                route, side = layer.split('_RIGHT')[0], 'RIGHT'
            other = 'RIGHT' if side == 'LEFT' else 'LEFT'
            point = (D(c['tap_x']), D(c['tap_y']))
            a = next(w for w in walls if w['handle'] == c['nearest_handle'])
            b = min((w for w in walls if w['layer'].startswith(route+'_'+other)), key=lambda w: project(w, point))
            if c['case'] != 'wide_main_center':
                # The older CSV uses segment-interior offsets, which can lie OUTSIDE
                # the excavation. Build new inside-floor controls from the source walls.
                _, index, t, _ = project(a, point)
                av, bv = a['vertices'][index:index+2]
                qa = tuple(av[k] + t*(bv[k]-av[k]) for k in range(2))
                _, index, t, _ = project(b, qa)
                av, bv = b['vertices'][index:index+2]
                qb = tuple(av[k] + t*(bv[k]-av[k]) for k in range(2))
                weight = D('0.25') if side == 'LEFT' else D('0.65')
                point = tuple(qa[k]+weight*(qb[k]-qa[k]) for k in range(2))
            d1, i1, _, z1 = project(a, point)
            d2, i2, _, z2 = project(b, point)
            z = z1 if d1 == 0 else z2 if d2 == 0 else (z1*d2+z2*d1)/(d1+d2)
            writer.writerow([level, c['case'], *point, a['handle'], i1, z1, d1, b['handle'], i2, z2, d2, z])
    return output.getvalue().encode()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--dxf-dir', type=Path, help='Audit existing DXFs instead of generating temporary files')
    args = parser.parse_args()
    with survey_fixture_directory(args.dxf_dir) as fixtures, localcontext() as context:
        context.prec = 50
        expected = generate(fixtures)
    target = FIXTURES / 'two_wall_elevation_controls.csv'
    if args.check:
        if target.read_bytes() != expected:
            raise SystemExit('Two-wall reference controls differ')
    else:
        target.write_bytes(expected)
    print('Independent Decimal two-wall controls verified:', len(expected.splitlines())-1)
