# W1: excavation and schematic joint orientations

Implementation: **w1-geometry-v1**, iPhone prototype, Issue [#29](https://github.com/tinuvael/FieldForge/issues/29). No mechanical or finite-wedge analysis.

## Workflow and ownership

Open «Клинья», enter/capture axis azimuth, explicitly choose north, enter B/H/L, then select a Mapping source and exactly three interpreted J1–J5 systems. Exactly three geometrically complete systems are preselected; four/five require explicit choice. Invalid systems are listed with an explanation. Fewer than three preserves the excavation shell. Horizontal dip 0° with blank direction is a complete plane; vertical dip 90° requires the source's confirmed conventional side/direction. A directionless vertical plane cannot be drawn.

Sources are the current unsaved draft or explicitly selected latest-effective saved point **within the active project/horizon/excavation**. No nearest-point choice. `WedgeMappingSource` retains context, point/draft UUID, point revision UUID/version (original = version 1, no correction UUID), original interpreted-set UUID/revision, representative input text/north/convention and complete original provenance/evidence links. Drafts retain their original `JointSetDraft`; no artificial revision/time/author is assigned. Read-only snapshots refresh from the shared `MappingModel.workflow`; changing source/revision resets selection. They never save, reinterpret or replace source records. Mapping remains the only entry for interpreted J systems.

All W1 state lives in view memory and is marked unsaved. It survives tab selection while the view exists, not process termination. No persistent scenarios, schema, migrations, database/attachment/export edits or storage calls were added. The current main storage format is unchanged (including its existing schema 8); W1 does not reconcile historical local branches' schema policies.

## Axis and dimensions

Clockwise azimuth A from the explicitly selected north, 0–360° (360 normalizes to 0; manual text retained). Magnetic, true, grid and unknown are separate. Planes require the same **known** north as the axis; no declination/grid convergence conversion or unknown-north reconciliation. Grid CRS/realizations must be checked by the engineer: legacy representative metadata has no grid realization ID. W1 cannot certify compatibility of different grids merely bearing the same label.

«Замерить ось» reuses `CoreMotionSensorProvider` in its magnetic-NWU frame, not the geological plane calculation. Point the portrait phone's top edge (+device Y) forward along increasing chainage, screen up, nearly horizontal. Transpose the reference-to-device rotation and project that edge horizontally: `A=atan2(-v_W, v_N)`. Retain the full original sample and method `phone-top-edge-horizontal-projection-v1`. Require physical Core Motion, valid diagnostics, high magnetic calibration, field 10–100 µT, age ≤2 s, acceleration <0.05 g, angular speed <0.1 rad/s and horizontal edge projection >0.5. These are prototype acceptance guards, **not validated accuracy thresholds**. Pause/dismiss stops acquisition; confirm rechecks freshness. No GPS/CLLocation or geological journal changes. True/grid headings use manual entry; unreliable sensors fall back to manual. Editing the accepted azimuth/north marks it manual and retains the original capture separately.

B = clear width; H = total floor-to-crown height, including roof; L = straight horizontal extent in metres. Finite positive input, decimal comma/dot; H > B/3. Empty/invalid values remain missing. An explicit Float-rendering range/aspect-ratio guard rejects numerically unrepresentable scenes, not geological dimensions. Width/height actions reuse P6.1 `DistanceMeasurementSheet`. Only a non-nil successful distance changes the field; all original precision and LiDAR/detected-plane source remain available. Subsequent manual corrections keep that original result and change the displayed provenance. W1 opts into cancellation on «Закрыть» (the existing utility keeps its default close behavior); «Готово» accepts a successful result. Cancel/failure/unsupported leaves the field intact. AR distance is approximate, unqualified on hardware; length is manual.

## Three-circle construction

Verified source: Ivanova N.A., *Основы горного дела*, Polar State University college practical-work guide, **2023**, practical work 5, printed pp. 23–24, equations (5.7), (5.10), table 5.1 ([PDF](https://polaruniversity.ru/vikon/sveden/files/MU_k_PR_OGD_1.pdf)). It specifies a central arc and two lateral arcs, with B/3 rise for f≤12 in the stated unlined/shotcrete/anchor context. W1 fixes that assumption; it is not a support design. The supplied secondary [Строительная геотехнология PDF](https://www.geokniga.org/bookfiles/geokniga-stroitelnayageotehnologiya.pdf), table 2.2, could not be retrieved during implementation and is not independently asserted as verified.

The table's rounded R≈0.692B, r≈0.262B overconstrain exact tangency/rise. W1 holds R=0.692B and h=B/3; let a=B/2, w=H−h. In section (x,z), central center C=(0,H−R), right lateral center S=(a−r,w). Internal tangency `|S−C|=R−r` gives:

```
r = (2Rh − h² − a²) / (2(R−a))
r/B = 451/1728 = 0.260995370370…
theta = atan2(R−h, a−r)
```

This is the documented W1 geometric adjustment, not a new empirical strength law. Circle parameters are `(cx+r cos(t), cz+r sin(t))`: right lateral t=0…theta, central theta…π−theta, left lateral π−theta…π. Centers/radii give coincident points and identical unit tangents at both joins; lateral endpoints have vertical tangents at the straight walls. Crown = H, width = B, wall height = H−B/3. Evaluate normalized coefficients before multiplying by B. Sample each arc into 32 segments including endpoints/crown; share seam vertices. Extrude the convex perimeter along local Y from 0 to L, with outward-wound floor/walls/roof and fan end caps, and explicit front/rear outlines. Caps are visualization boundaries, not surveyed faces. Renderer uses per-face normals and translucent materials; the mesh is closed. This discretization is a rendering approximation to the exact circles.

Protodyakonov f is dimensionless, **not UCS (MPa), RMR or Q**. Later work must introduce actual qualified f, validate other profile ranges including f>12 (candidate h=B/4, R≈0.905B, r≈0.173B), and establish a qualified Mapping linkage. No automatic conversion/profile selection is implemented.

## Joint transformation and intersections

Local right-handed axes: X right looking forward, Y forward along increasing chainage, Z up, origin floor center at the front display section. Geographic ENU basis: `eX=(cos A,−sin A,0)`, `eY=(sin A,cos A,0)`, `eZ=(0,0,1)`. For dip δ downward from horizontal and clockwise dip-direction D, upward normal in ENU is `(sinδ sinD, sinδ cosD, cosδ)`. Dotting with the local basis gives:

```
n_local = (sinδ sin(D−A), sinδ cos(D−A), cosδ)
```

At δ=0 use (0,0,1), with undefined D; at 90° source conventional side fixes orientation while reversing it represents the same geometric plane. No 0.5° sensor singularity rounding is imposed on interpreted inputs. The independent fixture: A=90°, δ=45°, D=0° yields n=(−1,0,1)/√2, perpendicular to downhill (−1,0,−1). These are analytic geometry, not rock-mechanics rules. Mathematical reference: OpenStax, *Calculus Volume 3*, **2016**, [§2.4, eq. 2.9](https://openstax.org/books/calculus-volume-3/pages/2-4-the-cross-product), [§2.5, planes in space](https://openstax.org/books/calculus-volume-3/pages/2-5-equations-of-lines-and-planes-in-space).

All three schematic planes pass through **display-only P=(0,L/2,H/2)**. Pairwise trace direction is normalized `n_i × n_j`; near-parallel pairs (cross norm ≤1e−10) have no unique displayed line. Rectangles and shortened traces are finite display patches only, not persistence/termination evidence. SceneKit uses `(X,Z,−Y)` and one uniform display scale; the physics/math stays in metres. Touch orbit and pinch zoom are native SCNView controls. Numeric dimensions, local axes and actual selected J labels accompany the scene.

No measured offsets/persistence/bounds exist. No real finite wedge, volume, weight, failure mechanism, stable/unstable classification, cohesion/friction or Factor of Safety is inferred. Mechanics require the owner's methodology, verified references and independent engineering validation.

## Verification and limits

Focused tests only: `swift test --filter WedgeW1Tests` (8 tests); one generic iOS Simulator build (no install/test). Result: 8/8 passed (0 failures); the generic Debug Simulator build succeeded. After that build, small final changes added explicit cancellation on the reused distance sheet, a grid-reference warning and a short point UUID in the source picker. These final changes were reviewed but not rebuilt/retested, respecting the owner’s one-build/stop-testing limit. `git diff --check` passed. Tests cover rise/walls at several widths, exact rational radius, symmetry/continuity/tangency, validation, closed mesh/indices/outward normals, independently verified orientation and singular cases, trace orthogonality, 3-system/north rules, source context/latest revision/provenance without writes, distance cancel/manual correction, heading projection/freshness/quality gates.

Per owner instruction: **no regression suites, Xcode test runs, existing P1–P6 tests, UI tests, simulator interaction, or physical-device installation/testing**. UI readability, camera orbit/zoom, compass interference/calibration/fixture and LiDAR accuracy/lifecycle still need owner trials on iPhone. No claim of engineering or sensor accuracy, grid realization validation, finite-wedge validity or mechanical safety. Future scenarios, inclined/curved axes, other profiles and all mechanics remain deferred in Issue #29.
