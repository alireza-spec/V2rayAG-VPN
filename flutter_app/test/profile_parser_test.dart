import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:v2rayag_vpn/profile_parser.dart';

void main() {
  group('ProfileParser', () {
    test('extracts only destination metadata from VLESS', () {
      final profile = ProfileParser.parse(
        'vless://secret-user-id@example.org:443?security=tls#Amsterdam',
      );
      expect(profile.protocol, 'VLESS');
      expect(profile.destination, 'example.org:443');
      expect(profile.name, 'Amsterdam');
    });

    test('extracts metadata from a VMess share link', () {
      final payload = base64.encode(utf8.encode(jsonEncode({
        'add': 'vmess.example.net',
        'port': '8443',
        'ps': 'Test route',
        'id': 'secret-uuid',
      })));
      final profile = ProfileParser.parse('vmess://$payload');
      expect(profile.protocol, 'VMess');
      expect(profile.destination, 'vmess.example.net:8443');
      expect(profile.name, 'Test route');
      expect(profile.toString().contains('secret-uuid'), isFalse);
    });

    test('parses Trojan and Shadowsocks destinations', () {
      expect(ProfileParser.parse('trojan://secret@example.net:443#Paris').destination,
          'example.net:443');
      expect(ProfileParser.parse('ss://aes-256-gcm:secret@ss.example.net:8388#Tokyo').destination,
          'ss.example.net:8388');
    });

    test('rejects subscription URLs and malformed links', () {
      expect(() => ProfileParser.parse('https://provider.example/subscription'),
          throwsFormatException);
      expect(() => ProfileParser.parse('vless://missing-port'), throwsFormatException);
    });
  });
}
