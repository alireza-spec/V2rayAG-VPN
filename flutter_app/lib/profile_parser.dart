import 'dart:convert';

/// Safe display metadata extracted from a single server share link.
/// Credentials and the original URI are intentionally not retained.
class ParsedProfile {
  const ParsedProfile({
    required this.name,
    required this.protocol,
    required this.host,
    required this.port,
  });

  final String name;
  final String protocol;
  final String host;
  final int port;

  String get destination => host.contains(':') ? '[$host]:$port' : '$host:$port';
}

/// Parses one supported server share URI into non-secret display metadata.
/// This does not fetch subscription URLs, persist credentials, or connect a tunnel.
class ProfileParser {
  static const _supported = {'vless', 'vmess', 'ss', 'trojan'};

  static ParsedProfile parse(String rawInput) {
    final input = rawInput.trim();
    final scheme = input.split('://').first.toLowerCase();
    if (!_supported.contains(scheme) || !input.startsWith('$scheme://')) {
      throw const FormatException(
        'Paste one VLESS, VMess, Shadowsocks, or Trojan server link.',
      );
    }

    return switch (scheme) {
      'vmess' => _parseVmess(input),
      'ss' => _parseShadowsocks(input),
      'vless' || 'trojan' => _parseUri(input, scheme.toUpperCase()),
      _ => throw const FormatException('Unsupported server link.'),
    };
  }

  static ParsedProfile _parseUri(String input, String protocol) {
    final uri = Uri.tryParse(input);
    if (uri == null || uri.host.isEmpty) {
      throw const FormatException('The server address is not valid.');
    }
    return _profile(
      protocol: protocol,
      host: uri.host,
      port: uri.port,
      name: _fragmentName(uri.fragment, protocol),
    );
  }

  static ParsedProfile _parseVmess(String input) {
    final encoded = input.substring('vmess://'.length).split('#').first;
    try {
      final jsonText = utf8.decode(_decodeBase64(encoded));
      final data = jsonDecode(jsonText);
      if (data is! Map<String, dynamic>) {
        throw const FormatException();
      }
      final host = (data['add'] ?? data['host'] ?? '').toString();
      final port = int.tryParse((data['port'] ?? '').toString());
      final name = (data['ps'] ?? 'VMess server').toString();
      return _profile(
        protocol: 'VMess',
        host: host,
        port: port ?? 0,
        name: name,
      );
    } on FormatException {
      throw const FormatException('The VMess link could not be decoded.');
    } on Object {
      throw const FormatException('The VMess link could not be decoded.');
    }
  }

  static ParsedProfile _parseShadowsocks(String input) {
    final withoutScheme = input.substring('ss://'.length);
    final hashAt = withoutScheme.indexOf('#');
    final beforeFragment = hashAt < 0
        ? withoutScheme
        : withoutScheme.substring(0, hashAt);
    final fragment = hashAt < 0 ? '' : withoutScheme.substring(hashAt + 1);
    final at = beforeFragment.lastIndexOf('@');

    String authority;
    if (at >= 0) {
      authority = beforeFragment.substring(at + 1);
    } else {
      // SIP002 form: the entire method:password@host:port part is Base64.
      final decoded = utf8.decode(_decodeBase64(beforeFragment));
      final decodedAt = decoded.lastIndexOf('@');
      if (decodedAt < 0) {
        throw const FormatException('The Shadowsocks link is not valid.');
      }
      authority = decoded.substring(decodedAt + 1);
    }

    final endpoint = Uri.tryParse('ss://$authority');
    if (endpoint == null || endpoint.host.isEmpty) {
      throw const FormatException('The Shadowsocks server address is not valid.');
    }
    return _profile(
      protocol: 'Shadowsocks',
      host: endpoint.host,
      port: endpoint.port,
      name: _fragmentName(fragment, 'Shadowsocks server'),
    );
  }

  static ParsedProfile _profile({
    required String protocol,
    required String host,
    required int port,
    required String name,
  }) {
    final cleanHost = host.trim();
    if (cleanHost.isEmpty || port < 1 || port > 65535) {
      throw const FormatException('The server link is missing a valid host or port.');
    }
    return ParsedProfile(
      name: name.trim().isEmpty ? '$protocol server' : name.trim(),
      protocol: protocol,
      host: cleanHost,
      port: port,
    );
  }

  static String _fragmentName(String value, String fallback) {
    if (value.isEmpty) return fallback;
    try {
      return Uri.decodeComponent(value);
    } on FormatException {
      return fallback;
    }
  }

  static List<int> _decodeBase64(String value) {
    var normalized = value.replaceAll('-', '+').replaceAll('_', '/');
    normalized += List<String>.filled((4 - normalized.length % 4) % 4, '=').join();
    return base64.decode(normalized);
  }
}
