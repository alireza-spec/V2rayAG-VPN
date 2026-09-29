import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vless/flutter_vless.dart';
import 'package:v2rayag_vpn/vpn_profile.dart';

void main() {
  test('round-trips a saved profile config and metadata without changing route', () {
    final parsed = FlutterVless.parse(
      'vless://00000000-0000-4000-8000-000000000001@example.org:443?security=tls&type=tcp#Test%20route',
    );
    final original = VpnProfile.fromParsed(parsed);
    final restored = VpnProfile.fromJson(original.toJson());

    expect(restored.config, original.config);
    expect(restored.name, original.name);
    expect(restored.protocol, original.protocol);
    expect(restored.destination, original.destination);
  });
}
