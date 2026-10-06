import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_vless/flutter_vless.dart';

import 'vpn_profile.dart';

class SavedSubscription {
  const SavedSubscription({
    required this.id,
    required this.name,
    required this.url,
  });

  final String id;
  final String name;
  final String url;

  Map<String, String> toJson() => {'id': id, 'name': name, 'url': url};

  factory SavedSubscription.fromJson(Map<String, dynamic> json) => SavedSubscription(
        id: json['id'] as String,
        name: json['name'] as String,
        url: json['url'] as String,
      );
}

/// Versioned encrypted storage that never resets or deletes an unreadable
/// namespace. New data goes into isolated app-owned namespaces; legacy data is
/// copied only when readable, verified in the new store, then cleaned up by key.
class _VersionedSecureStorage {
  _VersionedSecureStorage({FlutterSecureStorage? injected})
      : _primary = injected ??
            FlutterSecureStorage(
              aOptions: AndroidOptions(
                storageNamespace: 'v2rayag_secure_store_v2',
                migrateWithBackup: false,
                resetOnError: false,
              ),
            ),
        _fallback = injected == null
            ? FlutterSecureStorage(
                aOptions: AndroidOptions(
                  storageNamespace: 'v2rayag_secure_store_v3',
                  migrateWithBackup: false,
                  resetOnError: false,
                ),
              )
            : null,
        _legacy = injected == null
            ? FlutterSecureStorage(
                aOptions: AndroidOptions(
                  migrateOnAlgorithmChange: false,
                  migrateWithBackup: false,
                  resetOnError: false,
                ),
              )
            : null;

  static const _envelopeMarker = 'v2rayag_secure_payload_v1';
  final FlutterSecureStorage _primary;
  final FlutterSecureStorage? _fallback;
  final FlutterSecureStorage? _legacy;
  final Map<String, int> _generations = {};
  FlutterSecureStorage? _active;
  bool legacyDataUnreadable = false;
  bool namespaceRotated = false;

  String _migrationMarkerKey(String key) => 'v2rayag_migrated_legacy_$key';

  Future<void> _cleanupLegacyAfterVerifiedMigration(String key) async {
    final target = _active;
    final legacy = _legacy;
    if (target == null || legacy == null) return;
    try {
      final markerRaw = await target.read(key: _migrationMarkerKey(key));
      if (markerRaw == null || _decode(markerRaw).payload != 'true') return;
      await legacy.delete(key: key);
      // Verification is best-effort; if deletion did not take, keep the
      // protected duplicate rather than risking any active data.
      await legacy.read(key: key);
    } on Object {
      // Never clear a legacy key when its namespace is not readable.
    }
  }

  ({String payload, int generation, int updatedAt}) _decode(String raw) {
    try {
      final value = jsonDecode(raw);
      if (value is Map &&
          value['_marker'] == _envelopeMarker &&
          value['payload'] is String &&
          value['generation'] is int) {
        return (
          payload: value['payload'] as String,
          generation: value['generation'] as int,
          updatedAt: value['updatedAt'] is int ? value['updatedAt'] as int : 0,
        );
      }
    } on Object {
      // Legacy repository values are raw JSON strings, not store envelopes.
    }
    return (payload: raw, generation: 0, updatedAt: 0);
  }

  Future<String?> read(String key) async {
    String? primaryRaw;
    String? fallbackRaw;
    Object? primaryError;
    Object? fallbackError;
    try {
      primaryRaw = await _primary.read(key: key);
    } on Object catch (error) {
      primaryError = error;
    }
    final fallback = _fallback;
    if (fallback != null) {
      try {
        fallbackRaw = await fallback.read(key: key);
      } on Object catch (error) {
        fallbackError = error;
      }
    }

    final primaryRecord = primaryRaw == null ? null : _decode(primaryRaw);
    final fallbackRecord = fallbackRaw == null ? null : _decode(fallbackRaw);
    if (primaryRecord != null || fallbackRecord != null) {
      final chooseFallback = fallbackRecord != null &&
          (primaryRecord == null ||
              fallbackRecord.updatedAt > primaryRecord.updatedAt ||
              (fallbackRecord.updatedAt == primaryRecord.updatedAt &&
                  fallbackRecord.generation > primaryRecord.generation));
      final chosen = chooseFallback ? fallbackRecord : primaryRecord!;
      _active = chooseFallback ? fallback : _primary;
      namespaceRotated = namespaceRotated || chooseFallback;
      _generations[key] = chosen.generation;
      await _cleanupLegacyAfterVerifiedMigration(key);
      return chosen.payload;
    }

    // If one isolated namespace is readable but empty, use it. If the primary
    // is unreadable, start in the isolated fallback without touching its data.
    if (primaryError == null) {
      _active = _primary;
    } else if (fallback != null && fallbackError == null) {
      _active = fallback;
      namespaceRotated = true;
    } else {
      // A newer namespaced record may be unreadable while the legacy encrypted
      // store is still usable (for example after an Android Keystore upgrade).
      // Try that existing encrypted record before declaring the user's data
      // unavailable. Never clear or overwrite either unreadable namespace.
      final legacy = _legacy;
      if (legacy != null) {
        try {
          final legacyRaw = await legacy.read(key: key);
          if (legacyRaw != null) {
            final legacyRecord = _decode(legacyRaw);
            _active = legacy;
            _generations[key] = legacyRecord.generation;
            return legacyRecord.payload;
          }
        } on Object {
          // Preserve all copies and fail closed if no encrypted store can be read.
        }
      }
      Error.throwWithStackTrace(
        primaryError,
        StackTrace.current,
      );
    }

    _generations.putIfAbsent(key, () => 0);
    final legacy = _legacy;
    if (legacy == null) return null;
    String? oldValue;
    try {
      oldValue = await legacy.read(key: key);
    } on Object {
      // Preserve the old encrypted namespace and let the new isolated store
      // accept future data. Never reset, clear, or overwrite the old record.
      legacyDataUnreadable = true;
      return null;
    }
    if (oldValue == null) return null;

    // Copy and verify the full repository value before marking migration.
    // A marker lets a later launch finish cleanup if the process dies between
    // copying and deleting the old ciphertext. The copy remains available in
    // the active encrypted namespace before any legacy delete is attempted.
    await write(key, oldValue);
    await write(_migrationMarkerKey(key), 'true');
    await _cleanupLegacyAfterVerifiedMigration(key);
    return oldValue;
  }

  Future<void> write(String key, String value) async {
    if (!_generations.containsKey(key)) await read(key);
    final target = _active;
    if (target == null) {
      throw StateError('No readable secure-storage namespace is available.');
    }
    final generation = (_generations[key] ?? 0) + 1;
    final envelope = jsonEncode({
      '_marker': _envelopeMarker,
      'generation': generation,
      'updatedAt': DateTime.now().microsecondsSinceEpoch,
      'payload': value,
    });
    await target.write(key: key, value: envelope);
    final persisted = await target.read(key: key);
    if (persisted == null) {
      throw StateError('Secure-storage read-back verification failed.');
    }
    final verified = _decode(persisted);
    if (verified.generation != generation || verified.payload != value) {
      throw StateError('Secure-storage read-back verification failed.');
    }
    _generations[key] = generation;
  }
}

/// Subscription URLs are credentials. Store only in encrypted platform
/// storage; never log or include them in UI errors, analytics, or repository files.
class SubscriptionRepository {
  SubscriptionRepository({FlutterSecureStorage? storage})
      : _storage = _VersionedSecureStorage(injected: storage);

  static const _key = 'saved_subscriptions_v1';
  final _VersionedSecureStorage _storage;
  bool get legacyDataUnreadable => _storage.legacyDataUnreadable;
  bool get namespaceRotated => _storage.namespaceRotated;

  Future<List<SavedSubscription>> readAll() async {
    final raw = await _storage.read(_key);
    if (raw == null || raw.isEmpty) return const [];
    final data = jsonDecode(raw);
    if (data is! List) {
      throw const FormatException('Saved subscription data is invalid.');
    }
    final subscriptions = <SavedSubscription>[];
    for (final item in data) {
      if (item is! Map) {
        throw const FormatException('A saved subscription record is invalid.');
      }
      subscriptions.add(SavedSubscription.fromJson(
        Map<String, dynamic>.from(item),
      ));
    }
    return subscriptions;
  }

  Future<void> saveAll(List<SavedSubscription> subscriptions) => _storage.write(
        _key,
        jsonEncode(subscriptions.map((item) => item.toJson()).toList()),
      );
}

/// Profiles include credentials; use the same versioned encrypted storage and
/// never fall back to plain preferences or silently discard corrupt records.
class StoredProfileState {
  const StoredProfileState({
    required this.profiles,
    required this.sources,
    required this.selectedIndex,
  });

  final List<VpnProfile> profiles;
  final List<String?> sources;
  final int? selectedIndex;

  static const empty = StoredProfileState(
    profiles: [],
    sources: [],
    selectedIndex: null,
  );
}

class ProfileRepository {
  ProfileRepository({FlutterSecureStorage? storage})
      : _storage = _VersionedSecureStorage(injected: storage);

  static const _key = 'saved_profiles_v1';
  final _VersionedSecureStorage _storage;
  bool get legacyDataUnreadable => _storage.legacyDataUnreadable;
  bool get namespaceRotated => _storage.namespaceRotated;

  Future<StoredProfileState> read() async {
    final raw = await _storage.read(_key);
    if (raw == null || raw.isEmpty) return StoredProfileState.empty;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic> || decoded['profiles'] is! List) {
      throw const FormatException('Saved profile data is invalid.');
    }
    final profiles = <VpnProfile>[];
    final sources = <String?>[];
    for (final item in decoded['profiles'] as List) {
      if (item is! Map || item['profile'] is! Map) {
        throw const FormatException('A saved profile record is invalid.');
      }
      final profile = VpnProfile.fromJson(
        Map<String, dynamic>.from(item['profile'] as Map),
      );
      final source = item['sourceId'];
      if (source != null && source is! String) {
        throw const FormatException('A saved profile source is invalid.');
      }
      profiles.add(profile);
      sources.add(source as String?);
    }
    final selectedValue = decoded['selectedIndex'];
    final selected = selectedValue is int &&
            selectedValue >= 0 && selectedValue < profiles.length
        ? selectedValue
        : null;
    return StoredProfileState(
      profiles: profiles,
      sources: sources,
      selectedIndex: selected,
    );
  }

  Future<void> save({
    required List<VpnProfile> profiles,
    required List<String?> sources,
    required int? selectedIndex,
  }) async {
    if (profiles.length != sources.length) {
      throw ArgumentError('Profile and source counts do not match.');
    }
    final value = jsonEncode({
      'profiles': [
        for (var i = 0; i < profiles.length; i++)
          {
            'sourceId': sources[i],
            'profile': profiles[i].toJson(),
          },
      ],
      'selectedIndex': selectedIndex,
    });
    await _storage.write(_key, value);
  }
}

class SubscriptionService {
  static const maxResponseBytes = 1024 * 1024;
  static const maxProfiles = 500;

  /// Fetches an HTTPS subscription, allowing only bounded same-origin HTTPS
  /// redirects so provider links cannot forward credentials to another host.
  /// flutter_vless handles supported link, Base64, Xray JSON, Clash, and
  /// sing-box formats. Raw URLs/configs are never logged or persisted here.
  static Future<List<VpnProfile>> fetchProfiles(String rawUrl) async {
    final uri = validateSubscriptionUrl(rawUrl);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      var currentUri = uri;
      HttpClientResponse? response;
      for (var redirects = 0; redirects <= 3; redirects++) {
        final request = await client
            .getUrl(currentUri)
            .timeout(const Duration(seconds: 15));
        request.followRedirects = false;
        request.headers.set(HttpHeaders.acceptHeader, 'text/plain, */*');
        request.headers.set(HttpHeaders.userAgentHeader, 'V2rayAG-VPN');
        response = await request.close().timeout(const Duration(seconds: 20));
        if (!response.isRedirect) break;

        final location = response.headers.value(HttpHeaders.locationHeader);
        await response.drain<void>().timeout(const Duration(seconds: 5));
        if (location == null || redirects == 3) {
          throw const FormatException(
            'The subscription has too many or incomplete redirects. Ask the provider for its direct HTTPS URL.',
          );
        }
        final target = currentUri.resolve(location);
        // A subscription URL itself is a credential. Do not forward its path
        // or query token to a different host, even over HTTPS.
        final sameOrigin = target.scheme.toLowerCase() == 'https' &&
            target.host.toLowerCase() == uri.host.toLowerCase() &&
            target.port == uri.port &&
            target.userInfo.isEmpty &&
            !target.hasFragment;
        if (!sameOrigin) {
          throw const FormatException(
            'The subscription redirects outside its HTTPS host. Ask the provider for a direct subscription URL.',
          );
        }
        currentUri = target;
      }

      final finalResponse = response;
      if (finalResponse == null || finalResponse.isRedirect) {
        throw const FormatException('The subscription redirect could not be followed safely.');
      }
      if (finalResponse.statusCode != HttpStatus.ok) {
        throw const FormatException(
          'The subscription server did not return a usable response. Check the URL and try again.',
        );
      }

      final bytes = <int>[];
      await for (final chunk in finalResponse.timeout(const Duration(seconds: 20))) {
        if (bytes.length + chunk.length > maxResponseBytes) {
          throw const FormatException('The subscription response is too large to import safely.');
        }
        bytes.addAll(chunk);
      }

      final body = utf8.decode(bytes, allowMalformed: false);
      final profiles = parsePayload(body);
      if (profiles.isEmpty) {
        throw const FormatException(
          'No supported server profiles were found in this subscription response.',
        );
      }
      return profiles;
    } on FormatException {
      rethrow;
    } on Object {
      throw const FormatException(
        'Could not safely fetch this subscription. Check the HTTPS URL and your connection.',
      );
    } finally {
      client.close(force: true);
    }
  }

  /// Parses provider payloads through the same maintained parser used to create
  /// native Xray profiles. Returned credentials may only be persisted through
  /// ProfileRepository, which uses platform secure storage.
  static List<VpnProfile> parsePayload(String payload) {
    final profiles = <VpnProfile>[];
    try {
      final parsed = FlutterVless.parseMany(payload);
      for (final item in parsed.take(maxProfiles)) {
        try {
          profiles.add(VpnProfile.fromParsed(item));
        } on FormatException {
          // Skip malformed entries without exposing provider data.
        } on Object {
          // A bad entry must not invalidate other usable profiles.
        }
      }
    } on Object {
      // Some provider payloads contain a bad line that makes parseMany fail as
      // a whole. Independently parsing recognized share links below preserves
      // any valid entries from mixed-quality subscriptions.
    }

    final links = SubscriptionPayloadParser.extractShareLinks(payload);
    for (final link in links) {
      if (profiles.length >= maxProfiles) break;
      try {
        final profile = VpnProfile.fromShareLink(link);
        if (!profiles.any((existing) => existing.config == profile.config)) {
          profiles.add(profile);
        }
      } on FormatException {
        // Keep valid nodes even if another line in the feed is malformed.
      } on Object {
        // Never expose raw provider data in errors.
      }
    }
    return profiles;
  }

  static Uri validateSubscriptionUrl(String rawUrl) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || uri.scheme.toLowerCase() != 'https' || uri.host.isEmpty) {
      throw const FormatException(
        'Enter a valid direct HTTPS subscription URL.',
      );
    }
    if (uri.userInfo.isNotEmpty) {
      throw const FormatException(
        'Remove the username or password from the URL authority; use the provider-issued subscription link.',
      );
    }
    if (uri.hasFragment) {
      throw const FormatException(
        'Remove the #fragment from the subscription URL; it is not sent to the provider.',
      );
    }
    return uri;
  }
}

class SubscriptionPayloadParser {
  static final _schemePattern = RegExp(
    r'(?:vless|vmess|ss|trojan|socks|hysteria2|hy2)://',
    caseSensitive: false,
  );
  static final _trailingPunctuation = RegExp(r'[.,;!?)\]}>，。；！？、]+$');

  /// Finds supported share links anywhere in pasted text, including messages
  /// with prose, emoji, bullets, or several links on one line. It only returns
  /// recognized URI schemes; unrelated text and ordinary web links are ignored.
  /// Also supports provider responses encoded as Base64.
  static List<String> extractShareLinks(String payload) {
    if (payload.length > SubscriptionService.maxResponseBytes * 2) {
      return const [];
    }
    final direct = _extractEmbeddedLinks(payload);
    if (direct.isNotEmpty) return _deduplicate(direct);

    final compact = payload.trim().replaceAll(RegExp(r'\s+'), '');
    if (compact.isEmpty || compact.length > SubscriptionService.maxResponseBytes * 2) {
      return const [];
    }
    try {
      var normalized = compact.replaceAll('-', '+').replaceAll('_', '/');
      normalized += List<String>.filled((4 - normalized.length % 4) % 4, '=').join();
      final decoded = utf8.decode(base64.decode(normalized), allowMalformed: false);
      return _deduplicate(_extractEmbeddedLinks(decoded));
    } on Object {
      return const [];
    }
  }

  static List<String> _extractEmbeddedLinks(String payload) {
    final matches = _schemePattern.allMatches(payload).toList(growable: false);
    if (matches.isEmpty) return const [];
    final links = <String>[];
    for (var index = 0;
        index < matches.length && links.length < SubscriptionService.maxProfiles;
        index++) {
      final match = matches[index];
      final start = match.start;
      final nextScheme = index + 1 < matches.length
          ? matches[index + 1].start
          : payload.length;
      var end = match.end;
      const maxLinkLength = 16384;
      while (end < payload.length &&
          end - start < maxLinkLength &&
          end < nextScheme &&
          payload[end].trim().isNotEmpty) {
        end++;
      }
      if (end - start >= maxLinkLength &&
          end < payload.length &&
          end < nextScheme &&
          payload[end].trim().isNotEmpty) {
        continue; // Ignore implausibly long/malformed tokens rather than truncate.
      }
      var candidate = payload.substring(start, end).trim();
      candidate = candidate.replaceFirst(_trailingPunctuation, '');
      if (candidate.length > match.end - match.start) links.add(candidate);
    }
    return links;
  }

  static List<String> _deduplicate(List<String> links) {
    final seen = <String>{};
    return links.where((link) => seen.add(link)).toList(growable: false);
  }
}
