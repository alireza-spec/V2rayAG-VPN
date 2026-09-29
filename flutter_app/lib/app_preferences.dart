import 'package:shared_preferences/shared_preferences.dart';

class AppearancePreferences {
  const AppearancePreferences({
    this.darkMode = false,
    this.reducedMotion = false,
    this.showDestination = true,
  });

  final bool darkMode;
  final bool reducedMotion;
  final bool showDestination;
}

/// Persists non-sensitive appearance and privacy-display choices separately
/// from the secure storage used for subscription URLs.
class AppAppearancePreferences {
  static const _darkKey = 'appearance_dark_mode_v1';
  static const _motionKey = 'appearance_reduced_motion_v1';
  static const _destinationKey = 'privacy_show_destination_v1';

  Future<AppearancePreferences> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return AppearancePreferences(
        darkMode: prefs.getBool(_darkKey) ?? false,
        reducedMotion: prefs.getBool(_motionKey) ?? false,
        showDestination: prefs.getBool(_destinationKey) ?? true,
      );
    } on Object {
      return const AppearancePreferences();
    }
  }

  Future<void> save(AppearancePreferences value) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = await Future.wait([
      prefs.setBool(_darkKey, value.darkMode),
      prefs.setBool(_motionKey, value.reducedMotion),
      prefs.setBool(_destinationKey, value.showDestination),
    ]);
    if (saved.any((ok) => !ok)) {
      throw StateError('Appearance preferences were not saved.');
    }
  }
}
