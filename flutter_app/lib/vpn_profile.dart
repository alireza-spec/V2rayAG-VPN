import 'package:flutter_vless/flutter_vless.dart';

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

  static VpnProfile fromShareLink(String input) {
    // The local parser extracts display-safe endpoint metadata only.
    final summary = ProfileParser.parse(input);
    // flutter_vless turns the single share URI into an Xray config for native
    // runtime use. The URI is not retained by this class.
    final parsed = FlutterVless.parse(ProfileParser.normalizeScheme(input));
    final config = parsed.getFullConfiguration();
    if (config.trim().isEmpty) {
      throw const FormatException('The server link did not produce a usable config.');
    }
    return VpnProfile(summary: summary, config: config);
  }
}
