import 'dart:convert';
import 'dart:io';

import 'vpn_profile.dart';

/// Safe display-only metadata for an automatic pool connection.
/// Never contains a share URI, credentials, or an active lease token.
class PoolConnectionSummary {
  const PoolConnectionSummary({
    required this.subscriptionName,
    required this.configurationName,
    required this.quotaKnown,
    required this.uploadBytes,
    required this.downloadBytes,
    required this.totalBytes,
    required this.expiresAt,
  });

  final String subscriptionName;
  final String configurationName;
  final bool quotaKnown;
  final int uploadBytes;
  final int downloadBytes;
  final int? totalBytes;
  final int? expiresAt;

  Map<String, Object?> toJson() => {
        'subscriptionName': subscriptionName,
        'configurationName': configurationName,
        'quotaKnown': quotaKnown,
        'upload': uploadBytes,
        'download': downloadBytes,
        'total': totalBytes,
        'expiresAt': expiresAt,
      };

  factory PoolConnectionSummary.fromJson(Map<String, dynamic> json) {
    final subName = (json['subscriptionName'] ?? '').toString().trim();
    final configName = (json['configurationName'] ?? '').toString().trim();
    if (subName.isEmpty || configName.isEmpty) {
      throw const FormatException('Saved pool status is incomplete.');
    }
    return PoolConnectionSummary(
      subscriptionName: subName,
      configurationName: configName,
      quotaKnown: json['quotaKnown'] == true,
      uploadBytes: ExclusivePoolService._nonNegativeInt(json['upload']),
      downloadBytes: ExclusivePoolService._nonNegativeInt(json['download']),
      totalBytes: ExclusivePoolService._optionalNonNegativeInt(json['total']),
      expiresAt: ExclusivePoolService._optionalNonNegativeInt(json['expiresAt']),
    );
  }

  int? get remainingBytes {
    final total = totalBytes;
    if (!quotaKnown || total == null || total <= 0) return null;
    return (total - uploadBytes - downloadBytes).clamp(0, total).toInt();
  }

  bool get unlimitedQuota => quotaKnown && totalBytes == 0;

  int? get daysUntilExpiry {
    final expiry = expiresAt;
    if (expiry == null || expiry <= 0) return null;
    final remaining = DateTime.fromMillisecondsSinceEpoch(expiry * 1000)
        .difference(DateTime.now());
    if (remaining.isNegative) return 0;
    return (remaining.inSeconds / const Duration(days: 1).inSeconds).ceil();
  }
}

class ExclusivePoolCandidate {
  const ExclusivePoolCandidate({
    required this.id,
    required this.profile,
    required this.subscriptionName,
    required this.quotaKnown,
    required this.uploadBytes,
    required this.downloadBytes,
    required this.totalBytes,
    required this.expiresAt,
  });

  /// Opaque server-side profile ID, used only to avoid retrying it in one
  /// connect attempt. It is not shown in the UI or persisted.
  final String id;
  final VpnProfile profile;
  final String subscriptionName;
  final bool quotaKnown;
  final int uploadBytes;
  final int downloadBytes;
  final int? totalBytes;
  final int? expiresAt;

  PoolConnectionSummary get summary => PoolConnectionSummary(
        subscriptionName: subscriptionName,
        configurationName: configurationName,
        quotaKnown: quotaKnown,
        uploadBytes: uploadBytes,
        downloadBytes: downloadBytes,
        totalBytes: totalBytes,
        expiresAt: expiresAt,
      );

  String get configurationName {
    final clean = profile.name
        .replaceAll(RegExp(r'[\x00-\x1F\x7F]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return clean.length <= 80 ? clean : clean.substring(0, 80);
  }

  int? get remainingBytes {
    final total = totalBytes;
    if (!quotaKnown || total == null || total <= 0) return null;
    return (total - uploadBytes - downloadBytes).clamp(0, total).toInt();
  }

  bool get unlimitedQuota => quotaKnown && totalBytes == 0;

  int? get daysUntilExpiry {
    final expiry = expiresAt;
    if (expiry == null || expiry <= 0) return null;
    final remaining = DateTime.fromMillisecondsSinceEpoch(expiry * 1000)
        .difference(DateTime.now());
    if (remaining.isNegative) return 0;
    return (remaining.inSeconds / const Duration(days: 1).inSeconds).ceil();
  }
}

class ExclusivePoolLease {
  const ExclusivePoolLease({required this.leaseId, required this.candidate});

  /// Opaque release token. Keep only in memory; do not persist or display it.
  final String leaseId;
  final ExclusivePoolCandidate candidate;
}

class ExclusivePoolService {
  ExclusivePoolService({HttpClient? client, Uri? endpoint})
      : _client = client ?? HttpClient(),
        _ownsClient = client == null,
        endpoint = endpoint ?? _defaultEndpoint;

  static const _defaultEndpoint =
      'https://v2rayag-app-pool-control.littlespring00.workers.dev';
  static const maxResponseBytes = 128 * 1024;
  static const maxProfileBytes = 16 * 1024;
  static const _supportedSchemes = {
    'vless', 'vmess', 'ss', 'shadowsocks', 'trojan', 'socks',
    'hysteria2', 'wireguard', 'http',
  };

  final HttpClient _client;
  final bool _ownsClient;
  final Uri endpoint;

  Future<ExclusivePoolLease> acquireLease({Set<String> excludeIds = const {}}) async {
    final excluded = excludeIds
        .where((id) => RegExp(r'^[0-9a-f]{24}$').hasMatch(id))
        .take(100)
        .toList(growable: false);
    final uri = endpoint.replace(path: '/v1/pool/leases', query: null);
    if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      throw const FormatException('The secure server pool is not configured.');
    }

    try {
      final request = await _client.postUrl(uri).timeout(const Duration(seconds: 12));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
      request.headers.set(HttpHeaders.userAgentHeader, 'V2rayAG');
      request.write(jsonEncode({'exclude': excluded}));
      final response = await request.close().timeout(const Duration(seconds: 15));
      final bytes = await _readResponse(response);
      if (response.statusCode != HttpStatus.ok) {
        final decoded = _decodeJson(bytes);
        final message = decoded is Map<String, dynamic> && decoded['error'] is String
            ? decoded['error'] as String
            : 'No usable server is available right now. Try again shortly.';
        throw FormatException(message);
      }
      return parseLease(_decodeJson(bytes));
    } on FormatException {
      rethrow;
    } on Object {
      throw const FormatException(
        'Could not reach the secure server pool. Check your internet and try again.',
      );
    }
  }

  Future<void> releaseLease(String leaseId) async {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(leaseId)) return;
    try {
      final uri = endpoint.replace(path: '/v1/pool/leases/release', query: null);
      if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) return;
      final request = await _client.postUrl(uri).timeout(const Duration(seconds: 5));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
      request.headers.set(HttpHeaders.userAgentHeader, 'V2rayAG');
      request.write(jsonEncode({'leaseId': leaseId}));
      final response = await request.close().timeout(const Duration(seconds: 8));
      await response.drain<void>();
    } on Object {
      // Lease records expire server-side if the device is offline or closed.
    }
  }

  static ExclusivePoolLease parseLease(Object? value) {
    if (value is! Map<String, dynamic> || value['success'] != true) {
      throw const FormatException(
        'No usable server is available right now. Try again shortly.',
      );
    }
    final leaseId = value['leaseId'];
    final entry = value['candidate'];
    if (leaseId is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(leaseId) ||
        entry is! Map<String, dynamic>) {
      throw const FormatException('The server pool returned an invalid response.');
    }
    final id = entry['id'];
    final rawUri = entry['uri'];
    if (id is! String || !RegExp(r'^[0-9a-f]{24}$').hasMatch(id) ||
        rawUri is! String || rawUri.length > maxProfileBytes) {
      throw const FormatException('The server pool returned an invalid profile.');
    }
    final uri = Uri.tryParse(rawUri.trim());
    if (uri == null || !_supportedSchemes.contains(uri.scheme.toLowerCase())) {
      throw const FormatException('The server pool returned an unsupported profile.');
    }
    try {
      final profile = VpnProfile.fromShareLink(rawUri);
      final subName = (entry['subscriptionName'] ?? 'Subscription').toString().trim();
      return ExclusivePoolLease(
        leaseId: leaseId,
        candidate: ExclusivePoolCandidate(
          id: id,
          profile: profile,
          subscriptionName: subName.isEmpty ? 'Subscription' : subName,
          quotaKnown: entry['quotaKnown'] == true,
          uploadBytes: _nonNegativeInt(entry['upload']),
          downloadBytes: _nonNegativeInt(entry['download']),
          totalBytes: _optionalNonNegativeInt(entry['total']),
          expiresAt: _optionalNonNegativeInt(entry['expiresAt']),
        ),
      );
    } on Object {
      throw const FormatException('The server pool returned an invalid profile.');
    }
  }

  static Object? _decodeJson(List<int> bytes) =>
      jsonDecode(utf8.decode(bytes, allowMalformed: false));

  static Future<List<int>> _readResponse(HttpClientResponse response) async {
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 15))) {
      if (bytes.length + chunk.length > maxResponseBytes) {
        throw const FormatException('The server pool response is too large.');
      }
      bytes.addAll(chunk);
    }
    return bytes;
  }

  static int _nonNegativeInt(Object? value) =>
      _optionalNonNegativeInt(value) ?? 0;

  static int? _optionalNonNegativeInt(Object? value) {
    if (value is int && value >= 0) return value;
    if (value is num && value >= 0 && value.isFinite) return value.toInt();
    final parsed = int.tryParse('$value');
    return parsed == null ? null : parsed.clamp(0, 0x7fffffffffffffff).toInt();
  }

  void dispose() {
    if (_ownsClient) _client.close(force: true);
  }
}
