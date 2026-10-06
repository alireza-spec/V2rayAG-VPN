import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:v2rayag_vpn/cdn_scanner.dart';

void main() {
  group('CdnEndpointScanner screenshot-domain preset', () {
    test('checks the screenshot domains while keeping the result reachability-only', () async {
      final probedSnis = <String>[];
      final scanner = CdnEndpointScanner(
        maxConcurrency: 8,
        lookup: (_) async => const <InternetAddress>[],
        probe: (address, sni, timeout) async {
          probedSnis.add(sni);
          return const CdnEndpointProbeResult(
            tcpConnectMs: 4,
            tlsHandshakeMs: 9,
          );
        },
      );

      final report = await scanner.scanSni(
        currentSni: 'user.example',
        cdnIps: '192.0.2.1',
      );

      expect(CdnEndpointScanner.screenshotDomainCandidates.length, greaterThan(150));
      expect(CdnEndpointScanner.screenshotDomainCandidates.toSet().length,
          CdnEndpointScanner.screenshotDomainCandidates.length);
      expect(CdnEndpointScanner.screenshotDomainCandidates,
          containsAll(['cloud.google.com', 'telegram.org', 'x.com', 'zoom.us']));
      expect(probedSnis, containsAll(CdnEndpointScanner.screenshotDomainCandidates));
      expect(probedSnis, contains('user.example'));
      expect(report.checked, probedSnis.length);
      expect(report.reachable, probedSnis.length);
      expect(report.candidates.map((candidate) => candidate.value),
          containsAll(CdnEndpointScanner.screenshotDomainCandidates));
    });

    test('cancels before probing domains', () async {
      var probeCalls = 0;
      final scanner = CdnEndpointScanner(
        lookup: (_) async => const <InternetAddress>[],
        probe: (address, sni, timeout) async {
          probeCalls++;
          return const CdnEndpointProbeResult(tcpConnectMs: 1, tlsHandshakeMs: 1);
        },
      );

      await expectLater(
        scanner.scanSni(
          cdnIps: '192.0.2.1',
          isCancelled: () => true,
        ),
        throwsA(isA<CdnScanCancelled>()),
      );
      expect(probeCalls, 0);
    });
  });
}
