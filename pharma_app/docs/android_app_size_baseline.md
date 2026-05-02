# Android app size baseline

Recorded from a single-ABI analysis build (required by Flutter for `--analyze-size`).

## Command

```bash
cd pharma_app
flutter build appbundle --release --analyze-size --target-platform=android-arm64
```

Date: 2026-05-01. Configuration: `com.pharmashelf.app`, R8 minify + shrink resources enabled, no Dart `--obfuscate` (see `tool/build_release_appbundle.sh` for obfuscated production builds).

## Summary (compressed AAB)

| Metric | Value |
|--------|------:|
| **Total compressed (analysis)** | ~25 MB |
| **Built artifact** | `build/app/outputs/bundle/release/app-release.aab` (~26.6 MB on disk) |

## Top-level breakdown (from Flutter size report)

| Section | Approx. size |
|---------|-------------:|
| `base/lib` (native `.so`, **arm64-v8a only** in this run) | 14 MB |
| Dart AOT symbols (decompressed accounting) | 8 MB |
| `base/dex` | 1 MB |
| `base/assets` | 847 KB |
| `base/res` | 721 KB |
| BUNDLE-METADATA debug symbols | 6 MB |
| BUNDLE-METADATA obfuscation mapping | 2 MB |

Notes:

- **Production AAB** uploaded to Play is a multi-ABI bundle; user **download** size is per-device via Play split delivery (not the full multi-ABI blob).
- **`package:mobile_scanner`** appears in Dart AOT symbol accounting at **~46 KB** (Dart side); the scanner’s **native** cost is inside **`base/lib`** together with Flutter engine and other JNI plugins.
- Re-run this command after major dependency or Gradle changes. Interactive treemap: `dart devtools --appSizeBase=$HOME/.flutter-devtools/aab-code-size-analysis_01.json` (filename increments per run).

## Related

- Obfuscated Play upload build: [`tool/build_release_appbundle.sh`](../tool/build_release_appbundle.sh).
- Play listing draft (Fastlane `supply` format): [`fastlane/metadata/android/en-US/`](../fastlane/metadata/android/en-US/).
- After changing the Android `applicationId` or iOS bundle identifier to **`com.pharmashelf.app`**, update Supabase Auth (and any OAuth providers) **redirect allowlists** if they still reference the old `com.example.*` identifiers.
