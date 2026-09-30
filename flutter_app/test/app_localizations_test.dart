import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:v2rayag_vpn/app_localizations.dart';

void main() {
  test('English remains the source-string fallback', () {
    const localizations = V2rayLocalizations(Locale('en'));
    expect(localizations.text('Settings'), 'Settings');
    expect(localizations.text('A server not yet translated'), 'A server not yet translated');
  });

  test('Persian translates UI text and preserves server data', () {
    const localizations = V2rayLocalizations(Locale('fa'));
    expect(localizations.text('Settings'), 'تنظیمات');
    expect(localizations.text('2 apps excluded from VPN'), '2 برنامه از VPN مستثنا شده‌اند');
    expect(localizations.text('Loaded 12 server profiles into app memory.'),
        '12 نمایهٔ سرور در حافظهٔ برنامه بارگذاری شد.');
    expect(
      localizations.text('VLESS · example.net:443\nCountry not looked up · ready'),
      'VLESS · example.net:443\nکشور بررسی نشده · آماده',
    );
  });

  test('Persian explains that a latency timeout does not prove a server is down', () {
    const localizations = V2rayLocalizations(Locale('fa'));
    expect(
      localizations.text('Latency probe unavailable'),
      'آزمون تأخیر نتیجه نداد',
    );
    expect(
      localizations.text('This does not prove the server is offline'),
      'این به‌تنهایی آفلاین بودن سرور را ثابت نمی‌کند',
    );
    expect(localizations.text('Test all server latencies'), 'آزمایش تأخیر همهٔ سرورها');
  });

  test('Persian explains persistent encrypted storage and batch progress', () {
    const localizations = V2rayLocalizations(Locale('fa'));
    expect(localizations.text('Testing latencies'), 'در حال سنجش تأخیر سرورها');
    expect(localizations.text('Secure storage unavailable'), 'فضای امن در دسترس نیست');
    expect(
      localizations.text('Secure storage status'),
      'وضعیت فضای امن',
    );
    expect(
      localizations.text('Some older encrypted profile data remains untouched but cannot be read on this device. New profiles can be saved separately.'),
      'برخی داده‌های رمزگذاری‌شدهٔ پروفایل قدیمی دست‌نخورده مانده اما در این دستگاه خوانده نمی‌شود. پروفایل‌های جدید جداگانه ذخیره می‌شوند.',
    );
  });

  testWidgets('Persian delegate provides RTL directionality', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('fa'),
        supportedLocales: V2rayLocalizations.supportedLocales,
        localizationsDelegates: V2rayLocalizations.localizationsDelegates,
        home: Scaffold(body: LocalizedText('Settings')),
      ),
    );

    expect(Directionality.of(tester.element(find.byType(LocalizedText))),
        TextDirection.rtl);
    expect(find.text('تنظیمات'), findsOneWidget);
  });
}
