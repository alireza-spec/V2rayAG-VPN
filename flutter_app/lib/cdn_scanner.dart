import 'dart:io';

import 'cdn_fronting.dart';

typedef CdnScanProgressCallback = void Function(CdnScanProgress progress);

class CdnEndpointProbeResult {
  const CdnEndpointProbeResult({this.tcpConnectMs, this.tlsHandshakeMs});

  final int? tcpConnectMs;
  final int? tlsHandshakeMs;

  bool get tcpReachable => tcpConnectMs != null;
  bool get tlsReachable => tlsHandshakeMs != null;
}

typedef CdnEndpointProbe = Future<CdnEndpointProbeResult> Function(
    String address, String sni, Duration timeout);

class CdnScanCandidate {
  const CdnScanCandidate({
    required this.value,
    required this.tcpLatencyMs,
    required this.tlsHandshakeMs,
  });

  final String value;
  final int tcpLatencyMs;
  final int tlsHandshakeMs;

  /// Kept as a convenience for existing sort/display callers.
  int get latencyMs => tlsHandshakeMs;
}

class CdnScanProgress {
  const CdnScanProgress({
    required this.completed,
    required this.total,
    required this.reachable,
    required this.tcpReachable,
    required this.failed,
  });

  final int completed;
  final int total;
  final int reachable;
  final int tcpReachable;
  final int failed;
}

class CdnScanReport {
  const CdnScanReport({
    required this.checked,
    required this.reachable,
    required this.tcpReachable,
    required this.failed,
    required this.candidates,
  });

  /// Number of IP/SNI TLS handshakes completed.
  final int checked;
  final int reachable;
  final int tcpReachable;
  final int failed;
  final List<CdnScanCandidate> candidates;
}

class CdnScanCancelled implements Exception {
  const CdnScanCancelled();
}

/// Low-rate, on-device Akamai endpoint reachability checks.
///
/// DNS is resolved on the phone for every scan. Results mean only that a valid
/// TLS handshake completed from the current network; they are not proof that
/// any particular VPN profile or tunnel protocol will work.
class CdnEndpointScanner {
  CdnEndpointScanner({
    this.timeout = const Duration(seconds: 3),
    this.maxConcurrency = 3,
    Future<List<InternetAddress>> Function(String host)? lookup,
    CdnEndpointProbe? probe,
  })  : _lookup = lookup ?? _lookupHost,
        _probe = probe ?? _probeTls {
    assert(maxConcurrency > 0);
  }

  // Resolve a broader set of commonly published Akamai hostnames live on
  // each device/network; do not present a static, potentially stale IP list.
  static const akamaiSniCandidates = <String>[
    'a248.e.akamai.net',
    'a77.net.akamai.net',
    'ds-aksb.akamaized.net',
    'www.akamai.com',
    'akamai.com',
    'www.akamai.net',
    'www.akamaihd.net',
    'www.akamaized.net',
    'www.akamaitechnologies.com',
    'www.edgesuite.net',
    'www.edgekey.net',
    'www.akamaiedge.net',
    'www.akamai.com.edgekey.net',
    'download.akamai.com',
    'content.akamai.com',
    'client.akamai.com',
  ];
  static const maxIpCandidates = 96;
  static const maxSniCandidates = 16;

  final Duration timeout;
  final int maxConcurrency;
  final Future<List<InternetAddress>> Function(String host) _lookup;
  final CdnEndpointProbe _probe;

  Future<CdnScanReport> scanIps({
    String preferredSni = '',
    bool Function()? isCancelled,
    CdnScanProgressCallback? onProgress,
  }) async {
    final preferred = preferredSni.trim().isEmpty
        ? null
        : CdnFrontingSettings.normalizeSniHostname(preferredSni);
    final snis = preferred == null
        ? akamaiSniCandidates
        : <String>[preferred];
    final tasks = <_ProbeTask>[];
    final seenPairs = <String>{};
    final seenIps = <String>{};
    for (final sni in snis) {
      if (isCancelled?.call() == true) throw const CdnScanCancelled();
      final addresses = await _safeLookup(sni);
      for (final address in addresses) {
        if (tasks.length >= maxIpCandidates) break;
        final ip = address.address;
        if (!seenIps.contains(ip) && seenIps.length >= maxIpCandidates) continue;
        seenIps.add(ip);
        final pair = '$ip|$sni';
        if (seenPairs.add(pair)) tasks.add(_ProbeTask(ip, sni));
      }
      if (tasks.length >= maxIpCandidates) break;
    }
    return _run(tasks, resultKey: (task) => task.address,
        isCancelled: isCancelled, onProgress: onProgress);
  }

  Future<CdnScanReport> scanSni({
    String currentSni = '',
    String cdnIps = '',
    bool Function()? isCancelled,
    CdnScanProgressCallback? onProgress,
  }) async {
    final domains = <String>[];
    final entered = currentSni.trim().isEmpty
        ? null
        : CdnFrontingSettings.normalizeSniHostname(currentSni);
    if (entered != null) domains.add(entered);
    for (final candidate in akamaiSniCandidates) {
      if (!domains.contains(candidate) && domains.length < maxSniCandidates) {
        domains.add(candidate);
      }
    }

    final ips = <String>[];
    for (final candidate in CdnFrontingSettings.parseCdnIps(cdnIps)) {
      if (!ips.contains(candidate) && ips.length < 8) ips.add(candidate);
    }

    final tasks = <_ProbeTask>[];
    final seenPairs = <String>{};
    for (final sni in domains) {
      if (isCancelled?.call() == true) throw const CdnScanCancelled();
      final addresses = ips.isEmpty
          ? (await _safeLookup(sni)).map((address) => address.address).toList()
          : ips;
      for (final ip in addresses) {
        final pair = '$ip|$sni';
        if (seenPairs.add(pair)) tasks.add(_ProbeTask(ip, sni));
        if (tasks.length >= maxIpCandidates) break;
      }
      if (tasks.length >= maxIpCandidates) break;
    }
    return _run(tasks, resultKey: (task) => task.sni,
        isCancelled: isCancelled, onProgress: onProgress);
  }

  Future<CdnScanReport> _run(
    List<_ProbeTask> tasks, {
    required String Function(_ProbeTask) resultKey,
    bool Function()? isCancelled,
    CdnScanProgressCallback? onProgress,
  }) async {
    final bestByKey = <String, CdnScanCandidate>{};
    var completed = 0;
    var successfulTcpPairs = 0;
    var successfulTlsPairs = 0;
    onProgress?.call(CdnScanProgress(
      completed: 0,
      total: tasks.length,
      reachable: 0,
      tcpReachable: 0,
      failed: 0,
    ));
    for (var offset = 0; offset < tasks.length; offset += maxConcurrency) {
      if (isCancelled?.call() == true) throw const CdnScanCancelled();
      final end = (offset + maxConcurrency).clamp(0, tasks.length).toInt();
      final batch = tasks.sublist(offset, end);
      final outcomes = await Future.wait(batch.map((task) async =>
          (task, await _probe(task.address, task.sni, timeout))));
      for (final (task, probe) in outcomes) {
        completed++;
        if (probe.tcpReachable) successfulTcpPairs++;
        final tlsMs = probe.tlsHandshakeMs;
        final tcpMs = probe.tcpConnectMs;
        if (tlsMs != null && tcpMs != null) {
          successfulTlsPairs++;
          final key = resultKey(task);
          final previous = bestByKey[key];
          if (previous == null || tlsMs < previous.tlsHandshakeMs) {
            bestByKey[key] = CdnScanCandidate(
              value: key,
              tcpLatencyMs: tcpMs,
              tlsHandshakeMs: tlsMs,
            );
          }
        }
      }
      onProgress?.call(CdnScanProgress(
        completed: completed,
        total: tasks.length,
        reachable: bestByKey.length,
        tcpReachable: successfulTcpPairs,
        failed: completed - successfulTlsPairs,
      ));
    }
    if (isCancelled?.call() == true) throw const CdnScanCancelled();
    final results = bestByKey.values.toList()
      ..sort((a, b) => a.tlsHandshakeMs.compareTo(b.tlsHandshakeMs));
    return CdnScanReport(
      checked: completed,
      reachable: results.length,
      tcpReachable: successfulTcpPairs,
      failed: completed - successfulTlsPairs,
      candidates: List.unmodifiable(results),
    );
  }

  Future<List<InternetAddress>> _safeLookup(String host) async {
    try {
      return await _lookup(host).timeout(timeout);
    } on Object {
      return const <InternetAddress>[];
    }
  }

  static Future<List<InternetAddress>> _lookupHost(String host) =>
      InternetAddress.lookup(host, type: InternetAddressType.any);

  static Future<CdnEndpointProbeResult> _probeTls(
    String address,
    String sni,
    Duration timeout,
  ) async {
    Socket? socket;
    SecureSocket? secure;
    int? tcpMs;
    try {
      final tcpWatch = Stopwatch()..start();
      socket = await Socket.connect(address, 443).timeout(timeout);
      tcpWatch.stop();
      tcpMs = tcpWatch.elapsedMilliseconds;

      final tlsWatch = Stopwatch()..start();
      try {
        secure = await SecureSocket.secure(socket, host: sni).timeout(timeout);
        tlsWatch.stop();
        return CdnEndpointProbeResult(
          tcpConnectMs: tcpMs,
          tlsHandshakeMs: tlsWatch.elapsedMilliseconds,
        );
      } on Object {
        return CdnEndpointProbeResult(tcpConnectMs: tcpMs);
      }
    } on Object {
      return const CdnEndpointProbeResult();
    } finally {
      secure?.destroy();
      socket?.destroy();
    }
  }
}

class _ProbeTask {
  const _ProbeTask(this.address, this.sni);
  final String address;
  final String sni;
}
