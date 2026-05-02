# Google Play production checklist

Use this before uploading a **release** build to Play Console. Order is approximate; some steps depend on your org.

## Signing and artifacts

1. **Upload keystore** — Create a keystore and register it with Play App Signing (Play holds the app signing key; you keep an upload key).
2. **`android/key.properties`** — Copy from [`android/key.properties.example`](../android/key.properties.example), point `storeFile` at your keystore (path relative to `android/`), set passwords and alias.
3. **Store build** — Run [`tool/build_release_appbundle.sh`](../tool/build_release_appbundle.sh) with **`REQUIRE_UPLOAD_KEY=1`** so the script fails if `key.properties` is missing:
   ```bash
   cd pharma_app
   REQUIRE_UPLOAD_KEY=1 ./tool/build_release_appbundle.sh
   ```
4. **Dart defines (optional)** — Copy [`tool/dart_defines.example.json`](../tool/dart_defines.example.json) to `tool/dart_defines.local.json` (gitignored) with production Supabase URL and anon key, or set `DART_DEFINE_FILE` to another JSON path. If omitted, the app uses compile-time defaults in [`lib/core/supabase_config.dart`](../lib/core/supabase_config.dart).
5. **Symbols** — Retain the directory printed as “Dart split debug info” and upload native debug symbols / mapping as required in Play (App bundle explorer) for deobfuscation.

## Supabase Auth

6. **Redirect URLs** — In the Supabase dashboard (Auth → URL configuration), allow **`pharmaapp://auth/callback`** (see [`lib/core/supabase_config.dart`](../lib/core/supabase_config.dart)).
7. **Site URL** — Set **Site URL** to the same Supabase project URL you ship in the app (`SUPABASE_URL` / default in code), not localhost.
8. **Bundle identifiers** — If you use Apple or Google sign-in, ensure allowed bundle IDs / SHA fingerprints match **`com.pharmashelf.app`** (Android) and the iOS bundle id from Xcode.

## Play Console listing and policy

9. **Version** — Bump `version:` in [`pubspec.yaml`](../pubspec.yaml) (`+` build number must increase for every upload).
10. **Store listing** — Paste or sync copy from [`fastlane/metadata/android/en-US/`](../fastlane/metadata/android/en-US/); add screenshots and feature graphic (see `SCREENSHOTS.md` there).
11. **Data safety** — Complete the Data safety form accurately (data collected, encryption, etc.).
12. **Privacy policy** — Host a privacy policy URL and add it where Play requires.
13. **Content rating** — Complete the questionnaire.
14. **Target audience** — Declare age groups and compliance as required.

## Verification

15. **`flutter test`** — Green before tagging a release.
16. **Smoke test** — Install the release build (internal testing track), sign in, and exercise auth deep links and core flows.

For download-size baselines, see [`docs/android_app_size_baseline.md`](android_app_size_baseline.md).
