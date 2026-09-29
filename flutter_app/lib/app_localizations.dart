import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// Small, app-owned localization layer for English and Persian UI copy.
/// English is deliberately the fallback for missing translations.
class V2rayLocalizations {
  const V2rayLocalizations(this.locale);

  final Locale locale;
  bool get isPersian => locale.languageCode == 'fa';

  static const supportedLocales = <Locale>[
    Locale('en'),
    Locale('fa'),
  ];

  static const localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    V2rayLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];

  static V2rayLocalizations of(BuildContext context) =>
      Localizations.of<V2rayLocalizations>(context, V2rayLocalizations)!;

  String text(String source) {
    if (!isPersian) return source;
    return _persian[source] ?? _translateDynamic(source);
  }

  String _translateDynamic(String source) {
    // Preserve dynamic server data and protocol names while translating the
    // surrounding fixed UI copy.
    final loaded = RegExp(r'^Loaded (\d+) server profiles into app memory\.$')
        .firstMatch(source);
    if (loaded != null) {
      return '${loaded.group(1)} نمایهٔ سرور در حافظهٔ برنامه بارگذاری شد.';
    }
    final measured = RegExp(r'^Measured route latency: (\d+) ms$')
        .firstMatch(source);
    if (measured != null) {
      return 'تأخیر مسیر اندازه‌گیری‌شده: ${measured.group(1)} ms';
    }
    final profileLine = source.split('\n');
    if (profileLine.length == 2 &&
        profileLine[1].startsWith('Country not looked up · ')) {
      final separator = profileLine[0].indexOf(' · ');
      if (separator >= 0) {
        final protocol = profileLine[0].substring(0, separator);
        final destination = profileLine[0].substring(separator + 3);
        final routeState = profileLine[1].substring('Country not looked up · '.length);
        final translatedDestination = text(destination);
        final translatedState = text(routeState);
        return '$protocol · $translatedDestination\nکشور بررسی نشده · $translatedState';
      }
    }
    return source;
  }

  static const Map<String, String> _persian = {
    'PRIVATE ROUTE': 'مسیر خصوصی',
    'CONNECTED': 'متصل',
    'CONNECTING': 'در حال اتصال',
    'DISCONNECTING': 'در حال قطع اتصال',
    'NOT CONNECTED': 'متصل نیست',
    'STATUS UNKNOWN': 'وضعیت نامشخص',
    'Connect': 'اتصال',
    'Your quiet corner of the internet.': 'گوشه‌ای آرام از اینترنت، برای شما.',
    'A clean route, on your terms.': 'مسیری امن و مطابق خواستهٔ شما.',
    'Import a server before connecting': 'پیش از اتصال، یک سرور وارد کنید',
    'Protected route active on this Android device': 'مسیر امن روی این دستگاه Android فعال است',
    'Waiting for the Android tunnel status…': 'در انتظار وضعیت تونل Android…',
    'Waiting for Android to confirm disconnect…': 'در انتظار تأیید قطع اتصال از Android…',
    'Waiting for a verified VPN status before starting.': 'برای شروع، در انتظار تأیید وضعیت VPN هستیم.',
    'Tap to request Android VPN permission': 'برای درخواست مجوز VPN در Android ضربه بزنید',
    'Preparing Android VPN engine…': 'در حال آماده‌سازی موتور VPN در Android…',
    'Exclusive V2rayAG Subs': 'اشتراک اختصاصی V2rayAG',
    'Saved securely on this device': 'به‌صورت امن در این دستگاه ذخیره شده است',
    'Add your private URL once for one-tap connect': 'نشانی خصوصی خود را یک‌بار اضافه کنید تا با یک ضربه وصل شوید',
    'Loading subscription…': 'در حال بارگذاری اشتراک…',
    'Connect to Exclusive Subs': 'اتصال به اشتراک اختصاصی',
    'Set up & connect': 'راه‌اندازی و اتصال',
    'DESTINATION': 'مقصد',
    'NO SERVER': 'بدون سرور',
    'Add a server link': 'افزودن پیوند سرور',
    'Destination hidden': 'مقصد پنهان است',
    'No client address is read or displayed.': 'نشانی دستگاه شما خوانده یا نمایش داده نمی‌شود.',
    'Country: not looked up': 'کشور: بررسی نشده',
    'Country not looked up': 'کشور بررسی نشده',
    'connected': 'متصل',
    'ready': 'آماده',
    'Live traffic stats appear after a real connection.': 'آمار زندهٔ ترافیک پس از اتصال واقعی نمایش داده می‌شود.',
    'Test latency': 'آزمایش تأخیر',
    'Import server': 'وارد کردن سرور',
    'View servers': 'نمایش سرورها',
    'Subscription URLs are encrypted in Android secure storage and never committed to GitHub. Imported server configs stay in app memory. The app never reads or displays your device IP.': 'نشانی‌های اشتراک در فضای امن Android رمزگذاری می‌شوند و هرگز در GitHub ثبت نمی‌شوند. پیکربندی سرورهای واردشده فقط در حافظهٔ برنامه می‌ماند. برنامه نشانی IP دستگاه شما را نمی‌خواند یا نمایش نمی‌دهد.',
    'Source: Telegram @V2rayAG  ·  Developer: HashtagAlireza': 'منبع: تلگرام @V2rayAG  ·  توسعه‌دهنده: HashtagAlireza',
    'Servers': 'سرورها',
    'Add your subscription, refresh servers, and choose a route.': 'اشتراک خود را اضافه کنید، سرورها را تازه‌سازی کنید و یک مسیر انتخاب کنید.',
    'Enter your private subscription URL once.': 'نشانی خصوصی اشتراک خود را یک‌بار وارد کنید.',
    'Saved securely on this device.': 'به‌صورت امن در این دستگاه ذخیره شده است.',
    'Fetching servers…': 'در حال دریافت سرورها…',
    'One-tap connect': 'اتصال با یک ضربه',
    'Change URL': 'تغییر نشانی',
    'My subscriptions': 'اشتراک‌های من',
    'Add': 'افزودن',
    'Paste a secure HTTPS URL or scan its QR code. URLs are stored on this device only.': 'نشانی امن HTTPS را جای‌گذاری یا QR آن را اسکن کنید. نشانی‌ها فقط در این دستگاه ذخیره می‌شوند.',
    'Private URL stored on this device': 'نشانی خصوصی در این دستگاه ذخیره شده است',
    'Refresh servers': 'تازه‌سازی سرورها',
    'Edit subscription': 'ویرایش اشتراک',
    'Remove subscription': 'حذف اشتراک',
    'Import one server link': 'وارد کردن یک پیوند سرور',
    'Remove profile': 'حذف نمایه',
    'Profile configs exist only in app memory during this session. Do not share screenshots or logs that reveal a server address.': 'پیکربندی نمایه‌ها فقط در حافظهٔ برنامه و در طول این نشست نگهداری می‌شود. تصویر صفحه یا گزارش‌هایی را که نشانی سرور را آشکار می‌کنند به‌اشتراک نگذارید.',
    'Your server list is empty': 'فهرست سرورهای شما خالی است',
    'Import a single VLESS, VMess, Shadowsocks, or Trojan server link to prepare an Android VPN route.': 'برای آماده‌سازی مسیر VPN در Android، یک پیوند سرور VLESS، VMess، Shadowsocks یا Trojan وارد کنید.',
    'Settings': 'تنظیمات',
    'Appearance settings work now; Android VPN connection is managed from Connect.': 'تنظیمات ظاهری در دسترس‌اند؛ اتصال VPN در Android از بخش اتصال مدیریت می‌شود.',
    'Dark appearance': 'نمایش تیره',
    'Change the app theme': 'تغییر پوستهٔ برنامه',
    'Reduce animations': 'کاهش پویانمایی‌ها',
    'Reduce decorative motion': 'کاهش حرکت‌های تزئینی',
    'Show destination address': 'نمایش نشانی مقصد',
    'Hides the server address in the UI': 'نشانی سرور را در برنامه پنهان می‌کند',
    'App language': 'زبان برنامه',
    'Choose the language used throughout the app': 'زبان مورد استفاده در سراسر برنامه را انتخاب کنید',
    'English': 'English',
    'فارسی': 'فارسی',
    'Platform scope': 'محدودهٔ پشتیبانی پلتفرم',
    'The Android tunnel uses the native Xray-backed VPN service. iPhone still needs its Network Extension project, Apple signing, and device testing. DNS policy, kill switch, auto-connect, and trusted country lookup are not enabled in this build.': 'تونل Android از سرویس VPN بومی مبتنی بر Xray استفاده می‌کند. نسخهٔ iPhone هنوز به پروژهٔ Network Extension، امضای Apple و آزمایش روی دستگاه نیاز دارد. سیاست DNS، قطع اضطراری اتصال (kill switch)، اتصال خودکار و بررسی معتبر کشور در این نسخه فعال نیستند.',
    'V2rayAG VPN': 'V2rayAG VPN',
    'Source: Telegram @V2rayAG\nDeveloper: V2rayAG telegram channel and HashtagAlireza': 'منبع: تلگرام @V2rayAG\nتوسعه‌دهنده: کانال تلگرام V2rayAG و HashtagAlireza',
    'Clipboard is empty.': 'حافظهٔ موقت خالی است.',
    'Could not read the clipboard.': 'خواندن حافظهٔ موقت ممکن نشد.',
    'Scan a subscription QR': 'اسکن QR اشتراک',
    'Keep the QR code inside the frame. Its contents stay on this device.': 'کد QR را داخل قاب نگه دارید. محتوای آن فقط در این دستگاه می‌ماند.',
    'Set up Exclusive V2rayAG Subs': 'راه‌اندازی اشتراک اختصاصی V2rayAG',
    'Add a subscription': 'افزودن اشتراک',
    'Paste or scan your provider’s HTTPS subscription URL. Your own URL is needed; none is bundled with this app.': 'نشانی اشتراک HTTPS ارائه‌دهندهٔ خود را جای‌گذاری یا اسکن کنید. باید نشانی خودتان را وارد کنید؛ هیچ نشانی‌ای همراه این برنامه ارائه نشده است.',
    'Name': 'نام',
    'Private HTTPS subscription URL': 'نشانی خصوصی اشتراک HTTPS',
    'https://…': 'https://…',
    'Show URL': 'نمایش نشانی',
    'Hide URL': 'پنهان کردن نشانی',
    'Paste clipboard': 'جای‌گذاری از حافظهٔ موقت',
    'Scan QR': 'اسکن QR',
    'Saved with Android Keystore-backed encrypted storage. Fetching requires HTTPS; server entries stay in memory and are not uploaded to V2rayAG.': 'اطلاعات با فضای ذخیره‌سازی رمزگذاری‌شده و متکی به Android Keystore ذخیره می‌شوند. دریافت به HTTPS نیاز دارد؛ ورودی‌های سرور فقط در حافظه می‌مانند و به V2rayAG بارگذاری نمی‌شوند.',
    'Save securely': 'ذخیرهٔ امن',
    'Import a server link': 'وارد کردن پیوند سرور',
    'One server link: VLESS, VMess, Shadowsocks, or Trojan.': 'یک پیوند سرور: VLESS، VMess، Shadowsocks یا Trojan.',
    'Paste one server share link': 'یک پیوند اشتراک‌گذاری سرور جای‌گذاری کنید',
    'A single server link is held in app memory for this session only. Use Add subscription for a provider URL.': 'یک پیوند سرور فقط در حافظهٔ برنامه و در طول این نشست نگهداری می‌شود. برای نشانی ارائه‌دهنده از «افزودن اشتراک» استفاده کنید.',
    'Add to this session': 'افزودن به این نشست',

    // Connection/status and validation messages surfaced by the UI.
    'Import a server link first.': 'ابتدا یک پیوند سرور وارد کنید.',
    'Secure subscription storage is unavailable on this device.': 'فضای ذخیره‌سازی امن اشتراک در این دستگاه در دسترس نیست.',
    'Server profile added to this session memory.': 'نمایهٔ سرور به حافظهٔ این نشست افزوده شد.',
    'Fetching subscription securely…': 'در حال دریافت امن اشتراک…',
    'Android tunnel was not ready to start. Try again after status is available.': 'تونل Android برای شروع آماده نبود. پس از نمایش وضعیت دوباره تلاش کنید.',
    'Disconnect before changing the active server.': 'پیش از تغییر سرور فعال، اتصال را قطع کنید.',
    'Disconnect before importing another server.': 'پیش از وارد کردن سرور دیگر، اتصال را قطع کنید.',
    'Disconnect before importing another active route.': 'پیش از وارد کردن مسیر فعال دیگر، اتصال را قطع کنید.',
    'Disconnect before refreshing subscriptions.': 'پیش از تازه‌سازی اشتراک‌ها، اتصال را قطع کنید.',
    'Disconnect before removing the active server.': 'پیش از حذف سرور فعال، اتصال را قطع کنید.',
    'Disconnect before changing subscriptions.': 'پیش از تغییر اشتراک‌ها، اتصال را قطع کنید.',
    'Disconnect the current route with the power button before switching subscriptions.': 'پیش از جابه‌جایی بین اشتراک‌ها، مسیر فعلی را با دکمهٔ روشن/خاموش قطع کنید.',
    'Android VPN is not ready yet. Wait for its status, then try again.': 'VPN در Android هنوز آماده نیست. منتظر وضعیت آن بمانید و دوباره تلاش کنید.',
    'Could not save this subscription securely on the device.': 'ذخیرهٔ امن این اشتراک در دستگاه ممکن نشد.',
    'Could not save the subscription securely on this device.': 'ذخیرهٔ امن اشتراک در این دستگاه ممکن نشد.',
    'Could not remove the saved subscription.': 'حذف اشتراک ذخیره‌شده ممکن نشد.',
    'Saved subscription removed from this device.': 'اشتراک ذخیره‌شده از این دستگاه حذف شد.',
    'Could not load this subscription. Check the HTTPS URL and supported server formats.': 'بارگذاری اشتراک ممکن نشد. نشانی HTTPS و قالب‌های پشتیبانی‌شدهٔ سرور را بررسی کنید.',
    'Could not load this subscription. Check the secure URL and try again.': 'بارگذاری اشتراک ممکن نشد. نشانی امن را بررسی و دوباره تلاش کنید.',
    'The native VPN tunnel is currently wired for Android only.': 'تونل بومی VPN در حال حاضر فقط برای Android آماده شده است.',
    'Android VPN setup is incomplete. Generate the Android project and rebuild.': 'راه‌اندازی VPN در Android کامل نیست. پروژهٔ Android را ایجاد و دوباره بسازید.',
    'Android VPN permission was not granted.': 'مجوز VPN در Android داده نشد.',
    'Could not start this route. Check the server link and try again.': 'شروع این مسیر ممکن نشد. پیوند سرور را بررسی و دوباره تلاش کنید.',
    'Could not stop the VPN yet. Please retry disconnecting.': 'قطع VPN هنوز ممکن نشد. لطفاً دوباره برای قطع اتصال تلاش کنید.',
    'The route did not return a latency result.': 'مسیر نتیجه‌ای برای تأخیر برنگرداند.',
    'Latency check failed. Try again when the server is reachable.': 'آزمایش تأخیر ناموفق بود. وقتی سرور در دسترس است دوباره تلاش کنید.',
    'Language preference could not be saved. English has been restored.': 'ذخیرهٔ زبان انتخاب‌شده ممکن نشد. زبان English بازگردانده شد.',

    // Safe parser/fetch validation errors. Inputs and credentials are never echoed.
    'Enter a direct HTTPS subscription URL (without embedded username/password or a fragment).': 'یک نشانی مستقیم HTTPS وارد کنید (بدون نام کاربری/گذرواژهٔ درون نشانی یا بخش fragment).',
    'This subscription redirects to another address. Ask the provider for its direct HTTPS subscription URL.': 'این اشتراک به نشانی دیگری هدایت می‌شود. نشانی مستقیم HTTPS را از ارائه‌دهنده بخواهید.',
    'The subscription server did not return a usable response. Check the URL and try again.': 'سرور اشتراک پاسخ قابل استفاده‌ای نداد. نشانی را بررسی و دوباره تلاش کنید.',
    'The subscription response is too large to import safely.': 'پاسخ اشتراک برای وارد کردن امن بیش از حد بزرگ است.',
    'No supported VLESS, VMess, Shadowsocks, or Trojan server links were found.': 'هیچ پیوند سرور پشتیبانی‌شدهٔ VLESS، VMess، Shadowsocks یا Trojan پیدا نشد.',
    'Could not safely fetch this subscription. Check the HTTPS URL and your connection.': 'دریافت امن این اشتراک ممکن نشد. نشانی HTTPS و اتصال خود را بررسی کنید.',
    'Paste one VLESS, VMess, Shadowsocks, or Trojan server link.': 'یک پیوند سرور VLESS، VMess، Shadowsocks یا Trojan جای‌گذاری کنید.',
    'The server address is not valid.': 'نشانی سرور معتبر نیست.',
    'The VMess link could not be decoded.': 'رمزگشایی پیوند VMess ممکن نشد.',
    'The Shadowsocks link is not valid.': 'پیوند Shadowsocks معتبر نیست.',
    'The Shadowsocks server address is not valid.': 'نشانی سرور Shadowsocks معتبر نیست.',
    'The server link is missing a valid host or port.': 'پیوند سرور فاقد میزبان یا درگاه معتبر است.',
    'Unsupported server link.': 'پیوند سرور پشتیبانی نمی‌شود.',
    'That link could not be parsed. Check the format and try again.': 'تجزیهٔ این پیوند ممکن نشد. قالب را بررسی و دوباره تلاش کنید.',
    'Add a name for this subscription.': 'برای این اشتراک نامی وارد کنید.',
  };
}

class V2rayLocalizationsDelegate extends LocalizationsDelegate<V2rayLocalizations> {
  const V2rayLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      V2rayLocalizations.supportedLocales.any((item) => item.languageCode == locale.languageCode);

  @override
  Future<V2rayLocalizations> load(Locale locale) =>
      SynchronousFuture<V2rayLocalizations>(V2rayLocalizations(locale));

  @override
  bool shouldReload(V2rayLocalizationsDelegate old) => false;
}

/// Text widget that translates fixed source copy while preserving formatting
/// and dynamic profile/server data.
class LocalizedText extends StatelessWidget {
  const LocalizedText(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });

  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) => Text(
        V2rayLocalizations.of(context).text(data),
        style: style,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow,
      );
}

extension V2rayLocalizationContext on BuildContext {
  String tr(String source) => V2rayLocalizations.of(this).text(source);
}
