# FieldForge icon artwork

The active master is `FieldForge-AppIcon-master.png`, a borderless derivative of the owner's `Faceted Compass Glow Icon.png` supplied on 2026-10-17. At the owner's request the exterior black margin, rounded plate edge and shadow were removed using the built-in imagegen editor; the navy background now reaches every edge. The supplied compass design, faceted needle, arcs and colors remain the visual reference. The original root file is untouched, and its byte-identical previous master remains recoverable in Git history. This is an artwork edit, not a new logo. The exact editing prompt is in [icon-edit-prompt.md](icon-edit-prompt.md).

Generate the iOS asset on macOS:

```sh
python3 scripts/generate_app_icon.py
```

The script uses native `/usr/bin/sips` for one proportional 1024×1024 PNG downsample from the 1254×1254 opaque RGB master, validates dimensions/format and checks that the universal iOS asset reference still names `AppIcon.png`. There is no additional crop, mask, tint or sharpening. iOS supplies the rounded corner mask. Repeated generation was byte-identical on the verification host; no cross-version encoder byte identity is claimed.

- Original supplied artwork SHA-256: `909be90d55d21d00d6d5c8b81b13e3a20b7aa8529d756f0af34607486bb163e2`
- Active borderless master SHA-256: `fb4c73dacc1e5d072c4d0b71e1ca5f935a30b52f5e91bb0e3e6fb4a4f5188f31`
- Generated AppIcon SHA-256: `1de1dd5ccab63738a1a1456a146b2816101e4469f71e0058a3e7235e114d37e9`
- App asset: `FieldForge/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`

`Contents.json`, the `AppIcon` build-setting reference, signing and bundle identifier are unchanged. Xcode project generation does not rewrite this artwork. The previous `FieldForge-AppIcon-master.jpg` is retained as historical supplied artwork; it is no longer the active source. Physical iPhone installation is outside this work.
