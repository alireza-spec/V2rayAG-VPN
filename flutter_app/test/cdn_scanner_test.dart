import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:v2rayag_vpn/cdn_scanner.dart';

void main() {
  group('CdnEndpointScanner', () {
    test('IP scan resolves candidates live and keeps TLS-reachable IPs', () async {
      var lookups = 0;
      final scanner = CdnEndpointScanner(
        maxConcurrency: 2,
        lookup: (_) async {
          lookups++;
          return [InternetAddress('192.0.2.10'), InternetAddress('192.0.2.11')];
        },
        probe: (address, sni, timeout) async =>
            sni == 'a248.e.akamai.net' ? (address.endsWith('.10') ? 45 : 82) : null,
      );
      final updates = <CdnScanProgress>[];

      final result = await scanner.scanIps(
        preferredSni: 'a248.e.akamai.net',
        onProgress: updates.add,
      );

      expect(lookups, 1);
      expect(result.checked, 2);
      expect(result.reachable, 2);
      expect(result.failed, 0);
      expect(result.candidates.map((candidate) => candidate.value),
          ['192.0.2.10', '192.0.2.11']);
      expect(updates.last.completed, 2);
      expect(updates.last.reachable, 2);
    });

    test('SNI scan checks names against current IPs and ranks by TLS delay', () async {
      final scanner = CdnEndpointScanner(
        lookup: (_) async => [InternetAddress('192.0.2.20')],
        probe: (_, sni, timeout) async => switch (sni) {
          'a77.net.akamai.net' => 31,
          'www.akamai.com' => 95,
          _ => null,
        },
      );

      final result = await scanner.scanSni(cdnIps: '192.0.2.20');

      expect(result.checked, CdnEndpointScanner.akamaiSniCandidates.length);
      expect(result.reachable, 2);
      expect(result.failed, 2);
      expect(result.candidates.first.value, 'a77.net.akamai.net');
      expect(result.candidates.last.value, 'www.akamai.com');
    });

    test('SNI scan rejects malformed entered IP lists before network probes', () async {
      var probed = false;
      final scanner = CdnEndpointScanner(
        lookup: (_) async => [InternetAddress('192.0.2.30')],
        probe: (_, __, ___) async {
          probed = true;
          return 10;
        },
      );

      await expectLater(
        scanner.scanSni(cdnIps: 'not-an-ip'),
        throwsA(isA<FormatException>()),
      );
      expect(probed, isFalse);
    });
  });
}
