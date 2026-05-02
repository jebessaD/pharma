# Pharma Shelf (`pharma_app`)

Flutter app for pharmacy operations (POS, stock, medicines, purchases) used with Supabase.

## Development

```bash
flutter pub get
flutter run
flutter test
```

## Production / Play Store

- **Operator checklist:** [docs/play_production_checklist.md](docs/play_production_checklist.md) (signing, Supabase, Play policy, symbols).
- **Release AAB (obfuscated):** `./tool/build_release_appbundle.sh` — optional `REQUIRE_UPLOAD_KEY=1`, optional `tool/dart_defines.local.json` (see [tool/dart_defines.example.json](tool/dart_defines.example.json)).
- **App size notes:** [docs/android_app_size_baseline.md](docs/android_app_size_baseline.md).
- **Store listing draft (title, descriptions):** [fastlane/metadata/android/en-US/](fastlane/metadata/android/en-US/).

Supabase URL and anon key default in code for local dev; override with `--dart-define` or `--dart-define-from-file` for production builds (see [lib/core/supabase_config.dart](lib/core/supabase_config.dart)).
