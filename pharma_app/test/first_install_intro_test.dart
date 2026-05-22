import 'package:flutter_test/flutter_test.dart';
import 'package:pharma_app/core/onboarding/first_install_intro.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('first install intro is unseen until marked', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    expect(hasSeenFirstInstallIntro(prefs), isFalse);

    await markFirstInstallIntroSeen(prefs);

    expect(hasSeenFirstInstallIntro(prefs), isTrue);
  });
}
