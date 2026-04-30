import 'package:flutter_test/flutter_test.dart';
import 'package:pharma_app/core/utils/app_version_compare.dart';

void main() {
  test('isBelowMinimumSupported respects semver', () {
    expect(isBelowMinimumSupported('1.0.0', '1.0.1'), true);
    expect(isBelowMinimumSupported('1.0.1', '1.0.0'), false);
    expect(isBelowMinimumSupported('1.0.0', '1.0.0'), false);
    expect(isBelowMinimumSupported('2.0.0+42', '1.9.9'), false);
    expect(isBelowMinimumSupported('1.0.0+99', '1.0.1'), true);
  });

  test('tryParseAppVersion strips build metadata', () {
    final v = tryParseAppVersion('1.2.3+100');
    expect(v?.major, 1);
    expect(v?.minor, 2);
    expect(v?.patch, 3);
  });
}
