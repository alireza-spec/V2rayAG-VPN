import 'package:flutter_test/flutter_test.dart';
import 'package:v2rayag_vpn/vpn_engine.dart';

void main() {
  group('subscription automatic failover policy', () {
    test('retries only profile-specific configuration rejections', () {
      expect(shouldRetryConfigRejectedProfile('InvalidConfiguration'), isTrue);
      expect(
        shouldRetryConfigRejectedProfile('PlatformException:INVALID_CONFIG'),
        isTrue,
      );
    });

    test('retries a rejected or safely failed individual subscription node', () {
      expect(shouldRetrySubscriptionProfile('InvalidConfiguration'), isTrue);
      expect(shouldRetrySubscriptionProfile('PlatformException:INVALID_CONFIG'), isTrue);
      expect(shouldRetrySubscriptionProfile('TunnelDisconnected'), isTrue);
      expect(shouldRetrySubscriptionProfile('ConnectTimeout'), isTrue);
      // Third-party HTTP probe failure is not evidence that the native tunnel
      // failed, so it must never rotate the selected profile.
      expect(shouldRetrySubscriptionProfile('RouteHealthCheckFailed'), isFalse);
    });

    test('does not rotate for permission, unresolved cleanup, or generic platform failures', () {
      expect(shouldRetrySubscriptionProfile('VpnPermissionDenied'), isFalse);
      expect(shouldRetrySubscriptionProfile('TunnelResetFailed'), isFalse);
      expect(shouldRetrySubscriptionProfile('PlatformException:OTHER'), isFalse);
      expect(shouldRetrySubscriptionProfile(null), isFalse);
      expect(shouldRetryConfigRejectedProfile('Timeout'), isFalse);
    });
  });

  group('automatic pool latency ranking', () {
    test('prefers lower measured delay and leaves inconclusive probes last', () {
      final values = <int?>[null, 92, 48, null, 310];
      values.sort(compareMeasuredLatency);
      expect(values, <int?>[48, 92, 310, null, null]);
    });

    test('does not pretend an inconclusive probe is a zero-millisecond route', () {
      expect(compareMeasuredLatency(null, 1), greaterThan(0));
      expect(compareMeasuredLatency(0, null), lessThan(0));
    });
  });
}
