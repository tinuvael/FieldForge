#!/usr/bin/env python3
"""Independent developer audit; requires ezdxf==1.4.4 in a temporary venv.
Not an app/runtime/test-suite dependency. Literal controls live in DXFRealTests.swift.
"""
from collections import Counter
import hashlib
import json
from pathlib import Path
import ezdxf

assert ezdxf.__version__ == '1.4.4'
root = Path(__file__).resolve().parents[1] / 'Tests/Fixtures/DXFReal'
report = {}
for level, count, vertex_count in [(200, 13, 627), (300, 13, 627), (400, 4, 294)]:
    path = root / f'horizon_{level}_3d.dxf'
    doc = ezdxf.readfile(path)
    audit = doc.audit()
    entities = list(doc.modelspace())
    assert Counter(e.dxftype() for e in entities) == {'POLYLINE': count}
    assert all(e.is_3d_polyline and e.dxf.flags == 8 for e in entities)
    vertices = [v for e in entities for v in e.vertices]
    assert len(vertices) == vertex_count and all(v.dxf.flags == 32 for v in vertices)
    assert not audit.errors and not audit.fixes
    xyz = [tuple(v.dxf.location) for v in vertices]
    report[path.name] = {
        'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
        'version': doc.dxfversion, 'polylines': len(entities), 'vertices': len(vertices),
        'layers': dict(sorted(Counter(e.dxf.layer for e in entities).items())),
        'first_xyz': xyz[0], 'last_xyz': xyz[-1],
        'min_xyz': [min(p[i] for p in xyz) for i in range(3)],
        'max_xyz': [max(p[i] for p in xyz) for i in range(3)],
        'audit_errors': len(audit.errors), 'audit_fixes': len(audit.fixes),
    }
print(json.dumps(report, indent=2))
