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
              aOptions: AndroidOptions(migrateWithBackup: true),
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
        await response.drain<void>();
        if (location == null || redirects == 3) {
          throw const FormatException(
            'The subscription has too many or incomplete redirects. Ask the provider for its direct HTTPS URL.',
          );
        }
        final target = currentUri.resolve(location);
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
  /// the native Xray profiles. Individual credentials remain only in memory.
  static List<VpnProfile> parsePayload(String payload) {
    final parsed = FlutterVless.parseMany(payload);
    final profiles = <VpnProfile>[];
    for (final item in parsed.take(maxProfiles)) {
      try {
        profiles.add(VpnProfile.fromParsed(item));
      } on FormatException {
        // Skip malformed entries without exposing provider data.
      } on Object {
        // A bad entry must not invalidate other usable profiles.
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
  static const _schemes = ['vless://', 'vmess://', 'ss://', 'trojan://'];

  /// Supports plain newline-separated share links and Base64-encoded provider
  /// responses. Lines containing unsupported schemes are ignored.
  static List<String> extractShareLinks(String payload) {
    final direct = _shareLines(payload);
    if (direct.isNotEmpty) return direct;

    final compact = payload.trim().replaceAll(RegExp(r'\s+'), '');
    if (compact.isEmpty || compact.length > SubscriptionService.maxResponseBytes * 2) {
      return const [];
    }
    try {
      var normalized = compact.replaceAll('-', '+').replaceAll('_', '/');
      normalized += List<String>.filled((4 - normalized.length % 4) % 4, '=').join();
      final decoded = utf8.decode(base64.decode(normalized), allowMalformed: false);
      return _shareLines(decoded);
    } on Object {
      return const [];
    }
  }

  static List<String> _shareLines(String payload) => payload
      .split(RegExp(r'[\r\n]+'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty &&
          _schemes.any((scheme) => line.toLowerCase().startsWith(scheme)))
      .toList(growable: false);
}
