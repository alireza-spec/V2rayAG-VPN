import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'subscription_service.dart';
import 'vpn_engine.dart';
import 'vpn_profile.dart';

void main() => runApp(const V2rayAgApp());

const _ink = Color(0xFF182321);
const _muted = Color(0xFF778581);
const _mint = Color(0xFF51D6AF);
const _coral = Color(0xFFFF886E);
const _canvas = Color(0xFFF6F7F3);

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

  @override
  Widget build(BuildContext context) {
    ThemeData buildTheme(Brightness brightness) {
      final dark = brightness == Brightness.dark;
      return ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: dark ? const Color(0xFF101817) : _canvas,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E9478),
          brightness: brightness,
          surface: dark ? const Color(0xFF17211F) : Colors.white,
        ),
        fontFamily: 'Roboto',
        appBarTheme: AppBarTheme(
          backgroundColor: dark ? const Color(0xFF101817) : _canvas,
          foregroundColor: dark ? Colors.white : _ink,
          surfaceTintColor: Colors.transparent,
        ),
      );
    }

    return MaterialApp(
      title: 'V2rayAG VPN',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: _themeMode,
      home: VpnShell(
        reducedMotion: _reducedMotion,
        showDestination: _showDestination,
        onReducedMotionChanged: (value) => setState(() => _reducedMotion = value),
        onShowDestinationChanged: (value) => setState(() => _showDestination = value),
        onThemeChanged: (value) => setState(
          () => _themeMode = value ? ThemeMode.dark : ThemeMode.light,
        ),
        darkMode: _themeMode == ThemeMode.dark,
      ),
    );
  }
}

class VpnShell extends StatefulWidget {
  const VpnShell({
    required this.reducedMotion,
    required this.showDestination,
    required this.onReducedMotionChanged,
    required this.onShowDestinationChanged,
    required this.onThemeChanged,
    required this.darkMode,
    super.key,
  });

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
  List<SavedSubscription> _savedSubscriptions = [];
  bool _subscriptionBusy = false;
  int? _selectedIndex;

  static const _exclusiveId = 'exclusive-v2rayag';

  @override
  void initState() {
    super.initState();
    _engine.addListener(_onEngineChanged);
    _engine.initialize();
    _restoreSubscriptions();
  }

  Future<void> _restoreSubscriptions() async {
    try {
      final saved = await _subscriptionRepository.readAll();
      if (mounted) setState(() => _savedSubscriptions = saved);
    } on Object {
      if (mounted) _showMessage('Secure subscription storage is unavailable on this device.');
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _toggleConnection() async {
    final profile = _selectedIndex == null ? null : _profiles[_selectedIndex!];
    if (profile == null) {
      _showMessage('Import a server link first.');
      return;
    }
    if (_engine.connected || _engine.connecting || _engine.disconnecting) {
      await _engine.disconnect();
    } else {
      await _engine.connect(profile);
    }
    if (mounted && _engine.message != null) _showMessage(_engine.message!);
  }

  Future<void> _measurePing() async {
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

  void _selectProfile(int index) {
    if (_engine.connected || _engine.connecting || _engine.disconnecting) {
      _showMessage('Disconnect before changing the active server.');
      return;
    }
    setState(() => _selectedIndex = index);
  }

  Future<void> _importProfile() async {
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

  Future<void> _saveSubscription(SavedSubscription subscription) async {
    final next = [..._savedSubscriptions];
    final index = next.indexWhere((item) => item.id == subscription.id);
    if (index < 0) {
      next.add(subscription);
    } else {
      next[index] = subscription;
    }
    await _subscriptionRepository.saveAll(next);
    if (mounted) setState(() => _savedSubscriptions = next);
  }

  Future<void> _addSubscription() async {
    if (_engine.connected || _engine.connecting || _engine.disconnecting) {
      _showMessage('Disconnect before refreshing subscriptions.');
      return;
    }
    final subscription = await _editSubscription(exclusive: false);
    if (subscription == null || !mounted) return;
    try {
      await _saveSubscription(subscription);
    } on Object {
      _showMessage('Could not save this subscription securely on the device.');
      return;
    }
    await _refreshSubscription(subscription);
  }

  Future<void> _editSavedSubscription(SavedSubscription existing) async {
    if (_engine.connected || _engine.connecting || _engine.disconnecting) {
      _showMessage('Disconnect before changing subscriptions.');
      return;
    }
    final updated = await _editSubscription(
      existing: existing,
      exclusive: existing.id == _exclusiveId,
    );
    if (updated == null || !mounted) return;
    try {
      await _saveSubscription(updated);
    } on Object {
      _showMessage('Could not save this subscription securely on the device.');
      return;
    }
    await _refreshSubscription(updated);
  }

  Future<void> _removeSubscription(SavedSubscription subscription) async {
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
    if (_engine.connected || _engine.connecting || _engine.disconnecting) {
      _showMessage('Disconnect the current route with the power button before switching subscriptions.');
      return;
    }
    final existing = _savedSubscriptions.where((item) => item.id == _exclusiveId).firstOrNull;
    SavedSubscription? subscription = existing;
    if (subscription == null) {
      subscription = await _editSubscription(exclusive: true);
      if (subscription == null || !mounted) return;
      try {
        await _saveSubscription(subscription);
      } on Object {
        _showMessage('Could not save the subscription securely on this device.');
        return;
      }
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
    if (connectFirst && !_engine.canStart) {
      _showMessage('Android VPN is not ready yet. Wait for its status, then try again.');
      return;
    }
    setState(() => _subscriptionBusy = true);
    _showMessage('Fetching subscription securely…');
    try {
      final profiles = await SubscriptionService.fetchProfiles(subscription.url);
      if (!mounted) return;
      setState(() {
        _profiles
          ..clear()
          ..addAll(profiles);
        _selectedIndex = 0;
        _tab = connectFirst ? 0 : 1;
      });
      if (connectFirst) {
        final started = await _engine.connect(profiles.first);
        if (mounted && !started) {
          _showMessage(_engine.message ?? 'Android tunnel was not ready to start. Try again after status is available.');
        } else if (mounted && _engine.message != null) {
          _showMessage(_engine.message!);
        }
      } else {
        _showMessage('Loaded ${profiles.length} server profiles into app memory.');
      }
    } on FormatException {
      if (mounted) _showMessage('Could not load this subscription. Check the HTTPS URL and supported server formats.');
    } on Object {
      if (mounted) _showMessage('Could not load this subscription. Check the secure URL and try again.');
    } finally {
      if (mounted) setState(() => _subscriptionBusy = false);
    }
  }

  void _removeProfile(int index) {
    if ((_engine.connected || _engine.connecting || _engine.disconnecting) && index == _selectedIndex) {
      _showMessage('Disconnect before removing the active server.');
      return;
    }
    setState(() {
      _profiles.removeAt(index);
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
        onImport: _importProfile,
        onToggleConnection: _toggleConnection,
        onMeasurePing: _measurePing,
        onOpenProfiles: () => setState(() => _tab = 1),
        onExclusiveConnect: _connectExclusiveSubscription,
        exclusiveReady: _savedSubscriptions.any((item) => item.id == _exclusiveId),
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
        reducedMotion: widget.reducedMotion,
        showDestination: widget.showDestination,
        darkMode: widget.darkMode,
        onReducedMotionChanged: widget.onReducedMotionChanged,
        onShowDestinationChanged: widget.onShowDestinationChanged,
        onThemeChanged: widget.onThemeChanged,
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
                Text('V2rayAG', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                Text('PRIVATE ROUTE', style: TextStyle(fontSize: 9, letterSpacing: 1.7, color: _muted)),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Import a server link',
            onPressed: _importProfile,
            icon: const Icon(Icons.add_link_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: IndexedStack(index: _tab, children: pages),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.radio_button_checked_rounded), label: 'Connect'),
          NavigationDestination(icon: Icon(Icons.public_rounded), label: 'Servers'),
          NavigationDestination(icon: Icon(Icons.tune_rounded), label: 'Settings'),
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
    required this.onImport,
    required this.onToggleConnection,
    required this.onMeasurePing,
    required this.onOpenProfiles,
    required this.onExclusiveConnect,
    required this.exclusiveReady,
    required this.subscriptionBusy,
  });

  final VpnProfile? profile;
  final VpnEngine engine;
  final bool showDestination;
  final bool reducedMotion;
  final VoidCallback onImport;
  final VoidCallback onToggleConnection;
  final VoidCallback onMeasurePing;
  final VoidCallback onOpenProfiles;
  final VoidCallback onExclusiveConnect;
  final bool exclusiveReady;
  final bool subscriptionBusy;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final card = dark ? const Color(0xFF192321) : Colors.white;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
      children: [
        Text('Your quiet corner of the internet.',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: dark ? Colors.white : _ink,
                  letterSpacing: -.6,
                )),
        const SizedBox(height: 6),
        const Text('A clean route, on your terms.', style: TextStyle(color: _muted, fontSize: 14)),
        const SizedBox(height: 28),
        Center(
          child: _PowerOrb(
            reducedMotion: reducedMotion,
            connected: engine.connected,
            enabled: profile != null &&
                !engine.busy &&
                (engine.canStart || engine.connected || engine.connecting || engine.disconnecting),
            onPressed: onToggleConnection,
          ),
        ),
        const SizedBox(height: 18),
        Center(
          child: Column(
            children: [
              Text(engine.stateLabel, style: TextStyle(fontSize: 12, letterSpacing: 2.1, fontWeight: FontWeight.w800, color: engine.connected ? const Color(0xFF28866A) : _ink)),
              const SizedBox(height: 5),
              Text(
                profile == null
                    ? 'Import a server before connecting'
                    : engine.connected
                        ? 'Protected route active on this Android device'
                        : engine.connecting
                            ? 'Waiting for the Android tunnel status…'
                            : engine.disconnecting
                                ? 'Waiting for Android to confirm disconnect…'
                                : !engine.stateKnown && engine.initialized
                                    ? 'Waiting for a verified VPN status before starting.'
                                    : engine.message ?? (engine.initialized ? 'Tap to request Android VPN permission' : 'Preparing Android VPN engine…'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: _muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFFE7F8F1), Color(0xFFF3EAFE)]),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.bolt_rounded, color: Color(0xFF25856C)),
              SizedBox(width: 8),
              Expanded(child: Text('Exclusive V2rayAG Subs', style: TextStyle(fontWeight: FontWeight.w800, color: _ink))),
              Icon(Icons.lock_outline_rounded, size: 18, color: _muted),
            ]),
            const SizedBox(height: 5),
            Text(
              exclusiveReady ? 'Saved securely on this device' : 'Add your private URL once for one-tap connect',
              style: const TextStyle(fontSize: 12, color: _muted),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: subscriptionBusy ? null : onExclusiveConnect,
                icon: subscriptionBusy
                    ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.flash_on_rounded),
                label: Text(subscriptionBusy ? 'Loading subscription…' : (exclusiveReady ? 'Connect to Exclusive Subs' : 'Set up & connect')),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 17),
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
                const Expanded(child: Text('DESTINATION', style: TextStyle(fontSize: 10, letterSpacing: 1.4, fontWeight: FontWeight.w800, color: _muted))),
                Text(profile?.protocol ?? 'NO SERVER', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: _muted)),
              ]),
              const SizedBox(height: 13),
              Text(
                showDestination ? (profile?.destination ?? 'Add a server link') : 'Destination hidden',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: dark ? Colors.white : _ink),
              ),
              const SizedBox(height: 5),
              Text(profile == null ? 'No client address is read or displayed.' : 'Country: not looked up',
                  style: const TextStyle(fontSize: 12, color: _muted)),
              const SizedBox(height: 8),
              Text(
                engine.connected
                    ? '↓ ${engine.status.downloadSpeed} B/s   ↑ ${engine.status.uploadSpeed} B/s'
                    : 'Live traffic stats appear after a real connection.',
                style: const TextStyle(fontSize: 11, color: _muted),
              ),
              const SizedBox(height: 10),
              Row(children: [
                OutlinedButton.icon(
                  onPressed: profile == null || engine.busy || engine.connecting || engine.disconnecting
                      ? null
                      : onMeasurePing,
                  icon: const Icon(Icons.speed_rounded, size: 17),
                  label: Text(engine.lastPingMs == null ? 'Test latency' : '${engine.lastPingMs} ms'),
                ),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: OutlinedButton.icon(
                  onPressed: onImport,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Import server'),
                  style: OutlinedButton.styleFrom(shape: const StadiumBorder(), foregroundColor: const Color(0xFF317D68)),
                )),
                const SizedBox(width: 10),
                IconButton.filledTonal(
                  tooltip: 'View servers',
                  onPressed: onOpenProfiles,
                  icon: const Icon(Icons.arrow_forward_rounded),
                ),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 15),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
          decoration: BoxDecoration(color: const Color(0xFFFFF1E8), borderRadius: BorderRadius.circular(17)),
          child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline_rounded, size: 17, color: Color(0xFFB35E49)),
            SizedBox(width: 9),
            Expanded(
              child: Text(
                'Subscription URLs are encrypted in Android secure storage and never committed to GitHub. Imported server configs stay in app memory. The app never reads or displays your device IP.',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.45,
                  color: Color(0xFF8A5548),
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 23),
        const Center(child: Text('Source: Telegram @V2rayAG  ·  Developer: HashtagAlireza',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: _muted))),
      ],
    );
  }
}

class _PowerOrb extends StatelessWidget {
  const _PowerOrb({
    required this.reducedMotion,
    required this.connected,
    required this.enabled,
    required this.onPressed,
  });
  final bool reducedMotion;
  final bool connected;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: reducedMotion ? Duration.zero : const Duration(milliseconds: 500),
      width: 190,
      height: 190,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: connected
            ? const [Color(0xFFE9FFF4), Color(0xFFC9F7E1), Color(0xFFC7E7DD)]
            : const [Color(0xFFFFF2E9), Color(0xFFFFD6C8), Color(0xFFE8D8FF)], stops: const [0, .66, 1]),
        boxShadow: [BoxShadow(color: (connected ? _mint : _coral).withValues(alpha: .19), blurRadius: 38, spreadRadius: 2)],
      ),
      child: Center(
        child: SizedBox(
          width: 126,
          height: 126,
          child: Material(
            color: Colors.white.withValues(alpha: .94),
            shape: const CircleBorder(),
            elevation: 8,
            shadowColor: (connected ? const Color(0xFF2E9478) : const Color(0xFFB65D50)).withValues(alpha: .16),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: enabled ? onPressed : null,
              child: Center(child: Icon(
                Icons.power_settings_new_rounded,
                size: 47,
                color: enabled ? (connected ? const Color(0xFF28866A) : const Color(0xFFCB7767)) : Colors.grey,
              )), 
            ),
          ),
        ),
      ),
    );
  }
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
      Text('Servers', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      const Text('Add your subscription, refresh servers, and choose a route.', style: TextStyle(color: _muted)),
      const SizedBox(height: 18),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFFE7F8F1), Color(0xFFF3EAFE)]),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.bolt_rounded, color: Color(0xFF25856C)),
            SizedBox(width: 8),
            Expanded(child: Text('Exclusive V2rayAG Subs', style: TextStyle(fontWeight: FontWeight.w800))),
            Icon(Icons.lock_outline_rounded, size: 18, color: _muted),
          ]),
          const SizedBox(height: 5),
          Text(
            exclusive == null ? 'Enter your private subscription URL once.' : 'Saved securely on this device.',
            style: const TextStyle(fontSize: 12, color: _muted),
          ),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: FilledButton.icon(
            onPressed: subscriptionBusy ? null : onConnectExclusive,
            icon: subscriptionBusy
                ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.flash_on_rounded),
            label: Text(subscriptionBusy ? 'Fetching servers…' : 'One-tap connect'),
          )),
          if (exclusive != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: connected ? null : () => onEditSubscription(exclusive),
                icon: const Icon(Icons.edit_outlined, size: 17),
                label: const Text('Change URL'),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 16),
      Row(children: [
        const Expanded(child: Text('My subscriptions', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
        TextButton.icon(onPressed: connected ? null : onAddSubscription, icon: const Icon(Icons.add_rounded), label: const Text('Add')),
      ]),
      if (customSubscriptions.isEmpty)
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text('Paste a secure HTTPS URL or scan its QR code. URLs are stored on this device only.', style: TextStyle(color: _muted, fontSize: 12)),
        )
      else
        ...customSubscriptions.map((subscription) => Card(
          elevation: 0,
          color: dark ? const Color(0xFF192321) : Colors.white,
          child: ListTile(
            leading: const CircleAvatar(backgroundColor: Color(0xFFE5F6EF), child: Icon(Icons.rss_feed_rounded, color: Color(0xFF317D68))),
            title: Text(subscription.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: const Text('Private URL stored on this device'),
            trailing: Wrap(spacing: 0, children: [
              IconButton(tooltip: 'Refresh servers', onPressed: connected || subscriptionBusy ? null : () => onRefreshSubscription(subscription), icon: const Icon(Icons.refresh_rounded)),
              IconButton(tooltip: 'Edit subscription', onPressed: connected ? null : () => onEditSubscription(subscription), icon: const Icon(Icons.edit_outlined)),
              IconButton(tooltip: 'Remove subscription', onPressed: connected ? null : () => onRemoveSubscription(subscription), icon: const Icon(Icons.delete_outline_rounded)),
            ]),
          ),
        )),
      const SizedBox(height: 10),
      FilledButton.tonalIcon(onPressed: connected ? null : onImport, icon: const Icon(Icons.add_link_rounded), label: const Text('Import one server link')),
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
              side: BorderSide(color: active ? const Color(0xFF52C59E) : Colors.black12, width: active ? 1.5 : 1),
            ),
            child: ListTile(
              onTap: () => onSelect(index),
              leading: CircleAvatar(backgroundColor: const Color(0xFFE5F6EF), child: Text(profile.protocol.substring(0, 1), style: const TextStyle(color: Color(0xFF317D68), fontWeight: FontWeight.w800))),
              title: Text(profile.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${profile.protocol} · ${showDestination ? profile.destination : 'Destination hidden'}\nCountry not looked up · ${active && connected ? 'connected' : 'ready'}', style: const TextStyle(height: 1.5)),
              isThreeLine: true,
              trailing: IconButton(tooltip: 'Remove profile', onPressed: connected && active ? null : () => onRemove(index), icon: const Icon(Icons.close_rounded)),
            ),
          );
        }),
      const SizedBox(height: 12),
      const Text('Profile configs exist only in app memory during this session. Do not share screenshots or logs that reveal a server address.', style: TextStyle(fontSize: 12, color: _muted, height: 1.45)),
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
          Text('Your server list is empty', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          SizedBox(height: 6),
          Text('Import a single VLESS, VMess, Shadowsocks, or Trojan server link to prepare an Android VPN route.', textAlign: TextAlign.center, style: TextStyle(color: _muted, height: 1.45)),
        ]),
      );
}

class _SettingsPage extends StatelessWidget {
  const _SettingsPage({
    required this.reducedMotion,
    required this.showDestination,
    required this.darkMode,
    required this.onReducedMotionChanged,
    required this.onShowDestinationChanged,
    required this.onThemeChanged,
  });

  final bool reducedMotion;
  final bool showDestination;
  final bool darkMode;
  final ValueChanged<bool> onReducedMotionChanged;
  final ValueChanged<bool> onShowDestinationChanged;
  final ValueChanged<bool> onThemeChanged;

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.fromLTRB(20, 18, 20, 28), children: [
        Text('Settings', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text('Appearance settings work now; Android VPN connection is managed from Connect.', style: TextStyle(color: _muted)),
        const SizedBox(height: 20),
        Card(elevation: 0, color: Theme.of(context).colorScheme.surface, child: Column(children: [
          SwitchListTile(title: const Text('Dark appearance'), subtitle: const Text('Change the app theme'), value: darkMode, onChanged: onThemeChanged),
          const Divider(height: 1, indent: 16, endIndent: 16),
          SwitchListTile(title: const Text('Reduce animations'), subtitle: const Text('Reduce decorative motion'), value: reducedMotion, onChanged: onReducedMotionChanged),
          const Divider(height: 1, indent: 16, endIndent: 16),
          SwitchListTile(title: const Text('Show destination address'), subtitle: const Text('Hides the server address in the UI'), value: showDestination, onChanged: onShowDestinationChanged),
        ])),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: const Color(0xFFFFF1E8), borderRadius: BorderRadius.circular(20)),
          child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Platform scope', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF8A5548))),
            SizedBox(height: 8),
            Text('The Android tunnel uses the native Xray-backed VPN service. iPhone still needs its Network Extension project, Apple signing, and device testing. DNS policy, kill switch, auto-connect, and trusted country lookup are not enabled in this build.', style: TextStyle(fontSize: 12, height: 1.5, color: Color(0xFF8A5548))),
          ]),
        ),
        const SizedBox(height: 20),
        const ListTile(leading: _BrandMark(), title: Text('V2rayAG VPN'), subtitle: Text('Source: Telegram @V2rayAG\nDeveloper: V2rayAG telegram channel and HashtagAlireza')),
      ]);
}

Future<String?> _readClipboard(BuildContext context) async {
  try {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!context.mounted) return null;
    final value = data?.text?.trim();
    if (value == null || value.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Clipboard is empty.')));
      return null;
    }
    return value;
  } on Object {
    if (!context.mounted) return null;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not read the clipboard.')));
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
            title: const Text('Scan a subscription QR'),
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
              child: Text('Keep the QR code inside the frame. Its contents stay on this device.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, shadows: [Shadow(blurRadius: 8, color: Colors.black)])),
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
          Text(widget.fixedName ? 'Set up Exclusive V2rayAG Subs' : 'Add a subscription', style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
          const SizedBox(height: 7),
          const Text('Paste or scan your provider’s HTTPS subscription URL. Your own URL is needed; none is bundled with this app.', style: TextStyle(fontSize: 12, color: _muted, height: 1.4)),
          if (!widget.fixedName) ...[
            const SizedBox(height: 14),
            TextField(
              controller: _nameController,
              decoration: InputDecoration(labelText: 'Name', filled: true, fillColor: const Color(0xFFF4F6F3), border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none)),
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
              labelText: 'Private HTTPS subscription URL',
              hintText: 'https://…',
              errorText: _error,
              filled: true,
              fillColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF101817) : const Color(0xFFF4F6F3),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
              suffixIcon: IconButton(tooltip: _hideUrl ? 'Show URL' : 'Hide URL', onPressed: () => setState(() => _hideUrl = !_hideUrl), icon: Icon(_hideUrl ? Icons.visibility_outlined : Icons.visibility_off_outlined)),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            OutlinedButton.icon(onPressed: _paste, icon: const Icon(Icons.content_paste_rounded), label: const Text('Paste clipboard')),
            OutlinedButton.icon(onPressed: _scan, icon: const Icon(Icons.qr_code_scanner_rounded), label: const Text('Scan QR')),
          ]),
          const SizedBox(height: 8),
          const Text('Saved with Android Keystore-backed encrypted storage. Fetching requires HTTPS; server entries stay in memory and are not uploaded to V2rayAG.', style: TextStyle(fontSize: 11, color: _muted, height: 1.4)),
          const SizedBox(height: 14),
          SizedBox(width: double.infinity, child: FilledButton(onPressed: _save, child: const Text('Save securely'))),
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
    try {
      final profile = VpnProfile.fromShareLink(_controller.text);
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
          const Text('Import a server link', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text('One server link: VLESS, VMess, Shadowsocks, or Trojan.', style: TextStyle(fontSize: 12, color: _muted)),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 2,
            maxLines: 4,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              hintText: 'Paste one server share link',
              errorText: _error,
              filled: true,
              fillColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF101817) : const Color(0xFFF4F6F3),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, children: [
            OutlinedButton.icon(onPressed: _paste, icon: const Icon(Icons.content_paste_rounded), label: const Text('Paste clipboard')),
            OutlinedButton.icon(onPressed: _scan, icon: const Icon(Icons.qr_code_scanner_rounded), label: const Text('Scan QR')),
          ]),
          const SizedBox(height: 6),
          const Text('A single server link is held in app memory for this session only. Use Add subscription for a provider URL.', style: TextStyle(fontSize: 11, color: _muted, height: 1.4)),
          const SizedBox(height: 15),
          SizedBox(width: double.infinity, child: FilledButton(onPressed: _preview, child: const Text('Add to this session'))),
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
