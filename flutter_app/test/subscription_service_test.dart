import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:v2rayag_vpn/subscription_service.dart';

void main() {
  group('SubscriptionPayloadParser', () {
    test('keeps supported links from a newline-separated subscription', () {
      const payload = '''
# comment
vless://token@edge.example:443?security=tls#One
vmess://eyJhZGQiOiJub2RlLmV4YW1wbGUiLCJwb3J0IjoiNDQzIn0=
unsupported://ignored
''';
      final links = SubscriptionPayloadParser.extractShareLinks(payload);
      expect(links, hasLength(2));
      expect(links.first, startsWith('vless://'));
      expect(links.last, startsWith('vmess://'));
    });

    test('decodes a base64 encoded provider response', () {
      const contents = 'trojan://secret@node.example:443#Tokyo\nss://YWVzLTEyOC1nY206cGFzcw@ss.example:8443#West';
      final payload = base64.encode(utf8.encode(contents));
      final links = SubscriptionPayloadParser.extractShareLinks(payload);
      expect(links, hasLength(2));
      expect(links.first, startsWith('trojan://'));
      expect(links.last, startsWith('ss://'));
    });

    test('returns no links for empty or unsupported content', () {
      expect(SubscriptionPayloadParser.extractShareLinks(''), isEmpty);
      expect(SubscriptionPayloadParser.extractShareLinks('provider login page'), isEmpty);
      expect(SubscriptionPayloadParser.extractShareLinks('socks5://node.example:80'), isEmpty);
    });
  });

  group('SubscriptionService URL validation', () {
    test('accepts direct HTTPS URLs and preserves provider query tokens', () {
      final uri = SubscriptionService.validateSubscriptionUrl(
        ' https://subs.example/path?token=private-value ',
      );
      expect(uri.scheme, 'https');
      expect(uri.host, 'subs.example');
      expect(uri.query, 'token=private-value');
    });

    test('rejects HTTP and credential-bearing authorities', () {
      expect(() => SubscriptionService.validateSubscriptionUrl('http://subs.example/key'), throwsFormatException);
      expect(() => SubscriptionService.validateSubscriptionUrl('https://user:pass@subs.example/key'), throwsFormatException);
      expect(() => SubscriptionService.validateSubscriptionUrl('https://subs.example/key#fragment'), throwsFormatException);
    });
  });
}
