# Screen-plane orientation: algorithm screen-plane-nwu-v1

This algorithm and its sensor gates are unchanged in Phase 2. Sensor records now use provenance-aware schema 2; manual compass observations bypass sensor processing and may explicitly record a vertical dip-side convention. See [coordinates](coordinate-systems.md) and [migration](persistence-migration.md). The acquisition/persistence narrative below describes the original Phase 1 implementation.

## Coordinate systems and Apple API boundary

The phone's fixed device axes are +X toward the right edge, +Y toward the top edge (portrait), and +Z out through the screen. These axes do not change when SwiftUI rotates its layout. The plane normal is `n_D = (0,0,1)`; changing screen orientation or rotating within the same geological plane does not change the geometric plane.

Core Motion's selected magnetic reference has +X magnetic north and vertical +Z upward. Its right-handed horizontal +Y is west. FieldForge uses this **NWU** frame throughout; east is negative Y. No ENU/NED relabeling is applied.

`CMAttitude.rotationMatrix` is a row-major direction cosine matrix `R` mapping reference vectors into device coordinates. In particular, `g_D = R (0,0,-1)`. To recover a device vector in reference coordinates, use `Rᵀ`: **`n_NWU = Rᵀ n_D = (m31,m32,m33)`**. Using the third column instead would calculate a different plane. The adapter preserves the complete matrix and quaternion rather than Euler pitch/yaw.

Apple's current [CMMotionManager documentation](https://developer.apple.com/documentation/coremotion/cmmotionmanager) defines the device axes, and [CMAttitudeReferenceFrame](https://developer.apple.com/documentation/coremotion/cmattitudereferenceframe) defines the available reference axes. The matrix direction is also illustrated by Apple's archived [pARk ARView source](https://developer.apple.com/library/archive/samplecode/pARk/Listings/pARk_ARView_m.html), which projects world coordinates into device coordinates using the attitude matrix. FieldForge additionally checks `Rᵀ g_D ≈ (0,0,-1)` for every sample; physical fixture tests must confirm the adapter convention in practice.

## Input validation

`Vector3.normalized()` first divides by the largest absolute component, then by the scaled norm to avoid numerical overflow/underflow. Zero, NaN and infinite normals are invalid. Geometry accepts arbitrary nonzero normal magnitude. The sensor path additionally requires:

- finite DCM elements, unit rows and mutually orthogonal rows within 1e-5, determinant +1 within 1e-5;
- finite quaternion components and unit length within 1e-4;
- finite timestamp, nonnegative finite sensor uptime, gravity, acceleration, angular velocity and magnetic vector;
- gravity magnitude within 0.1 of 1 g;
- reference-frame gravity residual below 0.05 g.

The quaternion is retained for diagnostics; the DCM drives the computation. The prototype does not validate the full quaternion/DCM equivalence for real samples. These gates reject malformed data and frame inconsistencies, not small sensor errors.

## Dip and maximum downhill direction

For the unit normal `n = (n_x,n_y,n_z)`, the angle between the plane and the horizontal is:

```text
dip = atan2(sqrt(n_x² + n_y²), abs(n_z)) · 180/π
```

This gives [0,90]°. It does not read the phone's pitch. The absolute vertical component treats opposite normals as the same unoriented plane.

Let `d = (0,0,-1)` be unit downward gravity in the reference frame. Project it into the plane:

```text
p = d - n (d·n)
```

For unit `n`, `n·p = 0`, so `p` lies in the plane. Among unit tangent directions `t`, the downward component `d·t = p·t` is maximal when `t` is parallel to `p` (Cauchy–Schwarz). Thus `p` is the maximum-downhill direction. It has horizontal components `(n_z n_x, n_z n_y)` and vertical component `-(1-n_z²)`. This derivation is independent of Euler angles and phone edge choice.

For nonsingular planes with a usable north reference:

```text
azimuth = atan2(-p_y, p_x) · 180/π
azimuth = azimuth modulo 360, shifted to [0,360)
```

The negative Y converts west to east, producing conventional clockwise azimuth from north. Reversing the normal leaves `n(d·n)` unchanged. A screen basis rotated within its plane leaves its reference normal unchanged up to sign, so the result is invariant. Independent test fixtures cover this property.

## Ambiguities and status order

The computed dip is retained without snapping to a nominal 0° or 90°. Status is selected in this order:

1. Invalid input: both values unavailable, saving forbidden.
2. `dip ≤ 0.5°`: horizontal ambiguity, dip retained, direction null. For exactly horizontal planes `p=0`; all tangent directions have zero downhill component.
3. `90° - dip ≤ 0.5°`: vertical ambiguity, dip retained, direction null. For exactly vertical planes `p=d` and its horizontal projection vanishes. No arbitrary dip-side or strike convention is substituted.
4. No usable north: reference unavailable, dip retained, direction null.
5. Otherwise: geometry valid, direction normalized.

The 0.5° guard limits numerical/sensor sensitivity near singularities. It is not a measured accuracy, and classification can change near the threshold. Azimuth's UI is rounded to 0.1°, with a rounded 360° shown as 0°; stored values are not rounded.

## Magnetic reference and quality

`CoreMotionSensorProvider` first checks hardware and available frames. It chooses `.xMagneticNorthZVertical` when available; otherwise `.xArbitraryZVertical` provides gravity and relative orientation only. It never assumes arbitrary yaw is geographic. True north is not requested; no location or declination model is used.

A physical sample's north is usable only with the magnetic frame, Apple's **high** calibration category and total field magnitude 10–100 μT. Low/medium/uncalibrated field or an out-of-range magnitude suppresses azimuth. The field magnitude is a broad prototype anomaly gate, not a regional geomagnetic model. Apple's calibrated field includes surrounding magnetic fields: good calibration cannot distinguish undisturbed north from local metal/rock/electrical interference. The UI explicitly states this and never labels any reading professionally accurate.

Quality is invalid for failed diagnostics; uncertain for `|userAcceleration| > 0.05 g` or `|rotationRate| > 0.1 rad/s`; inclination-only when no direction is returned; otherwise experimental. Uncertain/invalid data cannot be held or saved. A still reading is only a single instant, with no stability window, sensor covariance or claimed precision.

## Acquisition, HOLD and persistence

Core Motion delivers at 20 Hz. Timestamp is anchored to the sensor event using current wall-clock time and the difference between sensor and process uptime. A watchdog checks freshness every 0.5 s and drops live data older than 1.5 s; HOLD also rejects stale or future samples. Generation tokens reject callbacks from a stopped provider. Acquisition stops on HOLD, switching away from measurement and backgrounding, then resumes when appropriate. A held snapshot is historical and remains held after background/foreground transitions.

Mock readings refresh at 2 Hz, are generated from a prescribed synthetic screen basis and use `simulatedNorthZVertical`. Source and reference are stored permanently and shown in UI/CSV. Mock presets cannot be changed while held.

HOLD freezes UUID, event time, orientation, reference, quality and raw sample. Optional notes may be added before SAVE. Only a held admissible record can be saved, once. Store validation reconstructs the result from its raw sample, rejects inconsistent derived values/duplicates and commits the complete journal atomically in schema version 1. A load error disables writes while preserving the original file.

CSV contains result/status/source/reference, normal, gravity, row-major DCM, XYZW quaternion, magnetic magnitude and motion diagnostics. Full raw vectors and uptime remain in local JSON. System uptime is deliberately excluded from exports; the privacy manifest declares the approved absolute-event-timestamp use of system uptime (`8FFB.1`).

## Planned physical validation (not performed)

1. Use a nonmagnetic, flat fixture that makes the screen plane parallel to independently known test planes. Avoid pressing the camera bump against the surface.
2. Verify gravity/DCM convention face up/down, on each edge and on a 45° fixture. Record raw diagnostics and the expected normal.
3. Test 0°, 30°, 45°, 60° and 90° with a calibrated inclinometer and a geological compass; establish a common magnetic reference and document declination separately.
4. At several headings, rotate the phone within each fixed plane and reverse its face. Repeat after restarts and both UI orientations.
5. Collect repeated samples across placements, dates and temperatures. Compute dip error and circular azimuth error away from singularities; report bias, spread and rejection rates. Set acceptance criteria before evaluating results.
6. Compare outdoor undisturbed measurements with controlled proximity to steel, magnets, machinery and representative mine environments. Check whether interference is falsely accepted despite high calibration.
7. Validate the printed adapter independently. Establish permitted use conditions and empirical uncertainty before professional deployment.

No phase-1 sensor accuracy, calibration success or physical deployment is inferred from a simulator or mathematical unit test.
