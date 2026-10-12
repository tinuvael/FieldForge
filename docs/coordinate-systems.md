# Coordinate systems and orientation conventions

This document defines technical conventions for the three modules in the authoritative [product vision](product-vision.md). Plans/locations and wedge analysis below are future work; the implemented Phase 1/2 orientation conventions remain unchanged and will be shared by iPhone and native iPad.

## Orientation observations

- Dip angle: plane inclination from horizontal, 0–90 degrees.
- Dip direction: clockwise azimuth from the record's selected reference north, normalized to [0,360). It denotes maximum downhill for an inclined plane.
- Manual entry accepts 0–360 inclusive; 360 becomes 0 without rounding. Original text is kept for traceability. Decimal comma/dot is accepted; units are degrees.
- An exactly horizontal manual plane has no dip direction; the field must be blank. An exactly vertical plane may have no direction or a user-confirmed `conventionalDipSide`. This side is a reporting convention, not a uniquely determined downhill azimuth. Nonvertical manual entries cannot carry that flag.
- Manual angles near horizontal/vertical remain the values entered; the sensor's 0.5° singularity guard is not a manual-entry rounding rule.
- Magnetic, true, grid and unknown north are separate metadata. No declination or meridian-convergence correction is automatic. Unknown north can accompany an original compass reading; it cannot safely be combined with other orientations.
- Sensor observations retain historical `magneticNorth`, `simulatedNorth`, or `unavailable`; simulator north is synthetic, never geographic. No direction is inferred for reference-unavailable sensor samples.

If later adding a conversion, retain the original angle/reference and create a derived value with correction amount/sign, geographic position/date, geomagnetic model or survey reference/version, grid CRS, author and uncertainty. Never rewrite the original silently. A grid azimuth without a specified grid is incomplete metadata.

## Device boundary (unchanged Phase 1)

Fixed device axes: X right, Y toward the portrait top, Z out of the screen. Core Motion magnetic reference is right-handed **NWU**: X north, Y west, Z up. `CMAttitude.rotationMatrix` maps reference → device; its transpose maps device → reference. The screen normal in reference coordinates is the third row. SwiftUI layout rotation does not rotate these physical axes.

For a nonsingular sensor plane, dip azimuth uses `atan2(-p.y, p.x)`, where `p` is the downhill projection in NWU. The full algorithm, numeric validation, singularity behavior and Apple references are in [measurement-geometry.md](measurement-geometry.md). No NWU value should be mislabeled ENU/NED. Manual entries have no measured normal or device attitude.

## Survey, mine and geographic systems (future)

Every spatial asset must declare horizontal CRS, datum/epoch if relevant, vertical datum, axes/order/handedness and length units. Authority/code and WKT version are preferred for known CRSs; an explicitly described local mine grid may be authoritative on site without an EPSG identifier. Unlocated coordinates retain an `unknown` state rather than being treated as latitude/longitude.

Mine-grid metadata includes origin, axis names/directions, height definition and survey/georeferencing provenance. A transform record identifies source/target CRS and versions, translation/rotation/scale, units, method, control points, residuals and validity extent/date. A rigid local placement is not by itself a geographic datum transformation. Keep model transforms as Double-precision domain data; display matrices may use local Float coordinates after rebasing.

Chainage is a scalar **meters along the versioned alignment**, not a geographic coordinate. Declare chainage origin, increasing direction, station equations/discontinuities, branch, and whether distance is horizontal or 3D arc length. Left/right are viewed along increasing chainage. Store both the alignment version and placement parameters; later survey changes must not silently move observations. Interpolation should report unsupported geometry/gaps and out-of-range positions, not extrapolate without an explicit policy. No interpolation is implemented now.

Survey elevation must carry a vertical datum; phone AR altitude and GPS altitude are not replacements for surveyed mine levels. Geographic angular units and projected length units are distinct. GeoJSON RFC 7946 uses WGS84 longitude/latitude order, degrees (optional height in meters); arbitrary mine-grid XY cannot be emitted as standard GeoJSON coordinates without a verified transform.

## Prepared plans and manual underground positioning (future)

Underground GPS must not be assumed. Positions are declared by the engineer using surveyed points, chainage, recognizable excavation features and available survey geometry. Never label a manually selected plan point as an automatically detected phone location.

Retain surveyed coordinates, georeferenced-plan-derived coordinates, manually entered X/Y/Z and unknown model locations as distinct provenance. Approximate/uncertain quality is recorded separately; copying a surveyed value manually and selecting an approximate point on a calibrated plan are different evidence chains. Record source, author/time, units, CRS/vertical datum, axes, alignment version and transformation history for each location.

Raster georeferencing uses surveyed control-point revisions and a documented transform fitted to its declared model, not arbitrary image scale. Validate the model's required controls, nondegeneracy, residuals and spatial validity before reporting derived coordinates; acceptance criteria remain to be selected from survey requirements. PDF/raster page or pixel coordinates (including page, crop, rotation and origin direction) and device view coordinates must remain separate from mine-grid coordinates. Reverse zoom/pan/layout transforms before applying the versioned page/image-to-model transform; retain the original mark.

A 2D plan determines only the coordinates supported by its georeferencing. Z requires an explicit surveyed elevation or documented source/assumption; otherwise leave it unknown. With absent/invalid georeferencing, retain an unlocated plan mark or explicitly approximate coordinates rather than fabricate a surveyed location. A plan change or a revised alignment must not silently relocate saved records. Supported manual/derived locations are shared across mapping, plan selection and analysis through stable record IDs.

## Wedge analysis frames (future)

Excavation-axis azimuth and each discontinuity orientation require explicit north and angle conventions before entering one analysis frame. Unknown/incompatible north or grid metadata must produce a missing-reference result unless a documented conversion is supplied; do not combine magnetic joints and a grid survey axis silently. Record inclination sign, axis direction, local excavation-frame axes/handedness and length units in the geometry revision; the selected methodology must finalize these conventions before implementation.

Keep source orientations/coordinates, transformation revisions and local candidate geometry distinct. A local excavation/wedge frame serves visualization and the selected geometric model, not whole-mine modeling. Plane positions, persistence/termination, bounding surfaces and release assumptions are explicit inputs or missing information; orientation vectors alone do not prove finite volume. Mechanical cohesion/friction conventions and additional required quantities await the owner's verified formulation. Frame conversion does not establish mechanical stability.

## Display and AR

Separate authoritative model coordinates from viewport/device coordinates. Large mine coordinates require an explicit local origin/rebase before Float GPU rendering. RealityKit/ARKit scene tracking is local; device tracking and a visually aligned mesh do not establish a mine survey datum or engineering accuracy. Preserve the reversible display transform and georeferencing separately. Handedness/axis changes and scale must be declared and tested at each format/framework adapter.

The same source-to-model transform applies on iPhone and iPad; viewport, split-view and Pencil interactions must translate through their own reversible display transforms. AR and optional imported meshes are not prerequisites for offline plan positioning or compact wedge diagrams.
