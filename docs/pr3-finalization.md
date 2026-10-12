# PR #3 finalization and post-merge verification

Date: 2026-10-12. Branch: `feature/phase2-architecture-manual-entry`; target: `main`. This update documents core geological photo workflows within Mapping and Plan, point/photo/attachment relationships, offline storage/export/recovery and permanent development rules. No photo feature, camera workflow, database schema, calculation, dependency or SwiftUI redesign is implemented.

## Icon status

The user-supplied icon is now **integrated**. The authoritative 1254×1254 RGB/sRGB JPEG is preserved byte-for-byte as [branding/FieldForge-AppIcon-master.jpg](../branding/FieldForge-AppIcon-master.jpg), outside the application resource bundle. Its SHA-256 is `7ea539c752f97ad3e96e35dc69ba49e116c381690379656e8414c17274bb2dcd`.

The old placeholder was replaced at [AppIcon.png](../FieldForge/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png) with a 1024×1024 RGB PNG, using a single proportional Lanczos downsample (Pillow 12.3.0, preparation tooling only). The entire composition, background, embedded frame and proportions are retained; no cropping, stretching, color grading, sharpening, additional mask or redesign was applied. The supplied JPEG's sRGB declaration is retained as an explicit PNG sRGB chunk. No transparency existed or needed removal. PNG encoding introduces no further lossy compression after the necessary downsample; the unresized original remains available. AppIcon SHA-256: `35defcbbbcaf7bc8349ff3b83505e9560b576a5f5c207b6bc58d859a0cceb51c`.

Static inspection confirms the unchanged `Contents.json` selects this single 1024×1024 universal iOS icon, both FieldForge Debug/Release configurations select `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`, and `Assets.xcassets` is in the app resource phase. `scripts/generate_project.py` preserves those references and does not rewrite the image, master or asset JSON. No extra size/theme variants or dependencies were needed. Finalization is ready for the owner's review and manual merge; compiled asset handling and actual Home Screen appearance remain deliberately unverified until the post-merge checks.

## Static verification scope

Only Markdown link/consistency review, `git diff --check`, asset JSON/image header inspection, app resource/build-setting reference inspection and deterministic Python project generation are permitted for this task. Xcode builds, simulator builds, unit/UI tests and physical iPhone deployment are deliberately **not run**. No signing, bundle identifier or deployment changes are authorized. The [70-test report](phase2-verification.md) remains historical and is not proof of this final PR state.

Photo design includes stable point/photo/attachment UUID relationships, original image preservation, coordinate/capture/viewing-direction provenance, missing-file states, recoverable attachment operations and privacy-aware offline export. See the authoritative [product vision](product-vision.md), [domain model](data-model.md), [architecture](architecture.md) and [ZIP/register/manifest contract](import-export.md). The photo workflow and XLSX register remain future features.

The earlier photo-documentation commit changed nine Markdown files only and checked 53 relative links. The icon follow-up changes only AppIcon.png, its supplied master and this report. Current static checks cover 55 relative links, `git diff --check`, source/master byte equality, PNG dimensions/format/sRGB/opacity/chunk integrity, visual inspection and decoded-pixel equality to the specified master downsample. Two Python generations reproduce the checked-in project and leave new icon/master hashes unchanged. No source, schema, dependency, test, signing, bundle identifier, deployment or project-setting changes occurred; AGENTS rules and the historical 70-test report are preserved. These checks do not establish an iOS build or on-device appearance.

## Owner's post-merge checklist

After the owner reviews the completed photo documentation and supplied-icon integration:

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
