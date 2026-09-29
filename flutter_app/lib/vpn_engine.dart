import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_vless/flutter_vless.dart';

import 'vpn_profile.dart';

/// Android VPN bridge. Other platforms deliberately remain disabled until their
/// native projects and signing/entitlement setup are added and tested.
class VpnEngine extends ChangeNotifier {
  late final FlutterVless _client = FlutterVless(onStatusChanged: _onStatus);

  static const _probeUrls = <String>[
    'https://cp.cloudflare.com/generate_204',
    'https://www.google.com/generate_204',
  ];

  VlessStatus _status = VlessStatus();
  bool _initialized = false;
  bool _busy = false;
  bool _startPending = false;
  bool _awaitingStartStatus = false;
  bool _stopPending = false;
  bool _disposed = false;
  String? _message;
  String? _coreVersion;
  String? _failureCategory;
  String _phase = 'idle';
  int? _lastPingMs;
  Timer? _connectWatchdog;

  VlessStatus get status => _status;
  bool get initialized => _initialized;
  bool get busy => _busy;
  String? get message => _message;
  String? get coreVersion => _coreVersion;
  String? get failureCategory => _failureCategory;
  int? get lastPingMs => _lastPingMs;

  bool get connected => _status.connectionState == VlessConnectionState.connected;
  bool get connecting => !_stopPending &&
      (_startPending ||
          _awaitingStartStatus ||
          _status.connectionState == VlessConnectionState.connecting);
  bool get disconnecting =>
      _stopPending || _status.connectionState == VlessConnectionState.disconnecting;

  /// Allows first user-initiated start after native initialization even if the
  /// backend has not emitted an initial status event. Active/transitional states
  /// still prevent duplicate starts.
  bool get canStart =>
      _initialized &&
      _status.connectionState != VlessConnectionState.connected &&
      _status.connectionState != VlessConnectionState.connecting &&
      _status.connectionState != VlessConnectionState.disconnecting &&
      !_busy &&
      !_startPending &&
      !_awaitingStartStatus &&
      !_stopPending;

  String get stateLabel {
    if (disconnecting) return 'DISCONNECTING';
    if (connected) return 'CONNECTED';
    if (connecting) return 'CONNECTING';
    return switch (_status.connectionState) {
      VlessConnectionState.connected => 'CONNECTED',
      VlessConnectionState.connecting => 'CONNECTING',
      VlessConnectionState.disconnecting => 'DISCONNECTING',
      VlessConnectionState.disconnected => 'NOT CONNECTED',
      VlessConnectionState.unknown => 'STATUS UNKNOWN',
    };
  }

  /// Safe local summary: category and state only, never a URI/config or raw
  /// platform exception message.
  String get diagnosticSummary =>
      'Phase: $_phase\nNative status: ${_status.connectionState.name}\n'
      'Engine initialized: $_initialized\nFailure category: ${_failureCategory ?? 'none'}';

  static String _categoryFor(Object error) {
    if (error is PlatformException) {
      final safeCode = error.code.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '');
      return safeCode.isEmpty ? 'PlatformException' : 'PlatformException:$safeCode';
    }
    if (error is MissingPluginException) return 'MissingPluginException';
    if (error is TimeoutException) return 'Timeout';
    if (error is ArgumentError || error is FormatException) return 'InvalidConfiguration';
    final type = error.runtimeType.toString().replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '');
    return type.isEmpty ? 'NativeError' : type;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _onStatus(VlessStatus next) {
    if (_disposed) return;
    final previous = _status.connectionState;
    _status = next;
    switch (next.connectionState) {
      case VlessConnectionState.connected:
        _awaitingStartStatus = false;
        _connectWatchdog?.cancel();
        _connectWatchdog = null;
        _phase = 'connected';
        _message = null;
        _failureCategory = null;
        break;
      case VlessConnectionState.connecting:
        _awaitingStartStatus = false;
        _phase = 'connecting';
        break;
      case VlessConnectionState.disconnecting:
        _awaitingStartStatus = false;
        _connectWatchdog?.cancel();
        _phase = 'disconnecting';
        break;
      case VlessConnectionState.disconnected:
        if (_stopPending) {
          _stopPending = false;
          _awaitingStartStatus = false;
          _connectWatchdog?.cancel();
          _phase = 'disconnected';
        } else if (previous == VlessConnectionState.connecting ||
            previous == VlessConnectionState.connected) {
          _awaitingStartStatus = false;
          _connectWatchdog?.cancel();
          _phase = 'disconnected';
          _failureCategory = 'TunnelDisconnected';
          _message = 'The tunnel disconnected unexpectedly. Check the server, profile, and network.';
        }
        break;
      case VlessConnectionState.unknown:
        break;
    }
    _notify();
  }

  void _armConnectWatchdog() {
    _connectWatchdog?.cancel();
    _connectWatchdog = Timer(const Duration(seconds: 40), () {
      if (_disposed || connected || !connecting) return;
      _phase = 'connect-timeout';
      // If the plugin never emits even a connecting event, release the local
      // pending latch so the user can retry. A reported native `connecting`
      // state remains authoritative and is safely disconnected first.
      _awaitingStartStatus = false;
      _failureCategory = 'ConnectTimeout';
      _message = 'The tunnel is taking longer than expected. The app has not confirmed a working connection.';
      _notify();
    });
  }

  Future<void> initialize() async {
    if (_disposed) return;
    if (defaultTargetPlatform != TargetPlatform.android || kIsWeb) {
      _message = 'The native VPN tunnel is currently wired for Android only.';
      _phase = 'unsupported-platform';
      _notify();
      return;
    }
    if (_initialized || _busy) return;
    _busy = true;
    _phase = 'initializing';
    _failureCategory = null;
    _message = null;
    _notify();
    try {
      await _client.initializeVless(
        notificationIconResourceType: 'mipmap',
        notificationIconResourceName: 'ic_launcher',
      );
      _initialized = true;
      _phase = 'ready';
      try {
        _coreVersion = await _client.getCoreVersion();
      } on Object {
        _coreVersion = null;
      }
    } on Object catch (error) {
      _failureCategory = _categoryFor(error);
      _phase = 'initialization-failed';
      _message = 'Android VPN engine could not initialize. Open connection details for a diagnostic.';
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<bool> connect(VpnProfile profile) async {
    if (!canStart) return false;
    _busy = true;
    _startPending = true;
    _phase = 'permission-request';
    _failureCategory = null;
    _message = null;
    _lastPingMs = null;
    _notify();
    var startAccepted = false;
    try {
      final permitted = await _client.requestPermission();
      if (!permitted) {
        _failureCategory = 'VpnPermissionDenied';
        _phase = 'permission-denied';
        _message = 'Android VPN permission was not granted.';
        return false;
      }
      _awaitingStartStatus = true;
      _phase = 'native-start';
      await _client.startVless(
        remark: profile.name,
        config: profile.config,
        proxyOnly: false,
        notificationDisconnectButtonName: 'Disconnect',
      ).timeout(const Duration(seconds: 30));
      startAccepted = true;
      _phase = connected ? 'connected' : 'waiting-for-tunnel';
      if (!connected && _status.connectionState != VlessConnectionState.connecting) {
        _awaitingStartStatus = true;
      }
      if (!connected) _armConnectWatchdog();
      return true;
    } on Object catch (error) {
      if (connected) {
        _awaitingStartStatus = false;
        _phase = 'connected';
        _message = null;
        _failureCategory = null;
        return true;
      }
      _awaitingStartStatus = false;
      _connectWatchdog?.cancel();
      _connectWatchdog = null;
      _failureCategory = _categoryFor(error);
      _phase = error is ArgumentError || error is FormatException
          ? 'config-rejected'
          : 'native-start-failed';
      _message = error is ArgumentError || error is FormatException
          ? 'This profile was rejected before the VPN started. Re-import a supported server configuration.'
          : 'Could not start this route. Open connection details to inspect a safe diagnostic.';
      return false;
    } finally {
      _busy = false;
      _startPending = false;
      if (!startAccepted && !connected) _awaitingStartStatus = false;
      _notify();
    }
  }

  Future<bool> disconnect() async {
    if (!_initialized || _busy || (!connected && !connecting && !disconnecting)) {
      return false;
    }
    _busy = true;
    _stopPending = true;
    _awaitingStartStatus = false;
    _connectWatchdog?.cancel();
    _connectWatchdog = null;
    _phase = 'stopping';
    _message = null;
    _notify();
    try {
      await _client.stopVless().timeout(const Duration(seconds: 20));
      return true;
    } on Object catch (error) {
      _stopPending = false;
      _failureCategory = _categoryFor(error);
      _phase = 'stop-failed';
      _message = 'Could not stop the VPN yet. Please retry disconnecting.';
      return false;
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<int?> measurePing(VpnProfile profile) async {
    if (!_initialized || _busy || connecting || disconnecting) return null;
    _busy = true;
    _phase = 'latency-check';
    _failureCategory = null;
    _message = null;
    _lastPingMs = null;
    _notify();
    try {
      var shouldProbeProfile = !connected;
      if (connected) {
        try {
          final result = await _client
              .getConnectedServerDelay()
              .timeout(const Duration(seconds: 15));
          if (result >= 0) {
            _lastPingMs = result;
          } else {
            shouldProbeProfile = true;
          }
        } on Object catch (error) {
          _failureCategory = _categoryFor(error);
          shouldProbeProfile = true;
        }
      }
      if (shouldProbeProfile) {
        for (final url in _probeUrls) {
          try {
            final result = await _client
                .getServerDelay(config: profile.config, url: url)
                .timeout(const Duration(seconds: 15));
            if (result >= 0) {
              _lastPingMs = result;
              break;
            }
          } on Object catch (error) {
            _failureCategory = _categoryFor(error);
          }
        }
      }
      if (_lastPingMs == null) {
        _phase = 'latency-failed';
        _failureCategory ??= 'NoDelayResult';
        _message = 'Could not get a latency result. Try another profile or review connection details.';
      } else {
        _phase = 'latency-ok';
        _failureCategory = null;
      }
      return _lastPingMs;
    } on Object catch (error) {
      _phase = 'latency-failed';
      _failureCategory = _categoryFor(error);
      _message = 'Could not get a latency result. Try another profile or review connection details.';
      return null;
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// Returns native plugin diagnostics only when explicitly requested by the
  /// user. The caller must warn that a snapshot may contain destination IPs and
  /// paths; this method never logs or uploads the text.
  Future<String> getSupportDiagnostics() async {
    final summary = diagnosticSummary;
    try {
      final native = await _client
          .getProviderDebugSnapshot()
          .timeout(const Duration(seconds: 8));
      return '$summary\n\nNative diagnostic output:\n${native.trim().isEmpty ? 'No native diagnostic output was returned.' : native.trim()}';
    } on Object catch (error) {
      return '$summary\n\nNative diagnostic output unavailable (${_categoryFor(error)}).';
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _connectWatchdog?.cancel();
    super.dispose();
  }
}
