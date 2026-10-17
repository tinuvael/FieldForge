# P3.2a verification — 2026-10-17

## Environment and scope

Feature branch from merged `origin/main` at `1602cd8` (P3.1 / PR #16). Xcode 26.6 (`17F113`), iOS 26.5 simulator, iPhone 17 Pro Max (`9213E94D-6540-434F-AD58-074C439F967B`). Simulator builds use `CODE_SIGNING_ALLOWED=NO`; no physical-device installation, signing change or real application-data access.

## Automated verification

- Complete `swift test`: **133 tests passed, 0 failures**, including 14 new P3.2a domain/persistence cases.
- Deterministic `python3 scripts/generate_project.py`: repeat generation leaves project/scheme SHA-256 unchanged; 31 app sources, 14 unit-test sources, 3 UI-test sources. Generated project includes all new Swift files in the correct targets. Bundle ID and signing/build settings are preserved.
- Xcode simulator build/test results will be recorded after the final suite completes.

The new domain tests cover five distinct systems, blank representatives rather than automatic grouping, zero/multiple evidence links, shared evidence within a point, mixed north without conversion, foreign/missing/duplicate evidence rejection, immutable revision metadata and full precision, all positions and independent optional interval endpoints, invalid/reversed pickets, orientation degeneracies, optional nonnegative dimensions and missing values, multiple/arbitrary structures, duplicate IDs including across points, local draft evidence removal, atomic injected write failure/retry/reset, clean second-point capture, geological-only context guards, disk reopen/append-only protection/external-change failure, and schema-3 upgrade with exact original backup, evidence, coordinates and readable unchanged DXF assets. Existing P1/P2 migration and P3.1 measurement tests run in the same suite.

## Limits

Simulator/mock results do not establish physical measurement accuracy. Existing independent compass/fixture validation remains required. Fault/interval/set authoring introduces no geological classification calculation. Saved records are read-only; controlled historical corrections/revisions are deferred. Drafts survive navigation/backgrounding in memory, not process termination. Storage-failure verification uses injected errors and file-conflict fixtures, not physical power-loss/disk-full trials. Schema 4 is unreadable by old builds; any downgrade requires a reviewed recovery plan. Q/RMR, photo, new export and LiDAR capabilities remain excluded.
