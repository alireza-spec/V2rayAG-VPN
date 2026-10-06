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
    expect(localizations.text('Connection protocol'), 'پروتکل اتصال');
    expect(
      localizations.text('Stop the current connection attempt before changing protocol.'),
      'برای تغییر پروتکل، ابتدا تلاش اتصال فعلی را متوقف کنید.',
    );
    expect(localizations.text('Empty CDN fields keep CDN selected, but this build has no independent Meek engine.'),
        'کادرهای خالی حالت CDN را حفظ می‌کنند، اما این نسخه موتور مستقل Meek ندارد.');
    expect(localizations.text('CDN Fronting'), 'عبور از CDN');
    expect(localizations.text('CDN IPs'), 'IPهای CDN');
    expect(localizations.text('CDN SNI hostname'), 'نام میزبان SNI در CDN');
    expect(localizations.text('TCP open'), 'اتصال TCP برقرار است');
    expect(localizations.text('TLS OK'), 'TLS برقرار است');
    expect(localizations.text('V2rayAG logo'), 'لوگوی V2rayAG');
    expect(localizations.text('Terms & security'), 'شرایط استفاده و امنیت');
    expect(localizations.text('Join Telegram channel'), 'پیوستن به کانال تلگرام');
    expect(
      localizations.text('Added 3 server profiles and saved them securely.'),
      '3 پروفایل سرور به‌شکل امن ذخیره شد.',
    );
    expect(
      localizations.text('Loaded and saved 12 profiles for My Europe subscription.'),
      '12 پروفایل برای اشتراک «My Europe subscription» دریافت و ذخیره شد.',
    );
    expect(
      localizations.text('Profiles could not be saved securely (SecureStorageError); changes remain only until this app closes.'),
      'ذخیرهٔ امن پروفایل‌ها ممکن نشد (SecureStorageError). تغییرات فقط تا زمان بسته‌شدن برنامه باقی می‌مانند.',
    );
    expect(localizations.text('PERSONAL'), 'شخصی');
    expect(localizations.text('Remove profiles without ping (3)'),
        'حذف پروفایل‌های بدون نتیجهٔ پینگ (3)');
    expect(
      localizations.text('This will remove 3 profiles from this device. A missing ping result does not prove that a server is offline or cannot connect.'),
      'این کار 3 پروفایل را از این دستگاه حذف می‌کند. نداشتن نتیجهٔ پینگ ثابت نمی‌کند سرور قطع است یا امکان اتصال ندارد.',
    );
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
