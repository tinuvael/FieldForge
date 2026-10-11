# Coordinate systems and orientation conventions

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

## Display and AR

Separate authoritative model coordinates from viewport/device coordinates. Large mine coordinates require an explicit local origin/rebase before Float GPU rendering. RealityKit/ARKit scene tracking is local; device tracking and a visually aligned mesh do not establish a mine survey datum or engineering accuracy. Preserve the reversible display transform and georeferencing separately. Handedness/axis changes and scale must be declared and tested at each format/framework adapter.
