import 'package:flutter_vless/flutter_vless.dart';
import 'package:flutter_vless/url/xray_config_validator.dart';

import 'profile_parser.dart';

/// A server profile. `config` contains credentials and may only be serialized
/// for storage through platform secure storage; never log or expose it.
class VpnProfile {
  const VpnProfile({
    required this.summary,
    required this.config,
  });

  final ParsedProfile summary;
  final String config;

  String get name => summary.name;
  String get protocol => summary.protocol;
  String get destination => summary.destination;

  /// Includes secret config data. Call only from the secure-storage repository.
  Map<String, Object> toJson() => {
        'config': config,
        'name': summary.name,
        'protocol': summary.protocol,
        'host': summary.host,
        'port': summary.port,
      };

  /// Restores an encrypted local profile and validates its Xray shape again.
  factory VpnProfile.fromJson(Map<String, dynamic> json) {
    final config = json['config'];
    if (config is! String || config.trim().isEmpty) {
      throw const FormatException('Saved profile has no configuration.');
    }
    final decoded = const XrayConfigValidator().validateJsonString(config);
    if (decoded['outbounds'] is! List ||
        (decoded['outbounds'] as List).isEmpty) {
      throw const FormatException('Saved profile has no usable outbound.');
    }
    final name = (json['name'] ?? '').toString().trim();
    final protocol = (json['protocol'] ?? '').toString().trim();
    final host = (json['host'] ?? '').toString().trim();
    final portValue = json['port'];
    final port = portValue is int ? portValue : int.tryParse('$portValue') ?? 0;
    return VpnProfile(
      summary: ParsedProfile(
        name: name.isEmpty ? 'Saved server' : name,
        protocol: protocol.isEmpty ? 'Imported' : protocol,
        host: host.isEmpty ? 'Saved configuration' : host,
        port: port >= 0 && port <= 65535 ? port : 0,
      ),
      config: config,
    );
  }

  static VpnProfile fromShareLink(String input) =>
      fromParsed(FlutterVless.parse(ProfileParser.normalizeScheme(input)));

  /// Builds a runtime profile from the package's canonical parser output.
  /// This accepts supported formats understood by flutter_vless; the full
  /// config must be persisted only through the encrypted profile repository.
  static VpnProfile fromParsed(FlutterVlessURL parsed) {
    final config = parsed.getFullConfiguration();
    final decoded = const XrayConfigValidator().validateJsonString(config);
    if (decoded['outbounds'] is! List ||
        (decoded['outbounds'] as List).isEmpty) {
      throw const FormatException('The imported profile has no usable outbound.');
    }

    final rawProtocol =
        (parsed.outbound1['protocol'] ?? '').toString().trim().toLowerCase();
    final sanitizedProtocol =
        rawProtocol.replaceAll(RegExp(r'[^a-z0-9_-]'), '').toUpperCase();
    final protocol = switch (rawProtocol) {
      'vless' => 'VLESS',
      'vmess' => 'VMess',
      'shadowsocks' => 'Shadowsocks',
      'trojan' => 'Trojan',
      'hysteria2' => 'Hysteria2',
      'wireguard' => 'WireGuard',
      'socks' => 'SOCKS',
      'http' => 'HTTP',
      _ => sanitizedProtocol.isEmpty ? 'Imported' : sanitizedProtocol,
    };
    final address = parsed.address.trim();
    final port = parsed.port >= 1 && parsed.port <= 65535 ? parsed.port : 0;
    final name = parsed.remark.trim();
    final summary = ParsedProfile(
      name: name.isEmpty ? '$protocol server' : name,
      protocol: protocol,
      host: address.isEmpty ? 'Imported configuration' : address,
      port: port,
    );
    return VpnProfile(summary: summary, config: config);
  }
}
