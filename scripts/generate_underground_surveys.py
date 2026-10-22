#!/usr/bin/env python3
"""Synthetic floor surveys, NOT measured mine data or excavation design.

Python 3 standard library only. SI metres, local right-handed WCS X east/Y north/
Z up; unknown horizontal/vertical datum. Seeded deviations are illustrative.
Run from any directory; --check verifies committed bytes without writing.
See docs/underground-survey-z-verification.md for controls and references.
"""
import argparse
import csv
from dataclasses import dataclass
import hashlib
import io
import json
import math
from pathlib import Path
import random

ROOT = Path(__file__).resolve().parents[1]
STEP = 2.5


@dataclass
class Wall:
    layer: str
    vertices: list
    handle: str = ''


def trace(length, start, heading, turn, grade, seed, width=5.6):
    """Integrate prescribed synthetic heading/grade by horizontal chainage."""
    rng = random.Random(seed)
    points, headings, widths = [], [], []
    x, y, z = start
    count = round(length / STEP)
    ds = length / count
    for i in range(count + 1):
        s = i * ds
        h = heading + turn(s / length)
        if i:
            mid = (i - .5) * ds
            hm = heading + turn(mid / length)
            x += ds * math.cos(hm)
            y += ds * math.sin(hm)
            z += ds * grade(mid / length)
        points.append((x, y, z))
        headings.append(h)
        widths.append(width + .65 * math.sin(s / 26) + 1.0 * math.exp(-((s - length * .56) / 14)**2))
    walls = []
    for side in (1, -1):
        vertices = []
        for (x, y, z), h, w in zip(points, headings, widths):
            offset = side * w / 2 + rng.uniform(-.075, .075)
            vertices.append(tuple(round(v, 9) for v in (
                x - math.sin(h) * offset + rng.uniform(-.025, .025),
                y + math.cos(h) * offset + rng.uniform(-.025, .025),
                z + side * .035 + rng.uniform(-.012, .012))))
        walls.append(vertices)
    return points, headings, walls


def survey(level):
    # Different lengths, bearings, curvature, branch counts, directions and grades.
    configs = {
        500: (300, (4200, 8100, 501.7), .12, lambda u: .32 * math.sin(2 * math.pi * u),
              lambda u: .006 + .008 * math.cos(2 * math.pi * u),
              [(22, 1, 'RAMP_DOWN', 145, -.105), (58, -1, 'BLIND_A', 55, .012), (76, -1, 'BLIND_B', 42.5, -.009), (92, 1, 'RAMP_UP', 110, .108)]),
        600: (325, (5200, 9200, 601.2), 1.10, lambda u: -.65 * u + .10 * math.sin(3 * math.pi * u),
              lambda u: -.009 + .006 * math.sin(2 * math.pi * u),
              [(20, -1, 'BLIND_A', 65, -.015), (49, 1, 'RAMP_DOWN', 180, -.109),
               (82, -1, 'RAMP_UP', 155, .105), (99, -1, 'BLIND_C', 40, -.012), (113, 1, 'BLIND_B', 42.5, .018)]),
        700: (275, (6400, 10300, 697.8), 2.8, lambda u: .60 * math.sin(math.pi * u) - .2 * u,
              lambda u: .013 - .014 * u,
              [(6, -1, 'BLIND_D', 40, .009), (17, 1, 'BLIND_A', 47.5, -.011), (38, -1, 'RAMP_UP', 135, .110),
               (63, 1, 'BLIND_B', 70, .016), (85, -1, 'BLIND_C', 40, -.018),
               (102, 1, 'RAMP_DOWN', 175, -.107)])}
    length, start, heading, turn, grade, branches = configs[level]
    points, headings, main = trace(length, start, heading, turn, grade, level)
    openings = {1: [], -1: []}
    walls, routes = [], {'MAIN': points}
    for n, (index, side, name, run, slope) in enumerate(branches):
        h = headings[index]
        mouth = main[0 if side == 1 else 1][index]
        # Start on the actual main sidewall. Ramp approaches change smoothly
        # from a 1.5% throat to a 10–12% haulage grade, then flatten at the toe.
        def ramp_grade(u, slope=slope):
            transition = min(1., u / .13, (1 - u) / .13)
            return math.copysign(.015, slope) + (slope - math.copysign(.015, slope)) * transition
        cp, _, bw = trace(run, mouth, h + side * math.pi / 2,
                         lambda u, n=n: (.17 if n % 2 == 0 else -.23) * math.sin(math.pi * u),
                         ramp_grade if name.startswith('RAMP') else lambda u, slope=slope: slope + .003 * math.sin(2 * math.pi * u),
                         level + 17 * (n + 1), width=5.0)
        routes[name] = cp
        for label, vertices in zip(('LEFT', 'RIGHT'), bw):
            walls.append(Wall(f'{name}_{label}', vertices))
        # Open the parent wall at each T junction, with exact shared XYZ corners.
        corners = sorted([bw[0][0], bw[1][0]], key=lambda p: (p[0] - mouth[0]) * math.cos(h) + (p[1] - mouth[1]) * math.sin(h))
        openings[side].append((index - 1, index + 1, corners))
    main_walls = []
    for side, vertices in zip((1, -1), main):
        begin = 0
        label = 'LEFT' if side == 1 else 'RIGHT'
        for number, (lo, hi, corners) in enumerate(openings[side], 1):
            part = vertices[begin:lo + 1]
            part[-1] = corners[0]
            main_walls.append(Wall(f'MAIN_{label}_{number:02d}', part))
            vertices[hi] = corners[1]
            begin = hi
        main_walls.append(Wall(f'MAIN_{label}_{len(openings[side]) + 1:02d}', vertices[begin:]))
    walls = main_walls + walls
    # Stable hexadecimal entity handles independent of paths, clock or UUIDs.
    handle = 0x100
    for wall in walls:
        wall.handle = f'{handle:X}'
        handle += len(wall.vertices) + 2
    return walls, routes


def dxf(walls):
    pairs = []
    def add(*items):
        pairs.extend(items)
    add((0, 'SECTION'), (2, 'HEADER'), (9, '$ACADVER'), (1, 'AC1032'),
        (9, '$HANDSEED'), (5, '10000'), (9, '$INSUNITS'), (70, 6), (9, '$MEASUREMENT'), (70, 1), (0, 'ENDSEC'))
    add((0, 'SECTION'), (2, 'TABLES'), (0, 'TABLE'), (2, 'LTYPE'), (5, '10'), (100, 'AcDbSymbolTable'), (70, 1),
        (0, 'LTYPE'), (5, '11'), (330, '10'), (100, 'AcDbSymbolTableRecord'), (100, 'AcDbLinetypeTableRecord'),
        (2, 'CONTINUOUS'), (70, 0), (3, 'Solid line'), (72, 65), (73, 0), (40, 0), (0, 'ENDTAB'),
        (0, 'TABLE'), (2, 'LAYER'), (5, '12'), (100, 'AcDbSymbolTable'), (70, len(walls) + 1))
    for i, layer in enumerate(['0'] + [w.layer for w in walls]):
        add((0, 'LAYER'), (5, f'{0x20+i:X}'), (330, '12'), (100, 'AcDbSymbolTableRecord'), (100, 'AcDbLayerTableRecord'),
            (2, layer), (70, 0), (62, 3 if 'LEFT' in layer else 5), (6, 'CONTINUOUS'))
    add((0, 'ENDTAB'), (0, 'TABLE'), (2, 'BLOCK_RECORD'), (5, '13'), (100, 'AcDbSymbolTable'), (70, 2))
    for handle, name in [('14', '*Model_Space'), ('15', '*Paper_Space')]:
        add((0, 'BLOCK_RECORD'), (5, handle), (330, '13'), (100, 'AcDbSymbolTableRecord'), (100, 'AcDbBlockTableRecord'), (2, name), (70, 0))
    add((0, 'ENDTAB'), (0, 'ENDSEC'), (0, 'SECTION'), (2, 'BLOCKS'))
    for handle, owner, name in [(0x16, '14', '*Model_Space'), (0x18, '15', '*Paper_Space')]:
        add((0, 'BLOCK'), (5, f'{handle:X}'), (330, owner), (100, 'AcDbEntity'), (8, '0'), (100, 'AcDbBlockBegin'),
            (2, name), (70, 0), (10, 0), (20, 0), (30, 0), (3, name), (1, ''),
            (0, 'ENDBLK'), (5, f'{handle+1:X}'), (330, owner), (100, 'AcDbEntity'), (8, '0'), (100, 'AcDbBlockEnd'))
    add((0, 'ENDSEC'), (0, 'SECTION'), (2, 'ENTITIES'))
    for w in walls:
        h = int(w.handle, 16)
        add((0, 'POLYLINE'), (5, w.handle), (330, '14'), (100, 'AcDbEntity'), (8, w.layer),
            (100, 'AcDb3dPolyline'), (66, 1), (10, 0), (20, 0), (30, 0), (70, 8))
        for i, (x, y, z) in enumerate(w.vertices, 1):
            add((0, 'VERTEX'), (5, f'{h+i:X}'), (330, w.handle), (100, 'AcDbEntity'), (8, w.layer),
                (100, 'AcDbVertex'), (100, 'AcDb3dPolylineVertex'), (10, x), (20, y), (30, z), (70, 32))
        add((0, 'SEQEND'), (5, f'{h+len(w.vertices)+1:X}'), (330, w.handle), (100, 'AcDbEntity'), (8, w.layer))
    add((0, 'ENDSEC'), (0, 'EOF'))
    return ''.join(f'{code}\n{value}\n' for code, value in pairs).encode('ascii')


def nearest(walls, p):
    """Independent oracle: unit tangent/normal decomposition, not app dot/dot."""
    found = []
    for w in walls:
        for index, (a, b) in enumerate(zip(w.vertices, w.vertices[1:])):
            dx, dy = b[0] - a[0], b[1] - a[1]
            length = math.hypot(dx, dy)
            ux, uy = dx / length, dy / length
            along = (p[0] - a[0]) * ux + (p[1] - a[1]) * uy
            if p == a[:2]:
                distance, t = 0., 0.
            elif p == b[:2]:
                distance, t = 0., 1.
            elif along < 0:
                distance, t = math.hypot(p[0] - a[0], p[1] - a[1]), 0.
            elif along > length:
                distance, t = math.hypot(p[0] - b[0], p[1] - b[1]), 1.
            else:
                distance, t = abs((p[0] - a[0]) * uy - (p[1] - a[1]) * ux), along / length
            found.append((distance, int(w.handle, 16), index, t, a[2] * (1 - t) + b[2] * t, w))
    return sorted(found, key=lambda v: v[:3])


def controls(walls, routes):
    rows = []
    def add(case, p, expected_distance=None):
        p = tuple(round(v, 12) for v in p[:2])
        found = nearest(walls, p)
        distance, _, segment, t, z, wall = found[0]
        if expected_distance is not None:
            assert abs(distance - expected_distance) < 1e-8, (case, distance)
        similar = [v for v in found if v[0] <= min(2., distance + .1)]
        status = 'outside_tolerance' if distance > 2 else ('choice' if max(v[4] for v in similar) - min(v[4] for v in similar) > .5 else 'automatic')
        a, b = wall.vertices[segment:segment + 2]
        rows.append([case, *p, z, wall.layer, wall.handle, segment, *a, *b, t, distance,
                     a[0] * (1 - t) + b[0] * t, a[1] * (1 - t) + b[1] * t, status])
    def offset(w, i, t, distance, sign=1):
        a, b = w.vertices[i:i+2]
        dx, dy = b[0] - a[0], b[1] - a[1]
        length = math.hypot(dx, dy)
        return (a[0] + t * dx - sign * distance * dy / length, a[1] + t * dy + sign * distance * dx / length)
    for label in ['LEFT', 'RIGHT']:
        w = max((w for w in walls if w.layer.startswith(f'MAIN_{label}')), key=lambda w: len(w.vertices))
        add(f'main_{label.lower()}_interior', offset(w, len(w.vertices)//2, .37, .65))
    for name in ['RAMP_DOWN', 'RAMP_UP']:
        for label, t in [('LEFT', .25), ('RIGHT', .63)]:
            w = next(w for w in walls if w.layer == f'{name}_{label}')
            for stage, fraction in [('approach', .04), ('haul', .52), ('toe', .94)]:
                add(f'{name.lower()}_{label.lower()}_{stage}', offset(w, int((len(w.vertices)-2)*fraction), t, .45))
    # Dead ends and clamped endpoint projection beyond the surveyed face.
    w = next(w for w in walls if w.layer == 'BLIND_A_LEFT')
    a, b = w.vertices[-2:]
    dx, dy = b[0] - a[0], b[1] - a[1]
    length = math.hypot(dx, dy)
    add('blind_face_endpoint', (b[0] + .7 * dx / length, b[1] + .7 * dy / length))
    # Junction search uses all walls. Pick inside the mouth, close to either corner.
    for name in ['RAMP_DOWN', 'RAMP_UP', 'BLIND_A']:
        for label in ['LEFT', 'RIGHT']:
            w = next(w for w in walls if w.layer == f'{name}_{label}')
            add(f'junction_{name.lower()}_{label.lower()}', offset(w, 0, .43, .30))
    for side in ['LEFT', 'RIGHT']:
        w = next(w for w in walls if w.layer.startswith(f'MAIN_{side}'))
        add(f'junction_main_{side.lower()}', offset(w, len(w.vertices)-2, .55, .2))
    add('junction_shared_corner', next(w for w in walls if w.layer == 'RAMP_DOWN_LEFT').vertices[0])
    # Off-plan samples: query an existing extremal vertex, never move geometry.
    edge = min((p for w in walls for p in w.vertices), key=lambda p: p[0])
    for case, distance in [('at_2m', 2.), ('past_2m', 2.0001), ('at_5m', 5.), ('past_5m', 5.0001), ('at_8m', 8.)]:
        # Global minimum X is a supporting plane: no other vertex/segment can
        # be closer than this endpoint. Exact 2/5/8 offsets avoid boundary ulps.
        add(case, (edge[0] - distance, edge[1]), distance)
    add('wide_main_center', routes['MAIN'][round(len(routes['MAIN']) * .55)])
    output = io.StringIO(newline='')
    writer = csv.writer(output, lineterminator='\n')
    writer.writerow(['case', 'tap_x', 'tap_y', 'expected_z', 'nearest_layer', 'nearest_handle', 'segment_index',
                     'a_x', 'a_y', 'a_z', 'b_x', 'b_y', 'b_z', 't', 'distance_xy_m', 'projected_x', 'projected_y', 'default_2m_status'])
    writer.writerows(rows)
    return output.getvalue().encode('ascii'), rows


def preview(level, walls, routes, rows):
    """Dependency-free, equal-scale SVG; profiles use horizontal chainage."""
    xyz = [p for w in walls for p in w.vertices]
    xmin, xmax = min(p[0] for p in xyz)-12, max(p[0] for p in xyz)+12
    ymin, ymax = min(p[1] for p in xyz)-12, max(p[1] for p in xyz)+12
    scale = min(1000/(xmax-xmin), 500/(ymax-ymin))
    def xy(p):
        return 85+(p[0]-xmin)*scale, 105+(ymax-p[1])*scale
    svg = ['<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="1200" viewBox="0 0 1200 1200">',
           '<rect width="1200" height="1200" fill="#fbfcfe"/>',
           '<style>text{font-family:Arial,sans-serif;fill:#243449} .minor{font-size:14px} .title{font-size:23px;font-weight:bold}</style>',
           f'<text x="45" y="38" class="title">Synthetic underground floor survey — horizon {level}</text>',
           '<text x="45" y="65" class="minor">Metres · local WCS X east / Y north / Z up · unknown datum · illustrative, not surveyed evidence</text>']
    for x in range(math.ceil(xmin/50)*50, math.floor(xmax/50)*50+1, 50):
        sx, _ = xy((x, ymin))
        svg.extend([f'<path d="M{sx:.2f},100 V{105+(ymax-ymin)*scale:.2f}" stroke="#e0e6ed"/>', f'<text x="{sx-20:.2f}" y="97" class="minor">{x}</text>'])
    for y in range(math.ceil(ymin/50)*50, math.floor(ymax/50)*50+1, 50):
        _, sy = xy((xmin, y))
        svg.extend([f'<path d="M80,{sy:.2f} H{85+(xmax-xmin)*scale:.2f}" stroke="#e0e6ed"/>', f'<text x="24" y="{sy:.2f}" class="minor">{y}</text>'])
    for w in walls:
        color = '#16806e' if 'LEFT' in w.layer else '#3068bd'
        pts = ' '.join(f'{x:.2f},{y:.2f}' for x, y in map(xy, w.vertices))
        svg.append(f'<polyline points="{pts}" fill="none" stroke="{color}" stroke-width="1.6"><title>{w.layer} / handle {w.handle}</title></polyline>')
    for name, route in routes.items():
        x, y = xy(route[-1])
        svg.append(f'<text x="{x+5:.2f}" y="{y-7:.2f}" class="minor">{name}</text>')
    for row in rows:
        x, y = xy(row[1:3])
        svg.append(f'<circle cx="{x:.2f}" cy="{y:.2f}" r="2.3" fill="#cf6e28"><title>{row[0]} Z={row[3]:.6f} d={row[14]:.6f}</title></circle>')
    svg.append('<text x="45" y="640" class="minor">Green: LEFT · Blue: RIGHT · Orange: CSV controls · Main wall gaps are open T junctions · North ↑</text>')
    for panel, name in enumerate(['RAMP_DOWN', 'RAMP_UP']):
        selected = [w for w in walls if w.layer.startswith(name)]
        zmin = math.floor(min(p[2] for w in selected for p in w.vertices))
        zmax = math.ceil(max(p[2] for w in selected for p in w.vertices))
        x0, y0 = 90 + panel*570, 715
        svg.append(f'<text x="{x0}" y="685" style="font-size:18px;font-weight:bold">{name} — longitudinal floor profile</text>')
        maxs = max(sum(math.dist(a[:2], b[:2]) for a,b in zip(w.vertices, w.vertices[1:])) for w in selected)
        for z in range(zmin, zmax+1, 2):
            sy = y0+240-(z-zmin)/(zmax-zmin)*240
            svg.append(f'<path d="M{x0},{sy:.2f} h440" stroke="#e0e6ed"/><text x="{x0-40}" y="{sy:.2f}" class="minor">{z}</text>')
        for w in selected:
            s, pts = 0, []
            for i,p in enumerate(w.vertices):
                if i: s += math.dist(w.vertices[i-1][:2], p[:2])
                pts.append(f'{x0+s/maxs*440:.2f},{y0+240-(p[2]-zmin)/(zmax-zmin)*240:.2f}')
            color = '#16806e' if 'LEFT' in w.layer else '#3068bd'
            svg.append(f'<polyline points="{" ".join(pts)}" fill="none" stroke="{color}" stroke-width="2"/>')
        svg.append(f'<text x="{x0}" y="983" class="minor">0</text><text x="{x0+390}" y="983" class="minor">{maxs:.1f} m</text>')
    svg.append('<text x="45" y="1030" class="minor">Profile X: horizontal distance along each surveyed sidewall from its mouth; Z: floor elevation (m).</text>')
    svg.append('<text x="45" y="1055" class="minor">Vertical exaggeration varies by panel. Ramp transitions flatten at mouths and toes; no design/safety claim.</text></svg>\n')
    return '\n'.join(svg).encode('utf8')


def products():
    result, summary = {}, {}
    for level in (500, 600, 700):
        walls, routes = survey(level)
        raw = dxf(walls)
        controls_csv, rows = controls(walls, routes)
        result[f'Tests/Fixtures/underground_survey_{level}.dxf'] = raw
        result[f'Tests/Fixtures/underground_survey_{level}_controls.csv'] = controls_csv
        result[f'docs/images/underground_survey_{level}.svg'] = preview(level, walls, routes, rows)
        vertices = [v for w in walls for v in w.vertices]
        summary[str(level)] = dict(sha256=hashlib.sha256(raw).hexdigest(), polylines=len(walls), vertices=len(vertices),
                                  z_min=min(v[2] for v in vertices), z_max=max(v[2] for v in vertices), controls=len(rows),
                                  default_status_counts={s:sum(r[-1] == s for r in rows) for s in sorted(set(r[-1] for r in rows))},
                                  main_length_xy_m=sum(math.dist(a[:2],b[:2]) for a,b in zip(routes['MAIN'],routes['MAIN'][1:])))
    result['Tests/Fixtures/underground_surveys_manifest.json'] = (json.dumps(summary, indent=2, sort_keys=True)+'\n').encode()
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    for relative, data in products().items():
        path = ROOT / relative
        if args.check:
            if not path.exists() or path.read_bytes() != data:
                raise SystemExit(f'Generated bytes differ: {relative}')
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        print(('Verified ' if args.check else 'Generated ') + relative)


if __name__ == '__main__':
    main()
