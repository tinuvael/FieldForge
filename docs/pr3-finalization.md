# PR #3 finalization and post-merge verification

Date: 2026-10-12. Branch: `feature/phase2-architecture-manual-entry`; target: `main`. This update documents core geological photo workflows within Mapping and Plan, point/photo/attachment relationships, offline storage/export/recovery and permanent development rules. No photo feature, camera workflow, database schema, calculation, dependency or SwiftUI redesign is implemented.

## Icon status

The requested new user-supplied icon attachment is **not accessible in this session**. Its integration is pending receipt of the authoritative image; no replacement artwork was invented. The current `FieldForge/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png` and `Contents.json` are preserved. The existing image is a 1024×1024 RGB PNG with no alpha channel; it is not the requested new artwork.

Static inspection shows the FieldForge app's Debug/Release `ASSETCATALOG_COMPILER_APPICON_NAME` is `AppIcon`, and `Assets.xcassets` belongs to its resource phase. `scripts/generate_project.py` retains those references and does not rewrite the image or asset JSON. This confirms the **existing icon's reference**, not integration or on-device display of the missing supplied icon. PR stays Draft pending that asset; Apple-platform checks are separately deferred by owner instruction.

When the image arrives: inspect its format, dimensions, proportions, color profile and transparency; preserve the supplied artwork/master and use the existing single 1024×1024 universal iOS icon format if suitable. Resize/prepare only as needed for the asset format without redesign, cropping/stretching or unapproved background changes. Report insufficient source resolution or unresolved transparency requirements rather than invent artwork. Repeat JSON/dimension/reference/generation checks after integration; do not claim it is complete from the current placeholder checks.

## Static verification scope

Only Markdown link/consistency review, `git diff --check`, asset JSON/image header inspection, app resource/build-setting reference inspection and deterministic Python project generation are permitted for this task. Xcode builds, simulator builds, unit/UI tests and physical iPhone deployment are deliberately **not run**. No signing, bundle identifier or deployment changes are authorized. The [70-test report](phase2-verification.md) remains historical and is not proof of this final PR state.

Photo design includes stable point/photo/attachment UUID relationships, original image preservation, coordinate/capture/viewing-direction provenance, missing-file states, recoverable attachment operations and privacy-aware offline export. See the authoritative [product vision](product-vision.md), [domain model](data-model.md), [architecture](architecture.md) and [ZIP/register/manifest contract](import-export.md). The photo workflow and XLSX register remain future features.

Completed static checks: all nine changed files are Markdown; 53 relative links resolve; every prior AGENTS rule remains; `git diff --check` passes. Existing AppIcon JSON and PNG dimensions/format/chunk integrity are valid, and app resource/Debug/Release icon references are intact. Two Python generations reproduce the checked-in project and leave current icon files untouched. The diff contains no source, schema, dependency, test, resource or project-setting changes. None of these checks integrates or verifies the absent new artwork.

## Owner's post-merge checklist

After the requested icon is integrated and the owner reviews the PR:

1. Manually merge [PR #3](https://github.com/tinuvael/FieldForge/pull/3) into `main`. No agent merge or direct push to main.
2. On the MacBook, preserve local changes, switch to `main` and run `git pull --ff-only origin main`.
3. Open `FieldForge.xcodeproj` in a supported Xcode installation and select the shared FieldForge scheme.
4. Use Product → Clean Build Folder, then build for an available iPhone simulator; review compilation/asset warnings.
5. Run the full unit and UI suite (⌘U); optionally run `swift test` for independent core checks. Record new results rather than reuse the historical 70-test result.
6. Verify the supplied icon in the asset catalog, simulator Home Screen and later on iPhone; confirm artwork is not cropped/stretched and is the intended new design.
7. Preserve a complete copy of the existing iPhone journal, keep its bundle identifier/signing identity, and update the installed app in place with Xcode. **Do not uninstall, reset or delete its data.**
8. Confirm old UUIDs/timestamps/orientations/notes/diagnostics survived migration and inspect the preserved Phase 1 backup.
9. Test manual angles, decimal comma/dot, 360° normalization, horizontal undefined direction, vertical convention, north metadata, save-once/journal/relaunch and switching back to sensor HOLD.
10. Export a mixed manual/sensor CSV and inspect provenance, north, blank manual diagnostics and preserved numeric values.

These post-merge checks do not establish geological accuracy; controlled physical instrument comparison and longer-term reliability/interference validation remain separate work. Photo features are documentation only and should not be expected in the merged app.
