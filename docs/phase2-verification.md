# Phase 2 verification

Date: 2026-10-11. Base: `origin/main` **024458b577b948cf01a01b75e4a378968b9b1259**, containing merged Phase 1 PR #1. Branch: `feature/phase2-architecture-manual-entry`.

## Environment and checks performed

The supplied workspace had no FieldForge working tree. The existing GitHub repository was cloned (no `git init`), fetched, inspected clean, and the feature branch created from latest `origin/main`. Source, tests, README, documentation, resources, project and generation script were inspected. The license, bundle identifier, deployment/signing/build settings and Phase 1 geometric/sensor algorithms are preserved.

Execution environment: Debian 13, Linux x86_64. Xcode, Apple SDKs and CoreSimulator are absent. Official Swift **6.0.3** Ubuntu 24.04 toolchain was downloaded into the workspace, outside the repository. No toolchain, credential or personal-device artifact is committed. SwiftPM/Clang caches were directed to `/tmp` because the default home cache was read-only.

| Check | Result |
| --- | --- |
| Swift Package core build and XCTest | **70 tests, 0 failures**; 20 geometry, 17 automatic/HOLD/storage/mock, 6 original CSV, 15 manual/provenance/CSV, 12 migration |
| Legacy fixture | Literal synthetic v1 bytes produced by unchanged Phase 1 encoder in a detached worktree; all original fields and exact backup bytes preserved |
| Mixed journal and CSV | Manual + sensor + simulator save/reload; north/convention/source, empty manual diagnostics and numeric precision covered |
| Corrupt/unknown/invalid/duplicate journals | Read/write protection and source preservation covered, including backup conflict/failure and intervening file changes |
| Xcode regeneration | Two generations produce identical SHA-256 hashes; 18 app Swift sources, 6 unit source/helper files and 1 UI test file |
| Project inventory/settings | Every Swift file present; object IDs unique; scheme XML, plists and asset JSON parse; all build settings/bundle IDs match main |
| Geometry and physical sensor implementation diff | No changes to `PlaneOrientation.swift`, `Vector3.swift`, `CoreMotionSensorProvider.swift`, `MockSensorProvider.swift`, or HOLD session implementation |
| Swift UI/app source syntax | `swiftc -frontend -parse` succeeds; **this is not Apple SDK type checking or an iOS build** |
| Simulator build/test/inventory attempts | `xcodebuild` and `xcrun` return command not found (exit 127); unavailable |
| New manual UI workflow test | Added entry → validation → save-once → journal → relaunch → Share Sheet test; **not executed here** |

The existing Phase 1 tests remain. CSV expectations now cover 28 columns and full-precision numeric formatting; the signed-diagnostic assertion parses a real negative numeric cell to tighter precision. The unsupported-schema fixture uses 999 because schema 2 is supported. No geometry/HOLD/quality assertion was removed or weakened.

The first executable iteration identified an overly complex CSV expression, then an incompatible Foundation atomic/non-overwrite flag combination for backup creation. These were corrected by splitting CSV field construction and using non-overwriting `FileManager.copyItem`, with exact byte verification before the active atomic write. The completed core run has no Swift compiler warnings. UI/compiler/platform warnings cannot be reviewed without Xcode.

## Reproduce core tests

On a supported Mac, `swift test` suffices. The exact Linux invocation used:

```sh
CLANG_MODULE_CACHE_PATH=/tmp/FieldForge-ClangCache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/FieldForge-SwiftCache \
/workspace/shared/downloads/swift-6.0.3-RELEASE-ubuntu24.04/usr/bin/swift test \
  --cache-path /tmp/FieldForge-PackageCache \
  --config-path /tmp/FieldForge-PackageConfig \
  --security-path /tmp/FieldForge-PackageSecurity
```

Migration tests use temporary journals exclusively. No deployed iPhone journal was read, overwritten, erased or used as a fixture. The UI tests use the existing Debug `ui-testing.json` path and retain source labels.

## Required before marking the PR ready

1. On a supported Mac, run the [README](../README.md) simulator build/test commands with an actual available device UUID. Confirm all 70 unit tests and both UI workflows, inspect keyboard/scrolling/north selection, VoiceOver, small screens, rotation and light/dark appearance.
2. Test sensor HOLD → manual → sensor across tabs/backgrounding, save-once states, validation boundaries, undefined direction and conventional vertical entries.
3. Preserve a complete copy of the real Phase 1 journal before a **signed in-place upgrade**. Keep `com.tinuvael.FieldForge`; do not uninstall/reset. Compare record IDs/timestamps/orientations/notes/raw diagnostics and inspect the exact v1 backup. Save a manual record and export a mixed CSV. Device upgrade and disk-full/power-loss behavior remain unverified here.
4. Perform controlled instrument comparison before claiming geological accuracy. The owner's Phase 1 physical startup/acquisition/save report does not qualify accuracy, interference handling or long-term persistence.

The PR is Draft because iOS compilation and simulator/UI execution remain significant incomplete verification. Historical Phase 1 Apple build results are in [verification.md](verification.md) and do not establish Phase 2 correctness. JSON still rewrites whole journals, lacks relational queries, and requires explicit manual recovery for corrupt/conflicting files; [architecture.md](architecture.md) documents the planned SQLite/attachment transition.
