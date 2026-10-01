import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_vless/flutter_vless.dart';

import 'vpn_profile.dart';

/// Configuration rejection and a fully cleaned-up unreachable node are safe
/// reasons to try another profile in an automatic subscription connection.
bool shouldRetrySubscriptionProfile(String? category) =>
    category == 'InvalidConfiguration' ||
    category == 'PlatformException:INVALID_CONFIG' ||
    category == 'TunnelDisconnected' ||
    category == 'ConnectTimeout';

/// Backwards-compatible policy name retained for existing tests/callers.
bool shouldRetryConfigRejectedProfile(String? category) =>
    category == 'InvalidConfiguration' ||
    category == 'PlatformException:INVALID_CONFIG';

/// Sorts measured delay values before inconclusive probes without treating an
/// unreachable test endpoint as proof that a server is unusable.
int compareMeasuredLatency(int? leftMs, int? rightMs) {
  if (leftMs == null) return rightMs == null ? 0 : 1;
  if (rightMs == null) return -1;
  return leftMs.compareTo(rightMs);
}

/// Android VPN bridge. Other platforms deliberately remain disabled until their
/// native projects and signing/entitlement setup are added and tested.
class VpnEngine extends ChangeNotifier {
  late final FlutterVless _client = FlutterVless(onStatusChanged: _onStatus);

  static const _probeUrls = <String>[
    'https://cp.cloudflare.com/generate_204',
    'https://www.google.com/generate_204',
  ];
  // Batch scans use one provider-independent check per node to avoid doing
  // two sequential fallback requests for hundreds of profiles. An unavailable
  // result remains unverified; it is never treated as proof of a dead server.
  static const _batchProbeUrls = <String>[
    'https://cp.cloudflare.com/generate_204',
  ];

  VlessStatus _status = VlessStatus();
  bool _initialized = false;
  bool _busy = false;
  bool _pingBusy = false;
  int _pingGeneration = 0;
  bool _startPending = false;
  bool _awaitingStartStatus = false;
  bool _stopPending = false;
  bool _ignoreConnectedUntilDisconnected = false;
  int _statusRevision = 0;
  bool _disposed = false;
  String? _message;
  String? _coreVersion;
  String? _failureCategory;
  String _phase = 'idle';
  int? _lastPingMs;
  Completer<bool>? _connectResult;
  Completer<void>? _disconnectResult;
  Stopwatch? _sessionClock;
  Duration _lastSessionDuration = Duration.zero;
  bool _hasSessionData = false;
  Timer? _sessionTicker;
  int _sessionUpload = 0;
  int _sessionDownload = 0;
  int _lastNativeUpload = 0;
  int _lastNativeDownload = 0;

  VlessStatus get status => _status;
  bool get initialized => _initialized;
  bool get busy => _busy;
  bool get pingBusy => _pingBusy;
  String? get message => _message;
  String? get coreVersion => _coreVersion;
  String? get failureCategory => _failureCategory;
  int? get lastPingMs => _lastPingMs;
  int get sessionUploadBytes => _sessionUpload;
  int get sessionDownloadBytes => _sessionDownload;

  Duration get connectedDuration => connected && _sessionClock != null
      ? _lastSessionDuration + _sessionClock!.elapsed
      : _lastSessionDuration;
  bool get hasSessionData => _hasSessionData;

  bool get connected => _status.connectionState == VlessConnectionState.connected;
  bool get connecting => !_stopPending &&
      (_startPending ||
          _awaitingStartStatus ||
          _status.connectionState == VlessConnectionState.connecting);
  bool get disconnecting =>
      _stopPending || _status.connectionState == VlessConnectionState.disconnecting;

  /// Allows the first user-initiated start after native initialization even if
  /// the backend has not yet emitted its initial disconnected status.
  bool get canStart =>
      _initialized &&
      _status.connectionState != VlessConnectionState.connected &&
      _status.connectionState != VlessConnectionState.connecting &&
      _status.connectionState != VlessConnectionState.disconnecting &&
      !_busy &&
      !_startPending &&
      !_awaitingStartStatus &&
      !_stopPending &&
      !_ignoreConnectedUntilDisconnected;

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

  void _completeConnect(bool result) {
    final completer = _connectResult;
    if (completer != null && !completer.isCompleted) completer.complete(result);
  }

  void _completeDisconnect() {
    final completer = _disconnectResult;
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  void _beginSession(VlessStatus next) {
    _sessionClock?.stop();
    // Native status includes the true service-side elapsed time. Use it as the
    // baseline when the Dart process is recreated while Android keeps the VPN
    // service alive, then continue measuring locally from that point.
    _lastSessionDuration = Duration(seconds: next.duration < 0 ? 0 : next.duration);
    _sessionClock = Stopwatch()..start();
    _hasSessionData = true;
    _sessionUpload = 0;
    _sessionDownload = 0;
    _lastNativeUpload = 0;
    _lastNativeDownload = 0;
    _sessionTicker?.cancel();
    _sessionTicker = Timer.periodic(const Duration(seconds: 1), (_) => _notify());
    _recordTraffic(next);
  }

  void _endSession() {
    final clock = _sessionClock;
    if (clock != null) {
      clock.stop();
      _lastSessionDuration += clock.elapsed;
      _sessionClock = null;
    }
    _sessionTicker?.cancel();
    _sessionTicker = null;
  }

  void _recordTraffic(VlessStatus next) {
    if (_sessionClock == null) return;
    final upload = next.upload < 0 ? 0 : next.upload;
    final download = next.download < 0 ? 0 : next.download;
    // Native counters are session cumulative. If the runtime restarts a counter,
    // keep already-accounted bytes and add the new counter's current value.
    _sessionUpload += upload >= _lastNativeUpload
        ? upload - _lastNativeUpload
        : upload;
    _sessionDownload += download >= _lastNativeDownload
        ? download - _lastNativeDownload
        : download;
    _lastNativeUpload = upload;
    _lastNativeDownload = download;
  }

  void _onStatus(VlessStatus next) {
    if (_disposed) return;
    // A late callback from a worker we explicitly stopped must not resurrect
    // the UI or confirm a different connection attempt.
    if (next.connectionState == VlessConnectionState.connected &&
        _ignoreConnectedUntilDisconnected) {
      return;
    }
    _statusRevision++;
    final previous = _status.connectionState;
    final wasConnected = previous == VlessConnectionState.connected;
    _status = next;

    if (next.connectionState == VlessConnectionState.connected && !wasConnected) {
      _beginSession(next);
    } else {
      _recordTraffic(next);
    }

    switch (next.connectionState) {
      case VlessConnectionState.connected:
        _awaitingStartStatus = false;
        _phase = 'connected';
        _message = null;
        _failureCategory = null;
        _completeConnect(true);
        break;
      case VlessConnectionState.connecting:
        _awaitingStartStatus = false;
        _phase = 'connecting';
        break;
      case VlessConnectionState.disconnecting:
        _awaitingStartStatus = false;
        _phase = 'disconnecting';
        break;
      case VlessConnectionState.disconnected:
        _ignoreConnectedUntilDisconnected = false;
        _pingGeneration++;
        _pingBusy = false;
        _endSession();
        if (_stopPending) {
          _stopPending = false;
          _awaitingStartStatus = false;
          _phase = 'disconnected';
          _completeDisconnect();
          _completeConnect(false);
          _message = null;
          _failureCategory = null;
        } else if ((_awaitingStartStatus && previous == VlessConnectionState.connecting) ||
            previous == VlessConnectionState.connected) {
          _awaitingStartStatus = false;
          _phase = 'disconnected';
          _failureCategory = 'TunnelDisconnected';
          _message = 'The tunnel stopped before a working session was confirmed. Check the server, profile, and network.';
          _completeConnect(false);
        } else if (_awaitingStartStatus) {
          // A native initial DISCONNECTED snapshot can precede CONNECTING.
          // Keep waiting for the start result instead of treating it as failure.
        } else {
          _phase = 'disconnected';
        }
        break;
      case VlessConnectionState.unknown:
        break;
    }
    _notify();
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
        notificationIconResourceType: 'drawable',
        notificationIconResourceName: 'ic_v2rayag_notification',
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

  Future<bool> connect(
    VpnProfile profile, {
    List<String> blockedApps = const [],
  }) async {
    if (!canStart) return false;
    _pingGeneration++;
    _pingBusy = false;
    _busy = true;
    _startPending = true;
    _awaitingStartStatus = false;
    _phase = 'permission-request';
    _failureCategory = null;
    _message = null;
    _lastPingMs = null;
    final result = Completer<bool>();
    _connectResult = result;
    _notify();
    var ownsBusy = true;
    var nativeStartAttempted = false;
    _ignoreConnectedUntilDisconnected = false;
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
      nativeStartAttempted = true;
      await _client.startVless(
        remark: profile.name,
        config: profile.config,
        blockedApps: blockedApps,
        proxyOnly: false,
        // Keep the imported provider configuration intact. Forced proxy-DNS
        // rewriting can conflict with provider-supplied DNS/routing rules; the
        // user can still test the selected route explicitly after connecting.
        androidDnsPolicy: AndroidDnsPolicy.config,
        notificationDisconnectButtonName: 'Disconnect',
      ).timeout(const Duration(seconds: 30));
      _phase = connected ? 'native-connected' : 'waiting-for-connected-status';

      // startVless() acknowledges a native request, not a usable data path.
      // Release the operation lock while waiting so a slow/hung connect can be
      // cancelled by the user.
      _busy = false;
      ownsBusy = false;
      _notify();
      bool confirmed;
      try {
        confirmed = await result.future.timeout(const Duration(seconds: 25));
      } on TimeoutException {
        _phase = 'connect-timeout';
        _failureCategory = 'ConnectTimeout';
        _message = 'The app did not receive confirmation of a working tunnel in time.';
        _busy = true;
        ownsBusy = true;
        _notify();
        final cleaned = await _stopNativeAndWait(forceRequest: true);
        if (!cleaned) {
          _failureCategory = 'TunnelResetFailed';
          _phase = 'connect-cleanup-failed';
          _message = 'The connection timed out and Android did not confirm cleanup. Retry disconnect before starting another server.';
        } else {
          _failureCategory = 'ConnectTimeout';
          _phase = 'connect-timeout';
          _message = 'The server did not confirm a working connection in time.';
        }
        return false;
      }
      if (!confirmed) {
        _failureCategory ??= 'TunnelDisconnected';
        _message ??= 'The native tunnel stopped before connection was confirmed.';
        return false;
      }
      if (_stopPending || disconnecting || !connected) {
        _failureCategory = 'TunnelDisconnected';
        _phase = 'disconnected';
        _message = 'The tunnel disconnected before its route could be verified.';
        return false;
      }

      // The pinned native engine reports CONNECTED only after its authenticated
      // packet-path readiness check. Do not tear down a ready tunnel merely
      // because an external latency endpoint is blocked or unreachable; ping is
      // measured separately and must not control session ownership.
      _phase = 'connected';
      _failureCategory = null;
      _message = null;
      _notify();
      return true;
    } on Object catch (error) {
      _awaitingStartStatus = false;
      final timedOut = error is TimeoutException;
      final invalidConfig = error is ArgumentError ||
          error is FormatException ||
          (error is PlatformException && error.code == 'INVALID_CONFIG');
      _failureCategory = timedOut ? 'ConnectTimeout' : _categoryFor(error);
      _phase = invalidConfig
          ? 'config-rejected'
          : timedOut
              ? 'connect-timeout'
              : 'native-start-failed';
      _message = invalidConfig
          ? 'The VPN engine rejected this server configuration before starting. Choose another profile or contact the provider.'
          : timedOut
              ? 'Android did not finish accepting the connection request in time.'
              : 'Could not start this route. Open connection details to inspect a safe diagnostic.';
      _completeConnect(false);
      // A validator rejection while already disconnected is guaranteed to
      // happen before native session mutation, so it is safe to try another
      // profile without issuing a stop. Every other attempted start is
      // reconciled with a stop before retrying or allowing a new manual start.
      if (nativeStartAttempted && invalidConfig &&
          _status.connectionState == VlessConnectionState.disconnected) {
        _ignoreConnectedUntilDisconnected = false;
      } else if (nativeStartAttempted) {
        _ignoreConnectedUntilDisconnected = true;
        final failure = _failureCategory;
        final failedPhase = _phase;
        final failureMessage = _message;
        final cleanupBusyBefore = _busy;
        _busy = true;
        final cleaned = await _stopNativeAndWait(forceRequest: true);
        _busy = cleanupBusyBefore;
        if (!cleaned) {
          _failureCategory = 'TunnelResetFailed';
          _phase = 'start-cleanup-failed';
          _message = 'The start request failed and Android did not confirm cleanup. Retry disconnect before another attempt.';
        } else {
          _failureCategory = failure;
          _phase = failedPhase;
          _message = failureMessage;
        }
      }
      return false;
    } finally {
      if (ownsBusy) _busy = false;
      _startPending = false;
      if (!connected) _awaitingStartStatus = false;
      if (identical(_connectResult, result)) _connectResult = null;
      if (!result.isCompleted) result.complete(false);
      _notify();
    }
  }

  Future<bool> _stopNativeAndWait({required bool forceRequest}) async {
    if (!forceRequest && _status.connectionState == VlessConnectionState.disconnected) {
      _stopPending = false;
      return true;
    }
    final wasAlreadyDisconnected =
        _status.connectionState == VlessConnectionState.disconnected;
    final revisionAtRequest = _statusRevision;
    _stopPending = true;
    _awaitingStartStatus = false;
    _ignoreConnectedUntilDisconnected = true;
    _phase = 'stopping';
    final done = Completer<void>();
    _disconnectResult = done;
    _notify();
    try {
      await _client.stopVless().timeout(const Duration(seconds: 10));
      if (_status.connectionState == VlessConnectionState.disconnected &&
          (wasAlreadyDisconnected || _statusRevision > revisionAtRequest)) {
        _stopPending = false;
        _ignoreConnectedUntilDisconnected = false;
        _completeConnect(false);
        return true;
      }
      await done.future.timeout(const Duration(seconds: 3));
      return _status.connectionState == VlessConnectionState.disconnected;
    } on Object {
      _stopPending = false;
      return false;
    } finally {
      if (_status.connectionState != VlessConnectionState.disconnected) {
        _stopPending = false;
      }
      if (identical(_disconnectResult, done)) _disconnectResult = null;
      _notify();
    }
  }

  Future<bool> disconnect() async {
    // An Android foreground VPN session can outlive/restart the Flutter
    // activity. If native status says it is active, still issue stop even when
    // this Dart engine did not complete its fresh initialization sequence.
    if (_busy || (!connected && !connecting && !disconnecting)) {
      return false;
    }
    _pingGeneration++;
    _pingBusy = false;
    _busy = true;
    _stopPending = true;
    _awaitingStartStatus = false;
    _phase = 'stopping';
    _message = null;
    _notify();
    try {
      final stopped = await _stopNativeAndWait(forceRequest: true);
      if (!stopped) {
        _failureCategory = 'StopTimeout';
        _phase = 'stop-timeout';
        _message = 'Android has not confirmed disconnect yet. Retry disconnect before starting another route.';
        return false;
      }
      _phase = 'disconnected';
      _failureCategory = null;
      _message = null;
      return true;
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<int?> measurePing(
    VpnProfile? profile, {
    bool batchScan = false,
    bool automaticSelection = false,
  }) async {
    final connectedAtStart = connected;
    if (!_initialized || _busy || _pingBusy || connecting || disconnecting ||
        (!connectedAtStart && profile == null)) {
      return null;
    }
    final generation = ++_pingGeneration;
    _pingBusy = true;
    // A disconnected profile probe occupies the engine while its native
    // temporary core runs. A connected-path ping does not lock Disconnect.
    if (!connectedAtStart) _busy = true;
    _phase = 'latency-check';
    _failureCategory = null;
    _message = null;
    _lastPingMs = null;
    _notify();
    try {
      final urls = automaticSelection || batchScan
          ? _batchProbeUrls
          : _probeUrls;
      final timeout = Duration(seconds: batchScan || automaticSelection ? 4 : 5);
      for (final url in urls) {
        try {
          final result = connectedAtStart
              ? await _client
                  .getConnectedServerDelay(url: url)
                  .timeout(timeout)
              : await _client
                  .getServerDelay(config: profile!.config, url: url)
                  .timeout(timeout);
          if (generation != _pingGeneration) return null;
          if (result >= 0) {
            _lastPingMs = result;
            break;
          }
        } on Object catch (error) {
          if (generation != _pingGeneration) return null;
          _failureCategory = _categoryFor(error);
        }
      }
      if (generation != _pingGeneration) return null;
      if (_lastPingMs == null) {
        _phase = 'latency-failed';
        _failureCategory ??= 'NoDelayResult';
        _message = connectedAtStart
            ? 'The VPN is active, but the network health check did not get a response. Try another server or review DNS/network settings.'
            : 'Could not get a latency result. Try another profile or review connection details.';
      } else {
        _phase = connectedAtStart ? 'connected' : 'latency-ok';
        _failureCategory = null;
      }
      return _lastPingMs;
    } on Object catch (error) {
      if (generation != _pingGeneration) return null;
      _phase = 'latency-failed';
      _failureCategory = _categoryFor(error);
      _message = 'Could not get a latency result. Try another profile or review connection details.';
      return null;
    } finally {
      if (generation == _pingGeneration) {
        _pingBusy = false;
        if (!connectedAtStart) _busy = false;
        _notify();
      }
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
          .timeout(const Duration(seconds: 5));
      return '$summary\n\nNative diagnostic output:\n${native.trim().isEmpty ? 'No native diagnostic output was returned.' : native.trim()}';
    } on Object catch (error) {
      return '$summary\n\nNative diagnostic output unavailable (${_categoryFor(error)}).';
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _sessionTicker?.cancel();
    super.dispose();
  }
}
