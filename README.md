# FieldForge

Native, offline iOS prototype for geological and geomechanical field mapping in underground mines and open pits. The interface is Russian; code and technical documentation use English.

**Phase 1 is experimental. No professional measurement accuracy has been established.** The screen plane is the measured plane. Sensor readings require physical validation; simulator records are explicitly marked DEMO.

## Phase 1 scope

- Three SwiftUI tabs: Измерение, Журнал, Настройки; light/dark appearance, portrait/landscape and accessible system controls.
- Dip angle (0–90°) and nullable dip direction ([0,360)°), compass and inclination diagram.
- Core Motion acquisition at 20 Hz, preferably magnetic-north referenced, with gravity, DCM, quaternion, rotation, acceleration and calibrated magnetic-field diagnostics.
- HOLD freezes the complete observation and stops acquisition. SAVE accepts a frozen, fresh-at-capture, admissible observation once. Moving/invalid observations cannot be saved. Inclination-only observations can be saved with an explicit status.
- Simulator presets for angles/directions, magnetic-reference loss, movement, invalid data and unavailable hardware. Mock records retain their source permanently.
- Atomic versioned JSON journal, details, notes at capture and deletion. Load failures preserve the source file and disable writes.
- Offline CSV export using the native Share Sheet.
- Independent geometry/domain/storage/CSV tests plus a simulator UI workflow test.

Excavations, chainage, joint sets, faults, Q/RMR, photos and survey integration are intentionally deferred.

## Technology and architecture

Swift, SwiftUI, Foundation, Core Motion, Combine, UIKit Share Sheet and XCTest. Deployment target: **iOS 17.0**. Swift 5 language mode works with the detected Swift 6.3 compiler. No third-party runtime dependencies, networking, accounts or backend.

```text
FieldForge/
  App/                     composition, observable app state and lifecycle
  Features/Measurement/    measurements, compass, mock controls, Russian labels
  Features/Journal/        journal and observation details
  Features/Settings/       guidance, diagnostics and export UI
  Core/Geometry/           vectors, DCM, normal and downhill projection
  Core/Sensors/            sensor contract, Core Motion and mock providers
  Data/Models/             observations, quality rules and HOLD state
  Data/Storage/            versioned atomic JSON persistence
  Services/Export/         CSV formatting and temporary export file
  Resources/               plist, privacy manifest and asset catalog
Tests/                     hardware-independent XCTest
UITests/                   simulator HOLD/save/relaunch/export workflow
FieldForge.xcodeproj/      checked-in project and shared scheme
Package.swift              the same core sources tested independently on macOS
scripts/generate_project.py deterministic project regeneration, Python 3 only
```

`AppModel` composes the provider, session and store. Core calculations do not import SwiftUI or Core Motion. UI and sensor lifecycle run on the main actor. Provider callbacks carry value snapshots; stopped-session callbacks are discarded. A freshness watchdog invalidates stalled live samples. HOLD remains an explicitly historical observation across tabs/backgrounding.

## Development requirements and opening

Use a supported Xcode installation with an iOS SDK and at least one installed simulator runtime. No signing identity is needed for the simulator. Python 3 is needed only if regenerating the project after changing its source inventory.

1. Open `FieldForge.xcodeproj` in Xcode.
2. Select the **FieldForge** shared scheme.
3. Select an installed iPhone simulator and Run (⌘R).
4. Test using ⌘U. For independent core tests, run `swift test` in the repository.

If Xcode is outside `/Applications` or `xcode-select -p` is unset, point commands at the actual installation without moving/modifying it:

```sh
export DEVELOPER_DIR="/path/to/Xcode.app/Contents/Developer"
xcodebuild -version
xcodebuild -showsdks
xcrun simctl list devices available
xcodebuild -project FieldForge.xcodeproj -scheme FieldForge \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro Max,OS=17.2' \
  -derivedDataPath /tmp/FieldForge-DerivedData CODE_SIGNING_ALLOWED=NO build
xcodebuild -project FieldForge.xcodeproj -scheme FieldForge \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro Max,OS=17.2' \
  -derivedDataPath /tmp/FieldForge-DerivedData CODE_SIGNING_ALLOWED=NO test
swift test
```

Choose a destination returned by your own `simctl` inventory. The project supports both Intel simulator builds and ARM device builds; no architecture exclusions are hard-coded. If adding source files outside Xcode, regenerate with `python3 scripts/generate_project.py` and review its diff.

## Simulator walkthrough

Select a dip and azimuth under «Сценарий симулятора». Confirm DEMO is visible. HOLD freezes the display and disables preset changes; SAVE adds a DEMO journal entry. Inspect it in «Журнал», restart the app and confirm persistence. Swipe a journal row to delete it. «Настройки → Экспортировать CSV» opens the Share Sheet; save to Files for offline use.

Check 0°, 0.2°, 89.8° and 90°: azimuth must be undefined. Select «Нет магнитной опоры»: inclination remains available. «Движение телефона», «Ошибка данных» and «Нет датчиков» must prevent capture/save. Resume after HOLD to take a new observation.

UI tests use a separate `ui-testing.json` journal in Debug builds and never replace the normal journal.

## Physical iPhone deployment

Automatic signing is configured with no team committed. For a device that Xcode recognizes:

1. Connect/unlock the iPhone, trust the Mac and enable Developer Mode as requested by iOS.
2. In Xcode Settings → Accounts add your Apple account.
3. In FieldForge target → Signing & Capabilities choose your Team. Keep automatic signing and `com.tinuvael.FieldForge`; if this identifier belongs to another team, use an identifier owned by your team locally.
4. Select the physical device and Run. Grant motion permission if requested.
5. Verify the source is «Датчики iPhone», never DEMO. Follow the physical validation procedure before using readings.

No certificates, profiles or account data belong in Git. Personal-team provisioning restrictions remain Apple's responsibility.

On the inspected Intel Mac, Xcode 26.6 (17F113), Swift 6.3.3 and iOS SDK 26.5 were found. `xcode-select` was unset, but using `DEVELOPER_DIR` enables this installation. iOS 17.2 and 26.5 simulator runtimes were installed. No paired physical device was reported by `devicectl`.

**iPhone 15 Pro Max on iOS 27 deployment has not been verified.** An iOS 26.5 SDK build may run on a newer OS, but that does not establish pairing/debugging support. Check the device in Xcode's Devices window and use only supported device preparation. Apple states that [Xcode 27 runs only on Apple silicon](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes). Do not modify Xcode or transplant device-support files. If Xcode 26.6 cannot prepare the iOS 27 device, use a supported Apple silicon Mac/toolchain or an officially supported signed distribution route.

## Measurement and storage limitations

Azimuth is **magnetic**, never true north; no magnetic declination correction or location service is used. High magnetometer calibration and a 10–100 μT field guard cannot detect all interference (particularly mine steel, magnetic rock, machinery and cables). Even an admissible azimuth remains experimental. No true-north or absolute orientation claim is made without a north reference.

The horizontal and vertical singularity guard is 0.5°. It is a numerical usability policy, not an accuracy specification. Vertical-plane strike/conventional dip-side selection is not implemented. Displaying 0.1° does not imply 0.1° accuracy. Acquisition has no averaging, uncertainty estimate or calibration model; one frozen sample is saved. Screen/case contact needs a validated fixture. The app is not mine-certified equipment.

The journal is a single local versioned JSON file in Application Support/FieldForge. App removal removes its sandbox; export copies to retain data. The file is rewritten atomically for each change, appropriate for this small prototype. Corrupt/unknown-version journals require manual recovery; they are never silently replaced.

CSV uses UTF-8 BOM, comma separators, CRLF records, decimal points and ISO 8601 UTC timestamps. All fields are quoted, embedded quotes doubled, undefined numeric values empty. Notes that could be Excel formulas receive a leading apostrophe. Signed diagnostic numbers remain numeric. Use Excel's CSV import with UTF-8/comma/dot when regional auto-detection differs. CSV contains full orientation diagnostics, but system uptime remains local. Export cache files reside in the app's temporary directory and may be reclaimed by iOS.

See [coordinate systems and exact algorithm](docs/measurement-geometry.md) and [verification results](docs/verification.md).

Verified on 2026-10-11: simulator and unsigned ARM iPhone builds succeeded; 43 macOS core tests and 43 iOS simulator unit tests passed, plus one simulator UI test covering HOLD/save, relaunch persistence and Share Sheet export. Physical acquisition and iOS 27 deployment remain unverified.

## Roadmap

- **Phase 2:** excavation/chainage mapping intervals, J1–J5, faults, Barton Q and RMR.
- **Phase 3:** survey coordinates, excavation alignment interpolation and spatial exports.
- **Phase 4:** compass comparison, repeatability/error statistics, calibration, printed phone fixture and operational limitations.

The next step is a controlled physical sensor comparison before expanding the mining journal.
