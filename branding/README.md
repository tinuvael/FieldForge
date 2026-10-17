# FieldForge icon artwork

The active master is `FieldForge-AppIcon-master.png`, a borderless derivative of the owner's `Faceted Compass Glow Icon.png` supplied on 2026-10-17. At the owner's request the exterior black margin, rounded plate edge and shadow were removed using the built-in imagegen editor; the navy background now reaches every edge. A subsequent owner-requested composition pass enlarged the compass to approximately three quarters of the square, with balanced breathing room around the needle and arcs. The supplied compass design, faceted needle, arcs and colors remain the visual reference. The original root file is untouched, and earlier masters remain recoverable in Git history. These are artwork edits, not a new logo. The exact editing prompts are in [icon-edit-prompt.md](icon-edit-prompt.md).

Generate the iOS asset on macOS:

```sh
python3 scripts/generate_app_icon.py
```

The script uses native `/usr/bin/sips` for one proportional 1024×1024 PNG downsample from the 1254×1254 opaque RGB master, validates dimensions/format and checks that the universal iOS asset reference still names `AppIcon.png`. There is no additional crop, mask, tint or sharpening. iOS supplies the rounded corner mask. Repeated generation was byte-identical on the verification host; no cross-version encoder byte identity is claimed.

- Original supplied artwork SHA-256: `909be90d55d21d00d6d5c8b81b13e3a20b7aa8529d756f0af34607486bb163e2`
- Active borderless master SHA-256: `e6d9f87a929e0539bae571659fcc5205a67e69a2646471f5f757d0299b926f5f`
- Generated AppIcon SHA-256: `c167e778a5c2c49bb070a5d5856db1cf6c1f41c8645f61ca60542078b9131d17`
- App asset: `FieldForge/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`

`Contents.json`, the `AppIcon` build-setting reference, signing and bundle identifier are unchanged. Xcode project generation does not rewrite this artwork. The previous `FieldForge-AppIcon-master.jpg` is retained as historical supplied artwork; it is no longer the active source. Physical iPhone installation is outside this work.

## Composition review

Visually compared Things 3, Procreate Pocket and CARROT Weather on 2026-10-17. Procreate's diagonal silhouette and CARROT's large central mark informed the stronger optical size; Things illustrates balancing a clear central symbol with background space. The chosen FieldForge mark retains margins around all extremities and was reviewed at 60px alongside the previous version. The approximate three-quarter coverage is a design judgment, not an Apple-mandated percentage. Apple's guidance supports a simple full-bleed background and system-applied corner masking.

- [Things 3 icon](https://www.iosicongallery.com/icons/things-3-2025-11-06/)
- [Procreate Pocket](https://apps.apple.com/us/app/procreate-pocket/id916366645)
- [CARROT Weather](https://apps.apple.com/cl/app/clima-carrot-alertas-y-radar/id961390574)
- [Apple app-icon guidelines](https://developer.apple.com/design/human-interface-guidelines/app-icons)
