/// Central asset paths (must match [pubspec.yaml] `flutter.assets`).
abstract final class AppAssets {
  /// Root-level asset — replace [logo.png] at project root; no second copy to sync.
  static const String logo = 'logo.png';

  static const String welcomePharmacist =
      'assets/onboarding/welcome-pharmacist.png';

  static const String inventoryCheck = 'assets/onboarding/inventory-check.png';
}
