import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:v2rayag_vpn/language_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('defaults to English and remembers Persian without secure storage', () async {
    final repository = LanguagePreferenceRepository();

    expect(await repository.readLocale(), const Locale('en'));
    await repository.saveLocale(const Locale('fa'));
    expect(await repository.readLocale(), const Locale('fa'));
  });

  test('unsupported language values safely fall back to English', () async {
    SharedPreferences.setMockInitialValues({'app_language_v1': 'fr'});
    expect(await LanguagePreferenceRepository().readLocale(), const Locale('en'));
  });
}
