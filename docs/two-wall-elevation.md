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

## Wall correspondence policy v1

The distance-weighted expression is applied only after local geometry validation:

1. Group segments by expanded entity ordinal and block-instance path, **not**
   handle alone, layer, filename, vertex count or array position. Find each source
   wall's nearest position independently. Adjacent vertices may have different
   spacing/counts. Non-adjacent, equally close portions of a folded wall prevent
   automatic acceptance (distance tie allowance: the existing 0.1 m picking policy).
2. Enumerate pairs of distinct walls without a 2 m or 5 m candidate radius.
   Tangents must align within 30 degrees, independent of vertex order. Projection
   vectors from the tap must oppose within 30 degrees; their connecting section
   must lie within 30 degrees of perpendicular to **both** local tangents.
   Zero-width/coincident walls cannot form a pair. This also prevents extrapolation
   past an open dead end from automatically becoming a transverse floor section.
3. Reject automatic sections crossing any intervening eligible wall geometry,
   even when that geometry has a different Z. Collinear overlaps and shared
   intervening endpoints also block a section. This prevents skipping a nearer
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
source units), 50 m review guard, resource bounds and tie policy are **application picking heuristics**,
not published geological coefficients, survey tolerances or excavation design
criteria. The 64 nearest source walls bound enumeration; truncated searches
cannot auto-accept. A conservative upper bound of 2,000,000 segment checks stops
complex searches and asks for explicit wall selection. Neither resource limit is
a radius; explicit wall picks search the whole eligible geometry.

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

## Independent validation

`TwoWallElevationTests` contains hand-calculated straight, asymmetric, sloping,
curved, unequal-spacing, variable-width, >5 m, direct-wall, dead-end, access,
T-junction, parallel-drive, rock-gap, overlap, missing/invalid Z and persistence
controls. For example at x=25, two 100 m ramp walls provide Z1=105 and Z2=120;
10 m across-width taps at y=2,5,8 must give **108,112.5,117**, respectively. On the
curved diagonal control Q1=(17,7), Q2=(14,10), d1=2√2, d2=√2 and Z1=17,Z2=26
must give **23**.

`audit_two_wall_elevations.py` independently reads committed DXF group-code pairs,
selects explicitly known fixture routes, and calculates 45 floor controls using
50-digit Decimal arithmetic. It imports neither the production service nor the
fixture generator. The older 90 controls audit **individual nearest-wall
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

Verification on 2026-10-22:

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
  intersection): [publisher/author contents](https://realtimecollisiondetection.net/books/rtcd/toc/).
- Autodesk AutoCAD DXF 2018 [VERTEX group codes](https://help.autodesk.com/cloudhelp/2018/ENU/AutoCAD-DXF/files/GUID-0741E831-599E-4CBF-91E1-8ADBCFD6556D.htm):
  explicit WCS XYZ for 3D polyline vertices; the existing supported extraction
  subset and exclusions remain as documented in [DXF revisions](dxf-elevation-plan-revisions.md).
- The across-width distance formula and two-wall workflow are the owner's explicit
  specification for this change; wall-pair discovery is the conservative versioned
  application policy above, not a claimed published rock-mechanics method.
