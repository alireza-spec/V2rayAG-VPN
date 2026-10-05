import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:v2rayag_vpn/cdn_fronting.dart';
import 'package:v2rayag_vpn/profile_parser.dart';
import 'package:v2rayag_vpn/vpn_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const config = '{"outbounds":[{"protocol":"vless","settings":{"vnext":[{"address":"origin.example.com","port":443,"users":[{"id":"test-id","encryption":"none"}]}]},"streamSettings":{"network":"ws","security":"tls","tlsSettings":{"serverName":"origin.example.com"},"wsSettings":{"path":"/tunnel","headers":{"Host":"origin.example.com"}}}}]}';

  VpnProfile profile([String value = config]) => VpnProfile(
        summary: const ParsedProfile(
          name: 'Test route',
          protocol: 'VLESS',
          host: 'origin.example.com',
          port: 443,
        ),
        config: value,
      );

  Map<String, dynamic> decoded(String value) =>
      jsonDecode(value) as Map<String, dynamic>;

  Map<String, dynamic> proxy(Map<String, dynamic> value) =>
      (value['outbounds'] as List).first as Map<String, dynamic>;

  group('CDN Fronting inputs', () {
    test('accepts ordered IPv4/IPv6 lists and normalizes duplicate entries', () {
      expect(
        CdnFrontingSettings.parseCdnIps('1.1.1.1, 2001:4860:4860::8888\n1.1.1.1'),
        ['1.1.1.1', '2001:4860:4860::8888'],
      );
    });

    test('accepts an optional DNS hostname and normalizes case', () {
      expect(
        CdnFrontingSettings.normalizeSniHostname(' Edge.Example.COM. '),
        'edge.example.com',
      );
      expect(CdnFrontingSettings.normalizeSniHostname(''), isNull);
    });

    test('rejects malformed IPs, URLs, ports, and IP literals as SNI', () {
      expect(() => CdnFrontingSettings.parseCdnIps('1.1.1.999'), throwsFormatException);
      expect(() => CdnFrontingSettings.normalizeSniHostname('https://edge.example.com'), throwsFormatException);
      expect(() => CdnFrontingSettings.normalizeSniHostname('edge.example.com:443'), throwsFormatException);
      expect(() => CdnFrontingSettings.normalizeSniHostname('1.1.1.1'), throwsFormatException);
    });
  });

  group('Xray CDN overrides', () {
    test('Auto and blank CDN settings return the original profile unchanged', () {
      final original = profile();
      expect(buildCdnProfileAttempts(original, const CdnFrontingSettings()).single,
          same(original));
      expect(
        buildCdnProfileAttempts(
          original,
          const CdnFrontingSettings(protocol: ConnectionProtocol.cdnFronting),
        ).single,
        same(original),
      );
      expect(applyCdnFrontingOverrides(config), config);
    });

    test('IP-only override keeps the original TLS identity and WebSocket Host', () {
      final result = decoded(applyCdnFrontingOverrides(config, cdnIp: '1.1.1.1'));
      final outbound = proxy(result);
      expect(((outbound['settings'] as Map)['vnext'] as List).first['address'], '1.1.1.1');
      final stream = outbound['streamSettings'] as Map;
      expect((stream['tlsSettings'] as Map)['serverName'], 'origin.example.com');
      expect(((stream['wsSettings'] as Map)['headers'] as Map)['Host'], 'origin.example.com');
    });

    test('SNI-only override leaves the server IP unchanged and updates TLS plus Host', () {
      final result = decoded(applyCdnFrontingOverrides(
        config,
        sniHostname: 'edge.example.net',
      ));
      final outbound = proxy(result);
      expect(((outbound['settings'] as Map)['vnext'] as List).first['address'], 'origin.example.com');
      final stream = outbound['streamSettings'] as Map;
      expect((stream['tlsSettings'] as Map)['serverName'], 'edge.example.net');
      expect(((stream['wsSettings'] as Map)['headers'] as Map)['Host'], 'edge.example.net');
    });

    test('each supplied CDN IP gets a separate automatic-pool attempt in order', () {
      final attempts = buildCdnProfileAttempts(
        profile(),
        const CdnFrontingSettings(
          protocol: ConnectionProtocol.cdnFronting,
          cdnIps: '1.1.1.1\n1.0.0.1',
          sniHostname: 'edge.example.net',
        ),
      );
      expect(attempts, hasLength(2));
      final addresses = attempts.map((attempt) {
        final outbound = proxy(decoded(attempt.config));
        return ((outbound['settings'] as Map)['vnext'] as List).first['address'];
      }).toList();
      expect(addresses, ['1.1.1.1', '1.0.0.1']);
    });

    test('supports VMess and Trojan TLS WebSocket outbounds', () {
      const vmess = '{"outbounds":[{"protocol":"vmess","settings":{"vnext":[{"address":"origin.example.com","port":443,"users":[]}]},"streamSettings":{"network":"ws","security":"tls","tlsSettings":{},"wsSettings":{"headers":{}}}}]}';
      const trojan = '{"outbounds":[{"protocol":"trojan","settings":{"servers":[{"address":"origin.example.com","port":443,"password":"synthetic"}]},"streamSettings":{"network":"ws","security":"tls","tlsSettings":{},"wsSettings":{"headers":{}}}}]}';
      for (final source in [vmess, trojan]) {
        final result = decoded(applyCdnFrontingOverrides(
          source,
          cdnIp: '2001:4860:4860::8888',
          sniHostname: 'edge.example.net',
        ));
        final outbound = proxy(result);
        final settings = outbound['settings'] as Map<String, dynamic>;
        final servers = (outbound['protocol'] == 'trojan'
            ? settings['servers']
            : settings['vnext']) as List;
        expect(servers.first['address'], '2001:4860:4860::8888');
        final stream = outbound['streamSettings'] as Map;
        expect((stream['tlsSettings'] as Map)['serverName'], 'edge.example.net');
        expect(((stream['wsSettings'] as Map)['headers'] as Map)['Host'], 'edge.example.net');
      }
    });

    test('rejects unsupported, ambiguous, malformed, and unidentifiable routes', () {
      final unsupported = config.replaceFirst('"network":"ws"', '"network":"tcp"');
      expect(
        () => applyCdnFrontingOverrides(unsupported, cdnIp: '1.1.1.1'),
        throwsA(isA<CdnProfileNotSupportedException>()),
      );
      expect(
        () => applyCdnFrontingOverrides('{"outbounds":[]} ', sniHostname: 'edge.example.net'),
        throwsA(isA<CdnProfileNotSupportedException>()),
      );
      expect(() => applyCdnFrontingOverrides('{invalid'), throwsFormatException);
      expect(() => applyCdnFrontingOverrides(
        '{"outbounds":[{"protocol":"vless","settings":{"vnext":[{"address":"1.1.1.1"}]},"streamSettings":{"network":"ws","security":"tls","wsSettings":{}}}]}',
        cdnIp: '1.0.0.1',
      ), throwsFormatException);
      final duplicateRoot = jsonDecode(config) as Map<String, dynamic>;
      (duplicateRoot['outbounds'] as List).add({
        'protocol': 'vmess',
        'settings': {'vnext': [{'address': 'other.example.com'}]},
        'streamSettings': {'network': 'ws', 'security': 'tls', 'wsSettings': {}},
      });
      final duplicate = jsonEncode(duplicateRoot);
      expect(
        () => applyCdnFrontingOverrides(duplicate, sniHostname: 'edge.example.net'),
        throwsA(isA<CdnProfileNotSupportedException>()),
      );
    });
  });

  test('persists protocol and optional CDN values, including empty values', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = CdnFrontingPreferencesRepository();
    const blankCdn = CdnFrontingSettings(protocol: ConnectionProtocol.cdnFronting);
    await repository.save(blankCdn);
    expect((await repository.read()).protocol, ConnectionProtocol.cdnFronting);
    expect((await repository.read()).hasOverrides, isFalse);

    const configured = CdnFrontingSettings(
      protocol: ConnectionProtocol.cdnFronting,
      cdnIps: '1.1.1.1\n1.0.0.1',
      sniHostname: 'edge.example.net',
    );
    await repository.save(configured);
    final restored = await repository.read();
    expect(restored.protocol, ConnectionProtocol.cdnFronting);
    expect(restored.parsedIps, ['1.1.1.1', '1.0.0.1']);
    expect(restored.normalizedSniHostname, 'edge.example.net');

    await repository.save(restored.withProtocol(ConnectionProtocol.auto));
    final automatic = await repository.read();
    expect(automatic.protocol, ConnectionProtocol.auto);
    expect(automatic.parsedIps, ['1.1.1.1', '1.0.0.1']);
    expect(automatic.normalizedSniHostname, 'edge.example.net');
  });
}
