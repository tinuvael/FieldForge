# P2 Issue #14 hotfix verification — 2026-10-16

Branch: `codex/hotfix-p2-issue-14`, from fetched `origin/main` at `73f0b6a`.
Initial working tree was clean. No physical iPhone installation, removal, reset,
record access, identifier, signing or branding changes were performed.

## Failure reproduced before implementation

The fixture directory was initially absent. Work on the fix waited for the owner
archive, then extracted the three original DXFs without rewriting their bytes.
A new `DXFRealTests.testAllThreeOriginalFilesImport` was run against the original
parser before any parser/UI fixes. It tried every file and failed with levels
`[200, 300, 400]`; each produced the exact issue error:
`DXF: нет поддерживаемой 2D-геометрии. BLOCK/INSERT не разворачиваются.`
Local evidence: `/tmp/fieldforge-issue14-red.log`.

```sh
swift test --scratch-path /tmp/fieldforge-issue14-baseline-spm --filter DXFRealTests
```

## Independent original-file audit

A separate Python environment with **ezdxf 1.4.4** executed
`scripts/audit_real_dxf.py`; it is not a runtime or required unit-test dependency.
It confirmed AC1015, POLYLINE flag 8 and VERTEX flag 32 throughout, all open,
**0 audit errors and 0 automatic fixes** per file. Raw group-code-pair inspection
independently agreed. SHA-256 matches the supplied archive manifest; see the
[fixture provenance and hashes](../Tests/Fixtures/DXFReal/README.md).

| Original | Polylines | Vertices | X bounds | Y bounds | Z bounds |
| --- | ---: | ---: | --- | --- | --- |
| 200 | 13 | 627 | 4320…5337.978491389462 | 10054.5…10354.5 | 150…250 |
| 300 | 13 | 627 | 4320…5337.998076178854 | 9914.5…10214.5 | 250…350 |
| 400 | 4 | 294 | 4500…5337.97534562561 | 9847…10073 | 350…400 |

`DXFRealTests` asserts literal original XYZ endpoints, XYZ extrema, counts,
layer controls, open/3D status, insertion units and exact projected paths. File
staging/readback asserts byte identity, corrupt-import safety, source-plan
isolation, XY after pan/zoom and both horizon-default/manual Z. These are synthetic
local metre examples, not surveyed mine data or validated physical accuracy.

## Executed core verification

Baseline before fixes: **101 tests, 0 failures**. Current full SPM suite:
**109 tests, 0 failures**, including all original files, POINT/TEXT/MTEXT,
Windows-1251/unsupported encoding, mesh/fit/visibility/OCS warnings, journal
project/horizon/excavation/search/date/sort and all existing migration/evidence tests.

```sh
swift test --scratch-path /tmp/fieldforge-issue14-baseline-spm
python3 scripts/generate_project.py
```

No persistence schema/version, journal path, migration or evidence mutation
infrastructure was added. Original managed-file and append-only journal protections
remain. Source 3D geometry is a transient parsed drawing beside immutable original
bytes, separate from observation coordinates. The source inventory and test-only
resources are included in the generated Xcode project and SPM.

## Simulator acceptance

Target: iPhone 15 Pro Max simulator `BD08E87B-C0C8-4B44-AB68-BA35A4F3174D`,
iOS 26.5, Xcode 26.6 (17F113). Final simulator results are recorded below.

The original-file UI cases import **each** original, select the plan, assert
polyline/vertex counts, pan/zoom and pick independent bounding-box centres,
retain picket/manual Z, save/reset horizon Z, render/select the saved marker,
open its original journal record and reopen the plan after relaunch. Journal
horizon/excavation selectors/search/reset are also exercised. Existing two-plan,
overlap, Files-picker open/cancel, mapping and standalone measurement UI cases
remain in the complete suite.

### PR #15 journal search/focus follow-up

The three original-horizon UI tests were rerun before the fix; all three reproduced
the keyboard-focus failure at the horizon search. Failure logs and accessibility
hierarchies show that `app.searchFields.firstMatch` selected the underlying
«Пикет или метры» field instead of the presented filter's search.

The native fields now have distinct identifiers (`journalPicketSearch`,
`journalHorizonSearch`, `journalExcavationSearch`) and the tests scope each query
to its navigation bar. A journal-local UIKit accessibility adapter labels the
native fields; filtering still uses the existing SwiftUI bindings and query.
Filter search bars remain visible, and search dismissal recognizes iOS 26's
«Закрыть» label within the journal navigation bar.

The same three tests check keyboard availability, entered values, option removal
and restoration for nonmatching/matching horizon and excavation searches, matching
and case-insensitive picket searches, zero record rows for a nonmatch, and the same
saved record UUID after cancel/reset. No DXF parsing, geometry, persistence or
unrelated application behavior changed in this follow-up.

Corrected targeted run: **3 tests, 0 failures, 0 skipped**
(`/tmp/fieldforge-pr15-targeted.xcresult`), before the complete simulator suite.
Full SPM rerun: **109 tests, 0 failures** (`/tmp/fieldforge-pr15-spm`). Two project
generator runs produced byte-identical, unchanged project and scheme files.

The subsequent **complete simulator suite passed all 116 tests: 109 core and
7 UI, with 0 failures and 0 skipped** (`/tmp/fieldforge-pr15-complete.xcresult`).
Both Xcode result-bundle summaries confirm the counts. Commands used the shared
`FieldForge` scheme, the simulator above, `-parallel-testing-enabled NO` and
`CODE_SIGNING_ALLOWED=NO`; the targeted run selected only the three
`testOriginalHorizon{200,300,400}ImportProjectionPickingAndMarker` methods before
the unfiltered `xcodebuild test` run.

## Limitations

- Simulator fixture input is DEBUG/simulator-only. It passes the original UTF-8
  bytes through the normal setup, managed-file parsing/staging, integrity checks,
  graph registration and viewer. It does not qualify real Files/iCloud/storage
  providers. The owner must smoke-test manual Files import on iPhone; no physical
  phone was touched by this task.
- Bounded XY display is not full CAD. Unsupported features are counted/warned;
  labels use approximate native font layout. See [adapter contract](p2-dxf.md).
- No surveyed accuracy, sensor calibration, mechanical stability, storage-full
  or power-loss validation is claimed. The three supplied drawings are synthetic.
