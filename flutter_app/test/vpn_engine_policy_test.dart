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

    test('does not rotate profiles for permission or platform failures', () {
      expect(shouldRetryConfigRejectedProfile('VpnPermissionDenied'), isFalse);
      expect(shouldRetryConfigRejectedProfile('Timeout'), isFalse);
      expect(shouldRetryConfigRejectedProfile('PlatformException:OTHER'), isFalse);
      expect(shouldRetryConfigRejectedProfile(null), isFalse);
    });
  });
}
