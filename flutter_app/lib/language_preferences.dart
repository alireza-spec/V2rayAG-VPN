import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores only the chosen language code in platform secure storage.
class LanguagePreferenceRepository {
  LanguagePreferenceRepository({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'app_language_v1';
  final FlutterSecureStorage _storage;

  /// Any missing, unsupported, or unreadable value safely selects English.
  Future<Locale> readLocale() async {
    try {
      final stored = await _storage.read(key: _key);
      return stored == 'fa' ? const Locale('fa') : const Locale('en');
    } on Object {
      return const Locale('en');
    }
  }

  Future<void> saveLocale(Locale locale) => _storage.write(
        key: _key,
        value: locale.languageCode == 'fa' ? 'fa' : 'en',
      );
}
