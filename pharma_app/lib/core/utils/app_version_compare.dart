import 'package:pub_semver/pub_semver.dart';

/// Parses Flutter [PackageInfo.version] (strips build metadata after `+`).
Version? tryParseAppVersion(String raw) {
  final s = raw.split('+').first.trim();
  if (s.isEmpty) return null;
  try {
    return Version.parse(s);
  } catch (_) {
    return null;
  }
}

/// True when [currentVersion] is strictly below [minSupported] (semver).
bool isBelowMinimumSupported(String currentVersion, String minSupported) {
  final c = tryParseAppVersion(currentVersion);
  final m = tryParseAppVersion(minSupported);
  if (c == null || m == null) return false;
  return c < m;
}
