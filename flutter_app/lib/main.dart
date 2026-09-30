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
  // Parallel to _profiles: saved-subscription ID, or null for pasted links.
  final List<String?> _profileSources = [];
  final VpnEngine _engine = VpnEngine();
  final SubscriptionRepository _subscriptionRepository = SubscriptionRepository();
  final ProfileRepository _profileRepository = ProfileRepository();
  final Completer<void> _subscriptionsReady = Completer<void>();
  final Completer<void> _profilesReady = Completer<void>();
  final Completer<void> _routingPreferencesReady = Completer<void>();
  Future<void> _profileWriteQueue = Future<void>.value();
  bool _profileRestoreFailed = false;
  String? _profileStorageErrorCode;
  bool _subscriptionRestoreFailed = false;
  final Set<String> _sessionOnlySubscriptionIds = {};
  List<SavedSubscription> _savedSubscriptions = [];
  bool _subscriptionBusy = false;
  int? _selectedIndex;
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
      if (mounted) setState(() => _savedSubscriptions = personal);
    } on Object catch (error) {
      _subscriptionRestoreFailed = true;
      if (mounted) {
        _showMessage('Subscription storage could not be read (${_safeStorageFailure(error)}). Existing secure data will not be overwritten.');
      }
    } finally {
      if (!_subscriptionsReady.isCompleted) _subscriptionsReady.complete();
    }
  }

  Future<void> _restoreProfiles() async {
    try {
      final saved = await _profileRepository.read();
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
    } on Object catch (error) {
      _profileRestoreFailed = true;
      _profileStorageErrorCode = _safeStorageFailure(error);
      if (mounted) {
        _showMessage(
          'Saved profiles could not be restored ($_profileStorageErrorCode). Existing secure data will not be overwritten.',
        );
      }
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
          '${context.tr('New servers are temporary until secure storage is repaired')} '
          '${context.tr('Existing unreadable data has not been overwritten')}.',
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const LocalizedText('Repair secure storage?'),
        content: const LocalizedText(
          'Android cannot decrypt some saved app data. You can keep it and cancel, or delete only the unreadable subscription/profile records. Deleted records cannot be recovered; you may need to add those subscriptions and profiles again. Other app data is not affected. Any servers added during this app session will be kept and saved after repair.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const LocalizedText('Keep data'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const LocalizedText('Delete unreadable records'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final repairSubscriptions = _subscriptionRestoreFailed;
    final repairProfiles = _profileRestoreFailed;
    try {
      if (repairSubscriptions) {
        await _subscriptionRepository.deleteSaved();
      }
      if (repairProfiles) {
        await _profileRepository.deleteSaved();
      }
      if (!mounted) return;
      setState(() {
        _subscriptionRestoreFailed = false;
        _profileRestoreFailed = false;
        _profileStorageErrorCode = null;
      });

      // Preserve servers imported in this live session. The user explicitly
      // confirmed removal of only the unreadable old records; discarding the
      // newly imported, still-readable profiles here would be surprising.
      var subscriptionsSaved = true;
      if (repairSubscriptions) {
        try {
          await _subscriptionRepository.saveAll(_savedSubscriptions);
          _sessionOnlySubscriptionIds.clear();
        } on Object {
          subscriptionsSaved = false;
        }
      }
      var profilesSaved = true;
      if (repairProfiles) profilesSaved = await _persistProfiles();
      if (!mounted) return;
      _showMessage(subscriptionsSaved && profilesSaved
          ? 'Unreadable old records were removed. Current servers and subscriptions were saved; re-add any old unreadable items you still need.'
          : 'Unreadable old records were removed, but some current items could not be saved. Keep the app open and try saving again.');
    } on Object catch (error) {
      _showMessage('Secure storage repair failed (${_safeStorageFailure(error)}). Try again; some unreadable records may already have been removed.');
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
    if (_subscriptionBusy) {
      _showMessage('Wait for the subscription operation to finish.');
      return;
    }
    final isActive = _engine.connected || _engine.connecting || _engine.disconnecting;
    final profile = _selectedIndex == null ? null : _profiles[_selectedIndex!];
    if (!isActive && profile == null) {
      _showMessage('Import a server link first.');
      return;
    }
    if (isActive) {
      await _engine.disconnect();
    } else {
      await _engine.connect(
        profile!,
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

  Future<int?> _probeProfile(int index) async {
    if (index < 0 || index >= _profiles.length || _probingProfiles.contains(index)) {
      return null;
    }
    setState(() {
      _probingProfiles.add(index);
      _profilePings.remove(index);
      _profilePingFailures.remove(index);
      _failedPings.remove(index);
    });
    final result = await _engine.measurePing(_profiles[index]);
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
        final result = await _probeProfile(index);
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
    if (_subscriptionBusy || !_profilesReady.isCompleted) return;
    if (_engine.connected || _engine.connecting || _engine.disconnecting) {
      _showMessage('Disconnect before changing the active server.');
      return;
    }
    setState(() => _selectedIndex = index);
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
            'The app will not replace data it cannot read. You can repair storage in Servers, or use this subscription for this session only. It will not be saved and will disappear when the app closes.',
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
    if (_subscriptionBusy) return;
    if ((_engine.connected || _engine.connecting || _engine.disconnecting) && index == _selectedIndex) {
      _showMessage('Disconnect before removing the active server.');
      return;
    }
    setState(() {
      _profiles.removeAt(index);
      if (index < _profileSources.length) _profileSources.removeAt(index);
      _profilePings.clear();
      _profilePingFailures.clear();
      _failedPings.clear();
      _probingProfiles.clear();
      if (_profiles.isEmpty) {
        _selectedIndex = null;
      } else if (_selectedIndex == index) {
        _selectedIndex = 0;
      } else if (_selectedIndex != null && _selectedIndex! > index) {
        _selectedIndex = _selectedIndex! - 1;
      }
    });
    unawaited(_persistProfiles().then<void>((_) {}));
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
        subscriptionBusy: _subscriptionBusy || _batchPingSubscriptionId != null,
      ),
      _ProfilesPage(
        profiles: _profiles,
        profileSources: _profileSources,
        selectedIndex: _selectedIndex,
        showDestination: widget.showDestination,
        connected: _engine.connected || _engine.connecting || _engine.disconnecting,
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
        onRepairSecureStorage: _recoverUnreadableSecureStorage,
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
            enabled: canToggleVpnAction(
              hasProfile: profile != null,
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
              LocalizedText(engine.stateLabel, style: TextStyle(fontSize: 12, letterSpacing: 2.1, fontWeight: FontWeight.w800, color: engine.connected ? const Color(0xFF67DDB7) : (dark ? const Color(0xFFE0EAE6) : _ink))),
              const SizedBox(height: 5),
              LocalizedText(
                profile == null
                    ? activeOrPending
                        ? 'VPN service is active, but no saved server is available. Tap the shield to disconnect.'
                        : 'Import a server before connecting'
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
                'Subscription URLs and imported server configs are saved in encrypted Android storage after a successful save and are never committed to GitHub. If secure storage fails, the app reports it rather than overwriting unreadable data. The app never reads or displays your device IP.',
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
      if (secureStorageNeedsRepair)
        Card(
          color: dark ? const Color(0xFF3A2C1D) : const Color(0xFFFFF1E5),
          child: ListTile(
            leading: const Icon(Icons.warning_amber_rounded, color: _coral),
            title: const LocalizedText('Saved data cannot be decrypted'),
            subtitle: const LocalizedText('New subscriptions can be used for one session, or repair storage after confirming removal of unreadable records.'),
            trailing: IconButton(
              tooltip: context.tr('Repair secure storage'),
              onPressed: subscriptionBusy ? null : onRepairSecureStorage,
              icon: const Icon(Icons.build_circle_outlined),
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
                    ? '${context.tr('Testing pings')}: ${pingBatchCompleted < pingBatchTotal ? pingBatchCompleted + 1 : pingBatchTotal}/$pingBatchTotal'
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
                    : indices.map((index) => _profileCard(context, index, dark)).toList(),
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
