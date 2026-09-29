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

/// Subscription URLs are credentials. Store them only through platform secure
/// storage; never log or include them in UI errors, analytics, or repository files.
class SubscriptionRepository {
  SubscriptionRepository({FlutterSecureStorage? storage})
      : _storage = storage ??
            FlutterSecureStorage(
              // Preserve crash-safe cipher migration, but never silently reset
              // encrypted records when Android Keystore cannot unwrap a key.
              aOptions: AndroidOptions(
                migrateWithBackup: true,
                resetOnError: false,
              ),
            );

  static const _key = 'saved_subscriptions_v1';
  final FlutterSecureStorage _storage;

  Future<List<SavedSubscription>> readAll() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final data = jsonDecode(raw);
      if (data is! List) return const [];
      return data
          .whereType<Map<String, dynamic>>()
          .map(SavedSubscription.fromJson)
          .toList(growable: true);
    } on Object {
      // Corrupt or obsolete local data must not crash app startup.
      return const [];
    }
  }

  Future<void> saveAll(List<SavedSubscription> subscriptions) => _storage.write(
        key: _key,
        value: jsonEncode(subscriptions.map((item) => item.toJson()).toList()),
      );

  /// Explicit recovery only: remove this app's unreadable subscription record
  /// after the user confirms data loss. Never clear the whole secure store.
  Future<void> deleteSaved() => _storage.delete(key: _key);
}

/// Profiles include credentials, so this repository uses the same encrypted
/// platform storage as subscription URLs and never falls back to plain prefs.
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
      : _storage = storage ??
            FlutterSecureStorage(
              aOptions: AndroidOptions(
                migrateWithBackup: true,
                resetOnError: false,
              ),
            );

  static const _key = 'saved_profiles_v1';
  final FlutterSecureStorage _storage;

  Future<StoredProfileState> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return StoredProfileState.empty;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic> || decoded['profiles'] is! List) {
      throw const FormatException('Saved profile data is invalid.');
    }
    final profiles = <VpnProfile>[];
    final sources = <String?>[];
    for (final item in decoded['profiles'] as List) {
      if (item is! Map<String, dynamic> || item['profile'] is! Map) {
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
    await _storage.write(key: _key, value: value);
  }

  /// Explicit recovery only: remove this app's unreadable profile record after
  /// the user confirms that inaccessible saved profiles may be discarded.
  Future<void> deleteSaved() => _storage.delete(key: _key);
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
