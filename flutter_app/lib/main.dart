import 'package:flutter/material.dart';

import 'profile_parser.dart';

void main() => runApp(const V2rayAgApp());

const _ink = Color(0xFF182321);
const _muted = Color(0xFF778581);
const _mint = Color(0xFF51D6AF);
const _coral = Color(0xFFFF886E);
const _canvas = Color(0xFFF6F7F3);

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
    final theme = ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: _canvas,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF2E9478),
        brightness: _themeMode == ThemeMode.dark ? Brightness.dark : Brightness.light,
        surface: _themeMode == ThemeMode.dark ? const Color(0xFF17211F) : Colors.white,
      ),
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(
        backgroundColor: _canvas,
        foregroundColor: _ink,
        surfaceTintColor: Colors.transparent,
      ),
    );
    return MaterialApp(
      title: 'V2rayAG VPN',
      debugShowCheckedModeBanner: false,
      theme: theme,
      darkTheme: theme.copyWith(
        scaffoldBackgroundColor: const Color(0xFF101817),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF101817),
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
        ),
      ),
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
  final List<ParsedProfile> _profiles = [];
  int? _selectedIndex;

  Future<void> _importProfile() async {
    final profile = await showModalBottomSheet<ParsedProfile>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ImportSheet(),
    );
    if (profile == null || !mounted) return;
    setState(() {
      _profiles.add(profile);
      _selectedIndex = _profiles.length - 1;
      _tab = 1;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Server details previewed in memory only.')),
    );
  }

  void _removeProfile(int index) {
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
        showDestination: widget.showDestination,
        reducedMotion: widget.reducedMotion,
        onImport: _importProfile,
        onOpenProfiles: () => setState(() => _tab = 1),
      ),
      _ProfilesPage(
        profiles: _profiles,
        selectedIndex: _selectedIndex,
        showDestination: widget.showDestination,
        onImport: _importProfile,
        onSelect: (index) => setState(() => _selectedIndex = index),
        onRemove: _removeProfile,
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
    required this.showDestination,
    required this.reducedMotion,
    required this.onImport,
    required this.onOpenProfiles,
  });

  final ParsedProfile? profile;
  final bool showDestination;
  final bool reducedMotion;
  final VoidCallback onImport;
  final VoidCallback onOpenProfiles;

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
            onPressed: null,
          ),
        ),
        const SizedBox(height: 18),
        const Center(
          child: Column(
            children: [
              Text('NOT CONNECTED', style: TextStyle(fontSize: 12, letterSpacing: 2.1, fontWeight: FontWeight.w800, color: _ink)),
              SizedBox(height: 5),
              Text('VPN tunnel integration is the next milestone', textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: _muted)),
            ],
          ),
        ),
        const SizedBox(height: 24),
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
              const SizedBox(height: 14),
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
            Expanded(child: Text('This build previews server metadata only. It does not connect, fetch subscriptions, or save credentials.',
                style: TextStyle(fontSize: 11, height: 1.45, color: Color(0xFF8A5548)))),
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
  const _PowerOrb({required this.reducedMotion, required this.onPressed});
  final bool reducedMotion;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: reducedMotion ? Duration.zero : const Duration(milliseconds: 500),
      width: 190,
      height: 190,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(colors: [Color(0xFFFFF2E9), Color(0xFFFFD6C8), Color(0xFFE8D8FF)], stops: [0, .66, 1]),
        boxShadow: [BoxShadow(color: _coral.withValues(alpha: .19), blurRadius: 38, spreadRadius: 2)],
      ),
      child: Center(
        child: SizedBox(
          width: 126,
          height: 126,
          child: Material(
            color: Colors.white.withValues(alpha: .94),
            shape: const CircleBorder(),
            elevation: 8,
            shadowColor: const Color(0xFFB65D50).withValues(alpha: .16),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPressed,
              child: const Center(child: Icon(Icons.power_settings_new_rounded, size: 47, color: Color(0xFFCB7767))),
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
    required this.onImport,
    required this.onSelect,
    required this.onRemove,
  });

  final List<ParsedProfile> profiles;
  final int? selectedIndex;
  final bool showDestination;
  final VoidCallback onImport;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ListView(padding: const EdgeInsets.fromLTRB(20, 18, 20, 28), children: [
      Text('Servers', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      const Text('Add one server share link to preview its destination.', style: TextStyle(color: _muted)),
      const SizedBox(height: 20),
      FilledButton.icon(onPressed: onImport, icon: const Icon(Icons.add_link_rounded), label: const Text('Import server link')),
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
              subtitle: Text('${profile.protocol} · ${showDestination ? profile.destination : 'Destination hidden'}\nCountry not looked up · preview only', style: const TextStyle(height: 1.5)),
              isThreeLine: true,
              trailing: IconButton(tooltip: 'Remove preview', onPressed: () => onRemove(index), icon: const Icon(Icons.close_rounded)),
            ),
          );
        }),
      const SizedBox(height: 12),
      const Text('Imported entries are temporary display summaries. Link credentials are discarded and nothing is stored.', style: TextStyle(fontSize: 12, color: _muted, height: 1.45)),
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
          Text('Import a single VLESS, VMess, Shadowsocks, or Trojan server link to preview its destination.', textAlign: TextAlign.center, style: TextStyle(color: _muted, height: 1.45)),
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
        const Text('These controls affect this app preview only.', style: TextStyle(color: _muted)),
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
            Text('Not active in this milestone', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF8A5548))),
            SizedBox(height: 8),
            Text('VPN protocol and transport selection, DNS, kill switch, auto-connect, live ping, notifications, and country lookup need the native tunnel and server metadata. They are intentionally not shown as working controls yet.', style: TextStyle(fontSize: 12, height: 1.5, color: Color(0xFF8A5548))),
          ]),
        ),
        const SizedBox(height: 20),
        const ListTile(leading: _BrandMark(), title: Text('V2rayAG VPN'), subtitle: Text('Source: Telegram @V2rayAG\nDeveloper: V2rayAG telegram channel and HashtagAlireza')),
      ]);
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

  void _preview() {
    try {
      final profile = ProfileParser.parse(_controller.text);
      _controller.clear();
      Navigator.of(context).pop(profile);
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
          const Text('Preview a server link', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text('One link at a time: VLESS, VMess, Shadowsocks, or Trojan.', style: TextStyle(fontSize: 12, color: _muted)),
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
          const Text('Do not paste a subscription URL. This preview does not connect, fetch, or save credentials.', style: TextStyle(fontSize: 11, color: _muted, height: 1.4)),
          const SizedBox(height: 15),
          SizedBox(width: double.infinity, child: FilledButton(onPressed: _preview, child: const Text('Preview destination'))),
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
