import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_localizations.dart';

void main() {
  test('English remains the source-string fallback', () {
    const localizations = V2rayLocalizations(Locale('en'));
    expect(localizations.text('Settings'), 'Settings');
    expect(localizations.text('A server not yet translated'), 'A server not yet translated');
  });

  test('Persian translates UI text and preserves server data', () {
    const localizations = V2rayLocalizations(Locale('fa'));
    expect(localizations.text('Settings'), 'تنظیمات');
    expect(localizations.text('Loaded 12 server profiles into app memory.'),
        '12 نمایهٔ سرور در حافظهٔ برنامه بارگذاری شد.');
    expect(
      localizations.text('VLESS · example.net:443\nCountry not looked up · ready'),
      'VLESS · example.net:443\nکشور بررسی نشده · آماده',
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
