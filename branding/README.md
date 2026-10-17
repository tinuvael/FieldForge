# FieldForge icon artwork

The current authoritative master is `FieldForge-AppIcon-master.png`, copied byte-for-byte from the owner's `Faceted Compass Glow Icon.png` supplied on 2026-10-17. The root original is left untouched. This 1254×1254 opaque RGB PNG is unprofiled, as supplied; its full composition, embedded frame, background and proportions are retained.

Generate the iOS asset on macOS:

```sh
python3 scripts/generate_app_icon.py
```

The script uses native `/usr/bin/sips` for one proportional 1024×1024 PNG downsample, validates the master/output dimensions and opaque RGB format, and checks that the universal iOS asset reference still names `AppIcon.png`. Native sips tags the generated PNG as sRGB for this unprofiled input. There is no crop, new mask, manual tint, sharpening, redesign or runtime dependency. Repeated generation was byte-identical on the verification host (macOS native image tooling); no cross-version encoder byte identity is claimed.

- Current master SHA-256: `909be90d55d21d00d6d5c8b81b13e3a20b7aa8529d756f0af34607486bb163e2`
- Generated AppIcon SHA-256: `e0e4b6bdd99ae9a4d1369f1d0da6c4a8b80c929524ed47075e8a12bdf9e873f3`
- App asset: `FieldForge/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`

`Contents.json`, the `AppIcon` build-setting reference, signing and bundle identifier are unchanged. Xcode project generation does not rewrite this artwork. The previous `FieldForge-AppIcon-master.jpg` is retained as historical supplied artwork; it is no longer the source for the active icon. Physical iPhone installation is outside this work.
