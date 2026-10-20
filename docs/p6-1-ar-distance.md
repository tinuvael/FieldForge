# P6.1 — transient two-point AR distance utility

## Contract and integration

«Картирование» has «Замерить расстояние» immediately after its original-orientation measurement section. It presents a full-screen camera, centred aim, «Точка 1», «Точка 2», numbered world-space markers/line, a large distance in metres, «Повторить», «Готово» and Close. Controls scroll in a bounded panel on short/landscape screens. Selection is disabled without a current accepted 3D solution. Both exit actions return to the unchanged mapping draft. The result may remain in Mapping view memory until a new distance measurement starts; it is not a saved observation and does not survive app termination.

This is the narrowed P6.1 part of [Issue #11](https://github.com/tinuvael/FieldForge/issues/11): persistence, manual entry, linking and journal recording in that broader issue remain deferred. No new primary module, mapping schema/migration, database entity, automatic joint-spacing/rating update, wedge computation or orientation algorithm is introduced. The sheet cannot access MappingModel or MappingDraft. Existing photos, exports, DXF and evidence history are untouched.

## API selection and placement provenance

Native ARKit APIs available since iOS 14 (app minimum remains iOS 17):

- `ARWorldTrackingConfiguration`, `.gravity` world alignment and horizontal/vertical plane detection. `ARWorldTrackingConfiguration.isSupported` is checked before requesting camera permission or constructing the camera view. Simulator explicitly reports unavailable; it supplies no mock distance.
- On devices with `supportsFrameSemantics(.sceneDepth)`, enable `.sceneDepth` and read `ARFrame.sceneDepth`, `ARDepthData.depthMap` and `confidenceMap`. Only `ARConfidenceLevel.high`, finite positive depth, normal camera tracking and a fresh frame can supply a selectable point. If depth/confidence is unavailable, placement is refused; visual estimates are never substituted and labelled LiDAR.
- Convert the centre aim through the inverse `ARFrame.displayTransform(for:viewportSize:)` to account for interface rotation and camera aspect-fill crop. Read the corresponding depth pixel with its actual row stride. Back-project that pixel centre using scaled `ARCamera.intrinsics` and `imageResolution`; apply `ARCamera.transform` to produce a world point. Use unsmoothed scene depth from the same AR frame as the pose. No 2D pixel-distance measurement or fabricated depth.
- On world-tracking devices **without** scene depth support, use `ARSCNView.raycastQuery(from:allowing:.existingPlaneGeometry,alignment:.any)` and `ARSession.raycast`. Accept only detected bounded plane geometry, labelled «Оценка по плоскости · без LiDAR». No estimated-plane or infinite-plane fallback. Merely enabling mesh reconstruction would not prove a particular hit came from a mesh; no such provenance claim is made here.
- `ARSCNView` displays camera and SceneKit numbered markers/line. Markers are illustrative local AR placements, not survey control points. They are removed when tracking becomes unreliable.

Target hardware is iPhone 15 Pro Max; other LiDAR-equipped iPhones/iPads require the same runtime capability checks. World-tracking devices without LiDAR may offer the explicitly less certain plane method. Camera access uses `AVCaptureDevice.authorizationStatus/requestAccess`; denial/restriction shows instructions for iOS Settings. ARKit and camera are not required device capabilities for installing or using the other app features.

Primary API references (Apple ARKit documentation, checked 2026-10-20): [scene-depth sample and back-projection](https://developer.apple.com/documentation/arkit/displaying-a-point-cloud-using-scene-depth), [ARDepthData](https://developer.apple.com/documentation/arkit/ardepthdata), [camera intrinsics](https://developer.apple.com/documentation/arkit/arcamera/intrinsics), [camera transform](https://developer.apple.com/documentation/arkit/arcamera/transform), [raycast queries](https://developer.apple.com/documentation/arkit/arraycastquery), [tracking lifecycle](https://developer.apple.com/documentation/arkit/managing-session-life-cycle-and-tracking-quality).

## Mathematics and coordinates

Implementation version: `DistanceMath` P6.1. Euclidean straight-line metric in three dimensions: `sqrt((bx-ax)^2 + (by-ay)^2 + (bz-az)^2)`; evaluate with nested `hypot` to avoid unnecessary overflow. Reference: OpenStax, *Calculus Volume 3* (2016), [§2.2, Theorem 2.2, Equation 2.1 and Example 2.12](https://openstax.org/books/calculus-volume-3/pages/2-2-vectors-in-three-dimensions), accessed 2026-10-20. Independent fixtures include a 3–4–12 triangle (13 m), negative/translated endpoints, symmetry and sub-display precision. Zero, nonfinite coordinates, overflow and nonfinite/zero/negative depth are rejected.

AR world coordinates are a session-local right-handed Cartesian system in metres, +Y aligned against gravity, with arbitrary local horizontal axes and origin. Camera coordinates are +X right, +Y up, −Z forward. Captured-image pixels use +Y down. For image pixel `(u,v)`, axial depth `d`, focal lengths `(fx,fy)` and principal point `(cx,cy)`, the camera point is `((u-cx)*d/fx, -(v-cy)*d/fy, -d)`, then multiplied by the camera-to-world transform. This does not establish magnetic/true/grid north, mine coordinates, underground GPS or a surveyed location. Core geological orientation types and algorithms are unchanged.

Results retain Double precision; Russian formatting rounds to three decimal places only for display (e.g. «1,247 м»). Display resolution is **not accuracy**. A single high-confidence depth pixel can still be wrong at an edge or under drift.

## Quality and lifecycle

`DistanceSession` is an injectable main-actor boundary with start, pause and snapshot operations. `DistanceMeasurementController` validates transient points and controls two-point selection, retake and lifecycle. Unit fixtures supply explicit snapshots; they do not emulate sensors or validate hardware.

A 0.15 s foreground timer queries current tracking/surface for the UI; each tap re-queries rather than accepting the preview cache. Frames from before the current session start, future frames and frames older than 0.5 s are refused (a freshness guard, not an accuracy specification). Non-normal tracking, initializing/relocalizing, missing frames and excessive motion clear any pair and require Retake if points had been selected. Missing surface alone blocks selection while preserving the first point in the still-tracked coordinate frame. Tracking-state delegate events also invalidate points immediately, including a brief loss between timer polls. A completed pair is cleared on tracking loss. Returning to normal tracking cannot silently revalidate it.

`ARSessionDelegate` interruption/failure callbacks stop the session and clear points. `delegateQueue = .main` allows synchronous main-actor handling. After interruption ends in the foreground, a new world-tracking session starts with `.resetTracking` and `.removeExistingAnchors`. Any inactive/background scene phase pauses AR, invalidates the polling timer, clears points and cancels pending permission activation via a generation token. Return starts a new local frame. Close, Done, sheet disappearance and representable dismantling pause AR; the camera view/session are released with the sheet. No physical-device install/reset is part of verification.

Insufficient lighting is not separately diagnosed by an invented lux threshold: ARKit's `.insufficientFeatures` explicitly asks for more light/detail. In darkness LiDAR may return depth while camera tracking remains poor; placement is still refused. Failure and permission denial allow closing/retrying; AR-unsupported devices show a clear unavailable state.

## Limits and required physical qualification

This is an **approximate field utility**, not a surveyed instrument, and not qualified for millimetre-scale fracture apertures. No numerical accuracy/range claim is made. Reflective, translucent, wet, dark, featureless, moving or occluded surfaces, oblique angles, mixed pixels at edges, distance, accumulated pose drift and poor lighting can cause refusal or inaccurate results even with normal tracking/high confidence. Plane estimates are less certain and cannot model arbitrary rough rock. Three-dimensional markers may drift; points are not continuously re-estimated or corrected after selection.

Later, on the actual iPhone 15 Pro Max, compare several independently measured short/medium/long reference distances in different orientations, repeated from different standoffs and angles. Record reference method, device/iOS, illumination/surface, placement method, nominal and reference distance, error, repeatability and refusals. Include dark/wet/low-texture conditions, permission denial/regrant, interruptions, background/return, camera release on exit and preservation of a populated mapping draft. Establish any accepted operating envelope only after this physical comparison. Simulator success cannot establish measurement accuracy.

Automated build/test evidence and the retained initial UI failures are recorded in [P6.1 verification](p6-1-verification.md).
