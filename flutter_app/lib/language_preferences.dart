import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores the non-sensitive language choice in ordinary app preferences.
/// Secure storage is reserved for subscription credentials, not UI settings.
class LanguagePreferenceRepository {
  static const _key = 'app_language_v1';

  Future<Locale> readLocale() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return preferences.getString(_key) == 'fa'
          ? const Locale('fa')
          : const Locale('en');
    } on Object {
      return const Locale('en');
    }
  }

  Future<void> saveLocale(Locale locale) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(
      _key,
      locale.languageCode == 'fa' ? 'fa' : 'en',
    );
    if (!saved) throw StateError('Language preference was not saved.');
  }
}
