import 'package:flutter_test/flutter_test.dart';
import 'package:v2rayag_vpn/main.dart';

void main() {
  group('VPN power control policy', () {
    test('allows stopping an active native session without a restored profile', () {
      expect(
        canToggleVpnAction(
          hasProfile: false,
          activeOrPending: true,
          subscriptionBusy: false,
          engineBusy: false,
          canStart: false,
        ),
        isTrue,
      );
    });

    test('does not allow starting without a profile', () {
      expect(
        canToggleVpnAction(
          hasProfile: false,
          activeOrPending: false,
          subscriptionBusy: false,
          engineBusy: false,
          canStart: true,
        ),
        isFalse,
      );
    });

    test('allows starting only when a profile exists and engine is ready', () {
      expect(
        canToggleVpnAction(
          hasProfile: true,
          activeOrPending: false,
          subscriptionBusy: false,
          engineBusy: false,
          canStart: true,
        ),
        isTrue,
      );
      expect(
        canToggleVpnAction(
          hasProfile: true,
          activeOrPending: false,
          subscriptionBusy: false,
          engineBusy: true,
          canStart: true,
        ),
        isFalse,
      );
    });
  });
}
