# Phase 1 verification

Verification date: 2026-10-11. This report distinguishes executable checks from physical validation.

## Environment

- Intel x86_64 Mac, macOS Tahoe 26.6.2 (25G83).
- Xcode 26.6 (17F113) found in Downloads. During the follow-up deployment checks, `xcode-select -p` returned `/Library/Developer/CommandLineTools`; commands used `DEVELOPER_DIR` to select full Xcode without modifying the installation.
- Apple Swift 6.3.3; project Swift 5 language mode.
- iPhoneOS and iPhoneSimulator SDK 26.5. Installed simulator runtimes: iOS 17.2 (21C62), iOS 26.5 (23F77).
- Initial test destination: iPhone 15 Pro Max, iOS 17.2, x86_64. Follow-up test destination: iPhone 15 Pro Max, iOS 26.5 (23F77), x86_64.
- No physical device was found in the initial Phase 1 check. The follow-up deployment check detected a paired physical iPhone 15 Pro Max on iOS 27.0.1 (24A446).
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
| Follow-up iOS 26.5 simulator build | BUILD SUCCEEDED, iPhone 15 Pro Max, x86_64 |
| Follow-up device compile | BUILD SUCCEEDED, physical iPhone destination, arm64, unsigned |
| Follow-up iOS 26.5 simulator tests | 43 unit tests + 1 UI test; 44 passed, 0 failed/skipped; TEST SUCCEEDED |
| Ordinary iOS 26.5 simulator launch | Process running; Russian measurement screen with DEMO label visually inspected |
| Physical device discovery/preparation | Xcode destination available; wired pairing, Developer Mode enabled; compatible, usable DDI |
| Physical installation | `devicectl device info apps` confirmed com.tinuvael.FieldForge, version 0.1.0, build 1 |
| Physical app launch | Owner reported the app works after automatic signing and certificate trust; no independent breakpoint/LLDB check |

The compile-only builds used `CODE_SIGNING_ALLOWED=NO`. An unsigned device binary is a compilation check, not an installable release or proof of hardware behavior. Physical installation subsequently used automatic signing with the owner's Personal Team selected locally. The shared project retains an empty `DEVELOPMENT_TEAM`; credentials, certificates, profiles and the owner's local Xcode signing changes are excluded from this documentation update.

## Physical deployment follow-up

Xcode 26.6 and `devicectl` both recognized the physical iPhone as an available run destination. `devicectl device info ddiServices` reported DDI build `17F113`, `contentIsCompatible: true` and `isUsable: true`. Pairing and device preparation used the installed Apple tools without transplanting device-support files or modifying Xcode. Apple's [Xcode 26.6 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-26_6-release-notes) specify on-device debugging support for iOS 15 and later; SDK 26.5 alone is not evidence that iOS 27 cannot be prepared.

The first normal signed build was blocked by the missing development team. The owner selected their Personal Team in FieldForge → Signing & Capabilities with automatic signing enabled. Xcode then installed the app but initially refused to launch it because the Developer App Certificate was not trusted. The owner was guided to Settings → General → VPN & Device Management → Developer App on the iPhone, to trust their own account and complete any requested restart before running again. The owner subsequently reported: “Всё работает”. `devicectl` independently confirmed the installed version was 0.1.0 (1).

This is an installation check and an owner-reported launch/smoke check for the specific iPhone 15 Pro Max / iOS 27.0.1 / Intel Mac / Xcode 26.6 combination. The owner's statement does not establish calibrated measurement accuracy or independently verify each physical HOLD/save/export path. No breakpoint/LLDB connection was independently demonstrated in this follow-up.

## Coverage

Twenty geometry tests cover horizontal/vertical, 30°/45°/60°, cardinal/diagonal azimuths, north wraparound, in-plane screen rotations, inverted normals, near-singular planes, missing north, matrix transpose direction, invalid/reflected/scaled matrices, non-finite input and extreme finite scales. Expected values use explicit analytic fixtures, not the production mock generator.

Seventeen domain/storage/mock tests cover snapshot HOLD, save-once, live/unavailable/stale/future rejection, acceleration/rotation gates, magnetic calibration/field guards, gravity-frame mismatch, non-finite diagnostics, tampered derived data, admissible inclination-only records, persisted reload/deletion, corrupt and unsupported schema preservation, duplicate/invalid record rejection, mock start/stop/unavailable behavior and independently expanded quaternion/DCM consistency.

Six export tests cover UTF-8 BOM, UTC, numeric format, column inventory, CRLF, commas/quotes/newlines, Russian text, formula-text protection, undefined values, signed diagnostics and a real temporary CSV file.

Screenshots were inspected for all three tabs. Review caught and corrected an English magnetic-calibration enum label and AM time formatting; dates now use Russian month names and 24-hour time. The accent color uses separate light/dark values for contrast. Final light and dark measurement screens were both launched and visually inspected after these changes.

The UI test exercises DEMO labeling, HOLD/save enabled states, journal appearance, persistence after app termination/relaunch and native Share Sheet presentation. It uses a separate Debug test journal.

## Warnings inspected

No Swift compiler warnings were reported in the completed app builds or macOS core tests. Xcode emits “Metadata extraction skipped. No AppIntents.framework dependency found”; this app has no App Intents. Test packaging also reports that already-signed Apple XCTest framework binaries are not stripped. These are tool-generated warnings, not failed app compilation.

Initial sandbox-only Swift/Xcode invocations could not write normal developer caches or connect to CoreSimulator. Authorized builds/tests were rerun with normal access. No toolchain binaries or system developer selection were modified. Physical deployment used iOS's normal developer-certificate trust flow.

## Outstanding physical checks

- Actual Core Motion acquisition, compass calibration, screen/DCM convention on a physical iPhone and real magnetic-interference behavior.
- Independently checked physical breakpoint/LLDB debugging and a documented physical HOLD/save/relaunch/export walkthrough. Pairing, compatible DDI preparation and installation are confirmed; successful launch is owner-reported.
- Accuracy, repeatability, bias, fixture alignment and suitability for professional geology.
- Regional Excel automatic import behavior; UTF-8/comma/decimal-dot import is documented, but Microsoft Excel was not used in this verification.

Use the [validation procedure](measurement-geometry.md) before professional measurement. Xcode 27 is Apple-silicon-only according to [Apple's release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes); no unsupported Intel/Xcode modifications were attempted.

Physical installation and the owner-reported launch are now recorded. The remaining physical measurement validation items are still open; simulator values establish software behavior only. This follow-up does not merge PR #1 or change its review state.
