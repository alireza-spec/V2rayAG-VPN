import 'dart:io';

import 'cdn_fronting.dart';

typedef CdnScanProgressCallback = void Function(CdnScanProgress progress);

class CdnScanCandidate {
  const CdnScanCandidate({required this.value, required this.latencyMs});

  final String value;
  final int latencyMs;
}

class CdnScanProgress {
  const CdnScanProgress({
    required this.completed,
    required this.total,
    required this.reachable,
    required this.failed,
  });

  final int completed;
  final int total;
  final int reachable;
  final int failed;
}

class CdnScanReport {
  const CdnScanReport({
    required this.checked,
    required this.reachable,
    required this.failed,
    required this.candidates,
  });

  /// Number of IP/SNI TLS handshakes completed.
  final int checked;
  final int reachable;
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
    Future<int?> Function(String address, String sni, Duration timeout)? probe,
  })  : _lookup = lookup ?? _lookupHost,
        _probe = probe ?? _probeTls {
    assert(maxConcurrency > 0);
  }

  static const akamaiSniCandidates = <String>[
    'a248.e.akamai.net',
    'a77.net.akamai.net',
    'ds-aksb.akamaized.net',
    'www.akamai.com',
  ];
  static const maxIpCandidates = 24;
  static const maxSniCandidates = 8;

  final Duration timeout;
  final int maxConcurrency;
  final Future<List<InternetAddress>> Function(String host) _lookup;
  final Future<int?> Function(String address, String sni, Duration timeout) _probe;

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
    final bestLatency = <String, int>{};
    var completed = 0;
    var successfulHandshakes = 0;
    onProgress?.call(CdnScanProgress(
      completed: 0,
      total: tasks.length,
      reachable: 0,
      failed: 0,
    ));
    for (var offset = 0; offset < tasks.length; offset += maxConcurrency) {
      if (isCancelled?.call() == true) throw const CdnScanCancelled();
      final end = (offset + maxConcurrency).clamp(0, tasks.length).toInt();
      final batch = tasks.sublist(offset, end);
      final outcomes = await Future.wait(batch.map((task) async =>
          (task, await _probe(task.address, task.sni, timeout))));
      for (final (task, latency) in outcomes) {
        completed++;
        if (latency != null) {
          successfulHandshakes++;
          final key = resultKey(task);
          final previous = bestLatency[key];
          if (previous == null || latency < previous) bestLatency[key] = latency;
        }
      }
      onProgress?.call(CdnScanProgress(
        completed: completed,
        total: tasks.length,
        reachable: bestLatency.length,
        failed: completed - successfulHandshakes,
      ));
    }
    if (isCancelled?.call() == true) throw const CdnScanCancelled();
    final results = bestLatency.entries
        .map((entry) => CdnScanCandidate(value: entry.key, latencyMs: entry.value))
        .toList()
      ..sort((a, b) => a.latencyMs.compareTo(b.latencyMs));
    return CdnScanReport(
      checked: completed,
      reachable: results.length,
      failed: completed - successfulHandshakes,
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

  static Future<int?> _probeTls(
    String address,
    String sni,
    Duration timeout,
  ) async {
    Socket? socket;
    SecureSocket? secure;
    final watch = Stopwatch()..start();
    try {
      socket = await Socket.connect(address, 443).timeout(timeout);
      secure = await SecureSocket.secure(socket, host: sni).timeout(timeout);
      watch.stop();
      return watch.elapsedMilliseconds;
    } on Object {
      return null;
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
