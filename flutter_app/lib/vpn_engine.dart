import 'package:flutter/foundation.dart';
import 'package:flutter_vless/flutter_vless.dart';

import 'vpn_profile.dart';

/// Android VPN bridge. Other platforms deliberately remain disabled until their
/// native projects and signing/entitlement setup are added and tested.
class VpnEngine extends ChangeNotifier {
  late final FlutterVless _client = FlutterVless(onStatusChanged: _onStatus);

  VlessStatus _status = VlessStatus();
  bool _initialized = false;
  bool _busy = false;
  bool _startPending = false;
  bool _awaitingStartStatus = false;
  bool _stopPending = false;
  bool _disposed = false;
  String? _message;
  String? _coreVersion;
  int? _lastPingMs;

  VlessStatus get status => _status;
  bool get initialized => _initialized;
  bool get busy => _busy;
  String? get message => _message;
  String? get coreVersion => _coreVersion;
  int? get lastPingMs => _lastPingMs;

  bool get connected => _status.connectionState == VlessConnectionState.connected;
  bool get connecting => !_stopPending &&
      (_startPending ||
          _awaitingStartStatus ||
          _status.connectionState == VlessConnectionState.connecting);
  bool get disconnecting =>
      _stopPending || _status.connectionState == VlessConnectionState.disconnecting;

  /// Allows the first user-initiated start after plugin initialization even if
  /// the native backend has not emitted an initial status event. Unknown status
  /// must not leave the connect control disabled forever. Explicit active or
  /// transitional states still prevent duplicate starts.
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

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _onStatus(VlessStatus next) {
    if (_disposed) return;
    _status = next;
    if (next.connectionState != VlessConnectionState.unknown) {
      if (_awaitingStartStatus) _awaitingStartStatus = false;
      if (_stopPending && next.connectionState == VlessConnectionState.disconnected) {
        _stopPending = false;
      }
    }
    _notify();
  }

  Future<void> initialize() async {
    if (_disposed) return;
    if (defaultTargetPlatform != TargetPlatform.android || kIsWeb) {
      _message = 'The native VPN tunnel is currently wired for Android only.';
      _notify();
      return;
    }
    if (_initialized || _busy) return;
    _busy = true;
    _message = null;
    _notify();
    try {
      await _client.initializeVless(
        notificationIconResourceType: 'mipmap',
        notificationIconResourceName: 'ic_launcher',
      );
      // Core-version reporting is informational. A failure here must not make
      // an otherwise initialized VPN backend unusable.
      _initialized = true;
      try {
        _coreVersion = await _client.getCoreVersion();
      } on Object {
        _coreVersion = null;
      }
    } catch (_) {
      _message = 'Android VPN engine could not initialize. Restart the app and try again.';
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<bool> connect(VpnProfile profile) async {
    if (!canStart) return false;
    _busy = true;
    _startPending = true;
    _message = null;
    _lastPingMs = null;
    _notify();
    var startRequested = false;
    try {
      final permitted = await _client.requestPermission();
      if (!permitted) {
        _message = 'Android VPN permission was not granted.';
        return false;
      }
      // Keep the UI in a pending state until the native service reports its
      // first status after the request; this avoids duplicate start requests.
      _awaitingStartStatus = true;
      startRequested = true;
      await _client.startVless(
        remark: profile.name,
        config: profile.config,
        proxyOnly: false,
        notificationDisconnectButtonName: 'Disconnect',
      );
      return true;
    } catch (_) {
      _awaitingStartStatus = false;
      _message = 'Could not start this route. Check the server link and try again.';
      return false;
    } finally {
      _busy = false;
      _startPending = false;
      if (!startRequested) _awaitingStartStatus = false;
      _notify();
    }
  }

  Future<bool> disconnect() async {
    if (!_initialized || _busy || (!connected && !connecting && !disconnecting)) {
      return false;
    }
    _busy = true;
    _stopPending = true;
    _message = null;
    _notify();
    try {
      await _client.stopVless();
      // Do not claim disconnection until the native status event confirms it.
      return true;
    } catch (_) {
      _stopPending = false;
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
    _message = null;
    _notify();
    try {
      final result = connected
          ? await _client.getConnectedServerDelay()
          : await _client.getServerDelay(config: profile.config);
      _lastPingMs = result >= 0 ? result : null;
      if (_lastPingMs == null) _message = 'The route did not return a latency result.';
      return _lastPingMs;
    } catch (_) {
      _message = 'Latency check failed. Try again when the server is reachable.';
      return null;
    } finally {
      _busy = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
