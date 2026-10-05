import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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

class _PoolAuthorizationException implements Exception {
  const _PoolAuthorizationException(this.message);
  final String message;
}

/// The Worker has no additional usable profiles to lease for this search.
class PoolCandidatesUnavailableException implements Exception {
  const PoolCandidatesUnavailableException(this.message);
  final String message;

  @override
  String toString() => 'PoolCandidatesUnavailableException';
}

/// A leased node that the client parser cannot use. Carries only opaque IDs so
/// the lease can be released and the pool can provide another candidate.
class PoolCandidateRejectedException implements Exception {
  const PoolCandidateRejectedException({
    required this.leaseId,
    required this.candidateId,
  });

  final String leaseId;
  final String candidateId;

  @override
  String toString() => 'PoolCandidateRejectedException';
}

class ExclusivePoolService {
  ExclusivePoolService({
    HttpClient? client,
    FlutterSecureStorage? storage,
    Uri? endpoint,
  })  : _client = client ?? HttpClient(),
        _ownsClient = client == null,
        _storage = storage ??
            FlutterSecureStorage(
              aOptions: AndroidOptions(
                storageNamespace: 'v2rayag_auto_access_v1',
                migrateWithBackup: false,
                resetOnError: false,
              ),
            ),
        endpoint = endpoint ?? Uri.parse(_defaultEndpoint);

  static const _defaultEndpoint =
      'https://v2rayag-app-pool-control.littlespring00.workers.dev';
  static const maxResponseBytes = 128 * 1024;
  static const maxProfileBytes = 16 * 1024;
  static const _deviceTokenKey = 'v2rayag_auto_access_token_v1';
  static const _deviceTokenOriginKey = 'v2rayag_auto_access_origin_v1';
  static const _supportedSchemes = {
    'vless', 'vmess', 'ss', 'shadowsocks', 'trojan', 'socks',
    'hysteria2', 'wireguard', 'http',
  };

  final HttpClient _client;
  final bool _ownsClient;
  final FlutterSecureStorage _storage;
  final Uri endpoint;

  Future<String>? _enrollmentInFlight;
  String? _sessionDeviceToken;
  bool _sessionDeviceTokenAutomatic = false;

  Future<bool> hasDeviceAccessToken() async => (await _readDeviceToken()) != null;

  Future<void> saveDeviceAccessToken(String rawToken) async {
    final token = rawToken.trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(token)) {
      throw const FormatException('Device key must be 64 hexadecimal characters.');
    }
    await _storeDeviceToken(token, automatic: false);
  }

  Future<void> _storeDeviceToken(String token, {required bool automatic}) async {
    if (automatic) {
      // Keep a newly issued token for this process even if Android's encrypted
      // preferences cannot be opened on this device. This lets the current
      // connection proceed; only this replaceable access token is affected.
      _sessionDeviceToken = token;
      _sessionDeviceTokenAutomatic = true;
    }
    try {
      await _storage.write(key: _deviceTokenKey, value: token);
      final savedToken = (await _storage.read(key: _deviceTokenKey))?.trim().toLowerCase();
      if (savedToken != token) {
        throw StateError('Device access secure-storage read-back verification failed.');
      }
      await _storage.write(
        key: _deviceTokenOriginKey,
        value: automatic ? 'automatic' : 'manual',
      );
      _sessionDeviceToken = token;
      _sessionDeviceTokenAutomatic = automatic;
    } on Object {
      if (!automatic) {
        _sessionDeviceToken = null;
        _sessionDeviceTokenAutomatic = false;
        rethrow;
      }
      // Do not block first-connect enrollment on an unreadable legacy key or a
      // device Keystore issue. Never clear profile/subscription storage here.
    }
  }

  Future<void> clearDeviceAccessToken() async {
    _sessionDeviceToken = null;
    _sessionDeviceTokenAutomatic = false;
    await _discardStoredDeviceToken();
  }

  Future<void> _discardStoredDeviceToken() async {
    // This namespace holds only the revocable device access token and its
    // origin marker; user profiles and subscriptions live elsewhere.
    for (final key in [_deviceTokenKey, _deviceTokenOriginKey]) {
      try {
        await _storage.delete(key: key);
      } on Object {
        // A broken encrypted store must not prevent temporary auto-enrollment.
      }
    }
  }

  Future<String?> _readDeviceToken() async {
    final sessionToken = _sessionDeviceToken;
    if (sessionToken != null && RegExp(r'^[0-9a-f]{64}$').hasMatch(sessionToken)) {
      return sessionToken;
    }
    try {
      final token = (await _storage.read(key: _deviceTokenKey))?.trim().toLowerCase();
      if (token == null) return null;
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(token)) {
        await _discardStoredDeviceToken();
        return null;
      }
      return token;
    } on Object {
      // The saved value is only a revocable access credential, not user data.
      // Discard these two entries and enroll a fresh token; do not touch the
      // separate profile/subscription namespace.
      await _discardStoredDeviceToken();
      return null;
    }
  }

  Future<bool> _hasAutomaticToken() async {
    if (_sessionDeviceToken != null) return _sessionDeviceTokenAutomatic;
    try {
      return (await _storage.read(key: _deviceTokenOriginKey)) == 'automatic';
    } on Object {
      return false;
    }
  }

  Future<String> _ensureDeviceToken() async {
    final existing = await _readDeviceToken();
    if (existing != null) return existing;
    final pending = _enrollmentInFlight;
    if (pending != null) return pending;
    final enrollment = _enrollDevice();
    _enrollmentInFlight = enrollment;
    try {
      return await enrollment;
    } finally {
      if (identical(_enrollmentInFlight, enrollment)) _enrollmentInFlight = null;
    }
  }

  Future<String> _enrollDevice() async {
    final uri = endpoint.replace(path: '/v1/app/devices/enroll', query: null);
    if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      throw const FormatException('The secure server pool is not configured.');
    }
    try {
      final request = await _client.postUrl(uri).timeout(const Duration(seconds: 12));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
      request.headers.set(HttpHeaders.userAgentHeader, 'V2rayAG');
      request.write(jsonEncode({'platform': Platform.isAndroid ? 'android' : 'mobile'}));
      final response = await request.close().timeout(const Duration(seconds: 15));
      final bytes = await _readResponse(response);
      Object? decoded;
      try {
        decoded = _decodeJson(bytes);
      } on FormatException {
        throw FormatException(
          'Automatic access server returned an unreadable response (HTTP ${response.statusCode}).',
        );
      }
      if (response.statusCode != HttpStatus.ok) {
        final message = _safeServerError(decoded) ??
            'Automatic access setup was rejected (HTTP ${response.statusCode}).';
        throw FormatException(message);
      }
      final token = parseEnrollmentToken(decoded);
      try {
        await _storeDeviceToken(token, automatic: true);
      } on Object {
        throw const FormatException(
          'Automatic access could not be saved securely on this phone. Check secure storage and try again.',
        );
      }
      return token;
    } on FormatException {
      rethrow;
    } on Object {
      throw const FormatException(
        'Could not initialize automatic access. Check your internet and try again.',
      );
    }
  }

  static String parseEnrollmentToken(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Automatic access server returned an unreadable response.');
    }
    if (value['success'] != true) {
      final message = _safeServerError(value);
      throw FormatException(message ??
          'Automatic access server rejected setup without a reason.');
    }
    final token = value['token'];
    if (token is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(token)) {
      throw const FormatException('The server returned an invalid access token.');
    }
    return token;
  }

  Future<ExclusivePoolLease> _requestLease(
    List<String> excluded,
    String deviceToken,
  ) async {
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
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $deviceToken');
      request.write(jsonEncode({'exclude': excluded}));
      final response = await request.close().timeout(const Duration(seconds: 15));
      final bytes = await _readResponse(response);
      final decoded = _decodeJson(bytes);
      if (response.statusCode != HttpStatus.ok) {
        final message = decoded is Map<String, dynamic> && decoded['error'] is String
            ? decoded['error'] as String
            : 'No usable server is available right now. Try again shortly.';
        if (response.statusCode == HttpStatus.unauthorized) {
          throw _PoolAuthorizationException(message);
        }
        if (response.statusCode == HttpStatus.serviceUnavailable) {
          throw PoolCandidatesUnavailableException(message);
        }
        throw FormatException(message);
      }
      return parseLease(decoded);
    } on _PoolAuthorizationException {
      rethrow;
    } on PoolCandidatesUnavailableException {
      rethrow;
    } on PoolCandidateRejectedException {
      rethrow;
    } on FormatException {
      rethrow;
    } on Object {
      throw const FormatException(
        'Could not reach the secure server pool. Check your internet and try again.',
      );
    }
  }

  Future<ExclusivePoolLease> acquireLease({Set<String> excludeIds = const {}}) async {
    final excluded = <String>{
      ...excludeIds.where((id) => RegExp(r'^[0-9a-f]{24}$').hasMatch(id)),
    };
    var deviceToken = await _ensureDeviceToken();
    while (true) {
      try {
        return await _requestLease(
          excluded.toList(growable: false),
          deviceToken,
        );
      } on PoolCandidateRejectedException catch (error) {
        await releaseLease(error.leaseId);
        if (!excluded.add(error.candidateId)) {
          throw const FormatException(
            'The server pool repeated an unsupported profile. Try again shortly.',
          );
        }
      } on _PoolAuthorizationException catch (error) {
        // Migrate a previously pasted key if it is no longer valid. Never
        // silently replace an already automatic/revoked token.
        if (await _hasAutomaticToken()) {
          throw FormatException(error.message);
        }
        await clearDeviceAccessToken();
        deviceToken = await _enrollDevice();
      }
    }
  }

  Future<void> releaseLease(String leaseId) async {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(leaseId)) return;
    try {
      final deviceToken = await _readDeviceToken();
      if (deviceToken == null) return;
      final uri = endpoint.replace(path: '/v1/pool/leases/release', query: null);
      if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) return;
      final request = await _client.postUrl(uri).timeout(const Duration(seconds: 5));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
      request.headers.set(HttpHeaders.userAgentHeader, 'V2rayAG');
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $deviceToken');
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
    if (id is! String || !RegExp(r'^[0-9a-f]{24}$').hasMatch(id)) {
      throw const FormatException('The server pool returned an invalid profile.');
    }
    if (rawUri is! String || rawUri.length > maxProfileBytes) {
      throw PoolCandidateRejectedException(leaseId: leaseId, candidateId: id);
    }
    final uri = Uri.tryParse(rawUri.trim());
    if (uri == null || !_supportedSchemes.contains(uri.scheme.toLowerCase())) {
      throw PoolCandidateRejectedException(leaseId: leaseId, candidateId: id);
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
    } on PoolCandidateRejectedException {
      rethrow;
    } on Object {
      throw PoolCandidateRejectedException(leaseId: leaseId, candidateId: id);
    }
  }

  static String? _safeServerError(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final raw = value['error'];
    if (raw is! String) return null;
    final message = raw.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), ' ').trim();
    if (message.isEmpty) return null;
    return message.length <= 180 ? message : '${message.substring(0, 177)}…';
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
    return parsed?.clamp(0, 0x7fffffffffffffff).toInt();
  }

  void dispose() {
    if (_ownsClient) _client.close(force: true);
  }
}
