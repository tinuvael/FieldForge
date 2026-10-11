# FieldForge development instructions

## Project
- Build native iOS features with Swift and SwiftUI. UI is Russian; code identifiers and technical documentation are English.
- Work offline first, minimize external dependencies, and keep modules maintainable. Avoid unnecessary abstractions and premature optimization.
- Core geological orientation types must not depend on Core Motion or SwiftUI. Adapt sensors at the boundary.
- Preserve `com.tinuvael.FieldForge`, existing application data, and the Phase 1 geometry algorithms unless a tested defect requires correction.

## Engineering
- Never invent geological classification methods, rating scales, or empirical coefficients. Implement published methods only with documented references and versions.
- Distinguish measured, manually entered, calculated, and interpreted data. Preserve original observations and provenance; representative joint sets are interpretations, not automatically grouped measurements.
- Document coordinate systems, units, and angle conventions. Never silently convert magnetic, true, or grid azimuths.
- Do not claim measurement accuracy without physical validation. Preserve engineering precision; round only for presentation.

## Development
- Preserve compatibility with existing records. Use explicit persistence schema versions and non-destructive migrations with backups and failure protection.
- Test engineering calculations and migrations, including legacy fixtures, corrupted data, and record integrity.
- Run available builds and tests before submission: `swift test`, deterministic `python3 scripts/generate_project.py`, and Xcode simulator build/test where available. Clearly report unavailable checks.
- Update `README.md` for working features and `docs/` when models or architecture change.
- Keep Xcode generation deterministic. Regenerate and commit the project after source inventory changes. Keep core tests runnable through both Swift Package Manager and Xcode.
- Do not commit credentials, signing certificates/profiles, personal data, device journals, or generated build artifacts.

## Git
- Develop on feature branches and submit Pull Requests. Never push directly to `main` or merge a PR automatically.
- Preserve unrelated user changes. Review diffs and report incomplete verification and material limitations.
