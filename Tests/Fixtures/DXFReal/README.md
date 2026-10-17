# Original Issue #14 fixtures

These three files were extracted byte-for-byte from the owner's
`FieldForge_3D_Test_Plans.zip`, supplied on 2026-10-16. They are synthetic local
XYZ metre examples, not qualified survey data or a surveyed CRS/vertical datum.
They are test resources only (SPM, Xcode unit/UI bundles), never app resources.

| File | SHA-256 | Polylines | Vertices |
| --- | --- | ---: | ---: |
| horizon_200_3d.dxf | 75915a3ceffefa765553b88b6a0e663a893d070a318f29755f6d36b924f64790 | 13 | 627 |
| horizon_300_3d.dxf | 209eb7ceb89446f61a1765c975cee8281e0fb866af231cd2c688a22dd9b077b1 | 13 | 627 |
| horizon_400_3d.dxf | c711ebee6a2e2a23ca5ae0e7faa0171387d9f37f3457070fd0981aaec5f82cd0 | 4 | 294 |

Before implementation the original parser rejected **all three** with
`DXF: нет поддерживаемой 2D-геометрии. BLOCK/INSERT не разворачиваются.`

Independent audit: `scripts/audit_real_dxf.py` uses **ezdxf 1.4.4** in a temporary
Python environment; raw group-code pair inspection was also used. The script
prints original WCS endpoints, bounding XYZ, layer counts and audit diagnostics.
`DXFRealTests.swift` asserts literal controls independently of the Swift parser;
`P2MappingUITests` imports the original UTF-8 bytes through simulator-only
fixture input, then exercises normal setup/storage, XY pan/zoom picking, Z,
marker selection, draft retention and reopening. Actual Files providers still
require an owner smoke test.
