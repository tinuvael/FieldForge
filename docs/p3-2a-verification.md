# P3.2a verification — 2026-10-17

## Environment and scope

Feature branch from merged `origin/main` at `1602cd8` (P3.1 / PR #16). Xcode 26.6 (`17F113`), iOS 26.5 simulator, iPhone 17 Pro Max (`9213E94D-6540-434F-AD58-074C439F967B`). Simulator builds use `CODE_SIGNING_ALLOWED=NO`; no physical-device installation, signing change or real application-data access.

## Automated verification

- Complete `swift test`: **133 tests passed, 0 failures**, including 14 new P3.2a domain/persistence cases.
- Deterministic `python3 scripts/generate_project.py`: repeat generation leaves project/scheme SHA-256 unchanged; 31 app sources, 14 unit-test sources, 3 UI-test sources. Generated project includes all new Swift files in the correct targets. Bundle ID and signing/build settings are preserved.
- Complete fresh Xcode simulator build/test succeeded with the P3.2a source and first borderless icon: **133 unit tests + 9 UI tests = 142 passed, 0 failures**. UI runtime was 2420.470 seconds; the P3.2a end-to-end case passed in 798.732 seconds. The same run also passed P3.1 mixed manual/sensor capture, independent measurement journaling, successive-point/context-guard/relaunch behavior, all three original horizon DXFs (200/300/400), and two-plan/overlapping-marker/draft-retention behavior.
- Borderless icon edit requested by the owner: original artwork retained, opaque square master and 1024px asset visually inspected. Repeated `python3 scripts/generate_app_icon.py` produced identical asset SHA-256 `1de1dd5ccab63738a1a1456a146b2816101e4469f71e0058a3e7235e114d37e9`; asset reference remains valid. See `branding/README.md` for provenance and the editing prompt.

The new domain tests cover five distinct systems, blank representatives rather than automatic grouping, zero/multiple evidence links, shared evidence within a point, mixed north without conversion, foreign/missing/duplicate evidence rejection, immutable revision metadata and full precision, all positions and independent optional interval endpoints, invalid/reversed pickets, orientation degeneracies, optional nonnegative dimensions and missing values, multiple/arbitrary structures, duplicate IDs including across points, local draft evidence removal, atomic injected write failure/retry/reset, clean second-point capture, geological-only context guards, disk reopen/append-only protection/external-change failure, and schema-3 upgrade with exact original backup, evidence, coordinates and readable unchanged DXF assets. Existing P1/P2 migration and P3.1 measurement tests run in the same suite.

## Reproduction and local evidence

```sh
swift test
python3 scripts/generate_project.py
python3 scripts/generate_app_icon.py
xcodebuild -project FieldForge.xcodeproj -scheme FieldForge \
  -destination 'platform=iOS Simulator,id=9213E94D-6540-434F-AD58-074C439F967B' \
  -derivedDataPath /tmp/FieldForge-P32a-Final-borderless \
  -resultBundlePath /tmp/FieldForge-P32a-Final-borderless.xcresult \
  CODE_SIGNING_ALLOWED=NO test
```

Final local logs: `/tmp/fieldforge-p32a-swift.log`, `/tmp/fieldforge-p32a-final-borderless.log`. The Xcode result bundle above contains UI steps and the saved tectonic-structures screenshot. Logs and simulator application data are not committed; `/tmp` evidence is transient. Earlier interrupted diagnostic runs are not counted as a complete suite pass.

## Subsequent icon-only composition refinement

At the owner's request, enlarged the compass after visually comparing Things 3, Procreate Pocket and CARROT Weather. The chosen result fills approximately three quarters of the square and was checked beside the old version at 60px. The full-bleed background and absence of a black frame remain intact. Built-in imagegen edit provenance and prompts are recorded in `branding/`.

Repeated icon generation is byte-identical: current asset SHA-256 `c167e778a5c2c49bb070a5d5856db1cf6c1f41c8645f61ca60542078b9131d17`. The generator validates 1024×1024 opaque RGB output and the asset reference. A subsequent `xcodebuild -project FieldForge.xcodeproj -scheme FieldForge -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/FieldForge-Icon-Proportions CODE_SIGNING_ALLOWED=NO build` succeeded (exit 0; log `/tmp/fieldforge-icon-proportions-build.log`). No Swift source, project configuration or data changed in this follow-up. The full test counts above precede this artwork-only refinement; the entire UI suite was not repeated for it. No physical-device installation.

## Limits

Simulator/mock results do not establish physical measurement accuracy. Existing independent compass/fixture validation remains required. Fault/interval/set authoring introduces no geological classification calculation. Saved records are read-only; controlled historical corrections/revisions are deferred. Drafts survive navigation/backgrounding in memory, not process termination. Storage-failure verification uses injected errors and file-conflict fixtures, not physical power-loss/disk-full trials. Schema 4 is unreadable by old builds; any downgrade requires a reviewed recovery plan. Q/RMR, photo, new export and LiDAR capabilities remain excluded.
