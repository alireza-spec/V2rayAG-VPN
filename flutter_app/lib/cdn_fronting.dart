import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'vpn_profile.dart';

enum ConnectionProtocol { auto, cdnFronting }

/// User-selected transport behavior. These settings contain no credentials.
/// CDN remains a distinct mode; blank overrides must never fall back to Auto.
class CdnFrontingSettings {
  const CdnFrontingSettings({
    this.protocol = ConnectionProtocol.auto,
    this.cdnIps = '',
    this.sniHostname = '',
  });

  final ConnectionProtocol protocol;
  final String cdnIps;
  final String sniHostname;

  bool get hasOverrides => parsedIps.isNotEmpty || normalizedSniHostname != null;

  List<String> get parsedIps => parseCdnIps(cdnIps);
  String? get normalizedSniHostname => normalizeSniHostname(sniHostname);

  CdnFrontingSettings validated() => CdnFrontingSettings(
        protocol: protocol,
        cdnIps: parsedIps.join('\n'),
        sniHostname: normalizedSniHostname ?? '',
      );

  CdnFrontingSettings withProtocol(ConnectionProtocol value) =>
      CdnFrontingSettings(
        protocol: value,
        cdnIps: cdnIps,
        sniHostname: sniHostname,
      );

  static List<String> parseCdnIps(String raw) {
    final values = raw
        .split(RegExp(r'[,;\s]+'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (values.length > 20) {
      throw const FormatException('Enter no more than 20 CDN IP addresses.');
    }
    final unique = <String>[];
    for (final value in values) {
      if (InternetAddress.tryParse(value) == null) {
        throw const FormatException('Enter valid IPv4 or IPv6 addresses only.');
      }
      if (!unique.contains(value)) unique.add(value);
    }
    return List.unmodifiable(unique);
  }

  static String? normalizeSniHostname(String raw) {
    final value = raw.trim().replaceFirst(RegExp(r'\.$'), '').toLowerCase();
    if (value.isEmpty) return null;
    if (value.length > 253 || value.contains('://') || value.contains('/') ||
        value.contains(':') || value.contains('@') || value.contains(' ')) {
      throw const FormatException('Enter a hostname only, without a scheme, path, or port.');
    }
    final labels = value.split('.');
    if (labels.length < 2 || labels.any((label) =>
        label.isEmpty || label.length > 63 ||
        !RegExp(r'^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$').hasMatch(label))) {
      throw const FormatException('Enter a valid CDN SNI hostname.');
    }
    if (InternetAddress.tryParse(value) != null) {
      throw const FormatException('SNI must be a hostname, not an IP address.');
    }
    return value;
  }
}

class CdnProfileNotSupportedException implements Exception {
  const CdnProfileNotSupportedException();

  @override
  String toString() => 'This server does not use a supported TLS WebSocket route.';
}

class CdnMeekEngineUnavailableException implements Exception {
  const CdnMeekEngineUnavailableException();

  @override
  String toString() => 'No independent Meek engine is available for empty CDN overrides.';
}

/// Creates per-IP variants for an automatic-pool profile. Auto mode returns
/// the original profile. CDN mode with blank overrides fails closed because
/// this build has no independent Meek engine or default Meek server source.
List<VpnProfile> buildCdnProfileAttempts(
  VpnProfile profile,
  CdnFrontingSettings settings,
) {
  if (settings.protocol != ConnectionProtocol.cdnFronting) return [profile];
  if (!settings.hasOverrides) throw const CdnMeekEngineUnavailableException();

  final ips = settings.parsedIps;
  final targets = ips.isEmpty
      ? const <String?>[null]
      : ips.map<String?>((ip) => ip).toList(growable: false);
  final sni = settings.normalizedSniHostname;
  return List.unmodifiable(targets.map((ip) => VpnProfile(
        summary: profile.summary,
        config: applyCdnFrontingOverrides(
          profile.config,
          cdnIp: ip,
          sniHostname: sni,
        ),
      )));
}

/// Applies classic CDN-over-WebSocket overrides to one compatible Xray
/// outbound. Only VLESS, VMess and Trojan over TLS/WebSocket are accepted.
/// Other transports are rejected explicitly rather than silently connecting
/// without the requested CDN settings.
String applyCdnFrontingOverrides(
  String config, {
  String? cdnIp,
  String? sniHostname,
}) {
  final ip = cdnIp == null || cdnIp.trim().isEmpty
      ? null
      : CdnFrontingSettings.parseCdnIps(cdnIp).single;
  final sni = sniHostname == null || sniHostname.trim().isEmpty
      ? null
      : CdnFrontingSettings.normalizeSniHostname(sniHostname);
  if (ip == null && sni == null) return config;

  final dynamic decoded;
  try {
    decoded = jsonDecode(config);
  } on Object {
    throw const FormatException('The server configuration is not valid JSON.');
  }
  if (decoded is! Map<String, dynamic> || decoded['outbounds'] is! List) {
    throw const CdnProfileNotSupportedException();
  }
  final outbounds = decoded['outbounds'] as List;
  final candidates = <(int, Map<String, dynamic>)>[];
  for (var index = 0; index < outbounds.length; index++) {
    final value = outbounds[index];
    if (value is! Map) continue;
    final candidate = Map<String, dynamic>.from(value);
    final protocol = (candidate['protocol'] ?? '').toString().toLowerCase();
    if (const {'vless', 'vmess', 'trojan'}.contains(protocol)) {
      candidates.add((index, candidate));
    }
  }
  if (candidates.length != 1) throw const CdnProfileNotSupportedException();
  final (outboundIndex, outbound) = candidates.single;
  outbounds[outboundIndex] = outbound;

  final streamValue = outbound['streamSettings'];
  if (streamValue is! Map) throw const CdnProfileNotSupportedException();
  final stream = Map<String, dynamic>.from(streamValue);
  outbound['streamSettings'] = stream;
  if ((stream['network'] ?? '').toString().toLowerCase() != 'ws' ||
      (stream['security'] ?? '').toString().toLowerCase() != 'tls') {
    throw const CdnProfileNotSupportedException();
  }

  final settingsValue = outbound['settings'];
  if (settingsValue is! Map) throw const CdnProfileNotSupportedException();
  final outboundSettings = Map<String, dynamic>.from(settingsValue);
  outbound['settings'] = outboundSettings;
  late String originalAddress;
  final protocol = (outbound['protocol'] ?? '').toString().toLowerCase();
  if (protocol == 'vless' || protocol == 'vmess') {
    final serversValue = outboundSettings['vnext'];
    if (serversValue is! List || serversValue.isEmpty || serversValue.first is! Map) {
      throw const CdnProfileNotSupportedException();
    }
    final server = Map<String, dynamic>.from(serversValue.first as Map);
    serversValue[0] = server;
    originalAddress = (server['address'] ?? '').toString().trim();
    if (originalAddress.isEmpty) throw const CdnProfileNotSupportedException();
    if (ip != null) server['address'] = ip;
  } else {
    final serversValue = outboundSettings['servers'];
    if (serversValue is! List || serversValue.isEmpty || serversValue.first is! Map) {
      throw const CdnProfileNotSupportedException();
    }
    final server = Map<String, dynamic>.from(serversValue.first as Map);
    serversValue[0] = server;
    originalAddress = (server['address'] ?? '').toString().trim();
    if (originalAddress.isEmpty) throw const CdnProfileNotSupportedException();
    if (ip != null) server['address'] = ip;
  }

  final tlsValue = stream['tlsSettings'];
  final tls = tlsValue is Map
      ? Map<String, dynamic>.from(tlsValue)
      : <String, dynamic>{};
  stream['tlsSettings'] = tls;
  final websocketValue = stream['wsSettings'];
  if (websocketValue is! Map) throw const CdnProfileNotSupportedException();
  final websocket = Map<String, dynamic>.from(websocketValue);
  stream['wsSettings'] = websocket;
  final headersValue = websocket['headers'];
  final headers = headersValue is Map
      ? Map<String, dynamic>.from(headersValue)
      : <String, dynamic>{};
  websocket['headers'] = headers;

  final existingTlsName = (tls['serverName'] ?? '').toString().trim();
  final existingHost = (headers['Host'] ?? headers['host'] ?? '').toString().trim();
  final fallbackHost = InternetAddress.tryParse(originalAddress) == null
      ? originalAddress
      : existingHost;
  final effectiveSni = sni ?? existingTlsName.ifEmpty(fallbackHost);
  if (ip != null && effectiveSni.isEmpty) {
    throw const FormatException(
      'This profile has no hostname to preserve. Enter a CDN SNI hostname before using an IP override.',
    );
  }
  if (sni != null) {
    tls['serverName'] = sni;
  } else if (ip != null && existingTlsName.isEmpty) {
    // Preserve the original TLS identity when the transport previously relied
    // on its domain address rather than an explicit serverName.
    tls['serverName'] = effectiveSni;
  }
  if (sni != null || ip != null) {
    // Cloudflare needs the HTTP Host header to keep naming the origin even
    // when the socket itself is connected to a CDN edge IP.
    headers.remove('host');
    if (sni != null) {
      headers['Host'] = sni;
    } else if (ip != null) {
      headers['Host'] = existingHost.isEmpty ? effectiveSni : existingHost;
    }
  }
  return jsonEncode(decoded);
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

class CdnFrontingPreferencesRepository {
  static const _protocolKey = 'connection_protocol_v1';
  static const _ipsKey = 'cdn_fronting_ips_v1';
  static const _sniKey = 'cdn_fronting_sni_v1';

  Future<CdnFrontingSettings> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final protocol = prefs.getString(_protocolKey) == 'cdn_fronting'
          ? ConnectionProtocol.cdnFronting
          : ConnectionProtocol.auto;
      return CdnFrontingSettings(
        protocol: protocol,
        cdnIps: prefs.getString(_ipsKey) ?? '',
        sniHostname: prefs.getString(_sniKey) ?? '',
      ).validated();
    } on Object {
      return const CdnFrontingSettings();
    }
  }

  Future<void> save(CdnFrontingSettings settings) async {
    final value = settings.validated();
    final prefs = await SharedPreferences.getInstance();
    final saved = await Future.wait([
      prefs.setString(
        _protocolKey,
        value.protocol == ConnectionProtocol.cdnFronting ? 'cdn_fronting' : 'auto',
      ),
      prefs.setString(_ipsKey, value.cdnIps),
      prefs.setString(_sniKey, value.sniHostname),
    ]);
    if (saved.any((ok) => !ok)) {
      throw StateError('Connection protocol settings were not saved.');
    }
  }
}
