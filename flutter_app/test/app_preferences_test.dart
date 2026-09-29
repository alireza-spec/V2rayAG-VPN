import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:v2rayag_vpn/app_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('appearance defaults are safe and stable', () async {
    final actual = await AppAppearancePreferences().read();
    expect(actual.darkMode, isFalse);
    expect(actual.reducedMotion, isFalse);
    expect(actual.showDestination, isTrue);
  });

  test('persists dark mode, reduced motion, and hidden destination', () async {
    const expected = AppearancePreferences(
      darkMode: true,
      reducedMotion: true,
      showDestination: false,
    );
    final repository = AppAppearancePreferences();

    await repository.save(expected);

    final actual = await repository.read();
    expect(actual.darkMode, expected.darkMode);
    expect(actual.reducedMotion, expected.reducedMotion);
    expect(actual.showDestination, expected.showDestination);
  });
}
