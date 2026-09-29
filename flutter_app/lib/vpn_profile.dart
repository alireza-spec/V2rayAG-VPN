import 'package:flutter_vless/flutter_vless.dart';
import 'package:flutter_vless/url/xray_config_validator.dart';

import 'profile_parser.dart';

/// A server profile held only in app memory for the current run.
/// `config` contains credentials; never log, stringify, or persist it unencrypted.
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

  static VpnProfile fromShareLink(String input) =>
      fromParsed(FlutterVless.parse(ProfileParser.normalizeScheme(input)));

  /// Builds a runtime profile from the package's canonical parser output.
  /// This accepts all import formats understood by flutter_vless, including
  /// subscription JSON/YAML, while keeping the full config only in memory.
  static VpnProfile fromParsed(FlutterVlessURL parsed) {
    final config = parsed.getFullConfiguration();
    final decoded = const XrayConfigValidator().validateJsonString(config);
    if (decoded['outbounds'] is! List ||
        (decoded['outbounds'] as List).isEmpty) {
      throw const FormatException('The imported profile has no usable outbound.');
    }

    final rawProtocol =
        (parsed.outbound1['protocol'] ?? '').toString().trim().toLowerCase();
    final protocol = switch (rawProtocol) {
      'vless' => 'VLESS',
      'vmess' => 'VMess',
      'shadowsocks' => 'Shadowsocks',
      'trojan' => 'Trojan',
      'hysteria2' => 'Hysteria2',
      'wireguard' => 'WireGuard',
      'socks' => 'SOCKS',
      'http' => 'HTTP',
      '' => 'Imported',
      _ => rawProtocol.replaceAll(RegExp(r'[^a-z0-9_-]'), '').toUpperCase(),
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
