# Two-wall DXF floor elevation

This supersedes the nearest-segment picking and nominal-horizon fallback described
in older DXF documents. It does not modify geological classifications, orientation
algorithms, wedge mechanics, the mapping schema number (8), or measurement-journal
compatibility. Horizon identifiers and filenames never supply point elevation.

## Calculation and coordinate contract

Implementation: `PlanElevationSnap` and `PlanWallSection`, pure Foundation shared
by SwiftPM and iOS. Method `DXF-WCS-two-wall-section/1` uses explicit WCS endpoint
XYZ from supported straight LINE/POLYLINE/LWPOLYLINE geometry. Open polylines are
supported; no artificial closing edge is added. Segment projection is
`clamp(dot(P-A,B-A)/dot(B-A,B-A),0,1)` in drawing XY; each wall Z is independently
linearly interpolated using that parameter. The final floor estimate is
`(Z1*d2+Z2*d1)/(d1+d2)`. An exact wall hit uses that wall's Z, without division by
zero or an invented second source. A wall hit is recorded as a single-source result.

Distances are XY distances, not XYZ distances. All wall Z and distances convert
to metres using the existing explicitly confirmed metric unit contract. The
selected X/Y remain the original drawing-space tap, unrounded and unprojected.
Drawing axes, horizontal CRS and the source hash/revision remain attached; the
vertical datum remains unknown. No GPS, north/datum conversion, or accuracy claim
is introduced. Z remains manually editable, with manual override clearing derived
provenance. On a plan tap without usable Z, a nominal-horizon suggestion is cleared;
an existing deliberate manual entry or deliberate empty manual value is preserved.
Historical observations and their nominal-horizon values are never rewritten.

## Wall correspondence policy and local spatial search

The distance-weighted expression is applied only after local geometry validation:

1. The loaded `DXFDocument` owns one immutable `PlanElevationIndex`. Its XY
   bounding-volume hierarchy (BVH) stores complete segment AABBs, not just source
   vertices or centres. Document value copies share the same index reference;
   taps do not build indexes or regroup the drawing. Source-wall membership is
   grouped once by expanded entity ordinal and block-instance path, **not** handle,
   layer, filename or vertex count. Walls with more than eight segments have an
   additional per-wall BVH for independent continuation projections.
2. Find the exact nearest eligible segment using point-to-AABB lower bounds and
   branch-and-bound traversal. Query a disk initially twice that segment's XY
   distance, doubling it until a transverse candidate exists or all source bounds
   have been covered. There is no fixed candidate radius or drawing-wide count
   cutoff. A discovered section of width W closes the search with an exact 2W
   disk: this includes every competing section allowed by the 1.5W rule and every
   extra parallel rail allowed by the 2W rule. Distant geometry outside this local
   envelope cannot change the result. Query results sort by exact segment distance,
   entity ordinal, segment index, wall identity and original array index.
   Deduplicate walls only after that ordering, preserving nearest source positions.
   Angular bins limit pairing to opposite projection directions; an incumbent
   minimum width prunes pairs beyond the competitive distance. Adjacent vertices
   may have different spacing/counts. Non-adjacent, equally close portions of a
   folded wall prevent automatic acceptance (existing 0.1 m tie allowance).
   Evaluate pairs of distinct local walls without a 2 m or 5 m candidate radius.
   Tangents must align within 30 degrees, independent of vertex order. Projection
   vectors from the tap must oppose within 30 degrees; their connecting section
   must lie within 30 degrees of perpendicular to **both** local tangents.
   Zero-width/coincident walls cannot form a pair. This also prevents extrapolation
   past an open dead end from automatically becoming a transverse floor section.
3. Reject automatic sections crossing any intervening eligible wall geometry,
   even when that geometry has a different Z. An indexed chord-AABB query supplies
   only potentially intersecting segments to the unchanged exact intersection
   predicate; no pair scans the full segment collection. Collinear overlaps and
   shared intervening endpoints also block a section. This prevents skipping a nearer
   boundary to reach another drive or overpass.
4. Reproject independently on each complete source wall at probe points half a
   local width forward and backward along the mean tangent. Each must retain a
   compatible transverse section, a width between half and twice the original
   width, and no intervening geometry. Missing continuation at a throat, sharp
   corner or end requires confirmation. Sections wider than 50 m also require
   confirmation, even with long continuous walls. This is a product review guard,
   not a maximum excavation width or a candidate search radius; distant geometry
   remains selectable. Very distant, short walls also fail the support check.
5. Consider competing sections whose total wall distance is at most 1.5 times
   the smallest candidate section. More than one requires explicit choice,
   **even if the resulting elevations agree**. A distinct-height competitor is
   never silently discarded merely for having the less convenient Z. Wider
   sections remain available through explicit plan wall selection.
6. Additional parallel rails within twice the section width may bound intervening
   rock rather than an excavation. Without correspondence hints this requires
   confirmation. Optional `route_LEFT` / `route_RIGHT` layer hints can support
   an otherwise valid pair; conflicting route/side hints require confirmation.
   Hints never overcome overlap, geometry or competing-section checks, and no
   naming convention is mandatory. Two isolated unnamed wall polylines work.

These dimensionless angles/ratios, numerical XY coincidence tolerance (1e-8
source units), 50 m review guard and tie policy are **application picking heuristics**,
not published geological coefficients, survey tolerances or excavation design
criteria. The former 64-wall cutoff and 2,000,000-operation guard are removed.
Neither total wall count nor total segment count participates in acceptance.
The 50 m *section-width review* guard is retained; it does not stop search or
prevent explicit source selection. Manual wall hit testing uses the same global
index, and highlighting uses cached per-wall membership rather than full scans.

The BVH uses deterministic longest-axis median splits and at most eight segments
per leaf. Storage is linear in source segment count, with shared source arrays;
construction sorts subranges, taking O(N log² N) worst-case work once on the
existing background DXF-loading path. Typical nearest/disk/chord queries prune
unrelated nodes; a dense local overlap can still require many exact predicates.
Worst-case query work is data-dependent, rather than a universal logarithmic or
physical-iPhone timing guarantee. Local geometric ambiguity still requires review;
distant source complexity never constitutes ambiguity by itself.

To make an actual 100,000-LINE DXF loadable, the ASCII parser's pair budget is
raised from 300,000 to 1,000,000 (2,000,000 text lines). The 10 MB source cap,
200,000 display vertices, 200,000 expanded records, 1,000,000 expansion-work budget,
and all numeric/geometry validation remain in force. A stress source with 100,000
segments is 6,100,047 bytes and has exactly 200,000 display vertices. The index is
transient; it adds no database fields, migration, dependencies or evidence rewrite.

A single isolated wall within the existing 2 m single-source estimate tolerance
can supply a clearly marked `DXF · 1 стена ≈` estimate. That limit does not restrict
two-wall candidates. Multiple similar-distance single sources require explicit
choice. A failed multi-wall pairing never automatically copies the nearest wall.
Distinct coincident wall elevations require a source choice. Missing endpoint Z,
unsupported OCS/bulge geometry and XY-degenerate segments cannot invent Z.

## Intersections, topology and user review

A bare DXF wall graph cannot prove mine topology. In particular, multiple parallel
unlabelled rails cannot distinguish excavation from intervening rock; perfectly
superposed XY floors cannot establish the intended level. T-junction mouths may
lack a complete transverse section. These cases require highlighted source review
or leave Z unknown. This is intentionally conservative rather than a claim of
universal branch recognition from raw linework. Sharp bends, large width changes,
short wall fragments and incomplete survey extents can also need confirmation.

The plan displays the proposed point at the original XY and highlights the
selected source walls in cyan. A source picker previews candidate walls, source
Z and distances. «Указать две стены на плане» lets the user tap the two source
walls without moving the original point. When sources overlap in plan, a wall
chooser exposes layer, handle and interpolated Z so the upper/lower source can be
selected deliberately. User confirmation may override the global overlap and
continuation checks after review; it **cannot** override opposite-side/local
transverse validation. Confirming XY with no DXF source leaves unknown Z (or an
existing manual value). No stable/unstable or engineering confidence label is used.

Mapping and correction forms keep one compact trailing provenance button in the
Z row (`DXF · 2 стены`, a confirmed estimate marked `≈`, or single-wall estimate). Its popover shows both source
wall elevations/distances; no additional coordinate-information section is added.

## Persistence and evidence

`PlanGeometryElevation` keeps the existing first segment/parameter/distance and
now optionally includes `secondWall` (segment XYZ/identity, parameter, distance,
wall elevation), and `confirmedByUser`. The final `elevationMeters` is the across-
width result; the first source elevation is reproducible from its segment. Layers
are optional descriptive segment metadata; the extraction version remains
`Autodesk-DXF-2018-straight-WCS-blocks/2` because extraction coordinates are unchanged.
Both source identities remain qualified by the original SHA-256 and plan revision.

Validation recomputes both projections, the local transverse check and weighted
Z, rejects a missing second wall for the new method, and retains support for
historical `DXF-WCS-XY-segment-projection/1` records. Global picking heuristics are
not rerun when opening evidence: the original hashed plan/source snapshot and
recorded method remain authoritative for that saved calculation. CSV's existing
JSON provenance column and technical workbook provenance preserve the complete
optional source record. Old schema-8 journals decode without rewriting. No mapping
migration, reset or older-schema support is added. Manual corrections create the
existing append-only observation revision and retain original derived evidence.

## Local-search verification

`PlanElevationIndexTests` covers 10,000 and 100,000 independent segment/wall sources
with a two-wall ramp near the tap and unrelated sources on both sides far away.
Each size compares 20 repeated results with the complete small baseline record,
requires automatic Z=108 (Z1=105, Z2=120, d1=2, d2=8), and preserves exact XY.
Disk-query projection counts verify spatial pruning; index identity verifies reuse.
Additional controls cover real 100,000-segment DXF loading, expanding beyond the
initial disk, complete long-segment bounds, deterministic ties versus independent
brute-force ordering, invalid segments, crossing/adjacent ambiguity, and explicit
wall confirmation. Wall/index arrays and process resident-memory deltas are
reported separately; array payload counts do not pretend to measure Dictionary,
String, allocator or parser peak memory. Timing assertions are broad test-host
regression ceilings, not a claimed survey-device performance specification.

Local-search revision, 2026-10-22: **60 focused SwiftPM tests and 38 focused
Xcode simulator tests, zero failures**. This selection covers DXF extraction,
indexing, two-wall geometry, provenance, persistence and plan revisions; no whole-
project regression run was performed for this revision. The app/test bundles
build successfully for iPhone 17 Pro Simulator, iOS 26.5, Xcode 26.6.

Final simulator stress measurements (debug build, 20 complete resolutions each):

| Segments / independent walls | Index construction | Average resolution | Index array payload | Added resident bytes | Disk query projections |
| --- | ---: | ---: | ---: | ---: | ---: |
| 10,000 | 0.170 s | 0.983 ms | 538,656 B | 0 B incremental* | 9 |
| 100,000 | 3.933 s | 1.186 ms | 5,059,744 B | 22,712,320 B | 12 |

*The allocator reused already resident memory in the 10k case; this does not mean
zero memory consumption. Payload counts exclude source arrays, dictionaries and
strings. Both stress sizes additionally verify local competing drives remain
ambiguous and explicit confirmation recovers the expected Z=108 at unchanged XY.

The actual 100k-segment DXF imported and indexed in **8.385 s** in the final
simulator run. The concurrent final SwiftPM import took **41.654 s**; earlier
isolated runs took 7.884 s, demonstrating test-host scheduling sensitivity. Loading
stays on the existing background task. These are service/loader measurements;
Canvas redraw, Files-provider latency and physical-device performance are not
timed or claimed. Source geometry outside the local query envelope is pruned
regardless of the total drawing size.

The independent 45-point Decimal control check passes. Consecutive Xcode project
and scheme generations match; current project SHA-256:
`ca16ae9a24dfb4fdd0070eabe4b20b7bfdf9c438d4a3a6e3a6501e0746203026`.
The earlier whole-suite results below are historical.

## Independent validation

`TwoWallElevationTests` contains hand-calculated straight, asymmetric, sloping,
curved, unequal-spacing, variable-width, >5 m, direct-wall, dead-end, access,
T-junction, parallel-drive, rock-gap, overlap, missing/invalid Z and persistence
controls. For example at x=25, two 100 m ramp walls provide Z1=105 and Z2=120;
10 m across-width taps at y=2,5,8 must give **108,112.5,117**, respectively. On the
curved diagonal control Q1=(17,7), Q2=(14,10), d1=2√2, d2=√2 and Z1=17,Z2=26
must give **23**.

`audit_two_wall_elevations.py` independently reads hash-pinned DXF group-code pairs,
selects explicitly known fixture routes, and calculates 45 floor controls using
50-digit Decimal arithmetic. It imports neither the production service nor the
fixture generator. By default a subprocess creates the source DXFs in a temporary
directory, verifies the original manifest hashes and removes them after the audit;
`--dxf-dir` can select existing DXFs. SwiftPM/Xcode reconstruct identical DXFs from
the compact coordinate resource without Python; see [fixture reproduction](underground-survey-z-verification.md#reproduction).
The older 90 controls audit **individual nearest-wall
projections**; “interior” in those names refers to segment parameters, and some
points are outside the excavation. They must not be reused as across-floor Z.
The new CSV constructs interior cross-wall samples and includes the three original
widened-drift centers. Names 500/600/700 remain identifiers only. Renamed imports
and unrelated nominal +393 horizons exercise managed originals, save and reopen.

```sh
python3 scripts/audit_two_wall_elevations.py --check
python3 scripts/generate_underground_surveys.py --check
python3 scripts/generate_project.py
swift test
```

Earlier two-wall verification on 2026-10-22 (before the local-search revision):

- SwiftPM: **347 tests, 0 failures, 2 existing opt-in workbook skips**.
- Xcode simulator core suite: **347 tests, 0 failures, the same 2 skips**;
  app and test bundles build on Xcode 26.6 / iPhone 17 Pro, iOS 26.5.
- All **45** independent two-wall controls agree within 1e-8 m. Each survey
  supplies 14/15 automatic results; its throat sample requires explicit confirmation.
- The independent Decimal check and original survey-generator byte checks pass.
- Two consecutive project/scheme generations are identical. Project SHA-256:
  `36794ddce4b6765cb0e3c670b9f10073a56c412877585062e650846f21f4a2ab`.
- Focused simulator UI scenario: **1 test, 0 failures** (132.153 s), covering
  automatic two-wall Z, inline provenance, both source elevations/distances,
  popover dismissal, manual override preservation, explicit highlighted wall
  selection and unchanged original tap X/Y. The source button has an independent
  borderless action and 44 pt minimum hit height, so inspection does not focus Z.

Per owner steering, full regression runs were not repeated after that request;
subsequent verification is restricted to the focused UI scenario and its build.
Physical survey validation and Files-provider/device smoke tests remain outside
these synthetic numerical/UI checks.

## Published primitive references

- Christer Ericson, *Real-Time Collision Detection*, 2005, §§3.4 (barycentric/linear
  interpolation), 5.1.2 (closest point on a line segment), 5.1.9 (segment
  intersection), 6.2.1 (top-down BVH construction), 6.3 (hierarchy traversal),
  and 6.6.1 (array representation): [publisher/author contents](https://realtimecollisiondetection.net/books/rtcd/toc/).
- Autodesk AutoCAD DXF 2018 [VERTEX group codes](https://help.autodesk.com/cloudhelp/2018/ENU/AutoCAD-DXF/files/GUID-0741E831-599E-4CBF-91E1-8ADBCFD6556D.htm):
  explicit WCS XYZ for 3D polyline vertices; the existing supported extraction
  subset and exclusions remain as documented in [DXF revisions](dxf-elevation-plan-revisions.md).
- The across-width distance formula and two-wall workflow are the owner's explicit
  specification for this change; wall-pair discovery is the conservative versioned
  application policy above, not a claimed published rock-mechanics method.
