import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_localizations.dart';
import 'app_preferences.dart';
import 'cdn_fronting.dart';
import 'exclusive_pool_service.dart';
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

/// Keep the connection control available to stop an orphaned native VPN
/// session even when secure storage could not restore its selected profile.
bool canToggleVpnAction({
  required bool hasProfile,
  required bool activeOrPending,
  required bool subscriptionBusy,
  required bool engineBusy,
  required bool canStart,
}) =>
    !engineBusy &&
    (!subscriptionBusy || activeOrPending) &&
    (activeOrPending || (hasProfile && canStart));

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
  ThemeMode _themeMode = ThemeMode.dark;
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
  // Parallel to _profiles: saved-subscription ID, or null for pasted links.
  final List<String?> _profileSources = [];
  final VpnEngine _engine = VpnEngine();
  final ExclusivePoolService _exclusivePool = ExclusivePoolService();
  final SubscriptionRepository _subscriptionRepository = SubscriptionRepository();
  final ProfileRepository _profileRepository = ProfileRepository();
  final CdnFrontingPreferencesRepository _cdnPreferencesRepository =
      CdnFrontingPreferencesRepository();
  CdnFrontingSettings _cdnFrontingSettings = const CdnFrontingSettings();
  final Completer<void> _subscriptionsReady = Completer<void>();
  final Completer<void> _profilesReady = Completer<void>();
  final Completer<void> _routingPreferencesReady = Completer<void>();
  Future<void> _profileWriteQueue = Future<void>.value();
  bool _profileRestoreFailed = false;
  String? _profileStorageErrorCode;
  bool _subscriptionRestoreFailed = false;
  bool _legacySecureDataUnavailable = false;
  bool _secureNamespaceRotated = false;
  final Set<String> _sessionOnlySubscriptionIds = {};
  List<SavedSubscription> _savedSubscriptions = [];
  bool _subscriptionBusy = false;
  int? _selectedIndex;
  bool _useManualProfile = false;
  bool _connectionModeChangedByUser = false;
  bool _connectionProtocolChangedByUser = false;
  bool _poolSearching = false;
  bool _cancelPoolSearch = false;
  bool _poolSummaryRestored = false;
  PoolConnectionSummary? _activePoolSummary;
  VpnProfile? _activePoolProfile;
  bool _activePoolPingChecked = false;
  bool? _activePoolTelegramVerified;
  String? _activePoolLeaseId;
  static const _activePoolSummaryKey = 'active_pool_summary_v1';
  final Map<int, int> _profilePings = {};
  final Map<int, String> _profilePingFailures = {};
  final Set<int> _failedPings = {};
  final Set<int> _probingProfiles = {};
  String? _batchPingSubscriptionId;
  int _batchPingCompleted = 0;
  int _batchPingTotal = 0;
  bool _cancelBatchPing = false;
  final Set<String> _excludedPackages = {};
  static const MethodChannel _appPickerChannel =
      MethodChannel('v2rayag/app_picker');
  static const _excludedPackagesKey = 'excluded_packages_v1';
  static const _manualProfileModeKey = 'manual_profile_mode_v1';

  // Remove a legacy device-only Exclusive entry during migration. The app no
  // longer accepts or exposes centrally managed credentials locally.
  static const _retiredExclusiveId = 'exclusive-v2rayag';

  @override
  void initState() {
    super.initState();
    _engine.addListener(_onEngineChanged);
    _engine.initialize();
    _restoreSubscriptions();
    _restoreProfiles();
    _restoreExcludedPackages();
    _restorePoolSummary();
    _restoreConnectionMode();
  }

  String _safeStorageFailure(Object error) {
    if (error is PlatformException) {
      final code = error.code.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '');
      return code.isEmpty ? 'PlatformException' : code;
    }
    if (error is MissingPluginException) return 'MissingPluginException';
    if (error is FormatException) return 'InvalidStoredData';
    return 'SecureStorageError';
  }

  Future<void> _restoreSubscriptions() async {
    try {
      final saved = await _subscriptionRepository.readAll();
      final personal = saved
          .where((item) => item.id != _retiredExclusiveId)
          .toList(growable: true);
      if (personal.length != saved.length) {
        // Best-effort removal of the old private Exclusive URL from secure
        // storage; it is never copied into the new personal list.
        try {
          await _subscriptionRepository.saveAll(personal);
        } on Object {
          // Keep the legacy entry hidden even if secure storage is unavailable.
        }
      }
      _legacySecureDataUnavailable = _legacySecureDataUnavailable ||
          _subscriptionRepository.legacyDataUnreadable;
      _secureNamespaceRotated = _secureNamespaceRotated ||
          _subscriptionRepository.namespaceRotated;
      if (mounted) {
        setState(() => _savedSubscriptions = personal);
      }
    } on Object {
      _subscriptionRestoreFailed = true;
      // Keep the Connect screen quiet. Storage status remains available from
      // Servers when the user chooses to manage imported subscriptions.
    } finally {
      if (!_subscriptionsReady.isCompleted) _subscriptionsReady.complete();
    }
  }

  Future<void> _restoreProfiles() async {
    try {
      final saved = await _profileRepository.read();
      _legacySecureDataUnavailable = _legacySecureDataUnavailable ||
          _profileRepository.legacyDataUnreadable;
      _secureNamespaceRotated = _secureNamespaceRotated ||
          _profileRepository.namespaceRotated;
      if (!mounted) return;
      setState(() {
        _profiles
          ..clear()
          ..addAll(saved.profiles);
        _profileSources
          ..clear()
          ..addAll(saved.sources);
        _selectedIndex = saved.selectedIndex;
      });
      // Old unreadable user records stay untouched; do not interrupt first
      // launch with a non-actionable snackbar. Servers shows storage status.
    } on Object catch (error) {
      _profileRestoreFailed = true;
      _profileStorageErrorCode = _safeStorageFailure(error);
    } finally {
      if (!_profilesReady.isCompleted) _profilesReady.complete();
    }
  }

  Future<bool> _persistProfiles() async {
    await _profilesReady.future;
    if (_profileRestoreFailed) {
      if (mounted) {
        _showMessage(
          '${context.tr('Saved profile data cannot be decrypted')} (${_profileStorageErrorCode ?? 'Unknown'}). '
          '${context.tr('Existing unreadable data has not been overwritten')}. '
          '${context.tr('New profiles will persist only after a secure save succeeds')}.'
        );
      }
      return false;
    }
    final profiles = List<VpnProfile>.unmodifiable(_profiles);
    final sources = List<String?>.unmodifiable(_profileSources);
    final selectedIndex = _selectedIndex;
    final write = _profileWriteQueue
        .catchError((Object _) {})
        .then<void>((_) => _profileRepository.save(
              profiles: profiles,
              sources: sources,
              selectedIndex: selectedIndex,
            ));
    _profileWriteQueue = write;
    try {
      await write;
      return true;
    } on Object catch (error) {
      _profileStorageErrorCode = _safeStorageFailure(error);
      if (mounted) {
        _showMessage(
          'Profiles could not be saved securely ($_profileStorageErrorCode); changes remain only until this app closes.',
        );
      }
      return false;
    }
  }

  Future<void> _recoverUnreadableSecureStorage() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const LocalizedText('Secure storage status'),
        content: const LocalizedText(
          'Unreadable encrypted records are never deleted by this app. New data is written to an isolated encrypted storage namespace and verified after each save. Older records that Android cannot decrypt remain untouched; if they are not restored, add them again. If a new save fails, the app will report it instead of claiming the data was saved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const LocalizedText('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _restorePoolSummary() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(_activePoolSummaryKey);
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          final summary = PoolConnectionSummary.fromJson(decoded);
          if (mounted && (!_engine.initialized || _engine.connected || _engine.connecting)) {
            setState(() => _activePoolSummary = summary);
          } else if (_engine.initialized) {
            await preferences.remove(_activePoolSummaryKey);
          }
        }
      }
    } on Object {
      // This summary contains no secret configuration; ignore corrupt UI metadata.
    } finally {
      _poolSummaryRestored = true;
      if (mounted) setState(() {});
    }
  }

  Future<void> _persistPoolSummary(PoolConnectionSummary? summary) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      if (summary == null) {
        await preferences.remove(_activePoolSummaryKey);
      } else {
        await preferences.setString(_activePoolSummaryKey, jsonEncode(summary.toJson()));
      }
    } on Object {
      // Session recovery still works through native state even if labels cannot persist.
    }
  }

  Future<void> _releaseActivePoolLease() async {
    final leaseId = _activePoolLeaseId;
    _activePoolLeaseId = null;
    if (leaseId != null) await _exclusivePool.releaseLease(leaseId);
  }

  Future<void> _restoreConnectionMode() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final manual = preferences.getBool(_manualProfileModeKey) ?? false;
      final protocolSettings = await _cdnPreferencesRepository.read();
      if (mounted) {
        setState(() {
          if (!_connectionProtocolChangedByUser) {
            _cdnFrontingSettings = protocolSettings;
          }
          if (!_connectionModeChangedByUser) {
            // CDN Fronting is a protocol for automatic-pool candidates only.
            // Never restore it on top of a previously selected personal profile.
            final activeSettings = _connectionProtocolChangedByUser
                ? _cdnFrontingSettings
                : protocolSettings;
            _useManualProfile = activeSettings.protocol == ConnectionProtocol.cdnFronting
                ? false
                : manual;
          }
        });
      }
    } on Object {
      // Automatic pool mode is the safe default when preferences are unavailable.
    }
  }

  Future<bool> _saveConnectionProtocol(CdnFrontingSettings next) async {
    if (_engine.connected || _engine.connecting || _engine.disconnecting ||
        _poolSearching || _subscriptionBusy || _engine.busy) {
      _showMessage('Disconnect before changing connection protocol.');
      return false;
    }
    _connectionProtocolChangedByUser = true;
    try {
      final validated = next.validated();
      await _cdnPreferencesRepository.save(validated);
      if (!mounted) return false;
      setState(() {
        _cdnFrontingSettings = validated;
        if (validated.protocol == ConnectionProtocol.cdnFronting) {
          _useManualProfile = false;
        }
        _tab = 0;
      });
      if (validated.protocol == ConnectionProtocol.cdnFronting) {
        _connectionModeChangedByUser = true;
        unawaited(_saveConnectionMode(false));
      }
      _showMessage('Connection protocol settings saved.');
      return true;
    } on FormatException catch (error) {
      if (mounted) _showMessage(error.message);
      return false;
    } on Object {
      if (mounted) {
        final persisted = await _cdnPreferencesRepository.read();
        setState(() => _cdnFrontingSettings = persisted);
        _showMessage('Could not save connection protocol settings.');
      }
      return false;
    }
  }

  void _deactivateCdnProtocol() {
    if (_cdnFrontingSettings.protocol == ConnectionProtocol.auto) return;
    final next = _cdnFrontingSettings.withProtocol(ConnectionProtocol.auto);
    _connectionProtocolChangedByUser = true;
    setState(() => _cdnFrontingSettings = next);
    unawaited(_cdnPreferencesRepository.save(next).catchError((Object _) {
      if (mounted) _showMessage('Could not save connection protocol settings.');
    }));
  }

  Future<void> _saveConnectionMode(bool manual) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(_manualProfileModeKey, manual);
    } on Object {
      // Keep the current session usable even if this preference cannot be saved.
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
    if (_poolSummaryRestored && _engine.initialized && !_engine.connected &&
        !_engine.connecting && !_engine.disconnecting && !_poolSearching) {
      _activePoolSummary = null;
      _activePoolProfile = null;
      _activePoolPingChecked = false;
      _activePoolTelegramVerified = null;
      unawaited(_persistPoolSummary(null));
      unawaited(_releaseActivePoolLease());
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _engine.removeListener(_onEngineChanged);
    _engine.dispose();
    _exclusivePool.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: LocalizedText(message)));
  }

  Future<void> _toggleConnection() async {
    if (_subscriptionBusy) {
      _showMessage('Wait for the subscription operation to finish.');
      return;
    }
    final isActive = _engine.connected || _engine.connecting || _engine.disconnecting;
    if (isActive || _poolSearching) {
      _cancelPoolSearch = true;
      // Clear the previous session presentation immediately. The engine still
      // blocks a new start until Android confirms the native tunnel is stopped.
      if (mounted) {
        setState(() {
          _activePoolSummary = null;
          _activePoolProfile = null;
          _activePoolPingChecked = false;
          _activePoolTelegramVerified = null;
        });
      }
      unawaited(_persistPoolSummary(null));
      if (isActive) {
        final stopped = await _engine.disconnect();
        if (!stopped) {
          if (mounted && _engine.message != null) _showMessage(_engine.message!);
          return;
        }
        await _releaseActivePoolLease();
      } else if (!_poolSearching) {
        await _releaseActivePoolLease();
      }
      return;
    }

    final profile = _useManualProfile && _selectedIndex != null &&
            _selectedIndex! < _profiles.length
        ? _profiles[_selectedIndex!]
        : null;
    if (profile != null) {
      await _releaseActivePoolLease();
      setState(() {
        _activePoolSummary = null;
        _activePoolProfile = null;
        _activePoolPingChecked = false;
        _activePoolTelegramVerified = null;
      });
      unawaited(_persistPoolSummary(null));
      await _engine.connect(
        profile,
        blockedApps: _excludedPackages.toList(growable: false),
      );
      if (mounted && _engine.message != null) _showMessage(_engine.message!);
      return;
    }
    if (_useManualProfile) {
      _showMessage('Select a personal server or switch to automatic pool mode.');
      return;
    }
    await _connectAutomatically();
  }

  Future<void> _connectAutomatically() async {
    if (!_engine.canStart) {
      _showMessage('The VPN engine is not ready yet. Try again in a moment.');
      return;
    }

    // Acquire one lease, try the real native tunnel immediately, then move to
    // the next distinct profile only after Android safely cleans up a failure.
    // A standalone latency probe is diagnostic only; it must never gate a real
    // connection or delay the first usable candidate.
    final triedIds = <String>{};
    String? currentLeaseId;
    String? retainedLeaseId;
    var sawCdnCompatibleCandidate = false;
    var sawCdnIncompatibleCandidate = false;
    final cdnOverridesActive =
        _cdnFrontingSettings.protocol == ConnectionProtocol.cdnFronting &&
            _cdnFrontingSettings.hasOverrides;
    _activePoolLeaseId = null;
    setState(() {
      _poolSearching = true;
      _cancelPoolSearch = false;
      _activePoolSummary = null;
      _activePoolProfile = null;
      _activePoolPingChecked = false;
      _activePoolTelegramVerified = null;
    });
    unawaited(_persistPoolSummary(null));

    try {
      while (!_cancelPoolSearch) {
        late final ExclusivePoolLease lease;
        try {
          lease = await _exclusivePool.acquireLease(excludeIds: triedIds);
        } on PoolCandidatesUnavailableException {
          break;
        }
        currentLeaseId = lease.leaseId;
        if (!triedIds.add(lease.candidate.id)) {
          await _exclusivePool.releaseLease(lease.leaseId);
          currentLeaseId = null;
          break;
        }
        if (_cancelPoolSearch) {
          await _exclusivePool.releaseLease(lease.leaseId);
          currentLeaseId = null;
          break;
        }

        final candidate = lease.candidate;
        late final List<VpnProfile> profileAttempts;
        try {
          profileAttempts = buildCdnProfileAttempts(candidate.profile, _cdnFrontingSettings);
          sawCdnCompatibleCandidate = true;
        } on CdnProfileNotSupportedException {
          sawCdnIncompatibleCandidate = true;
          await _exclusivePool.releaseLease(lease.leaseId);
          currentLeaseId = null;
          continue;
        } on FormatException {
          // A malformed candidate must not strand its lease or prevent the
          // next automatic server from being tried.
          sawCdnIncompatibleCandidate = true;
          await _exclusivePool.releaseLease(lease.leaseId);
          currentLeaseId = null;
          continue;
        }
        VpnProfile? attemptedProfile;
        var connected = false;
        for (final profileAttempt in profileAttempts) {
          if (_cancelPoolSearch) break;
          attemptedProfile = profileAttempt;
          connected = await _engine.connect(
            profileAttempt,
            blockedApps: _excludedPackages.toList(growable: false),
          );
          if (connected || _cancelPoolSearch || _engine.connected ||
              _engine.connecting || _engine.disconnecting || !_engine.canStart) {
            break;
          }
        }

        if (_cancelPoolSearch) {
          // A cancel can arrive while Android's permission sheet or start
          // handshake is open. Do not release the lease until native state is
          // reconciled; never start another route over an uncertain tunnel.
          if (_engine.connected || _engine.connecting || _engine.disconnecting) {
            final stopped = await _engine.disconnect();
            if (!stopped &&
                (_engine.connected || _engine.connecting || _engine.disconnecting)) {
              retainedLeaseId = lease.leaseId;
              _activePoolLeaseId = lease.leaseId;
              _activePoolProfile = candidate.profile;
              if (mounted) {
                setState(() {
                  _activePoolSummary = candidate.summary;
                  _activePoolPingChecked = false;
                  _activePoolTelegramVerified = null;
                });
                unawaited(_persistPoolSummary(candidate.summary));
              }
            }
          }
          if (retainedLeaseId == null) {
            await _exclusivePool.releaseLease(lease.leaseId);
            currentLeaseId = null;
          }
          break;
        }

        if (connected) {
          // Native connection confirmation owns the session. A blocked third-
          // party ping endpoint is shown as inconclusive, never as a reason to
          // tear down a working tunnel or rotate to another profile.
          retainedLeaseId = lease.leaseId;
          currentLeaseId = null;
          _activePoolLeaseId = lease.leaseId;
          _activePoolProfile = attemptedProfile ?? candidate.profile;
          if (mounted) {
            setState(() {
              _activePoolSummary = candidate.summary;
              _activePoolPingChecked = false;
              _activePoolTelegramVerified = null;
            });
            unawaited(_persistPoolSummary(candidate.summary));
          }
          final latency = await _engine.measurePing(
            attemptedProfile ?? candidate.profile,
            telegramOnly: true,
          );
          if (mounted) {
            setState(() {
              _activePoolPingChecked = true;
              _activePoolTelegramVerified = latency != null &&
                  _engine.lastPingWasTelegram;
            });
          }
          return;
        }

        if (_engine.connected || _engine.connecting || _engine.disconnecting) {
          // A native start that did not settle cleanly still owns its lease.
          // Keep the current profile visible and block further automatic starts.
          retainedLeaseId = lease.leaseId;
          currentLeaseId = null;
          _activePoolLeaseId = lease.leaseId;
          _activePoolProfile = attemptedProfile ?? candidate.profile;
          if (mounted) {
            setState(() {
              _activePoolSummary = candidate.summary;
              _activePoolPingChecked = false;
              _activePoolTelegramVerified = null;
            });
            unawaited(_persistPoolSummary(candidate.summary));
          }
          if (_engine.message != null && mounted) {
            _showMessage(_engine.message!);
          }
          break;
        }

        await _exclusivePool.releaseLease(lease.leaseId);
        currentLeaseId = null;
        if (!shouldRetrySubscriptionProfile(_engine.failureCategory) ||
            !_engine.canStart || _engine.busy || _engine.connected ||
            _engine.connecting || _engine.disconnecting) {
          if (_engine.message != null && mounted) {
            _showMessage(_engine.message!);
          }
          break;
        }
      }

      if (retainedLeaseId == null && !_cancelPoolSearch && mounted &&
          _engine.message == null) {
        if (cdnOverridesActive && sawCdnIncompatibleCandidate &&
            !sawCdnCompatibleCandidate) {
          _showMessage('CDN Fronting needs an automatic server using TLS WebSocket.');
        } else {
          _showMessage('Could not connect to an available server. Please try again later.');
        }
      }
    } on FormatException catch (error) {
      if (!_cancelPoolSearch && mounted) _showMessage(error.message);
    } on Object {
      if (!_cancelPoolSearch && mounted) {
        _showMessage('Could not reach the secure server pool. Check your internet and try again.');
      }
    } finally {
      if (currentLeaseId != null && currentLeaseId != retainedLeaseId) {
        await _exclusivePool.releaseLease(currentLeaseId);
      }
      if (mounted) setState(() => _poolSearching = false);
    }
  }

  void _useAutomaticPool() {
    if (_engine.connected || _engine.connecting || _engine.disconnecting || _poolSearching) return;
    _connectionModeChangedByUser = true;
    setState(() => _useManualProfile = false);
    _deactivateCdnProtocol();
    unawaited(_saveConnectionMode(false));
  }

  void _usePersonalProfile({bool openServers = true}) {
    if (_engine.connected || _engine.connecting || _engine.disconnecting || _poolSearching) {
      _showMessage('Disconnect before changing connection mode.');
      return;
    }
    _connectionModeChangedByUser = true;
    setState(() {
      _useManualProfile = true;
      if (openServers) _tab = 1;
    });
    _deactivateCdnProtocol();
    unawaited(_saveConnectionMode(true));
    if (_profiles.isEmpty) {
      _showMessage('Import a personal server profile to use this mode.');
    } else if (_selectedIndex == null) {
      _showMessage('Select a personal server before connecting.');
    }
  }

  Future<void> _measurePing() async {
    if (_subscriptionBusy || _engine.pingBusy) return;
    final profile = _activePoolSummary != null && _engine.connected
        ? _activePoolProfile
        : _selectedIndex == null
            ? null
            : _profiles[_selectedIndex!];
    if (profile == null && !_engine.connected) return;
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

  void _showAbout() {
    showAboutDialog(
      context: context,
      applicationName: 'V2rayAG',
      applicationVersion: '0.1.0',
      applicationIcon: const _BrandMark(size: 48),
      applicationLegalese: 'Android VPN client · V2rayAG · HashtagAlireza',
      children: [
        const SizedBox(height: 8),
        const LocalizedText(
          'Manage imported server links and subscriptions, choose a route, and inspect connection diagnostics. Unsupported tunnel features are not presented as working controls.',
          style: TextStyle(fontSize: 13),
        ),
        if (_engine.coreVersion != null) ...[
          const SizedBox(height: 8),
          Text('VPN core: ${_engine.coreVersion}', style: const TextStyle(fontSize: 12)),
        ],
      ],
    );
  }

  Future<int?> _probeProfile(int index, {bool batchScan = false}) async {
    if (index < 0 || index >= _profiles.length || _probingProfiles.contains(index)) {
      return null;
    }
    setState(() {
      _probingProfiles.add(index);
      _profilePings.remove(index);
      _profilePingFailures.remove(index);
      _failedPings.remove(index);
    });
    final result = await _engine.measurePing(
      _profiles[index],
      batchScan: batchScan,
    );
    if (!mounted) return null;
    setState(() {
      _probingProfiles.remove(index);
      if (result != null) {
        _profilePings[index] = result;
        _profilePingFailures.remove(index);
        _failedPings.remove(index);
      } else {
        // This is only a failed end-to-end latency probe; a timeout does not
        // establish that a profile is unusable or justify deleting it.
        _profilePingFailures[index] = _engine.failureCategory ?? 'NoDelayResult';
        _failedPings.add(index);
      }
    });
    return result;
  }

  Future<void> _testProfileLatency(int index) async {
    if (_subscriptionBusy || _batchPingSubscriptionId != null || _engine.connected ||
        _engine.connecting || _engine.disconnecting || _engine.busy) {
      return;
    }
    if (index < 0 || index >= _profiles.length || _probingProfiles.contains(index)) return;
    final result = await _probeProfile(index);
    if (result == null && mounted && _engine.message != null) {
      _showMessage(_engine.message!);
    }
  }

  Future<void> _testSubscriptionPings(SavedSubscription subscription) async {
    if (_subscriptionBusy || _batchPingSubscriptionId != null || _engine.connected ||
        _engine.connecting || _engine.disconnecting || _engine.busy) {
      return;
    }
    final indices = <int>[
      for (var i = 0; i < _profiles.length; i++)
        if (i < _profileSources.length && _profileSources[i] == subscription.id) i,
    ];
    if (indices.isEmpty) {
      _showMessage('Refresh this subscription to load its profiles before testing.');
      return;
    }
    setState(() {
      _subscriptionBusy = true;
      _batchPingSubscriptionId = subscription.id;
      _batchPingCompleted = 0;
      _batchPingTotal = indices.length;
      _cancelBatchPing = false;
      _profilePings.removeWhere((index, _) => indices.contains(index));
      _profilePingFailures.removeWhere((index, _) => indices.contains(index));
      _failedPings.removeAll(indices);
    });
    var responded = 0;
    var attempted = 0;
    try {
      for (final index in indices) {
        if (_cancelBatchPing || !mounted) break;
        final result = await _probeProfile(index, batchScan: true);
        attempted++;
        if (result != null) responded++;
        if (mounted) setState(() => _batchPingCompleted = attempted);
      }
    } finally {
      final cancelled = _cancelBatchPing;
      if (mounted) {
        setState(() {
          _subscriptionBusy = false;
          _batchPingSubscriptionId = null;
          _batchPingCompleted = 0;
          _batchPingTotal = 0;
        });
        _showMessage(cancelled
            ? 'Latency test stopped after $attempted of ${indices.length} profiles.'
            : 'Latency test complete: $responded of ${indices.length} profiles returned a result.');
      }
      _cancelBatchPing = false;
    }
  }

  void _cancelSubscriptionPings() {
    if (_batchPingSubscriptionId == null) return;
    setState(() => _cancelBatchPing = true);
  }

  void _selectProfile(int index) {
    if (_subscriptionBusy || _poolSearching || !_profilesReady.isCompleted) return;
    if (_engine.connected || _engine.connecting || _engine.disconnecting) {
      _showMessage('Disconnect before changing the active server.');
      return;
    }
    _connectionModeChangedByUser = true;
    setState(() {
      _selectedIndex = index;
      _useManualProfile = true;
    });
    _deactivateCdnProtocol();
    unawaited(_saveConnectionMode(true));
    unawaited(_persistProfiles().then<void>((_) {}));
  }

  Future<void> _importProfile() async {
    await _profilesReady.future;
    if (!mounted) return;
    if (_subscriptionBusy) {
      _showMessage('Wait for the subscription operation to finish.');
      return;
    }
    if (_engine.connected || _engine.connecting || _engine.disconnecting) {
      _showMessage('Disconnect before importing another server.');
      return;
    }
    final imported = await showModalBottomSheet<List<VpnProfile>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ImportSheet(),
    );
    if (imported == null || imported.isEmpty || !mounted) return;
    if (_engine.connected || _engine.connecting || _engine.disconnecting) {
      _showMessage('Disconnect before importing another active route.');
      return;
    }
    final added = <VpnProfile>[];
    for (final profile in imported) {
      final alreadyExists = _profiles.any((existing) => existing.config == profile.config) ||
          added.any((existing) => existing.config == profile.config);
      if (!alreadyExists) added.add(profile);
    }
    if (added.isEmpty) {
      _showMessage('These server links are already in the list.');
      return;
    }
    setState(() {
      final firstNewIndex = _profiles.length;
      _profiles.addAll(added);
      _profileSources.addAll(List<String?>.filled(added.length, null));
      _selectedIndex ??= firstNewIndex;
      _tab = 1;
    });
    final saved = await _persistProfiles();
    if (mounted && saved) {
      _showMessage('Added ${added.length} server profiles and saved them securely.');
    }
  }

  Future<SavedSubscription?> _editSubscription({SavedSubscription? existing}) {
    final id = existing?.id ?? 'custom-${DateTime.now().microsecondsSinceEpoch}';
    return showModalBottomSheet<SavedSubscription>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SubscriptionEditorSheet(
        id: id,
        initialName: existing?.name ?? '',
        initialUrl: existing?.url ?? '',
      ),
    );
  }

  void _rememberSessionOnlySubscription(SavedSubscription subscription) {
    setState(() {
      final index = _savedSubscriptions.indexWhere((item) => item.id == subscription.id);
      if (index < 0) {
        _savedSubscriptions.add(subscription);
      } else {
        _savedSubscriptions[index] = subscription;
      }
      _sessionOnlySubscriptionIds.add(subscription.id);
    });
  }

  Future<_SubscriptionSaveChoice> _saveSubscription(
    SavedSubscription subscription,
  ) async {
    if (_subscriptionRestoreFailed) {
      if (!mounted) return _SubscriptionSaveChoice.cancelled;
      final useOnce = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const LocalizedText('Secure storage is unreadable'),
          content: const LocalizedText(
            'The app will not replace data it cannot read. You can cancel, or use this subscription for this session only; it will not be saved and will disappear when the app closes.',
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
      if (useOnce != true || !mounted) return _SubscriptionSaveChoice.cancelled;
      _rememberSessionOnlySubscription(subscription);
      return _SubscriptionSaveChoice.useOnce;
    }
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
      if (useOnce != true || !mounted) {
        return _SubscriptionSaveChoice.cancelled;
      }
      _rememberSessionOnlySubscription(subscription);
      return _SubscriptionSaveChoice.useOnce;
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
    final subscription = await _editSubscription();
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
    final updated = await _editSubscription(existing: existing);
    if (updated == null || !mounted) return;
    final choice = await _saveSubscription(updated);
    if (!mounted || choice == _SubscriptionSaveChoice.cancelled) return;
    await _refreshSubscription(updated);
  }

  Future<void> _removeSubscription(SavedSubscription subscription) async {
    if (_subscriptionBusy || _engine.connected || _engine.connecting || _engine.disconnecting) return;
    await _subscriptionsReady.future;
    await _profilesReady.future;
    if (!mounted) return;
    final sessionOnly = _sessionOnlySubscriptionIds.contains(subscription.id);
    if (_subscriptionRestoreFailed && !sessionOnly) {
      _showMessage('Subscription storage could not be read; repair it before changing saved subscriptions.');
      return;
    }
    final next = _savedSubscriptions.where((item) => item.id != subscription.id).toList();
    final selectedConfig = _selectedIndex != null && _selectedIndex! < _profiles.length
        ? _profiles[_selectedIndex!].config
        : null;
    try {
      if (!_subscriptionRestoreFailed) {
        await _subscriptionRepository.saveAll(next);
      }
      if (!mounted) return;
      setState(() {
        _savedSubscriptions = next;
        _sessionOnlySubscriptionIds.remove(subscription.id);
        final retained = <VpnProfile>[];
        final retainedSources = <String?>[];
        for (var i = 0; i < _profiles.length; i++) {
          if (_profileSources[i] == subscription.id) continue;
          retained.add(_profiles[i]);
          retainedSources.add(_profileSources[i]);
        }
        _profiles
          ..clear()
          ..addAll(retained);
        _profileSources
          ..clear()
          ..addAll(retainedSources);
        _profilePings.clear();
        _failedPings.clear();
        _probingProfiles.clear();
        _selectedIndex = selectedConfig == null
            ? null
            : _profiles.indexWhere((profile) => profile.config == selectedConfig);
        if (_selectedIndex != null && _selectedIndex! < 0) _selectedIndex = null;
      });
      final profilesSaved = await _persistProfiles();
      if (mounted && profilesSaved) {
        _showMessage('Saved subscription and its profiles were removed from this device.');
      }
    } on Object {
      _showMessage('Could not remove the saved subscription.');
    }
  }

  Future<void> _refreshSubscription(SavedSubscription subscription) async {
    if (_subscriptionBusy) return;
    await _profilesReady.future;
    if (!mounted) return;
    if (_engine.connected || _engine.connecting || _engine.disconnecting) {
      _showMessage('Disconnect before refreshing subscriptions.');
      return;
    }
    setState(() => _subscriptionBusy = true);
    _showMessage('Fetching subscription securely…');
    try {
      final profiles = await SubscriptionService.fetchProfiles(subscription.url);
      if (!mounted) return;
      // Do not replace profiles if Android started or restored a tunnel while
      // the network fetch was in flight.
      if (_engine.connected || _engine.connecting || _engine.disconnecting) {
        _showMessage('Disconnect before refreshing subscriptions.');
        return;
      }
      final sourceId = _savedSubscriptions.any((item) => item.id == subscription.id)
          ? subscription.id
          : null;
      final selectedConfig = _selectedIndex != null && _selectedIndex! < _profiles.length
          ? _profiles[_selectedIndex!].config
          : null;
      final retainedProfiles = <VpnProfile>[];
      final retainedSources = <String?>[];
      for (var i = 0; i < _profiles.length; i++) {
        if (sourceId != null && _profileSources[i] == sourceId) continue;
        retainedProfiles.add(_profiles[i]);
        retainedSources.add(_profileSources[i]);
      }
      // Keep the same server in separate subscriptions visible under each
      // named group; deduplication is performed within each imported payload.
      setState(() {
        _profiles
          ..clear()
          ..addAll(retainedProfiles)
          ..addAll(profiles);
        _profileSources
          ..clear()
          ..addAll(retainedSources)
          ..addAll(List<String?>.filled(profiles.length, sourceId));
        _profilePings.clear();
        _failedPings.clear();
        _probingProfiles.clear();
        final preservedIndex = selectedConfig == null
            ? -1
            : _profiles.indexWhere((profile) => profile.config == selectedConfig);
        _selectedIndex = preservedIndex >= 0
            ? preservedIndex
            : (selectedConfig == null && profiles.isNotEmpty
                ? retainedProfiles.length
                : null);
        _tab = 1;
      });
      final saved = await _persistProfiles();
      if (mounted && saved) {
        _showMessage('Loaded and saved ${profiles.length} profiles for ${subscription.name}.');
      }
    } on FormatException catch (error) {
      // Show only fixed, credential-free parser/fetch messages.
      if (mounted) _showMessage(error.message);
    } on Object {
      if (mounted) _showMessage('Could not load this subscription. Check the secure URL and try again.');
    } finally {
      if (mounted) setState(() => _subscriptionBusy = false);
    }
  }

  void _removeProfile(int index) {
    if (_subscriptionBusy || _poolSearching) return;
    if ((_engine.connected || _engine.connecting || _engine.disconnecting) && index == _selectedIndex) {
      _showMessage('Disconnect before removing the active server.');
      return;
    }
    final removingManualSelection = _useManualProfile && _selectedIndex == index;
    setState(() {
      _profiles.removeAt(index);
      if (index < _profileSources.length) _profileSources.removeAt(index);
      _profilePings.clear();
      _profilePingFailures.clear();
      _failedPings.clear();
      _probingProfiles.clear();
      if (_profiles.isEmpty) {
        _selectedIndex = null;
        _useManualProfile = false;
      } else if (_selectedIndex == index) {
        _selectedIndex = 0;
        _useManualProfile = false;
      } else if (_selectedIndex != null && _selectedIndex! > index) {
        _selectedIndex = _selectedIndex! - 1;
      }
    });
    if (removingManualSelection) {
      _connectionModeChangedByUser = true;
      unawaited(_saveConnectionMode(false));
    }
    unawaited(_persistProfiles().then<void>((_) {}));
  }

  @override
  Widget build(BuildContext context) {
    final selected = _useManualProfile && _selectedIndex != null &&
            _selectedIndex! < _profiles.length
        ? _profiles[_selectedIndex!]
        : null;
    final pages = <Widget>[
      _HomePage(
        profile: selected,
        poolSummary: _activePoolSummary,
        poolPingChecked: _activePoolPingChecked,
        poolTelegramVerified: _activePoolTelegramVerified,
        poolSearching: _poolSearching,
        onUseAutomaticPool: _useAutomaticPool,
        onUsePersonalProfile: () => _usePersonalProfile(openServers: false),
        onOpenServers: () => setState(() => _tab = 1),
        personalMode: _useManualProfile,
        modeSelectionEnabled: !_engine.connected && !_engine.connecting &&
            !_engine.disconnecting && !_poolSearching && !_subscriptionBusy && !_engine.busy,
        engine: _engine,
        showDestination: widget.showDestination,
        reducedMotion: widget.reducedMotion,
        onToggleConnection: _toggleConnection,
        onMeasurePing: _measurePing,
        onShowDiagnostics: _showConnectionDiagnostics,
        subscriptionBusy: _subscriptionBusy || _batchPingSubscriptionId != null,
      ),
      _ProfilesPage(
        profiles: _profiles,
        profileSources: _profileSources,
        selectedIndex: _selectedIndex,
        showDestination: widget.showDestination,
        connected: _engine.connected || _engine.connecting || _engine.disconnecting || _poolSearching,
        onImport: _importProfile,
        onSelect: _selectProfile,
        onRemove: _removeProfile,
        profilePings: _profilePings,
        profilePingFailures: _profilePingFailures,
        failedPings: _failedPings,
        probingProfiles: _probingProfiles,
        onTestProfileLatency: _testProfileLatency,
        subscriptions: _savedSubscriptions,
        onAddSubscription: _addSubscription,
        onEditSubscription: _editSavedSubscription,
        onRemoveSubscription: _removeSubscription,
        onRefreshSubscription: _refreshSubscription,
        onTestSubscriptionPings: _testSubscriptionPings,
        onCancelSubscriptionPings: _cancelSubscriptionPings,
        pingingSubscriptionId: _batchPingSubscriptionId,
        pingBatchCompleted: _batchPingCompleted,
        pingBatchTotal: _batchPingTotal,
        subscriptionBusy: _subscriptionBusy,
        secureStorageNeedsRepair: _subscriptionRestoreFailed || _profileRestoreFailed,
        secureStorageNotice: _subscriptionRestoreFailed || _profileRestoreFailed ||
            _legacySecureDataUnavailable || _secureNamespaceRotated,
        legacyDataUnavailable: _legacySecureDataUnavailable,
        storageNamespaceRotated: _secureNamespaceRotated,
        onRepairSecureStorage: _recoverUnreadableSecureStorage,
      ),
      _SettingsPage(
        locale: widget.locale,
        manualProfileMode: _useManualProfile,
        connectionModeLocked: _engine.connected || _engine.connecting ||
            _engine.disconnecting || _poolSearching || _subscriptionBusy,
        onUseAutomaticPool: _useAutomaticPool,
        onUsePersonalProfile: _usePersonalProfile,
        onLocaleChanged: widget.onLocaleChanged,
        reducedMotion: widget.reducedMotion,
        showDestination: widget.showDestination,
        darkMode: widget.darkMode,
        onReducedMotionChanged: widget.onReducedMotionChanged,
        onShowDestinationChanged: widget.onShowDestinationChanged,
        onThemeChanged: widget.onThemeChanged,
        onEditAppRouting: _editExcludedApps,
        excludedAppsCount: _excludedPackages.length,
        onOpenConnectionProtocol: () => setState(() => _tab = 3),
      ),
      _ConnectionProtocolPage(
        key: const ValueKey('connection-protocol-page'),
        settings: _cdnFrontingSettings,
        locked: _engine.connected || _engine.connecting || _engine.disconnecting ||
            _poolSearching || _subscriptionBusy || _engine.busy,
        onSave: _saveConnectionProtocol,
        onBack: () => setState(() => _tab = 2),
      ),
    ];

    return Scaffold(
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              DrawerHeader(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                ),
                child: Row(
                  children: [
                    const _BrandMark(size: 48),
                    const SizedBox(width: 12),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const LocalizedText(
                          'V2rayAG',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _engine.connected
                              ? context.tr('CONNECTED')
                              : context.tr('NOT CONNECTED'),
                          style: const TextStyle(fontSize: 11, color: _muted),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.radio_button_checked_rounded),
                title: const LocalizedText('Connect'),
                selected: _tab == 0,
                onTap: () {
                  Navigator.of(context).pop();
                  setState(() => _tab = 0);
                },
              ),
              ListTile(
                leading: const Icon(Icons.public_rounded),
                title: const LocalizedText('Servers'),
                selected: _tab == 1,
                onTap: () {
                  Navigator.of(context).pop();
                  setState(() => _tab = 1);
                },
              ),
              ListTile(
                leading: const Icon(Icons.tune_rounded),
                title: const LocalizedText('Settings'),
                selected: _tab == 2,
                onTap: () {
                  Navigator.of(context).pop();
                  setState(() => _tab = 2);
                },
              ),
              ListTile(
                leading: const Icon(Icons.hub_rounded),
                title: const LocalizedText('Connection protocol'),
                subtitle: LocalizedText(_cdnFrontingSettings.protocol == ConnectionProtocol.auto
                    ? 'Auto'
                    : 'CDN Fronting'),
                selected: _tab == 3,
                onTap: () {
                  Navigator.of(context).pop();
                  setState(() => _tab = 3);
                },
              ),
              const Divider(indent: 16, endIndent: 16),
              ListTile(
                leading: const Icon(Icons.bug_report_outlined),
                title: const LocalizedText('Diagnostics & logs'),
                subtitle: const LocalizedText('Local connection status and safe diagnostics'),
                onTap: () {
                  Navigator.of(context).pop();
                  unawaited(_showConnectionDiagnostics());
                },
              ),
              ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: const LocalizedText('About'),
                onTap: () {
                  Navigator.of(context).pop();
                  _showAbout();
                },
              ),
            ],
          ),
        ),
      ),
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            tooltip: context.tr('Open navigation menu'),
            onPressed: () => Scaffold.of(context).openDrawer(),
            icon: const Icon(Icons.menu_rounded),
          ),
        ),
        titleSpacing: 20,
        title: Row(
          children: [
            const _BrandMark(size: 40),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  label: 'V2rayAG',
                  child: ExcludeSemantics(
                    child: RichText(
                      text: TextSpan(
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.35,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        children: const [
                          TextSpan(text: 'V2ray'),
                          TextSpan(text: 'AG', style: TextStyle(color: Color(0xFF22D3D0))),
                        ],
                      ),
                    ),
                  ),
                ),
                const LocalizedText('SECURE • RELIABLE', style: TextStyle(fontSize: 8, letterSpacing: 1.25, color: Color(0xFF7A8298))),
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
        selectedIndex: _tab > 2 ? 2 : _tab,
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
    required this.poolSummary,
    required this.poolPingChecked,
    required this.poolTelegramVerified,
    required this.poolSearching,
    required this.onUseAutomaticPool,
    required this.onUsePersonalProfile,
    required this.onOpenServers,
    required this.personalMode,
    required this.modeSelectionEnabled,
    required this.engine,
    required this.showDestination,
    required this.reducedMotion,
    required this.onToggleConnection,
    required this.onMeasurePing,
    required this.onShowDiagnostics,
    required this.subscriptionBusy,
  });

  final VpnProfile? profile;
  final PoolConnectionSummary? poolSummary;
  final bool poolPingChecked;
  final bool? poolTelegramVerified;
  final bool poolSearching;
  final VoidCallback onUseAutomaticPool;
  final VoidCallback onUsePersonalProfile;
  final VoidCallback onOpenServers;
  final bool personalMode;
  final bool modeSelectionEnabled;
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
    final activeOrPending = engine.connected || engine.connecting || engine.disconnecting || poolSearching;
    final candidate = poolSummary;
    final visibleLatencyMs = engine.latencyForProfile(profile);
    final poolConnected = candidate != null && engine.connected;
    final poolRouteLabel = poolConnected
        ? '${candidate.subscriptionName} · ${candidate.configurationName}'
        : null;
    final expiry = candidate?.expiresAt;
    final expiryDate = expiry == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(expiry * 1000).toLocal();
    final expiryDateLabel = expiryDate == null
        ? null
        : '${expiryDate.year.toString().padLeft(4, '0')}-${expiryDate.month.toString().padLeft(2, '0')}-${expiryDate.day.toString().padLeft(2, '0')}';
    final expiryDays = candidate?.daysUntilExpiry;
    final remainingQuota = candidate?.remainingBytes;
    final quotaLabel = candidate == null || !candidate.quotaKnown
        ? context.tr('Unknown')
        : candidate.unlimitedQuota
            ? context.tr('Unlimited')
            : remainingQuota == null || candidate.totalBytes == null
                ? context.tr('Unknown')
                : '${formatByteCount(remainingQuota)} / ${formatByteCount(candidate.totalBytes!)}';
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
        const SizedBox(height: 18),
        _ConnectionModeSelector(
          personalMode: personalMode,
          enabled: modeSelectionEnabled,
          onUseAutomaticPool: onUseAutomaticPool,
          onUsePersonalProfile: onUsePersonalProfile,
          onOpenServers: onOpenServers,
          hasPersonalProfile: profile != null,
        ),
        const SizedBox(height: 20),
        Center(
          child: _PowerOrb(
            reducedMotion: reducedMotion,
            dark: dark,
            connected: engine.connected,
            connecting: engine.connecting || poolSearching,
            disconnecting: engine.disconnecting,
            failed: engine.message != null && !engine.connected && !engine.connecting && !poolSearching,
            enabled: canToggleVpnAction(
              hasProfile: true,
              activeOrPending: activeOrPending,
              subscriptionBusy: subscriptionBusy,
              engineBusy: engine.busy,
              canStart: engine.canStart,
            ),
            onPressed: onToggleConnection,
          ),
        ),
        const SizedBox(height: 18),
        Center(
          child: Column(
            children: [
              LocalizedText(poolSearching ? 'CONNECTING' : engine.stateLabel, style: TextStyle(fontSize: 12, letterSpacing: 2.1, fontWeight: FontWeight.w800, color: engine.connected ? const Color(0xFF67DDB7) : (dark ? const Color(0xFFE0EAE6) : _ink))),
              const SizedBox(height: 5),
              LocalizedText(
                poolSearching
                    ? 'Connecting to a suitable server…'
                    : profile == null
                        ? poolSummary != null && engine.connected
                            ? poolTelegramVerified == false
                                ? 'Telegram could not be verified; connected using the best available route.'
                                : 'VPN service is connected through the automatic pool.'
                            : activeOrPending
                                ? 'VPN service is active. Tap the shield to disconnect.'
                                : engine.message ?? 'Tap to connect automatically'
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
              if (profile != null && !activeOrPending)
                TextButton(
                  onPressed: onUseAutomaticPool,
                  child: const LocalizedText('Use automatic server pool'),
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
                Expanded(child: LocalizedText(poolConnected ? 'SECURE ROUTE' : 'DESTINATION', style: const TextStyle(fontSize: 10, letterSpacing: 1.4, fontWeight: FontWeight.w800, color: _muted))),
                Text(
                  poolConnected || poolSearching
                      ? context.tr('AUTOMATIC')
                      : (profile?.protocol ?? context.tr(engine.connected ? 'ACTIVE SESSION' : 'NO SERVER')),
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: _muted),
                ),
              ]),
              const SizedBox(height: 13),
              Directionality(
                textDirection: !poolConnected && showDestination && profile != null
                    ? TextDirection.ltr
                    : Directionality.of(context),
                child: Text(
                  poolConnected
                      ? poolRouteLabel!
                      : poolSearching
                          ? context.tr('Connecting to a suitable server…')
                          : engine.connected && profile == null
                              ? context.tr('Active tunnel')
                              : showDestination
                                  ? (profile?.destination ?? context.tr('Add a server link'))
                                  : context.tr('Destination hidden'),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: dark ? Colors.white : _ink),
                ),
              ),
              const SizedBox(height: 5),
              LocalizedText(poolConnected
                      ? 'Subscription route. No device IP is displayed.'
                      : poolSearching
                          ? 'Testing candidate servers on this network.'
                          : profile == null
                              ? engine.connected
                                  ? 'Route details are not available for this active session.'
                                  : 'No client address is read or displayed.'
                              : 'Country: not looked up',
                  style: const TextStyle(fontSize: 12, color: _muted)),
              if (poolConnected) ...[
                const SizedBox(height: 8),
                _MetricRow(
                  label: 'SUBSCRIPTION QUOTA REMAINING',
                  value: quotaLabel,
                ),
                const SizedBox(height: 4),
                _MetricRow(
                  label: 'SUBSCRIPTION EXPIRY',
                  value: expiryDateLabel == null || expiryDays == null
                      ? context.tr('Unknown')
                      : '${context.tr('Expires in')} $expiryDays ${context.tr(expiryDays == 1 ? 'day' : 'days')} · $expiryDateLabel',
                ),
              ],
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
                  onPressed: (profile == null && !poolConnected && !engine.connected) || subscriptionBusy || engine.busy || engine.pingBusy || engine.connecting || engine.disconnecting
                      ? null
                      : onMeasurePing,
                  icon: const Icon(Icons.speed_rounded, size: 17),
                  label: LocalizedText(
                    visibleLatencyMs != null
                        ? '$visibleLatencyMs ms'
                        : poolConnected && poolPingChecked
                            ? 'No ping response'
                            : 'Test latency',
                  ),
                ),
              ]),
              const SizedBox(height: 8),
            ],
          ),
        ),
        const SizedBox(height: 23),
        const Center(child: LocalizedText('Source: Telegram @V2rayAG  ·  Developer: HashtagAlireza',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: _muted))),
      ],
    );
  }
}

class _ConnectionModeSelector extends StatelessWidget {
  const _ConnectionModeSelector({
    required this.personalMode,
    required this.enabled,
    required this.onUseAutomaticPool,
    required this.onUsePersonalProfile,
    required this.onOpenServers,
    required this.hasPersonalProfile,
  });

  final bool personalMode;
  final bool enabled;
  final VoidCallback onUseAutomaticPool;
  final VoidCallback onUsePersonalProfile;
  final VoidCallback onOpenServers;
  final bool hasPersonalProfile;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final border = dark ? Colors.white12 : const Color(0xFFE4E9E5);
    return Container(
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF151F1C) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LocalizedText(
            'CONNECTION MODE',
            style: TextStyle(fontSize: 10, letterSpacing: 1.3, fontWeight: FontWeight.w800, color: _muted),
          ),
          const SizedBox(height: 9),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [
              ButtonSegment<bool>(
                value: false,
                icon: Icon(Icons.auto_awesome_rounded, size: 17),
                label: LocalizedText('Automatic'),
              ),
              ButtonSegment<bool>(
                value: true,
                icon: Icon(Icons.key_rounded, size: 17),
                label: LocalizedText('Personal'),
              ),
            ],
            selected: <bool>{personalMode},
            onSelectionChanged: enabled
                ? (selection) {
                    if (selection.isEmpty) return;
                    if (selection.single) {
                      onUsePersonalProfile();
                    } else {
                      onUseAutomaticPool();
                    }
                  }
                : null,
          ),
          const SizedBox(height: 7),
          LocalizedText(
            personalMode
                ? 'Use a server or subscription you imported.'
                : 'Connect automatically using the supplied server pool.',
            style: const TextStyle(fontSize: 11, color: _muted),
          ),
          if (personalMode) ...[
            const SizedBox(height: 2),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                onPressed: enabled ? onOpenServers : null,
                icon: const Icon(Icons.dns_outlined, size: 16),
                label: LocalizedText(hasPersonalProfile ? 'Choose a personal server' : 'Import or choose a server'),
              ),
            ),
          ],
        ],
      ),
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
    required this.profileSources,
    required this.selectedIndex,
    required this.showDestination,
    required this.connected,
    required this.onImport,
    required this.onSelect,
    required this.onRemove,
    required this.profilePings,
    required this.profilePingFailures,
    required this.failedPings,
    required this.probingProfiles,
    required this.onTestProfileLatency,
    required this.subscriptions,
    required this.onAddSubscription,
    required this.onEditSubscription,
    required this.onRemoveSubscription,
    required this.onRefreshSubscription,
    required this.onTestSubscriptionPings,
    required this.onCancelSubscriptionPings,
    required this.pingingSubscriptionId,
    required this.pingBatchCompleted,
    required this.pingBatchTotal,
    required this.subscriptionBusy,
    required this.secureStorageNeedsRepair,
    required this.secureStorageNotice,
    required this.legacyDataUnavailable,
    required this.storageNamespaceRotated,
    required this.onRepairSecureStorage,
  });

  final List<VpnProfile> profiles;
  final List<String?> profileSources;
  final int? selectedIndex;
  final bool showDestination;
  final bool connected;
  final VoidCallback onImport;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onRemove;
  final Map<int, int> profilePings;
  final Map<int, String> profilePingFailures;
  final Set<int> failedPings;
  final Set<int> probingProfiles;
  final ValueChanged<int> onTestProfileLatency;
  final List<SavedSubscription> subscriptions;
  final VoidCallback onAddSubscription;
  final ValueChanged<SavedSubscription> onEditSubscription;
  final ValueChanged<SavedSubscription> onRemoveSubscription;
  final Future<void> Function(SavedSubscription) onRefreshSubscription;
  final Future<void> Function(SavedSubscription) onTestSubscriptionPings;
  final VoidCallback onCancelSubscriptionPings;
  final String? pingingSubscriptionId;
  final int pingBatchCompleted;
  final int pingBatchTotal;
  final bool subscriptionBusy;
  final bool secureStorageNeedsRepair;
  final bool secureStorageNotice;
  final bool legacyDataUnavailable;
  final bool storageNamespaceRotated;
  final VoidCallback onRepairSecureStorage;

  Widget _profileCard(BuildContext context, int index, bool dark) {
    final profile = profiles[index];
    final active = index == selectedIndex;
    return Card(
      elevation: 0,
      color: dark ? const Color(0xFF192321) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: active
              ? const Color(0xFF52C59E)
              : (dark ? Colors.white12 : Colors.black12),
          width: active ? 1.5 : 1,
        ),
      ),
      child: ListTile(
        onTap: () => onSelect(index),
        leading: CircleAvatar(
          backgroundColor: dark ? const Color(0xFF213B34) : const Color(0xFFE5F6EF),
          child: Text(
            profile.protocol.substring(0, 1),
            style: TextStyle(
              color: dark ? const Color(0xFF7AD9B7) : const Color(0xFF317D68),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        title: Text(profile.name, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text('${profile.protocol} · ${showDestination ? profile.destination : context.tr('Destination hidden')}'),
            ),
            Text('${context.tr('Country not looked up')} · ${context.tr(active && connected ? 'connected' : 'ready')}'),
            if (profilePings[index] != null)
              Text('${context.tr('Latency')}: ${profilePings[index]} ms',
                  style: const TextStyle(color: _muted, fontSize: 12)),
            if (failedPings.contains(index))
              Text(
                '${context.tr('Latency probe unavailable')} · ${profilePingFailures[index] ?? 'NoDelayResult'}. ${context.tr('This does not prove the server is offline')}',
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
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
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.speed_rounded),
          ),
          IconButton(
            tooltip: context.tr('Remove profile'),
            onPressed: connected && active ? null : () => onRemove(index),
            icon: const Icon(Icons.close_rounded),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final customSubscriptions = subscriptions;
    return ListView(padding: const EdgeInsets.fromLTRB(20, 18, 20, 28), children: [
      LocalizedText('Servers', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      const LocalizedText('Add your subscription, refresh servers, and choose a route.', style: TextStyle(color: _muted)),
      const SizedBox(height: 18),
      Row(children: [
        const Expanded(child: LocalizedText('My subscriptions', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
        TextButton.icon(onPressed: connected || subscriptionBusy ? null : onAddSubscription, icon: const Icon(Icons.add_rounded), label: const LocalizedText('Add')),
      ]),
      if (secureStorageNotice)
        Card(
          color: dark ? const Color(0xFF3A2C1D) : const Color(0xFFFFF1E5),
          child: ListTile(
            leading: const Icon(Icons.warning_amber_rounded, color: _coral),
            title: LocalizedText(secureStorageNeedsRepair
                ? 'Secure storage unavailable'
                : 'Encrypted storage notice'),
            subtitle: LocalizedText(secureStorageNeedsRepair
                ? 'A secure save could not be verified. Do not close the app until the save succeeds; unreadable records were not deleted.'
                : legacyDataUnavailable
                    ? 'Older encrypted records remain untouched but could not be read. New saves use a separate encrypted store; re-add any missing items.'
                    : storageNamespaceRotated
                        ? 'Storage was moved to an isolated encrypted namespace. Existing data was left untouched and new saves are verified.'
                        : 'Encrypted records were left untouched. New records are saved only after secure read-back verification.'),
            trailing: IconButton(
              tooltip: context.tr('Secure storage information'),
              onPressed: subscriptionBusy ? null : onRepairSecureStorage,
              icon: const Icon(Icons.info_outline_rounded),
            ),
          ),
        ),
      if (customSubscriptions.isEmpty)
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: LocalizedText('Paste a secure HTTPS URL or scan its QR code. URLs are stored on this device only.', style: TextStyle(color: _muted, fontSize: 12)),
        )
      else
        ...customSubscriptions.map((subscription) {
          final indices = <int>[
            for (var i = 0; i < profiles.length; i++)
              if (i < profileSources.length && profileSources[i] == subscription.id) i,
          ];
          indices.sort((a, b) {
            final pingA = profilePings[a];
            final pingB = profilePings[b];
            if (pingA == null && pingB == null) return a.compareTo(b);
            if (pingA == null) return 1;
            if (pingB == null) return -1;
            return pingA.compareTo(pingB);
          });
          final isPinging = pingingSubscriptionId == subscription.id;
          return Card(
            elevation: 0,
            color: dark ? const Color(0xFF192321) : Colors.white,
            child: Column(children: [
              ListTile(
                leading: CircleAvatar(backgroundColor: dark ? const Color(0xFF213B34) : const Color(0xFFE5F6EF), child: Icon(Icons.rss_feed_rounded, color: dark ? const Color(0xFF7AD9B7) : const Color(0xFF317D68))),
                title: Text(subscription.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(isPinging
                    ? '${context.tr('Testing latencies')}: ${pingBatchCompleted < pingBatchTotal ? pingBatchCompleted + 1 : pingBatchTotal}/$pingBatchTotal'
                    : context.tr('Private URL stored on this device')),
                trailing: Wrap(spacing: 0, children: [
                  IconButton(
                    tooltip: context.tr(isPinging ? 'Stop ping test' : 'Test all server latencies'),
                    onPressed: isPinging
                        ? onCancelSubscriptionPings
                        : (connected || subscriptionBusy
                            ? null
                            : () => onTestSubscriptionPings(subscription)),
                    icon: isPinging
                        ? const Icon(Icons.stop_circle_outlined, color: _coral)
                        : const Icon(Icons.speed_rounded),
                  ),
                  IconButton(tooltip: context.tr('Refresh servers'), onPressed: connected || subscriptionBusy ? null : () => onRefreshSubscription(subscription), icon: const Icon(Icons.refresh_rounded)),
                  IconButton(tooltip: context.tr('Edit subscription'), onPressed: connected || subscriptionBusy ? null : () => onEditSubscription(subscription), icon: const Icon(Icons.edit_outlined)),
                  IconButton(tooltip: context.tr('Remove subscription'), onPressed: connected || subscriptionBusy ? null : () => onRemoveSubscription(subscription), icon: const Icon(Icons.delete_outline_rounded)),
                ]),
              ),
              ExpansionTile(
                title: const LocalizedText('Server configurations'),
                subtitle: Text(indices.isEmpty ? context.tr('Refresh this subscription to load its profiles') : '${indices.length} ${context.tr('profiles')}'),
                children: indices.isEmpty
                    ? [const ListTile(title: LocalizedText('No profiles loaded yet.'))]
                    : indices.length > 40
                        ? [
                            SizedBox(
                              height: 600,
                              child: ListView.builder(
                                primary: false,
                                physics: const ClampingScrollPhysics(),
                                itemCount: indices.length,
                                itemBuilder: (context, row) =>
                                    _profileCard(context, indices[row], dark),
                              ),
                            ),
                          ]
                        : indices
                            .map((index) => _profileCard(context, index, dark))
                            .toList(),
              ),
            ]),
          );
        }),
      const SizedBox(height: 10),
      FilledButton.tonalIcon(onPressed: connected || subscriptionBusy ? null : onImport, icon: const Icon(Icons.add_link_rounded), label: const LocalizedText('Import server links')),
      const SizedBox(height: 14),
      if (profiles.isEmpty)
        _EmptyCard(dark: dark)
      else ...[
        if (profiles.asMap().keys.any((i) => i >= profileSources.length || profileSources[i] == null))
          const Padding(
            padding: EdgeInsets.only(top: 8, bottom: 4),
            child: LocalizedText('Pasted server links', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ...profiles.asMap().keys
            .where((i) => i >= profileSources.length || profileSources[i] == null)
            .map((index) => _profileCard(context, index, dark)),
      ],
      const SizedBox(height: 12),
      const LocalizedText('Profile configurations are encrypted in Android secure storage on this device. If secure storage is unavailable, changes remain session-only and the app shows a diagnostic code. Do not share screenshots or logs that reveal a server address.', style: TextStyle(fontSize: 12, color: _muted, height: 1.45)),
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
    required this.manualProfileMode,
    required this.connectionModeLocked,
    required this.onUseAutomaticPool,
    required this.onUsePersonalProfile,
    required this.onLocaleChanged,
    required this.reducedMotion,
    required this.showDestination,
    required this.darkMode,
    required this.onReducedMotionChanged,
    required this.onShowDestinationChanged,
    required this.onThemeChanged,
    required this.onEditAppRouting,
    required this.excludedAppsCount,
    required this.onOpenConnectionProtocol,
  });

  final Locale locale;
  final bool manualProfileMode;
  final bool connectionModeLocked;
  final VoidCallback onUseAutomaticPool;
  final VoidCallback onUsePersonalProfile;
  final ValueChanged<Locale> onLocaleChanged;
  final bool reducedMotion;
  final bool showDestination;
  final bool darkMode;
  final ValueChanged<bool> onReducedMotionChanged;
  final ValueChanged<bool> onShowDestinationChanged;
  final ValueChanged<bool> onThemeChanged;
  final VoidCallback onEditAppRouting;
  final int excludedAppsCount;
  final VoidCallback onOpenConnectionProtocol;

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
          SwitchListTile(
            title: const LocalizedText('Light / day mode'),
            subtitle: const LocalizedText('Change the app theme'),
            value: !darkMode,
            onChanged: (lightMode) => onThemeChanged(!lightMode),
          ),
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
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            leading: const Icon(Icons.hub_rounded),
            title: const LocalizedText('Connection protocol'),
            subtitle: const LocalizedText('Auto or optional CDN Fronting settings'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: onOpenConnectionProtocol,
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          SwitchListTile(
            secondary: const Icon(Icons.auto_awesome_rounded),
            title: const LocalizedText('Automatic server pool'),
            subtitle: LocalizedText(manualProfileMode
                ? 'Use the personal server selected in Servers.'
                : 'Connect to candidates directly; continue only after a safely cleaned-up failure.'),
            value: !manualProfileMode,
            onChanged: connectionModeLocked
                ? null
                : (automatic) {
                    if (automatic) {
                      onUseAutomaticPool();
                    } else {
                      onUsePersonalProfile();
                    }
                  },
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

class _ConnectionProtocolPage extends StatefulWidget {
  const _ConnectionProtocolPage({
    required this.settings,
    required this.locked,
    required this.onSave,
    required this.onBack,
    super.key,
  });

  final CdnFrontingSettings settings;
  final bool locked;
  final Future<bool> Function(CdnFrontingSettings) onSave;
  final VoidCallback onBack;

  @override
  State<_ConnectionProtocolPage> createState() => _ConnectionProtocolPageState();
}

class _ConnectionProtocolPageState extends State<_ConnectionProtocolPage> {
  late final TextEditingController _ipsController;
  late final TextEditingController _sniController;
  late ConnectionProtocol _selectedProtocol;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedProtocol = widget.settings.protocol;
    _ipsController = TextEditingController(text: widget.settings.cdnIps);
    _sniController = TextEditingController(text: widget.settings.sniHostname);
  }

  @override
  void didUpdateWidget(covariant _ConnectionProtocolPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings.protocol != widget.settings.protocol) {
      _selectedProtocol = widget.settings.protocol;
    }
    if (oldWidget.settings.cdnIps != widget.settings.cdnIps) {
      _ipsController.text = widget.settings.cdnIps;
    }
    if (oldWidget.settings.sniHostname != widget.settings.sniHostname) {
      _sniController.text = widget.settings.sniHostname;
    }
  }

  @override
  void dispose() {
    _ipsController.dispose();
    _sniController.dispose();
    super.dispose();
  }

  Future<void> _save(ConnectionProtocol protocol) async {
    if (widget.locked || _saving) return;
    setState(() => _saving = true);
    try {
      final settings = protocol == ConnectionProtocol.auto
          ? CdnFrontingSettings(
              protocol: ConnectionProtocol.auto,
              cdnIps: widget.settings.cdnIps,
              sniHostname: widget.settings.sniHostname,
            )
          : CdnFrontingSettings(
              protocol: protocol,
              cdnIps: _ipsController.text,
              sniHostname: _sniController.text,
            ).validated();
      final saved = await widget.onSave(settings);
      if (saved && mounted) {
        setState(() {
          _selectedProtocol = protocol;
          _ipsController.text = settings.cdnIps;
          _sniController.text = settings.sniHostname;
        });
      }
    } on FormatException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: LocalizedText(error.message)),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        children: [
          Row(children: [
            IconButton(
              tooltip: context.tr('Back to settings'),
              onPressed: widget.onBack,
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            Expanded(
              child: LocalizedText(
                'Connection protocol',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: LocalizedText(
              'Choose how automatic-pool connections should be routed. Auto is the default and leaves current connections unchanged.',
              style: TextStyle(color: _muted, height: 1.4),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            color: Theme.of(context).colorScheme.surface,
            child: Column(children: [
              RadioListTile<ConnectionProtocol>(
                value: ConnectionProtocol.auto,
                groupValue: _selectedProtocol,
                title: const LocalizedText('Auto'),
                subtitle: const LocalizedText(
                  'Use the existing automatic connection method with no CDN overrides.',
                ),
                onChanged: widget.locked || _saving
                    ? null
                    : (_) => _save(ConnectionProtocol.auto),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              RadioListTile<ConnectionProtocol>(
                value: ConnectionProtocol.cdnFronting,
                groupValue: _selectedProtocol,
                title: const LocalizedText('CDN Fronting'),
                subtitle: const LocalizedText(
                  'Optional CDN IP and TLS SNI overrides for compatible automatic servers. Selecting it uses the automatic pool, not personal profiles.',
                ),
                onChanged: widget.locked || _saving
                    ? null
                    : (_) => setState(() => _selectedProtocol = ConnectionProtocol.cdnFronting),
              ),
            ]),
          ),
          if (_selectedProtocol == ConnectionProtocol.cdnFronting) ...[
            const SizedBox(height: 14),
            Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.surface,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const LocalizedText(
                      'CDN IPs',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _ipsController,
                      enabled: !widget.locked && !_saving,
                      minLines: 2,
                      maxLines: 4,
                      keyboardType: TextInputType.multiline,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                        hintText: context.tr('One IP per line, or separate with commas'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const LocalizedText(
                      'CDN SNI hostname',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _sniController,
                      enabled: !widget.locked && !_saving,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                        hintText: context.tr('example.com'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const LocalizedText(
                      'Leave both fields empty to use the normal automatic connection. IP overrides are tried in order and require a compatible TLS WebSocket server.',
                      style: TextStyle(color: _muted, fontSize: 12, height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: widget.locked || _saving
                            ? null
                            : () => _save(ConnectionProtocol.cdnFronting),
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.save_rounded),
                        label: const LocalizedText('Save'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (widget.locked) ...[
            const SizedBox(height: 12),
            const LocalizedText(
              'Disconnect before changing connection protocol.',
              style: TextStyle(color: _coral),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      );
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
  });

  final String id;
  final String initialName;
  final String initialUrl;

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
    final name = _nameController.text.trim();
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
          const LocalizedText('Add a subscription', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
          const SizedBox(height: 7),
          const LocalizedText('Paste or scan your provider’s HTTPS subscription URL. Your own URL is needed; none is bundled with this app.', style: TextStyle(fontSize: 12, color: _muted, height: 1.4)),
          const SizedBox(height: 14),
          TextField(
            controller: _nameController,
            decoration: InputDecoration(labelText: context.tr('Name'), filled: true, fillColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF101817) : const Color(0xFFF4F6F3), border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none)),
          ),
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
    if (input.isEmpty) {
      setState(() => _error = 'Paste one or more server links.');
      return;
    }
    try {
      // parsePayload extracts supported links from copied chats/messages and
      // ignores surrounding prose, emoji, punctuation, and unrelated URLs.
      final profiles = SubscriptionService.parsePayload(input);
      if (profiles.isEmpty) {
        final containsWebUrl = RegExp(r'https?://', caseSensitive: false).hasMatch(input);
        setState(() => _error = containsWebUrl
            ? 'That looks like a subscription URL. Use Add subscription instead.'
            : 'No supported server links were found in the pasted text.');
        return;
      }
      _controller.clear();
      Navigator.of(context).pop(profiles);
    } on FormatException {
      setState(() => _error = 'No supported server links were found in the pasted text.');
    } catch (_) {
      setState(() => _error = 'The copied text could not be parsed. Check the links and try again.');
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
          const LocalizedText('Import server links', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const LocalizedText('Paste copied text with one or more VLESS, VMess, Shadowsocks, or Trojan links. Other text is ignored.', style: TextStyle(fontSize: 12, color: _muted)),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 3,
            maxLines: 8,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              hintText: context.tr('Paste one or more server links or a copied message'),
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
          const LocalizedText('Only supported server links are imported. Extra text is ignored. After import, profiles are saved using encrypted Android storage; if that storage is unavailable, the app will show an error and will not overwrite unreadable data. Use Add subscription for a provider URL.', style: TextStyle(fontSize: 11, color: _muted, height: 1.4)),
          const SizedBox(height: 15),
          SizedBox(width: double.infinity, child: FilledButton(onPressed: _preview, child: const LocalizedText('Import server links'))),
        ])),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({this.size = 35});

  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
        image: true,
        label: 'V2rayAG logo',
        child: Image.asset(
          'assets/brand/v2rayag_mark.png',
          width: size,
          height: size,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
      );
}
