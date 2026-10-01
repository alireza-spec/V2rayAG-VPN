import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:v2rayag_vpn/exclusive_pool_service.dart';

void main() {
  group('ExclusivePoolService', () {
    const validUri =
        'vless://11111111-1111-4111-8111-111111111111@node.example:443?type=tcp&security=none#Node-A';
    const leaseId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

    test('parses one bounded lease and subscription usage metadata', () {
      final lease = ExclusivePoolService.parseLease({
        'success': true,
        'leaseId': leaseId,
        'candidate': {
          'id': '0123456789abcdef01234567',
          'uri': validUri,
          'subscriptionName': 'Sub 0001',
          'quotaKnown': true,
          'upload': 1024,
          'download': 2048,
          'total': 8192,
          'expiresAt': (DateTime.now()
                      .add(const Duration(days: 5))
                      .millisecondsSinceEpoch /
                  1000)
              .floor(),
        },
      });

      final candidate = lease.candidate;
      expect(lease.leaseId, leaseId);
      expect(candidate.id, '0123456789abcdef01234567');
      expect(candidate.subscriptionName, 'Sub 0001');
      expect(candidate.configurationName, 'Node-A');
      expect(candidate.remainingBytes, 5120);
      expect(candidate.daysUntilExpiry, greaterThanOrEqualTo(4));
      expect(candidate.daysUntilExpiry, lessThanOrEqualTo(5));

      final restored = PoolConnectionSummary.fromJson(
        jsonDecode(jsonEncode(candidate.summary.toJson())) as Map<String, dynamic>,
      );
      expect(restored.subscriptionName, 'Sub 0001');
      expect(restored.configurationName, 'Node-A');
      expect(restored.remainingBytes, 5120);
      expect(restored.toJson().containsKey('leaseId'), isFalse);
    });

    test('does not invent quota or expiry when provider omits them', () {
      final candidate = ExclusivePoolService.parseLease({
        'success': true,
        'leaseId': leaseId,
        'candidate': {
          'id': '0123456789abcdef01234567',
          'uri': validUri,
          'subscriptionName': 'Sub 2',
          'quotaKnown': false,
        },
      }).candidate;

      expect(candidate.remainingBytes, isNull);
      expect(candidate.daysUntilExpiry, isNull);
      expect(candidate.unlimitedQuota, isFalse);
    });

    test('surfaces the access service refusal instead of a misleading generic error', () {
      expect(
        () => ExclusivePoolService.parseEnrollmentToken({
          'success': false,
          'error': 'Too many new app setups from this network today.',
        }),
        throwsA(isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('Too many new app setups'),
        )),
      );
    });

    test('identifies malformed enrollment responses clearly', () {
      expect(
        () => ExclusivePoolService.parseEnrollmentToken({'success': false}),
        throwsA(isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('rejected setup'),
        )),
      );
    });

    test('rejects invalid device access keys before secure storage writes', () async {
      final service = ExclusivePoolService();
      await expectLater(
        service.saveDeviceAccessToken('not-a-device-key'),
        throwsFormatException,
      );
      service.dispose();
    });

    test('accepts only a valid automatically issued device token', () {
      expect(
        ExclusivePoolService.parseEnrollmentToken({
          'success': true,
          'token': 'b' * 64,
        }),
        'b' * 64,
      );
      expect(
        () => ExclusivePoolService.parseEnrollmentToken({'success': false}),
        throwsFormatException,
      );
      expect(
        () => ExclusivePoolService.parseEnrollmentToken({
          'success': true,
          'token': 'short',
        }),
        throwsFormatException,
      );
    });

    test('rejects malformed leases and profiles', () {
      expect(
        () => ExclusivePoolService.parseLease({'success': false}),
        throwsFormatException,
      );
      expect(
        () => ExclusivePoolService.parseLease({
          'success': true,
          'leaseId': leaseId,
          'candidate': {
            'id': 'bad-id',
            'uri': validUri,
          },
        }),
        throwsFormatException,
      );
      expect(
        () => ExclusivePoolService.parseLease({
          'success': true,
          'leaseId': 'short',
          'candidate': {
            'id': '0123456789abcdef01234567',
            'uri': validUri,
          },
        }),
        throwsFormatException,
      );
    });
  });
}
