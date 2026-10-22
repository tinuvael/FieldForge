#!/usr/bin/env python3
"""Independent audit of committed bytes: ezdxf==1.4.4 + Decimal (50 digits).
Developer-only dependency, not required by generator, Swift tests or the app.
python3 -m venv /tmp/ff-dxf && /tmp/ff-dxf/bin/pip install ezdxf==1.4.4
/tmp/ff-dxf/bin/python scripts/audit_underground_surveys.py
"""
import csv
from decimal import Decimal as D, getcontext
import hashlib
import json
from pathlib import Path
import ezdxf

getcontext().prec = 50
ROOT = Path(__file__).resolve().parents[1]
assert ezdxf.__version__ == '1.4.4'


def project(a, b, p):
    dx, dy = b[0]-a[0], b[1]-a[1]
    t = max(D(0), min(D(1), ((p[0]-a[0])*dx+(p[1]-a[1])*dy)/(dx*dx+dy*dy)))
    x, y, z = [a[k]+t*(b[k]-a[k]) for k in range(3)]
    return ((p[0]-x)**2+(p[1]-y)**2).sqrt(), t, z


def cross(a, b, c):
    return (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])


def audit(level):
    path = ROOT / f'Tests/Fixtures/underground_survey_{level}.dxf'
    data = path.read_bytes()
    # Detect duplicate handles before ezdxf could replace a duplicate silently.
    lines = data.decode('ascii').splitlines()
    pairs = list(zip(map(int, lines[::2]), lines[1::2]))
    handles = [v for code, v in pairs if code == 5]
    assert len(handles) == len(set(handles))
    doc = ezdxf.readfile(path)
    check = doc.audit()
    assert not check.errors and not check.fixes, (check.errors, check.fixes)
    assert doc.dxfversion == 'AC1032' and doc.units == 6
    walls = list(doc.modelspace())
    segments = []
    for w in walls:
        assert w.dxftype() == 'POLYLINE' and w.dxf.flags == 8 and not w.is_closed
        assert w.seqend is not None and all(v.dxf.flags == 32 for v in w.vertices)
        vertices = [tuple(D(str(c)) for c in v.dxf.location) for v in w.vertices]
        assert vertices[0] != vertices[-1] and len(set(v[2] for v in vertices)) > 1
        for i,(a,b) in enumerate(zip(vertices, vertices[1:])):
            segments.append((w.dxf.handle, w.dxf.layer, i, a, b))
    # Reject proper XY intersections of any surveyed wall segments. Exact shared
    # T-junction corners are permitted; there are no overpasses in these fixtures.
    crossings = 0
    for i, (_, _, _, a, b) in enumerate(segments):
        for _, _, _, c, d in segments[i+1:]:
            if max(a[0],b[0]) < min(c[0],d[0]) or max(c[0],d[0]) < min(a[0],b[0]): continue
            if max(a[1],b[1]) < min(c[1],d[1]) or max(c[1],d[1]) < min(a[1],b[1]): continue
            if cross(a,b,c)*cross(a,b,d) < 0 and cross(c,d,a)*cross(c,d,b) < 0:
                crossings += 1
    assert crossings == 0, (level, crossings)
    statuses = {}
    error = D(0)
    rows = list(csv.DictReader((ROOT / f'Tests/Fixtures/underground_survey_{level}_controls.csv').open()))
    for row in rows:
        p = (D(row['tap_x']), D(row['tap_y']))
        projected = []
        for handle, layer, i, a, b in segments:
            distance, t, z = project(a,b,p)
            projected.append((distance, int(handle,16), i, t, z, layer, handle))
        projected.sort()
        distance, _, index, t, z, layer, handle = projected[0]
        assert (handle, layer, index) == (row['nearest_handle'], row['nearest_layer'], int(row['segment_index'])), row['case']
        for actual, name in [(distance, 'distance_xy_m'), (t, 't'), (z, 'expected_z')]:
            delta = abs(actual - D(row[name]))
            assert delta < D('1e-8'), (row['case'], name, delta)
            error = max(error, delta)
        similar = [v[4] for v in projected if v[0] <= min(D(2), distance + D('.1'))]
        status = 'outside_tolerance' if distance > 2 else ('choice' if max(similar)-min(similar) > D('.5') else 'automatic')
        assert row['default_2m_status'] == status, row['case']
        statuses[status] = statuses.get(status, 0) + 1
    return dict(sha256=hashlib.sha256(data).hexdigest(), polylines=len(walls), vertices=sum(len(w.vertices) for w in walls),
                segments=len(segments), controls=len(rows), audit_errors=0, audit_fixes=0, proper_xy_crossings=crossings,
                max_control_absolute_error=str(error), default_status_counts=statuses)


if __name__ == '__main__':
    print(json.dumps({str(level): audit(level) for level in [500,600,700]}, indent=2, sort_keys=True))
