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
}
