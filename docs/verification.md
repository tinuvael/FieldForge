# Phase 1 verification

Verification date: 2026-10-11. This report distinguishes executable checks from physical validation.

## Environment

- Intel x86_64 Mac, macOS Tahoe 26.6.2 (25G83).
- Xcode 26.6 (17F113) found in Downloads; `xcode-select` had no active developer directory. Commands used `DEVELOPER_DIR` without modifying the installation.
- Apple Swift 6.3.3; project Swift 5 language mode.
- iPhoneOS and iPhoneSimulator SDK 26.5. Installed simulator runtimes: iOS 17.2 (21C62), iOS 26.5 (23F77).
- Test destination: iPhone 15 Pro Max, iOS 17.2, x86_64.
- `devicectl list devices`: no physical devices found.
- Repository started clean on `main`, with README and existing LICENSE. Origin was fetched and the feature branch created from `origin/main`. The license was preserved.

## Confirmed checks

| Check | Result |
| --- | --- |
| Xcode project inventory | Shared FieldForge scheme, app/unit/UI targets recognized |
| Source/resource membership | All 15 app Swift files and resources present |
| Project and resource plist validation | Passed with `plutil` and Python plist parsing |
| Deterministic project regeneration | Generated project matches checked-in project |
| Simulator build | `xcodebuild build`, iPhone 15 Pro Max iOS 17.2: BUILD SUCCEEDED |
| ARM iPhone compile | `xcodebuild build`, generic iOS destination, SDK 26.5: BUILD SUCCEEDED, unsigned |
| Independent macOS core XCTest | `swift test`: 43 tests, 0 failures |
| iOS simulator unit XCTest | 43 tests, 0 failures |
| iOS simulator UI workflow | 1 test, 0 failures; full `xcodebuild test`: TEST SUCCEEDED |

Both builds used `CODE_SIGNING_ALLOWED=NO`. The unsigned device binary is a compilation check, not an installable release or proof of hardware behavior. Automatic signing is configured; selecting a development team remains a local deployment step.

## Coverage

Twenty geometry tests cover horizontal/vertical, 30°/45°/60°, cardinal/diagonal azimuths, north wraparound, in-plane screen rotations, inverted normals, near-singular planes, missing north, matrix transpose direction, invalid/reflected/scaled matrices, non-finite input and extreme finite scales. Expected values use explicit analytic fixtures, not the production mock generator.

Seventeen domain/storage/mock tests cover snapshot HOLD, save-once, live/unavailable/stale/future rejection, acceleration/rotation gates, magnetic calibration/field guards, gravity-frame mismatch, non-finite diagnostics, tampered derived data, admissible inclination-only records, persisted reload/deletion, corrupt and unsupported schema preservation, duplicate/invalid record rejection, mock start/stop/unavailable behavior and independently expanded quaternion/DCM consistency.

Six export tests cover UTF-8 BOM, UTC, numeric format, column inventory, CRLF, commas/quotes/newlines, Russian text, formula-text protection, undefined values, signed diagnostics and a real temporary CSV file.

Screenshots were inspected for all three tabs. Review caught and corrected an English magnetic-calibration enum label and AM time formatting; dates now use Russian month names and 24-hour time. The accent color uses separate light/dark values for contrast. Final light and dark measurement screens were both launched and visually inspected after these changes.

The UI test exercises DEMO labeling, HOLD/save enabled states, journal appearance, persistence after app termination/relaunch and native Share Sheet presentation. It uses a separate Debug test journal.

## Warnings inspected

No Swift compiler warnings were reported in the completed app builds or macOS core tests. Xcode emits “Metadata extraction skipped. No AppIntents.framework dependency found”; this app has no App Intents. Test packaging also reports that already-signed Apple XCTest framework binaries are not stripped. These are tool-generated warnings, not failed app compilation.

Initial sandbox-only Swift/Xcode invocations could not write normal developer caches or connect to CoreSimulator. Authorized builds/tests were rerun with normal access. No toolchain binaries, security settings or system developer selection were modified.

## Outstanding physical checks

- Actual Core Motion acquisition, compass calibration, screen/DCM convention on a physical iPhone and real magnetic-interference behavior.
- Deployment/pairing/debugging with the user's iPhone 15 Pro Max on iOS 27. A successful SDK 26.5 build does not establish this support.
- Accuracy, repeatability, bias, fixture alignment and suitability for professional geology.
- Regional Excel automatic import behavior; UTF-8/comma/decimal-dot import is documented, but Microsoft Excel was not used in this verification.

Use the [validation procedure](measurement-geometry.md) before professional measurement. Xcode 27 is Apple-silicon-only according to [Apple's release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes); no unsupported Intel/Xcode modifications were attempted.

The PR should remain Draft until important physical validation/deployment checks are resolved. Simulator values establish software behavior only.
