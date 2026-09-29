import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_localizations.dart';
import 'app_preferences.dart';
import 'language_preferences.dart';
import 'subscription_service.dart';
import 'vpn_engine.dart';
import 'vpn_profile.dart';
import 'traffic_format.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const V2rayAgApp());
}

const _ink = Color(0xFF182321);
const _muted = Color(0xFF778581);
const _mint = Color(0xFF51D6AF);
const _coral = Color(0xFFFF886E);
const _canvas = Color(0xFFF6F7F3);

enum _SubscriptionSaveChoice { saved, useOnce, cancelled }

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}

class V2rayAgApp extends StatefulWidget {
  const V2rayAgApp({super.key});

  @override
  State<V2rayAgApp> createState() => _V2rayAgAppState();
}

class _V2rayAgAppState extends State<V2rayAgApp> {
  ThemeMode _themeMode = ThemeMode.light;
  bool _reducedMotion = false;
  bool _showDestination = true;
  Locale _locale = const Locale('en');
  bool _languageChangedByUser = false;
  bool _appearanceChangedByUser = false;
  final LanguagePreferenceRepository _languagePreferences =
      LanguagePreferenceRepository();
  final AppAppearancePreferences _appearancePreferences =
      AppAppearancePreferences();

  @override
  void initState() {
    super.initState();
    _restoreLanguage();
    _restoreAppearance();
  }

  Future<void> _restoreAppearance() async {
    final preferences = await _appearancePreferences.read();
    if (!mounted || _appearanceChangedByUser) return;
    setState(() {
      _themeMode = preferences.darkMode ? ThemeMode.dark : ThemeMode.light;
      _reducedMotion = preferences.reducedMotion;
      _showDestination = preferences.showDestination;
    });
  }

  Future<void> _saveAppearance() async {
    try {
      await _appearancePreferences.save(AppearancePreferences(
        darkMode: _themeMode == ThemeMode.dark,
        reducedMotion: _reducedMotion,
        showDestination: _showDestination,
      ));
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: LocalizedText('Appearance choices may reset after restarting the app.')),
      );
    }
  }

  void _changeAppearance({bool? darkMode, bool? reducedMotion, bool? showDestination}) {
    _appearanceChangedByUser = true;
    setState(() {
      if (darkMode != null) _themeMode = darkMode ? ThemeMode.dark : ThemeMode.light;
      if (reducedMotion != null) _reducedMotion = reducedMotion;
      if (showDestination != null) _showDestination = showDestination;
    });
    unawaited(_saveAppearance());
  }

  Future<void> _restoreLanguage() async {
    final locale = await _languagePreferences.readLocale();
    if (mounted && !_languageChangedByUser) setState(() => _locale = locale);
  }

  Future<void> _changeLanguage(Locale locale) async {
    final supported = locale.languageCode == 'fa' ? const Locale('fa') : const Locale('en');
    _languageChangedByUser = true;
    setState(() => _locale = supported);
    try {
      await _languagePreferences.saveLocale(supported);
    } on Object {
      // Keep the selected locale active even if device preferences are temporarily
      // unavailable. A failed save must never flash back to English.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: LocalizedText('Language changed, but may reset after restarting the app.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ThemeData buildTheme(Brightness brightness) {
      final dark = brightness == Brightness.dark;
      final surface = dark ? const Color(0xFF17211F) : Colors.white;
      return ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: dark ? const Color(0xFF0D1412) : _canvas,
        canvasColor: dark ? const Color(0xFF0D1412) : _canvas,
        cardColor: surface,
        dialogTheme: DialogThemeData(backgroundColor: surface),
        dividerColor: dark ? const Color(0xFF2C3A36) : const Color(0xFFE4E9E5),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E9478),
          brightness: brightness,
          surface: surface,
        ),
        fontFamily: 'Roboto',
        appBarTheme: AppBarTheme(
          backgroundColor: dark ? const Color(0xFF0D1412) : _canvas,
          foregroundColor: dark ? Colors.white : _ink,
          surfaceTintColor: Colors.transparent,
        ),
        bottomSheetTheme: BottomSheetThemeData(backgroundColor: surface),
        popupMenuTheme: PopupMenuThemeData(color: surface),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: dark ? const Color(0xFF111A17) : const Color(0xFFEAF0EC),
          indicatorColor: dark ? const Color(0xFF25443A) : const Color(0xFFD5EEE4),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: const Color(0xFF26332F),
          contentTextStyle: const TextStyle(color: Colors.white),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    return MaterialApp(
      title: 'V2rayAG',
      debugShowCheckedModeBanner: false,
      locale: _locale,
      supportedLocales: V2rayLocalizations.supportedLocales,
      localizationsDelegates: V2rayLocalizations.localizationsDelegates,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: _themeMode,
      home: VpnShell(
        locale: _locale,
        onLocaleChanged: _changeLanguage,
        reducedMotion: _reducedMotion,
        showDestination: _showDestination,
        onReducedMotionChanged: (value) => _changeAppearance(reducedMotion: value),
        onShowDestinationChanged: (value) => _changeAppearance(showDestination: value),
        onThemeChanged: (value) => _changeAppearance(darkMode: value),
        darkMode: _themeMode == ThemeMode.dark,
      ),
    );
  }
}

class VpnShell extends StatefulWidget {
  const VpnShell({
    required this.locale,
    required this.onLocaleChanged,
    required this.reducedMotion,
    required this.showDestination,
    required this.onReducedMotionChanged,
    required this.onShowDestinationChanged,
    required this.onThemeChanged,
    required this.darkMode,
    super.key,
  });

  final Locale locale;
  final ValueChanged<Locale> onLocaleChanged;
  final bool reducedMotion;
  final bool showDestination;
  final ValueChanged<bool> onReducedMotionChanged;
  final ValueChanged<bool> onShowDestinationChanged;
  final ValueChanged<bool> onThemeChanged;
  final bool darkMode;

  @override
  State<VpnShell> createState() => _VpnShellState();
}

class _VpnShellState extends State<VpnShell> {
  int _tab = 0;
  final List<VpnProfile> _profiles = [];
  final VpnEngine _engine = VpnEngine();
  final SubscriptionRepository _subscriptionRepository = SubscriptionRepository();
  final Completer<void> _subscriptionsReady = Completer<void>();
  final Completer<void> _routingPreferencesReady = Completer<void>();
  List<SavedSubscription> _savedSubscriptions = [];
  bool _subscriptionBusy = false;
  bool _autoConnectActive = false;
  bool _cancelAutoConnect = false;
  int? _selectedIndex;
  final Map<int, int> _profilePings = {};
  final Set<int> _probingProfiles = {};
  final Set<String> _excludedPackages = {};
  static const MethodChannel _appPickerChannel =
      MethodChannel('v2rayag/app_picker');
  static const _excludedPackagesKey = 'excluded_packages_v1';

  static const _exclusiveId = 'exclusive-v2rayag';

  @override
  void initState() {
    super.initState();
    _engine.addListener(_onEngineChanged);
    _engine.initialize();
    _restoreSubscriptions();
    _restoreExcludedPackages();
  }

  Future<void> _restoreSubscriptions() async {
    try {
      final saved = await _subscriptionRepository.readAll();
      if (mounted) setState(() => _savedSubscriptions = saved);
    } on Object {
      if (mounted) _showMessage('Secure subscription storage is unavailable on this device.');
    } finally {
      if (!_subscriptionsReady.isCompleted) _subscriptionsReady.complete();
    }
  }

  Future<void> _restoreExcludedPackages() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final stored = preferences.getStringList(_excludedPackagesKey) ?? const [];
      if (mounted) {
        setState(() => _excludedPackages
          ..clear()
          ..addAll(stored));
      }
    } on Object {
      // Routing preferences are optional; default to routing all apps through VPN.
    } finally {
      if (!_routingPreferencesReady.isCompleted) {
        _routingPreferencesReady.complete();
      }
    }
  }

  Future<void> _editExcludedApps() async {
    if (_subscriptionBusy || _engine.connected || _engine.connecting ||
        _engine.disconnecting || _engine.busy) {
      _showMessage('Disconnect before changing app routing.');
      return;
    }
    await _routingPreferencesReady.future;
    if (!mounted) return;

    List<dynamic> rawApps;
    try {
      rawApps = await _appPickerChannel.invokeListMethod<dynamic>(
            'listLaunchableApps',
          ) ??
          const [];
    } on Object {
      if (mounted) {
        _showMessage('Could not list apps on this device. Restart the app and try again.');
      }
      return;
    }

    final apps = <_InstalledApp>[];
    for (final item in rawApps) {
      if (item is! Map) continue;
      final packageName = (item['packageName'] ?? '').toString().trim();
      final label = (item['label'] ?? packageName).toString().trim();
      if (packageName.isEmpty) continue;
      apps.add(_InstalledApp(packageName, label.isEmpty ? packageName : label));
    }
    apps.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    if (apps.isEmpty) {
      if (mounted) _showMessage('No apps with a launcher icon were found.');
      return;
    }

    if (!mounted) return;
    final selected = Set<String>.of(_excludedPackages);
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: const LocalizedText('Bypass apps'),
          content: SizedBox(
            width: double.maxFinite,
            height: MediaQuery.sizeOf(context).height * .55,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const LocalizedText(
                  'Choose apps whose traffic should use the normal connection.',
                  style: TextStyle(fontSize: 12, color: _muted),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    itemCount: apps.length,
                    itemBuilder: (context, index) {
                      final app = apps[index];
                      return CheckboxListTile(
                        dense: true,
                        value: selected.contains(app.packageName),
                        title: Text(app.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(app.packageName, maxLines: 1, overflow: TextOverflow.ellipsis),
                        onChanged: (checked) => refresh(() {
                          if (checked == true) {
                            selected.add(app.packageName);
                          } else {
                            selected.remove(app.packageName);
                          }
                        }),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const LocalizedText('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(selected),
              child: const LocalizedText('Apply'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    try {
      final preferences = await SharedPreferences.getInstance();
      final values = result.toList()..sort();
      await preferences.setStringList(_excludedPackagesKey, values);
      if (mounted) {
        setState(() {
          _excludedPackages
            ..clear()
            ..addAll(values);
        });
      }
    } on Object {
      if (mounted) _showMessage('Could not save app routing choices.');
    }
  }

  void _onEngineChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _engine.removeListener(_onEngineChanged);
    _engine.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: LocalizedText(message)));
  }

  Future<void> _toggleConnection() async {
    final isActive = _engine.connected || _engine.connecting || _engine.disconnecting;
    final canCancelAutoConnect = _subscriptionBusy && _autoConnectActive && isActive;
    if (_subscriptionBusy && !canCancelAutoConnect) {
      _showMessage('Wait for the subscription operation to finish.');
      return;
    }
    final profile = _selectedIndex == null ? null : _profiles[_selectedIndex!];
    if (profile == null) {
      _showMessage('Import a server link first.');
      return;
    }
    if (isActive) {
      if (canCancelAutoConnect) setState(() => _cancelAutoConnect = true);
      await _engine.disconnect();
    } else {
      await _engine.connect(
        profile,
        blockedApps: _excludedPackages.toList(growable: false),
      );
    }
    if (mounted && _engine.message != null) _showMessage(_engine.message!);
  }

  Future<void> _measurePing() async {
    if (_subscriptionBusy) return;
    final profile = _selectedIndex == null ? null : _profiles[_selectedIndex!];
    if (profile == null) return;
    final result = await _engine.measurePing(profile);
    if (!mounted) return;
    if (result != null) {
      _showMessage('Measured route latency: $result ms');
    } else if (_engine.message != null) {
      _showMessage(_engine.message!);
    }
  }

  Future<void> _showConnectionDiagnostics() async {
    final availableHeight = MediaQuery.sizeOf(context).height;
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const LocalizedText('Review connection diagnostics'),
        content: const LocalizedText(
          'Diagnostics can include server addresses, destinations, and local paths. Review and redact them before sharing. Nothing is sent automatically.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const LocalizedText('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const LocalizedText('Show details'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    final details = await _engine.getSupportDiagnostics();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const LocalizedText('Connection details'),
        content: SizedBox(
          width: double.maxFinite,
          height: availableHeight * .52,
          child: SingleChildScrollView(
            child: SelectableText(details, style: const TextStyle(fontSize: 12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const LocalizedText('Close'),
          ),
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: details));
              if (!mounted || !dialogContext.mounted) return;
              Navigator.of(dialogContext).pop();
              _showMessage('Copied to clipboard. Review and redact before sharing.');
            },
            icon: const Icon(Icons.copy_rounded),
            label: const LocalizedText('Copy diagnostics'),
          ),
        ],
      ),
    );
  }

  Future<void> _testProfileLatency(int index) async {
    if (_subscriptionBusy || _engine.connected || _engine.connecting || _engine.disconnecting || _engine.busy) return;
    if (index < 0 || index >= _profiles.length || _probingProfiles.contains(index)) return;
    setState(() => _probingProfiles.add(index));
    final result = await _engine.measurePing(_profiles[index]);
    if (!mounted) return;
    setState(() {
      _probingProfiles.remove(index);
      if (result != null) _profilePings[index] = result;
    });
    if (result == null && _engine.message != null) _showMessage(_engine.message!);
  }

  void _selectProfile(int index) {
    if (_subscriptionBusy) return;
    if (_engine.connected || _engine.connecting || _engine.disconnecting) {
      _showMessage('Disconnect before changing the active server.');
      return;
    }
    setState(() => _selectedIndex = index);
  }

  Future<void> _importProfile() async {
    if (_subscriptionBusy) {
      _showMessage('Wait for the subscription operation to finish.');
      return;
    }
    if (_engine.connected || _engine.connecting || _engine.disconnecting) {
      _showMessage('Disconnect before importing another server.');
      return;
    }
    final profile = await showModalBottomSheet<VpnProfile>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ImportSheet(),
    );
    if (profile == null || !mounted) return;
    if (_engine.connected || _engine.connecting || _engine.disconnecting) {
      _showMessage('Disconnect before importing another active route.');
      return;
    }
    setState(() {
      _profiles.add(profile);
      _selectedIndex = _profiles.length - 1;
      _tab = 1;
    });
    _showMessage('Server profile added to this session memory.');
  }

  Future<SavedSubscription?> _editSubscription({SavedSubscription? existing, required bool exclusive}) {
    final id = existing?.id ?? (exclusive ? _exclusiveId : 'custom-${DateTime.now().microsecondsSinceEpoch}');
    return showModalBottomSheet<SavedSubscription>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SubscriptionEditorSheet(
        id: id,
        initialName: exclusive ? 'Exclusive V2rayAG Subs' : (existing?.name ?? ''),
        initialUrl: existing?.url ?? '',
        fixedName: exclusive,
      ),
    );
  }

  Future<_SubscriptionSaveChoice> _saveSubscription(
    SavedSubscription subscription,
  ) async {
    final next = [..._savedSubscriptions];
    final index = next.indexWhere((item) => item.id == subscription.id);
    if (index < 0) {
      next.add(subscription);
    } else {
      next[index] = subscription;
    }
    try {
      await _subscriptionRepository.saveAll(next);
      if (mounted) setState(() => _savedSubscriptions = next);
      return _SubscriptionSaveChoice.saved;
    } on Object {
      if (!mounted) return _SubscriptionSaveChoice.cancelled;
      final useOnce = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const LocalizedText('Secure save is unavailable'),
          content: const LocalizedText(
            'Android could not save this URL in secure storage. You can use it once in this session without saving it. It will be discarded when the app closes and will not be stored as plain text.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const LocalizedText('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const LocalizedText('Use once'),
            ),
          ],
        ),
      );
      return useOnce == true
          ? _SubscriptionSaveChoice.useOnce
          : _SubscriptionSaveChoice.cancelled;
    }
  }

  Future<void> _addSubscription() async {
    if (_subscriptionBusy) return;
    await _subscriptionsReady.future;
    if (!mounted) return;
    if (_engine.connected || _engine.connecting || _engine.disconnecting) {
      _showMessage('Disconnect before refreshing subscriptions.');
      return;
    }
    final subscription = await _editSubscription(exclusive: false);
    if (subscription == null || !mounted) return;
    final choice = await _saveSubscription(subscription);
    if (!mounted || choice == _SubscriptionSaveChoice.cancelled) return;
    await _refreshSubscription(subscription);
  }

  Future<void> _editSavedSubscription(SavedSubscription existing) async {
    if (_subscriptionBusy) return;
    await _subscriptionsReady.future;
    if (!mounted) return;
    if (_engine.connected || _engine.connecting || _engine.disconnecting) {
      _showMessage('Disconnect before changing subscriptions.');
      return;
    }
    final updated = await _editSubscription(
      existing: existing,
      exclusive: existing.id == _exclusiveId,
    );
    if (updated == null || !mounted) return;
    final choice = await _saveSubscription(updated);
    if (!mounted || choice == _SubscriptionSaveChoice.cancelled) return;
    await _refreshSubscription(updated);
  }

  Future<void> _removeSubscription(SavedSubscription subscription) async {
    if (_subscriptionBusy || _engine.connected || _engine.connecting || _engine.disconnecting) return;
    await _subscriptionsReady.future;
    if (!mounted) return;
    final next = _savedSubscriptions.where((item) => item.id != subscription.id).toList();
    try {
      await _subscriptionRepository.saveAll(next);
      if (mounted) setState(() => _savedSubscriptions = next);
      _showMessage('Saved subscription removed from this device.');
    } on Object {
      _showMessage('Could not remove the saved subscription.');
    }
  }

  Future<void> _connectExclusiveSubscription() async {
    if (_subscriptionBusy) return;
    await _subscriptionsReady.future;
    if (!mounted) return;
    if (_engine.connected || _engine.connecting || _engine.disconnecting) {
      _showMessage('Disconnect the current route with the power button before switching subscriptions.');
      return;
    }
    final existing = _savedSubscriptions.where((item) => item.id == _exclusiveId).firstOrNull;
    SavedSubscription? subscription = existing;
    if (subscription == null) {
      subscription = await _editSubscription(exclusive: true);
      if (subscription == null || !mounted) return;
      final choice = await _saveSubscription(subscription);
      if (!mounted || choice == _SubscriptionSaveChoice.cancelled) return;
    }
    await _refreshSubscription(subscription, connectFirst: true);
  }

  Future<void> _refreshSubscription(
    SavedSubscription subscription, {
    bool connectFirst = false,
  }) async {
    if (_subscriptionBusy) return;
    if (_engine.connected || _engine.connecting || _engine.disconnecting) {
      _showMessage('Disconnect before refreshing subscriptions.');
      return;
    }
    setState(() => _subscriptionBusy = true);
    _showMessage('Fetching subscription securely…');
    try {
      final profiles = await SubscriptionService.fetchProfiles(subscription.url);
      if (!mounted) return;
      // Do not replace the selected profile list if Android started or restored
      // a tunnel while the network fetch was in flight.
      if (_engine.connected || _engine.connecting || _engine.disconnecting) {
        _showMessage('Disconnect before refreshing subscriptions.');
        return;
      }
      setState(() {
        _profiles
          ..clear()
          ..addAll(profiles);
        _profilePings.clear();
        _probingProfiles.clear();
        _selectedIndex = 0;
        _tab = connectFirst ? 0 : 1;
        _autoConnectActive = connectFirst;
        _cancelAutoConnect = false;
      });
      if (connectFirst) {
        if (!_engine.canStart) {
          _showMessage(_engine.message ?? 'Servers loaded; Android VPN is still preparing. Tap the power button when it is ready.');
          return;
        }

        // Provider subscriptions can contain expired or Xray-incompatible nodes.
        // Try profiles one at a time; never start concurrent native sessions.
        // Bound the automatic attempts so a very large subscription cannot
        // trap the user in a long sequence. Manual selection remains available.
        final attemptCount = profiles.length < 8 ? profiles.length : 8;
        var rejectedConfiguration = false;
        for (var index = 0; index < attemptCount; index++) {
          if (!mounted || _cancelAutoConnect) break;
          setState(() => _selectedIndex = index);
          final started = await _engine.connect(
            profiles[index],
            blockedApps: _excludedPackages.toList(growable: false),
          );
          if (!mounted) return;
          if (_cancelAutoConnect) break;
          if (started) {
            if (index > 0) {
              _showMessage('Exclusive subscription connected using a backup server.');
            } else if (_engine.message != null) {
              _showMessage(_engine.message!);
            }
            return;
          }

          final failure = _engine.failureCategory;
          if (_engine.connected || _engine.connecting || _engine.disconnecting) {
            break;
          }
          if (failure == 'VpnPermissionDenied') break;
          // Retry only when this attempt is known to have been rejected or
          // safely stopped after a route-specific timeout/disconnect. Never
          // rotate while a native tunnel may still be active.
          if (shouldRetrySubscriptionProfile(failure)) {
            if (failure == 'InvalidConfiguration' ||
                failure == 'PlatformException:INVALID_CONFIG') {
              rejectedConfiguration = true;
            }
          } else {
            break;
          }
        }

        if (!mounted) return;
        if (_cancelAutoConnect) {
          final stillActive =
              _engine.connected || _engine.connecting || _engine.disconnecting;
          _showMessage(stillActive
              ? (_engine.message ?? 'Android has not confirmed disconnect yet. Retry disconnect before starting another route.')
              : 'Automatic connection was cancelled.');
          return;
        }
        _showMessage(rejectedConfiguration
            ? 'The native VPN engine rejected subscription profiles. Refresh the subscription or choose a different server.'
            : 'No server in the subscription could be started. Check server access or choose another profile.');
      } else {
        _showMessage('Loaded ${profiles.length} server profiles into app memory.');
      }
    } on FormatException catch (error) {
      // These parser/fetch errors are fixed, credential-free messages; never
      // surface the URL or raw HTTP/network exception in the UI.
      if (mounted) _showMessage(error.message);
    } on Object {
      if (mounted) _showMessage('Could not load this subscription. Check the secure URL and try again.');
    } finally {
      if (mounted) {
        setState(() {
          _subscriptionBusy = false;
          _autoConnectActive = false;
        });
      }
    }
  }

  void _removeProfile(int index) {
    if (_subscriptionBusy) return;
    if ((_engine.connected || _engine.connecting || _engine.disconnecting) && index == _selectedIndex) {
      _showMessage('Disconnect before removing the active server.');
      return;
    }
    setState(() {
      _profiles.removeAt(index);
      _profilePings.clear();
      _probingProfiles.clear();
      if (_profiles.isEmpty) {
        _selectedIndex = null;
      } else if (_selectedIndex == index) {
        _selectedIndex = 0;
      } else if (_selectedIndex != null && _selectedIndex! > index) {
        _selectedIndex = _selectedIndex! - 1;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedIndex == null ? null : _profiles[_selectedIndex!];
    final pages = <Widget>[
      _HomePage(
        profile: selected,
        engine: _engine,
        showDestination: widget.showDestination,
        reducedMotion: widget.reducedMotion,
        onToggleConnection: _toggleConnection,
        onMeasurePing: _measurePing,
        onShowDiagnostics: _showConnectionDiagnostics,
        subscriptionBusy: _subscriptionBusy,
      ),
      _ProfilesPage(
        profiles: _profiles,
        selectedIndex: _selectedIndex,
        showDestination: widget.showDestination,
        connected: _engine.connected || _engine.connecting || _engine.disconnecting,
        onImport: _importProfile,
        onSelect: _selectProfile,
        onRemove: _removeProfile,
        profilePings: _profilePings,
        probingProfiles: _probingProfiles,
        onTestProfileLatency: _testProfileLatency,
        subscriptions: _savedSubscriptions,
        onAddSubscription: _addSubscription,
        onEditSubscription: _editSavedSubscription,
        onRemoveSubscription: _removeSubscription,
        onRefreshSubscription: _refreshSubscription,
        onConnectExclusive: _connectExclusiveSubscription,
        exclusiveId: _exclusiveId,
        subscriptionBusy: _subscriptionBusy,
      ),
      _SettingsPage(
        locale: widget.locale,
        onLocaleChanged: widget.onLocaleChanged,
        reducedMotion: widget.reducedMotion,
        showDestination: widget.showDestination,
        darkMode: widget.darkMode,
        onReducedMotionChanged: widget.onReducedMotionChanged,
        onShowDestinationChanged: widget.onShowDestinationChanged,
        onThemeChanged: widget.onThemeChanged,
        onEditAppRouting: _editExcludedApps,
        excludedAppsCount: _excludedPackages.length,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: const Row(
          children: [
            _BrandMark(),
            SizedBox(width: 11),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LocalizedText('V2rayAG', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                LocalizedText('PRIVATE ROUTE', style: TextStyle(fontSize: 9, letterSpacing: 1.7, color: _muted)),
              ],
            ),
          ],
        ),
        actions: const [SizedBox(width: 8)],
      ),
      body: SafeArea(
        top: false,
        child: IndexedStack(index: _tab, children: pages),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.radio_button_checked_rounded), label: context.tr('Connect')),
          NavigationDestination(icon: const Icon(Icons.public_rounded), label: context.tr('Servers')),
          NavigationDestination(icon: const Icon(Icons.tune_rounded), label: context.tr('Settings')),
        ],
      ),
    );
  }
}

class _HomePage extends StatelessWidget {
  const _HomePage({
    required this.profile,
    required this.engine,
    required this.showDestination,
    required this.reducedMotion,
    required this.onToggleConnection,
    required this.onMeasurePing,
    required this.onShowDiagnostics,
    required this.subscriptionBusy,
  });

  final VpnProfile? profile;
  final VpnEngine engine;
  final bool showDestination;
  final bool reducedMotion;
  final VoidCallback onToggleConnection;
  final VoidCallback onMeasurePing;
  final VoidCallback onShowDiagnostics;
  final bool subscriptionBusy;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final card = dark ? const Color(0xFF192321) : Colors.white;
    final activeOrPending = engine.connected || engine.connecting || engine.disconnecting;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
      children: [
        LocalizedText('Your quiet corner of the internet.',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: dark ? Colors.white : _ink,
                  letterSpacing: -.6,
                )),
        const SizedBox(height: 6),
        const LocalizedText('A clean route, on your terms.', style: TextStyle(color: _muted, fontSize: 14)),
        const SizedBox(height: 28),
        Center(
          child: _PowerOrb(
            reducedMotion: reducedMotion,
            dark: dark,
            connected: engine.connected,
            connecting: engine.connecting,
            disconnecting: engine.disconnecting,
            failed: engine.message != null && !engine.connected && !engine.connecting,
            enabled: profile != null &&
                (!subscriptionBusy || activeOrPending) &&
                !engine.busy &&
                (engine.canStart || engine.connected || engine.connecting || engine.disconnecting),
            onPressed: onToggleConnection,
          ),
        ),
        const SizedBox(height: 18),
        Center(
          child: Column(
            children: [
              LocalizedText(engine.stateLabel, style: TextStyle(fontSize: 12, letterSpacing: 2.1, fontWeight: FontWeight.w800, color: engine.connected ? const Color(0xFF67DDB7) : (dark ? const Color(0xFFE0EAE6) : _ink))),
              const SizedBox(height: 5),
              LocalizedText(
                profile == null
                    ? 'Import a server before connecting'
                    : engine.connected
                        ? 'VPN service is connected. Test latency to verify network access.'
                        : engine.message ??
                            (engine.connecting
                                ? 'Waiting for the Android tunnel status…'
                                : engine.disconnecting
                                    ? 'Waiting for Android to confirm disconnect…'
                                    : engine.initialized
                                        ? 'Tap to request Android VPN permission'
                                        : 'Preparing Android VPN engine…'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: _muted),
              ),
              if (engine.message != null && profile != null)
                TextButton.icon(
                  onPressed: onShowDiagnostics,
                  icon: const Icon(Icons.bug_report_outlined, size: 17),
                  label: const LocalizedText('Review connection diagnostics'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Container(
          decoration: BoxDecoration(
            color: card,
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: dark ? Colors.white12 : const Color(0xFFE8ECE8)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: dark ? .08 : .035), blurRadius: 24, offset: const Offset(0, 10))],
          ),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.route_rounded, size: 18, color: Color(0xFF31896F)),
                const SizedBox(width: 8),
                const Expanded(child: LocalizedText('DESTINATION', style: TextStyle(fontSize: 10, letterSpacing: 1.4, fontWeight: FontWeight.w800, color: _muted))),
                Text(profile?.protocol ?? context.tr('NO SERVER'), textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: _muted)),
              ]),
              const SizedBox(height: 13),
              Directionality(
                textDirection: showDestination && profile != null ? TextDirection.ltr : Directionality.of(context),
                child: Text(
                  showDestination ? (profile?.destination ?? context.tr('Add a server link')) : context.tr('Destination hidden'),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: dark ? Colors.white : _ink),
                ),
              ),
              const SizedBox(height: 5),
              LocalizedText(profile == null ? 'No client address is read or displayed.' : 'Country: not looked up',
                  style: const TextStyle(fontSize: 12, color: _muted)),
              const SizedBox(height: 8),
              if (engine.connected || engine.hasSessionData) ...[
                _MetricRow(
                  label: 'LIVE SPEED',
                  value: engine.connected
                      ? '↓ ${formatByteRate(engine.status.downloadSpeed)}   ↑ ${formatByteRate(engine.status.uploadSpeed)}'
                      : '↓ ${formatByteRate(0)}   ↑ ${formatByteRate(0)}',
                ),
                const SizedBox(height: 4),
                _MetricRow(
                  label: 'SESSION TOTAL',
                  value: '↓ ${formatByteCount(engine.sessionDownloadBytes)}   ↑ ${formatByteCount(engine.sessionUploadBytes)}',
                ),
                const SizedBox(height: 4),
                _MetricRow(
                  label: 'CONNECTED TIME',
                  value: formatConnectionDuration(engine.connectedDuration),
                ),
              ] else
                const LocalizedText(
                  'Live traffic stats appear after a real connection.',
                  style: TextStyle(fontSize: 11, color: _muted),
                ),

              const SizedBox(height: 10),
              Row(children: [
                OutlinedButton.icon(
                  onPressed: profile == null || subscriptionBusy || engine.busy || engine.connecting || engine.disconnecting
                      ? null
                      : onMeasurePing,
                  icon: const Icon(Icons.speed_rounded, size: 17),
                  label: LocalizedText(engine.lastPingMs == null ? 'Test latency' : '${engine.lastPingMs} ms'),
                ),
              ]),
              const SizedBox(height: 8),
            ],
          ),
        ),
        const SizedBox(height: 15),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF29221F) : const Color(0xFFFFF1E8),
            border: dark ? Border.all(color: const Color(0xFF594038)) : null,
            borderRadius: BorderRadius.circular(17),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline_rounded, size: 17, color: dark ? const Color(0xFFFFB29B) : const Color(0xFFB35E49)),
            const SizedBox(width: 9),
            Expanded(
              child: LocalizedText(
                'Subscription URLs are encrypted in Android secure storage and never committed to GitHub. Imported server configs stay in app memory. The app never reads or displays your device IP.',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.45,
                  color: dark ? const Color(0xFFE6C7BC) : const Color(0xFF8A5548),
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 23),
        const Center(child: LocalizedText('Source: Telegram @V2rayAG  ·  Developer: HashtagAlireza',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: _muted))),
      ],
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(child: LocalizedText(label, style: const TextStyle(fontSize: 10, color: _muted))),
          Flexible(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Text(value, textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, color: _muted)),
            ),
          ),
        ],
      );
}

class _PowerOrb extends StatefulWidget {
  const _PowerOrb({
    required this.reducedMotion,
    required this.dark,
    required this.connected,
    required this.connecting,
    required this.disconnecting,
    required this.failed,
    required this.enabled,
    required this.onPressed,
  });
  final bool reducedMotion;
  final bool dark;
  final bool connected;
  final bool connecting;
  final bool disconnecting;
  final bool failed;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  State<_PowerOrb> createState() => _PowerOrbState();
}

class _PowerOrbState extends State<_PowerOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void initState() {
    super.initState();
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant _PowerOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reducedMotion != widget.reducedMotion ||
        oldWidget.connected != widget.connected ||
        oldWidget.connecting != widget.connecting ||
        oldWidget.disconnecting != widget.disconnecting) {
      _syncMotion();
    }
  }

  void _syncMotion() {
    final active = widget.connected || widget.connecting || widget.disconnecting;
    if (widget.reducedMotion || !active) {
      _motion.stop();
      _motion.value = 0;
    } else {
      _motion.repeat();
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.connected ? _mint : (widget.failed ? _coral : const Color(0xFF9A83D8));
    return AnimatedBuilder(
      animation: _motion,
      builder: (context, child) {
        final pulse = widget.connected && !widget.reducedMotion
            ? .98 + .02 * (1 + _sinPulse(_motion.value))
            : 1.0;
        return Transform.scale(
          scale: pulse,
          child: AnimatedContainer(
            duration: widget.reducedMotion ? Duration.zero : const Duration(milliseconds: 450),
            width: 190,
            height: 190,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: widget.dark
                    ? (widget.connected
                        ? const [Color(0xFF235447), Color(0xFF193D35), Color(0xFF182A27)]
                        : widget.failed
                            ? const [Color(0xFF462B2B), Color(0xFF302526), Color(0xFF1B2422)]
                            : const [Color(0xFF493B50), Color(0xFF302733), Color(0xFF1B2422)])
                    : (widget.connected
                        ? const [Color(0xFFE9FFF4), Color(0xFFC9F7E1), Color(0xFFC7E7DD)]
                        : widget.failed
                            ? const [Color(0xFFFFEEE9), Color(0xFFFFD1C5), Color(0xFFEAD9D9)]
                            : const [Color(0xFFFFF2E9), Color(0xFFFFD6C8), Color(0xFFE8D8FF)]),
                stops: const [0, .66, 1],
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: widget.dark ? .15 : .21),
                  blurRadius: widget.connecting || widget.connected ? 42 : 34,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                if ((widget.connecting || widget.disconnecting) && !widget.reducedMotion)
                  const SizedBox(
                    width: 178,
                    height: 178,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: Color(0xFF6DD9B7),
                      backgroundColor: Colors.white12,
                    ),
                  ),
                SizedBox(
                  width: 126,
                  height: 126,
                  child: Material(
                    color: widget.dark ? const Color(0xFF1D2927) : Colors.white.withValues(alpha: .94),
                    shape: const CircleBorder(),
                    elevation: widget.dark ? 1 : 8,
                    shadowColor: accent.withValues(alpha: .18),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: widget.enabled ? widget.onPressed : null,
                      child: Center(
                        child: (widget.connecting && !widget.reducedMotion)
                            ? RotationTransition(
                                turns: _motion,
                                child: Icon(Icons.sync_rounded, size: 43, color: accent),
                              )
                            : AnimatedSwitcher(
                                duration: widget.reducedMotion ? Duration.zero : const Duration(milliseconds: 250),
                                child: Icon(
                                  widget.connected ? Icons.shield_rounded : Icons.power_settings_new_rounded,
                                  key: ValueKey('${widget.connected}-${widget.failed}'),
                                  size: 47,
                                  color: !widget.enabled
                                      ? (widget.dark ? const Color(0xFF899691) : Colors.grey)
                                      : widget.connected
                                          ? const Color(0xFF67DDB7)
                                          : widget.failed
                                              ? const Color(0xFFFF9B82)
                                              : const Color(0xFF9A83D8),
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  double _sinPulse(double value) =>
      (value < .5 ? value * 4 - 1 : 3 - value * 4);
}

class _ProfilesPage extends StatelessWidget {
  const _ProfilesPage({
    required this.profiles,
    required this.selectedIndex,
    required this.showDestination,
    required this.connected,
    required this.onImport,
    required this.onSelect,
    required this.onRemove,
    required this.profilePings,
    required this.probingProfiles,
    required this.onTestProfileLatency,
    required this.subscriptions,
    required this.onAddSubscription,
    required this.onEditSubscription,
    required this.onRemoveSubscription,
    required this.onRefreshSubscription,
    required this.onConnectExclusive,
    required this.exclusiveId,
    required this.subscriptionBusy,
  });

  final List<VpnProfile> profiles;
  final int? selectedIndex;
  final bool showDestination;
  final bool connected;
  final VoidCallback onImport;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onRemove;
  final Map<int, int> profilePings;
  final Set<int> probingProfiles;
  final ValueChanged<int> onTestProfileLatency;
  final List<SavedSubscription> subscriptions;
  final VoidCallback onAddSubscription;
  final ValueChanged<SavedSubscription> onEditSubscription;
  final ValueChanged<SavedSubscription> onRemoveSubscription;
  final Future<void> Function(SavedSubscription, {bool connectFirst}) onRefreshSubscription;
  final VoidCallback onConnectExclusive;
  final String exclusiveId;
  final bool subscriptionBusy;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final exclusive = subscriptions.where((item) => item.id == exclusiveId).firstOrNull;
    final customSubscriptions = subscriptions.where((item) => item.id != exclusiveId).toList();
    return ListView(padding: const EdgeInsets.fromLTRB(20, 18, 20, 28), children: [
      LocalizedText('Servers', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      const LocalizedText('Add your subscription, refresh servers, and choose a route.', style: TextStyle(color: _muted)),
      const SizedBox(height: 18),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: dark
              ? const [Color(0xFF17332D), Color(0xFF282239)]
              : const [Color(0xFFE7F8F1), Color(0xFFF3EAFE)]),
          borderRadius: BorderRadius.circular(22),
          border: dark ? Border.all(color: Colors.white10) : null,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.bolt_rounded, color: Color(0xFF58D7B2)),
            const SizedBox(width: 8),
            Expanded(child: LocalizedText('Exclusive V2rayAG Subs', style: TextStyle(fontWeight: FontWeight.w800, color: dark ? Colors.white : _ink))),
            const Icon(Icons.lock_outline_rounded, size: 18, color: _muted),
          ]),
          const SizedBox(height: 5),
          LocalizedText(
            exclusive == null ? 'Enter your private subscription URL once.' : 'Saved securely on this device.',
            style: const TextStyle(fontSize: 12, color: _muted),
          ),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: FilledButton.icon(
            onPressed: subscriptionBusy ? null : onConnectExclusive,
            icon: subscriptionBusy
                ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.flash_on_rounded),
            label: LocalizedText(subscriptionBusy ? 'Fetching servers…' : 'One-tap connect'),
          )),
          if (exclusive != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: connected || subscriptionBusy ? null : () => onEditSubscription(exclusive),
                icon: const Icon(Icons.edit_outlined, size: 17),
                label: const LocalizedText('Change URL'),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 16),
      Row(children: [
        const Expanded(child: LocalizedText('My subscriptions', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
        TextButton.icon(onPressed: connected || subscriptionBusy ? null : onAddSubscription, icon: const Icon(Icons.add_rounded), label: const LocalizedText('Add')),
      ]),
      if (customSubscriptions.isEmpty)
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: LocalizedText('Paste a secure HTTPS URL or scan its QR code. URLs are stored on this device only.', style: TextStyle(color: _muted, fontSize: 12)),
        )
      else
        ...customSubscriptions.map((subscription) => Card(
          elevation: 0,
          color: dark ? const Color(0xFF192321) : Colors.white,
          child: ListTile(
            leading: CircleAvatar(backgroundColor: dark ? const Color(0xFF213B34) : const Color(0xFFE5F6EF), child: Icon(Icons.rss_feed_rounded, color: dark ? const Color(0xFF7AD9B7) : const Color(0xFF317D68))),
            title: Text(subscription.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: const LocalizedText('Private URL stored on this device'),
            trailing: Wrap(spacing: 0, children: [
              IconButton(tooltip: context.tr('Refresh servers'), onPressed: connected || subscriptionBusy ? null : () => onRefreshSubscription(subscription), icon: const Icon(Icons.refresh_rounded)),
              IconButton(tooltip: context.tr('Edit subscription'), onPressed: connected || subscriptionBusy ? null : () => onEditSubscription(subscription), icon: const Icon(Icons.edit_outlined)),
              IconButton(tooltip: context.tr('Remove subscription'), onPressed: connected || subscriptionBusy ? null : () => onRemoveSubscription(subscription), icon: const Icon(Icons.delete_outline_rounded)),
            ]),
          ),
        )),
      const SizedBox(height: 10),
      FilledButton.tonalIcon(onPressed: connected || subscriptionBusy ? null : onImport, icon: const Icon(Icons.add_link_rounded), label: const LocalizedText('Import one server link')),
      const SizedBox(height: 14),
      if (profiles.isEmpty)
        _EmptyCard(dark: dark)
      else
        ...profiles.asMap().entries.map((entry) {
          final index = entry.key;
          final profile = entry.value;
          final active = index == selectedIndex;
          return Card(
            elevation: 0,
            color: dark ? const Color(0xFF192321) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: active ? const Color(0xFF52C59E) : (dark ? Colors.white12 : Colors.black12), width: active ? 1.5 : 1),
            ),
            child: ListTile(
              onTap: () => onSelect(index),
              leading: CircleAvatar(backgroundColor: dark ? const Color(0xFF213B34) : const Color(0xFFE5F6EF), child: Text(profile.protocol.substring(0, 1), style: TextStyle(color: dark ? const Color(0xFF7AD9B7) : const Color(0xFF317D68), fontWeight: FontWeight.w800))),
              title: Text(profile.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text('${profile.protocol} · ${showDestination ? profile.destination : context.tr('Destination hidden')}'),
                  ),
                  Text('${context.tr('Country not looked up')} · ${context.tr(active && connected ? 'connected' : 'ready')}'),
                  if (profilePings[index] != null)
                    Text('${context.tr('Latency')}: ${profilePings[index]} ms', style: const TextStyle(color: _muted, fontSize: 12)),
                ],
              ),
              isThreeLine: true,
              trailing: Wrap(spacing: 0, children: [
                IconButton(
                  tooltip: context.tr('Test latency'),
                  onPressed: connected || subscriptionBusy || probingProfiles.contains(index)
                      ? null
                      : () => onTestProfileLatency(index),
                  icon: probingProfiles.contains(index)
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.speed_rounded),
                ),
                IconButton(tooltip: context.tr('Remove profile'), onPressed: connected && active ? null : () => onRemove(index), icon: const Icon(Icons.close_rounded)),
              ]),
            ),
          );
        }),
      const SizedBox(height: 12),
      const LocalizedText('Profile configs exist only in app memory during this session. Do not share screenshots or logs that reveal a server address.', style: TextStyle(fontSize: 12, color: _muted, height: 1.45)),
    ]);
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.dark});
  final bool dark;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.fromLTRB(23, 31, 23, 30),
        decoration: BoxDecoration(color: dark ? const Color(0xFF192321) : Colors.white, borderRadius: BorderRadius.circular(24)),
        child: const Column(children: [
          Icon(Icons.public_rounded, size: 35, color: Color(0xFF58A98E)),
          SizedBox(height: 13),
          LocalizedText('Your server list is empty', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          SizedBox(height: 6),
          LocalizedText('Import a single VLESS, VMess, Shadowsocks, or Trojan server link to prepare an Android VPN route.', textAlign: TextAlign.center, style: TextStyle(color: _muted, height: 1.45)),
        ]),
      );
}

class _InstalledApp {
  const _InstalledApp(this.packageName, this.label);
  final String packageName;
  final String label;
}

class _SettingsPage extends StatelessWidget {
  const _SettingsPage({
    required this.locale,
    required this.onLocaleChanged,
    required this.reducedMotion,
    required this.showDestination,
    required this.darkMode,
    required this.onReducedMotionChanged,
    required this.onShowDestinationChanged,
    required this.onThemeChanged,
    required this.onEditAppRouting,
    required this.excludedAppsCount,
  });

  final Locale locale;
  final ValueChanged<Locale> onLocaleChanged;
  final bool reducedMotion;
  final bool showDestination;
  final bool darkMode;
  final ValueChanged<bool> onReducedMotionChanged;
  final ValueChanged<bool> onShowDestinationChanged;
  final ValueChanged<bool> onThemeChanged;
  final VoidCallback onEditAppRouting;
  final int excludedAppsCount;

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.fromLTRB(20, 18, 20, 28), children: [
        LocalizedText('Settings', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const LocalizedText('Appearance settings work now; Android VPN connection is managed from Connect.', style: TextStyle(color: _muted)),
        const SizedBox(height: 20),
        Card(elevation: 0, color: Theme.of(context).colorScheme.surface, child: Column(children: [
          ListTile(
            title: const LocalizedText('App language'),
            subtitle: const LocalizedText('Choose the language used throughout the app'),
            trailing: DropdownButton<Locale>(
              value: locale,
              onChanged: (value) { if (value != null) onLocaleChanged(value); },
              items: const [
                DropdownMenuItem(value: Locale('en'), child: LocalizedText('English')),
                DropdownMenuItem(value: Locale('fa'), child: LocalizedText('فارسی')),
              ],
            ),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          SwitchListTile(title: const LocalizedText('Dark appearance'), subtitle: const LocalizedText('Change the app theme'), value: darkMode, onChanged: onThemeChanged),
          const Divider(height: 1, indent: 16, endIndent: 16),
          SwitchListTile(title: const LocalizedText('Reduce animations'), subtitle: const LocalizedText('Reduce decorative motion'), value: reducedMotion, onChanged: onReducedMotionChanged),
          const Divider(height: 1, indent: 16, endIndent: 16),
          SwitchListTile(title: const LocalizedText('Show destination address'), subtitle: const LocalizedText('Hides the server address in the UI'), value: showDestination, onChanged: onShowDestinationChanged),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            leading: const Icon(Icons.apps_rounded),
            title: const LocalizedText('Bypass apps'),
            subtitle: Text(excludedAppsCount == 0
                ? context.tr('No apps excluded')
                : '$excludedAppsCount apps excluded from VPN'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: onEditAppRouting,
          ),
        ])),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF29221F) : const Color(0xFFFFF1E8),
            border: Theme.of(context).brightness == Brightness.dark ? Border.all(color: const Color(0xFF594038)) : null,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            LocalizedText('Platform scope', style: TextStyle(fontWeight: FontWeight.w800, color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFFFFB29B) : const Color(0xFF8A5548))),
            const SizedBox(height: 8),
            LocalizedText('Android VPN sessions route system DNS through the selected proxy. You can exclude selected launcher apps from the VPN. iPhone still needs its Network Extension project, Apple signing, and device testing. A kill switch, auto-connect, and trusted country lookup are not enabled in this build.', style: TextStyle(fontSize: 12, height: 1.5, color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFFE6C7BC) : const Color(0xFF8A5548))),
          ]),
        ),
        const SizedBox(height: 20),
        const ListTile(leading: _BrandMark(), title: LocalizedText('V2rayAG'), subtitle: LocalizedText('Source: Telegram @V2rayAG\nDeveloper: V2rayAG telegram channel and HashtagAlireza')),
      ]);
}

Future<String?> _readClipboard(BuildContext context) async {
  try {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!context.mounted) return null;
    final value = data?.text?.trim();
    if (value == null || value.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: LocalizedText('Clipboard is empty.')));
      return null;
    }
    return value;
  } on Object {
    if (!context.mounted) return null;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: LocalizedText('Could not read the clipboard.')));
    return null;
  }
}

Future<String?> _scanQr(BuildContext context) => showDialog<String>(
      context: context,
      builder: (_) => const _QrScanDialog(),
    );

class _QrScanDialog extends StatefulWidget {
  const _QrScanDialog();

  @override
  State<_QrScanDialog> createState() => _QrScanDialogState();
}

class _QrScanDialogState extends State<_QrScanDialog> {
  bool _returned = false;

  void _onDetect(BarcodeCapture capture) {
    if (_returned) return;
    final value = capture.barcodes
        .map((barcode) => barcode.rawValue)
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .firstOrNull;
    if (value == null) return;
    _returned = true;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: const LocalizedText('Scan a subscription QR'),
            leading: IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded)),
          ),
          body: Stack(fit: StackFit.expand, children: [
            MobileScanner(onDetect: _onDetect),
            IgnorePointer(
              child: Center(
                child: Container(
                  width: 270,
                  height: 210,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 3),
                    borderRadius: BorderRadius.circular(22),
                  ),
                ),
              ),
            ),
            const Positioned(
              left: 24,
              right: 24,
              bottom: 36,
              child: LocalizedText('Keep the QR code inside the frame. Its contents stay on this device.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, shadows: [Shadow(blurRadius: 8, color: Colors.black)])),
            ),
          ]),
        ),
      );
}

class _SubscriptionEditorSheet extends StatefulWidget {
  const _SubscriptionEditorSheet({
    required this.id,
    required this.initialName,
    required this.initialUrl,
    required this.fixedName,
  });

  final String id;
  final String initialName;
  final String initialUrl;
  final bool fixedName;

  @override
  State<_SubscriptionEditorSheet> createState() => _SubscriptionEditorSheetState();
}

class _SubscriptionEditorSheetState extends State<_SubscriptionEditorSheet> {
  late final TextEditingController _nameController = TextEditingController(text: widget.initialName);
  late final TextEditingController _urlController = TextEditingController(text: widget.initialUrl);
  bool _hideUrl = true;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.clear();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final text = await _readClipboard(context);
    if (text != null && mounted) setState(() { _urlController.text = text; _error = null; });
  }

  Future<void> _scan() async {
    final value = await _scanQr(context);
    if (value != null && mounted) setState(() { _urlController.text = value; _error = null; });
  }

  void _save() {
    final name = widget.fixedName ? 'Exclusive V2rayAG Subs' : _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Add a name for this subscription.');
      return;
    }
    try {
      final uri = SubscriptionService.validateSubscriptionUrl(_urlController.text);
      Navigator.of(context).pop(SavedSubscription(id: widget.id, name: name, url: uri.toString()));
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
        child: SafeArea(top: false, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 38, height: 4, decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(5)))),
          const SizedBox(height: 18),
          LocalizedText(widget.fixedName ? 'Set up Exclusive V2rayAG Subs' : 'Add a subscription', style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
          const SizedBox(height: 7),
          const LocalizedText('Paste or scan your provider’s HTTPS subscription URL. Your own URL is needed; none is bundled with this app.', style: TextStyle(fontSize: 12, color: _muted, height: 1.4)),
          if (!widget.fixedName) ...[
            const SizedBox(height: 14),
            TextField(
              controller: _nameController,
              decoration: InputDecoration(labelText: context.tr('Name'), filled: true, fillColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF101817) : const Color(0xFFF4F6F3), border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none)),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _urlController,
            obscureText: _hideUrl,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: context.tr('Private HTTPS subscription URL'),
              hintText: context.tr('https://…'),
              errorText: _error == null ? null : context.tr(_error!),
              filled: true,
              fillColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF101817) : const Color(0xFFF4F6F3),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
              suffixIcon: IconButton(tooltip: context.tr(_hideUrl ? 'Show URL' : 'Hide URL'), onPressed: () => setState(() => _hideUrl = !_hideUrl), icon: Icon(_hideUrl ? Icons.visibility_outlined : Icons.visibility_off_outlined)),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            OutlinedButton.icon(onPressed: _paste, icon: const Icon(Icons.content_paste_rounded), label: const LocalizedText('Paste clipboard')),
            OutlinedButton.icon(onPressed: _scan, icon: const Icon(Icons.qr_code_scanner_rounded), label: const LocalizedText('Scan QR')),
          ]),
          const SizedBox(height: 8),
          const LocalizedText('Saved with Android Keystore-backed encrypted storage. Fetching requires HTTPS; server entries stay in memory and are not uploaded to V2rayAG.', style: TextStyle(fontSize: 11, color: _muted, height: 1.4)),
          const SizedBox(height: 14),
          SizedBox(width: double.infinity, child: FilledButton(onPressed: _save, child: const LocalizedText('Save securely'))),
        ])),
      ),
    );
  }
}

class _ImportSheet extends StatefulWidget {
  const _ImportSheet();
  @override
  State<_ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends State<_ImportSheet> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.clear();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final text = await _readClipboard(context);
    if (text != null && mounted) setState(() { _controller.text = text; _error = null; });
  }

  Future<void> _scan() async {
    final value = await _scanQr(context);
    if (value != null && mounted) setState(() { _controller.text = value; _error = null; });
  }

  void _preview() {
    final input = _controller.text.trim();
    final scheme = Uri.tryParse(input)?.scheme.toLowerCase();
    if (scheme == 'http' || scheme == 'https') {
      setState(() => _error = 'That is a subscription URL, not a single server link. Open Servers and choose Add subscription.');
      return;
    }
    try {
      final profile = VpnProfile.fromShareLink(input);
      _controller.clear();
      Navigator.of(context).pop(profile);
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'That link could not be parsed. Check the format and try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
        child: SafeArea(top: false, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 38, height: 4, decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(5)))),
          const SizedBox(height: 18),
          const LocalizedText('Import a server link', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const LocalizedText('One server link: VLESS, VMess, Shadowsocks, or Trojan.', style: TextStyle(fontSize: 12, color: _muted)),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 2,
            maxLines: 4,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              hintText: context.tr('Paste one server share link'),
              errorText: _error == null ? null : context.tr(_error!),
              filled: true,
              fillColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF101817) : const Color(0xFFF4F6F3),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, children: [
            OutlinedButton.icon(onPressed: _paste, icon: const Icon(Icons.content_paste_rounded), label: const LocalizedText('Paste clipboard')),
            OutlinedButton.icon(onPressed: _scan, icon: const Icon(Icons.qr_code_scanner_rounded), label: const LocalizedText('Scan QR')),
          ]),
          const SizedBox(height: 6),
          const LocalizedText('A single server link is held in app memory for this session only. Use Add subscription for a provider URL.', style: TextStyle(fontSize: 11, color: _muted, height: 1.4)),
          const SizedBox(height: 15),
          SizedBox(width: double.infinity, child: FilledButton(onPressed: _preview, child: const LocalizedText('Add to this session'))),
        ])),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();
  @override
  Widget build(BuildContext context) => Container(
        width: 35,
        height: 35,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(colors: [_mint, Color(0xFF81E0B1), _coral], begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
        child: const Icon(Icons.shield_moon_rounded, size: 21, color: Colors.white),
      );
}
