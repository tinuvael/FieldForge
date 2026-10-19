# FieldForge development instructions

## Project

- Build native iOS features with Swift and SwiftUI. UI is Russian; code identifiers and technical documentation are English.
- Treat [docs/product-vision.md](docs/product-vision.md) as the authoritative product requirements. Exactly three primary modules: Geomechanical Mapping, Excavation Plans & Spatial Positioning, and Wedge Analysis; keep the restricted engineering field-tool scope.
- All modules share one project data model/database with stable relationships; do not duplicate observation entry between modules.
- Prepare one shared codebase for iPhone and future native iPad. Use adaptive SwiftUI components and window/size-class layouts, not stretched phone screens; share domain, storage, measurement, geometry, analysis, validation and export services.
- Work offline first, minimize external dependencies, and keep modules maintainable. Avoid unnecessary abstractions and premature optimization.
- Core geological orientation types must not depend on Core Motion or SwiftUI. Adapt sensors at the boundary.
- Preserve `com.tinuvael.FieldForge`, existing application data, and the Phase 1 geometry algorithms unless a tested defect requires correction.
- Use the supplied FieldForge branding/icon as authoritative artwork; preserve proportions/design, validate asset references and deterministic generation, and request missing artwork rather than invent a replacement.

## Engineering

- Never invent geological classification methods, rating scales, or empirical coefficients. Implement published methods only with documented references and versions.
- Require published references/versions and independent engineering tests for every engineering calculation, including geometric/kinematic and mechanical wedge methods.
- Distinguish measured, manually entered, calculated, and interpreted data. Preserve original observations and provenance; representative joint sets are interpretations, not automatically grouped measurements.
- Document coordinate systems, units, and angle conventions. Never silently convert magnetic, true, or grid azimuths.
- Never assume underground GPS or imply automatic phone positioning. Record surveyed, plan-derived, manual, approximate/unknown location provenance; preserve CRS, units, axes, alignment version, chainage origin/direction and transformation history.
- Keep original observations immutable as evidence; controlled corrections create explicit revisions preserving prior values. Interpretations and analyses are derived, versioned records referencing their input revisions.
- Separate wedge geometry/kinematics from mechanical stability; document missing geometric inputs/assumptions and never infer stable/unstable labels, safety factors or risk thresholds from geometry alone.
- Never invent rock-mechanics equations. Mechanical wedge calculations require owner-provided methodology, verified published references/versions and independent engineering tests before implementation; cohesion/friction stay planned inputs until then.
- Do not claim measurement accuracy without physical validation. Preserve engineering precision; round only for presentation.
- Integrate photo documentation into Mapping/Plan through shared iPhone/iPad point/photo/attachment UUID relationships. Preserve original images where practical, attachment hashes and explicit spatial provenance; never infer surveyed underground coordinates from EXIF/GPS or identify records by filenames.

## Development

- Owner decision before MVP: the mapping database has one current experimental format, schema **7**. Do not reuse older schema numbers, add mapping migrations/upgrade chains or an automatic reset. Reject noncurrent and corrupt mapping files, block writes and preserve every existing database, image, DXF and backup. Current-schema atomic saves, `.previous`, external-change detection, relationship integrity and append-only evidence/history remain required. Test fresh current-schema journals and safe refusal, using isolated temporary directories.
- This exception applies only to experimental mapping databases. Preserve the independent original-measurement journal and its existing deployed compatibility/migration/backup behavior. Do not change it as part of mapping work.
- Test engineering calculations, current-format persistence, corrupted data, record integrity and recoverable attachment failures. Keep independent measurement migration tests.
- Run available builds and tests before submission: `swift test`, deterministic `python3 scripts/generate_project.py`, and Xcode simulator build/test where available. Clearly report unavailable checks.
- Update `README.md` for working features and `docs/` when models or architecture change.
- Keep Xcode generation deterministic. Regenerate and commit the project after source inventory changes. Keep core tests runnable through both Swift Package Manager and Xcode.
- Do not commit credentials, signing certificates/profiles, personal data, device journals, or generated build artifacts.
- Design recoverable attachment operations and complete offline photo backups/exports with manifests, stable relative paths and missing-file reports. Keep thumbnails/export derivatives separate, and avoid exposing personal EXIF location metadata unnecessarily; see the product vision for details.

## Git

- Develop on feature branches and submit Pull Requests. Never push directly to `main` or merge a PR automatically.
- Preserve unrelated user changes. Review diffs and report incomplete verification and material limitations.
