import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vless/url/xray_config_validator.dart';
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

    test('extracts multiple links embedded in prose, emoji, and inline text', () {
      const payload = 'Copied routes ✅ number 7: '
          'vless://11111111-1111-4111-8111-111111111111@one.example:443?type=tcp&security=none#First, '
          'vmess://eyJhZGQiOiJ0d28uZXhhbXBsZSIsInBvcnQiOiI4NDQzIiwiaWQiOiJ4In0=.'
          ' extra text https://ordinary.example/page';
      final links = SubscriptionPayloadParser.extractShareLinks(payload);
      expect(links, hasLength(2));
      expect(links.first, startsWith('vless://'));
      expect(links.last, startsWith('vmess://'));
      expect(links.last, isNot(endsWith('.')));
    });

    test('deduplicates repeated links embedded in copied text', () {
      const link = 'vless://11111111-1111-4111-8111-111111111111@node.example:443?type=tcp&security=none#A';
      expect(SubscriptionPayloadParser.extractShareLinks('one $link two $link'), [link]);
    });

    test('decodes a base64 encoded provider response', () {
      const contents = 'trojan://secret@node.example:443#Tokyo\nss://YWVzLTEyOC1nY206cGFzcw@ss.example:8443#West';
      final payload = base64.encode(utf8.encode(contents));
      final links = SubscriptionPayloadParser.extractShareLinks(payload);
      expect(links, hasLength(2));
      expect(links.first, startsWith('trojan://'));
      expect(links.last, startsWith('ss://'));
    });

    test('recognizes additional flutter_vless share-link protocols in fallback parsing', () {
      const payload = '''
socks://proxy.example:1080#SOCKS
hysteria2://secret@hy.example:443#Hysteria
hy2://secret@hy2.example:443#Hy2
''';
      final links = SubscriptionPayloadParser.extractShareLinks(payload);
      expect(links, hasLength(3));
      expect(links.map((link) => link.split('://').first),
          containsAll(['socks', 'hysteria2', 'hy2']));
    });

    test('returns no links for empty or unsupported content', () {
      expect(SubscriptionPayloadParser.extractShareLinks(''), isEmpty);
      expect(SubscriptionPayloadParser.extractShareLinks('provider login page'), isEmpty);
      expect(SubscriptionPayloadParser.extractShareLinks('socks5://node.example:80'), isEmpty);
    });
  });

  group('SubscriptionService profile parsing', () {
    test('uses the maintained parser for a Base64 VLESS subscription payload', () {
      const link =
          'vless://11111111-1111-4111-8111-111111111111@node.example:443?type=tcp&security=none#Sample';
      final profiles = SubscriptionService.parsePayload(
        base64.encode(utf8.encode(link)),
      );

      expect(profiles, hasLength(1));
      expect(profiles.single.protocol, 'VLESS');
      expect(profiles.single.destination, 'node.example:443');
      final config = jsonDecode(profiles.single.config) as Map<String, dynamic>;
      expect(config['outbounds'], isNotEmpty);
    });

    test('parses all server links from mixed clipboard text', () {
      const payload = 'These are the routes 🛡️ 42: '
          'vless://11111111-1111-4111-8111-111111111111@one.example:443?type=tcp&security=none#One '
          'vmess://eyJhZGQiOiJ0d28uZXhhbXBsZSIsInBvcnQiOiI4NDQzIiwiaWQiOiIxMTExMTExMS0xMTExLTQxMTEtODExMS0xMTExMTExMTExMTEifQ== '
          'end of copied message';
      final profiles = SubscriptionService.parsePayload(payload);
      expect(profiles, hasLength(2));
      expect(profiles.map((profile) => profile.destination), containsAll(['one.example:443', 'two.example:8443']));
    });

    test('keeps valid share links when another subscription line is malformed', () {
      const payload = '''
vless://malformed
vless://11111111-1111-4111-8111-111111111111@node.example:443?type=tcp&security=none#GoodNode
''';
      final profiles = SubscriptionService.parsePayload(payload);
      expect(profiles.any((profile) => profile.name == 'GoodNode'), isTrue);
    });

    test('preserves host and path for a VLESS WebSocket profile', () {
      const link =
          'vless://11111111-1111-4111-8111-111111111111@edge.example:80?encryption=none&host=ws.example.net&path=%2F&security=none&type=ws#WebSocket';
      final profiles = SubscriptionService.parsePayload(link);

      expect(profiles, hasLength(1));
      final config = const XrayConfigValidator()
          .validateJsonString(profiles.single.config);
      final outbound = (config['outbounds'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((item) => item['protocol'] == 'vless');
      final stream = outbound['streamSettings'] as Map<String, dynamic>;
      expect(stream['network'], 'ws');
      final websocket = stream['wsSettings'] as Map<String, dynamic>;
      expect(websocket['path'], '/');
      final headers = websocket['headers'] as Map<String, dynamic>;
      expect(headers['Host'], 'ws.example.net');
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
