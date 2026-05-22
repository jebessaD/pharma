import 'package:shared_preferences/shared_preferences.dart';

const firstInstallIntroSeenKey = 'first_install_intro_seen_v1';

bool hasSeenFirstInstallIntro(SharedPreferences prefs) {
  return prefs.getBool(firstInstallIntroSeenKey) ?? false;
}

Future<void> markFirstInstallIntroSeen(SharedPreferences prefs) {
  return prefs.setBool(firstInstallIntroSeenKey, true);
}
