import 'package:flutter_test/flutter_test.dart';
import 'package:v2rayag_vpn/traffic_format.dart';

void main() {
  group('traffic formatting', () {
    test('formats bytes and rates with readable units', () {
      expect(formatByteCount(0), '0 B');
      expect(formatByteCount(1536), '1.5 KB');
      expect(formatByteCount(2 * 1024 * 1024), '2.0 MB');
      expect(formatByteRate(4096), '4.0 KB/s');
      expect(formatByteRate(-1), '0 B/s');
    });

    test('formats active duration without losing hours', () {
      expect(formatConnectionDuration(const Duration(seconds: 9)), '00:09');
      expect(formatConnectionDuration(const Duration(minutes: 4, seconds: 6)), '04:06');
      expect(formatConnectionDuration(const Duration(hours: 2, minutes: 3, seconds: 4)), '02:03:04');
      expect(formatConnectionDuration(const Duration(seconds: -1)), '00:00');
    });
  });
}
