# Approximate automatic DXF elevation

`PlanElevationSnap` uses `DXF-WCS-nearest-distinct-polyline-IDW/1` for new proposals.
It replaces strict wall-pair discovery. The existing schema-8 journal, immutable
observations/revisions, DXF extraction and original SHA-256 are preserved. There
is no migration, reset, CRS conversion, or rewriting of saved elevations.

## Calculation and coordinates

1. Query the loaded document's shared XY BVH within the configured search radius.
   Only finite, supported straight LINE/POLYLINE/LWPOLYLINE elevation segments
   participate. Missing explicit Z, unsupported OCS/bulge/mesh geometry and
   zero-length/vertical XY segments cannot provide a height.
2. Choose the nearest segment, then the nearest segment with a different wall ID.
   Wall identity is the expanded entity ordinal plus block-instance path, not the
   filename, layer, handle or vertex spacing. Adjacent segments of one polyline
   do not supply two independent sources. Stable index ordering resolves ties.
3. For each source, project P onto segment AB in drawing XY:
   `t = clamp(dot(P-A,B-A)/dot(B-A,B-A), 0, 1)`.
   Interpolate `Z = A.z + t*(B.z-A.z)` and calculate the XY distance to the projection.
4. Convert source elevations and distances to metres using explicitly confirmed
   drawing units. For two sources use the owner's specified inverse-distance
   weighting (power 1): `(Z1*d2 + Z2*d1)/(d1+d2)`.
   An exact segment hit uses that source's Z after the overlap safeguard. If only
   one eligible polyline is nearby, use its nearest segment's Z and mark the
   proposal «Приблизительная Z по одному сегменту».
5. Preserve the exact original selected X/Y in drawing coordinates, without
   projection, unit conversion or rounding. Z is in metres; its vertical datum
   stays unknown. All proposals are approximate and require field judgement.

There are no opposite-side, tangent, transverse-section, continuation, layer-name
or fixed excavation-width prerequisites, and no manual wall-selection workflow.
The search does not expand to drawing extents. Overlap checks use at most two
additional small BVH queries around the chosen projections. No tap scans all
source segments or rebuilds the index. Dense local geometry can still increase
query work; no physical-iPhone timing or survey accuracy is claimed.

## Configurable practical safeguards

`PlanElevationSnapPolicy` stores metre-valued application thresholds. These are
picking heuristics, not engineering accuracy, risk or excavation design limits.

| Setting | Default | Purpose |
| --- | ---: | --- |
| `searchRadiusMeters` | 25 m | Both sources must be nearby; do not combine a local source with remote geometry. A lone local source can still supply approximate Z. |
| `maximumElevationDifferenceMeters` | 25 m | Refuse substantially different levels among selected and equally close competing sources. |
| `similarDistanceMeters` | 0.1 m | XY overlap neighborhood around each source projection and distance tie allowance. |
| `distinctElevationMeters` | 0.5 m | Refuse overlapping XY geometry whose interpolated Z range exceeds this value, including self-overlaps of a polyline. |

All thresholds must be finite and nonnegative. Small consistent elevation
variations remain eligible. The legacy `toleranceMeters` (2 m) is retained for
validating old single-segment records only. New optional policy fields decode
absent in old JSON using the version-1 defaults. Full numerical precision is
preserved; display formatting is separate.

A DXF cannot establish excavation connectivity or the intended underground level.
Nearby unrelated geometry with consistent Z can still supply an approximate
result. The safeguards detect clear distance/height conflicts, without introducing
another topology classifier. Unavailable/unreliable Z leaves XY confirmation
available and asks for manual Z in Mapping. A nominal horizon, filename or phone
GPS never supplies plan-tap Z.

## Units and field UI

Supported `$INSUNITS` metres=6 / millimetres=4 are resolved automatically at
import and saved as `dxfINSUNITS`. Missing, unitless or unsupported declarations
require one explicit metres/millimetres source choice during import. Resolved
units are reused; supported declarations cannot be contradicted by a manual choice.

Existing unknown-unit plans have one-time confirmation in plan properties.
The existing `elevationUnitConfirmation` persists the decision/time for new Z
proposals without relabelling saved XY, CRS, original files or observations.
Updating the loaded plan recalculates the current proposed point automatically.

A tap displays X/Y and approximate Z, or «Z недоступна». The single primary
button «Использовать точку» transfers the point and returns to Mapping. Search
is always enabled and ambiguity safeguards remain unchanged. Detailed provenance
stays in plan properties and Mapping's Z-source popover. Manual Z always takes
priority over a new estimate, without a picker or dialog. Clearing manual Z
permits automatic filling on the next selection; subsequent automatic selections
replace previous automatic Z. Reopening a plan never changes saved observations.

## Provenance and historical compatibility

New evidence stores the method version, original plan UUID/revision/SHA-256,
exact selected XY, source segment XYZ/identity, projection parameters, distances,
interpolated result, policy and unit declaration/confirmation. `secondWall` remains
an optional second source field; absence explicitly identifies a single-source
estimate. Exports retain the complete existing JSON provenance column.

`DXF-WCS-XY-segment-projection/1` and `DXF-WCS-two-wall-section/1` keep their original
validation and source labels. `PlanWallSection.compatible` remains solely to
validate historical two-wall evidence; automatic discovery and manual pair picking
were removed. Opening old evidence does not rerun today's neighbor policy.
Controlled manual corrections retain the original evidence and add a revision.

## Lightweight verification

Routine changes follow [AGENTS.md](../AGENTS.md): one focused automated selection
and one iOS Simulator build. `TwoWallElevationTests` retains independent arithmetic
references for straight/asymmetric/curved/unequal-spacing/variable-width sources,
exact hits, single sources, shared-polyline adjacency, overlaps, levels, short
fragments, historical evidence and current-journal round trips.
`PlanElevationSnapTests` and `PlanRevisionManagementTests` cover units, missing/
unsupported geometry, manual preservation, tampering, revisions and persisted
confirmation without modifying earlier observations. Small `PlanElevationIndexTests`
check BVH ordering and complete segment bounds without performance campaigns.

The compact survey resources, their existing projection/control tests and optional
Python auditors remain useful for fixture or parser investigations. They are not
routine gates and are not regenerated for this change. The former 45-point
wall-route oracle now tests historical two-wall records independently of automatic
neighbor discovery. 10k/100k benchmarks remain opt-in through
`FIELD_FORGE_DXF_BENCHMARKS=1`; no essential CI check is disabled.

## Published primitive references

- Christer Ericson, *Real-Time Collision Detection* (2005), §§3.4, 5.1.2,
  6.2.1, 6.3, 6.6.1: linear interpolation, closest point on a segment and existing
  BVH construction/traversal. [Author's contents](https://realtimecollisiondetection.net/books/rtcd/toc/).
- Autodesk AutoCAD DXF 2018 [VERTEX group codes](https://help.autodesk.com/cloudhelp/2018/ENU/AutoCAD-DXF/files/GUID-0741E831-599E-4CBF-91E1-8ADBCFD6556D.htm):
  source WCS XYZ contract. Extraction version remains
  `Autodesk-DXF-2018-straight-WCS-blocks/2`.
- The two-source inverse-distance expression and approximate workflow are the
  owner's explicit specification. It is ordinary weighted interpolation, not a
  rock-mechanics calculation or a survey-grade elevation method. Historical
  two-wall validation retains its documented 30° tangent/opposition checks.

## Verification for this change (2026-10-22)

- Targeted SwiftPM selection: 39 tests for elevation, units, provenance, current
  persistence/plan revisions, supported DXF extraction and small BVH controls.
  Initial result: 38 passed, one incorrect junction expectation failed. The
  junction contains XY-coincident sources differing by 2 m; the corrected test
  expects refusal and passed in a one-test rerun. No passing suite was repeated.
- One generic iOS Simulator app build: **BUILD SUCCEEDED**, signing disabled,
  Xcode 26.6 / iOS Simulator SDK 26.5, arm64 and x86_64. The existing App Intents
  metadata warning is unrelated to this change.
- `python3 scripts/generate_project.py`: no project/scheme diff. No source
  inventory changed. `git diff --check`: passed.
- Deliberately skipped: full SwiftPM/Xcode regression, Simulator UI automation,
  manual field acceptance, 10k/100k stress/performance checks, survey regeneration
  and independent Python DXF audits. No repository CI workflow was removed or
  changed. Existing optional tools/compact fixtures remain available.

Commands (logs were written outside the repository):

```sh
swift test --scratch-path /tmp/FieldForge-nearest-spm \
  --filter 'PlanElevationSnapTests|TwoWallElevationTests|PlanRevisionManagementTests|DXFElevationAuditTests|PlanElevationIndexTests.test(Bounded|Nearest|Nearby)'
swift test --scratch-path /tmp/FieldForge-nearest-spm \
  --filter 'TwoWallElevationTests.testTJunctionAndShortFragmentsDoNotRequireTransverseSectionOrContinuation'
xcodebuild -project FieldForge.xcodeproj -scheme FieldForge \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/FieldForge-nearest-ios CODE_SIGNING_ALLOWED=NO build
```

Physical iPhone field usability/accuracy and actual mine topology are not verified
by these automated numerical checks or by the compile build.
