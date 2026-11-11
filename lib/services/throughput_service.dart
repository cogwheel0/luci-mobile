import 'dart:collection';
import 'dart:math';

class ThroughputService {
  final Queue<double> _rxHistory = Queue<double>();
  final Queue<double> _txHistory = Queue<double>();

  double _currentRxRate = 0;
  double _currentTxRate = 0;
  Map<String, dynamic>? _lastStats;
  DateTime? _lastTimestamp;

  // Per-interface tracking
  final Map<String, Queue<double>> _rxHistoryPerInterface = {};
  final Map<String, Queue<double>> _txHistoryPerInterface = {};
  final Map<String, double> _currentRxRatePerInterface = {};
  final Map<String, double> _currentTxRatePerInterface = {};
  final Map<String, Map<String, dynamic>?> _lastStatsPerInterface = {};
  final Map<String, DateTime?> _lastTimestampPerInterface = {};

  static const int _maxHistoryLength = 50;
  static const double _maxRate = 1000.0 * 1024.0 * 1024.0; // 1 GB/s
  static const double _minElapsedSeconds = 0.1;

  /// The interfaces in a `network.interface dump` that face the internet:
  /// those holding a default route, IPv4 or IPv6, and those named `wan…`.
  /// The name counts even without a route: a WAN that is down, or a
  /// standby `wanb` that takes over after the dump was read, still carries
  /// internet traffic, and the two-second poll reuses the dump. Empty when
  /// neither says - a dumb AP, or a dump that could not be read.
  static List<Map> upstreamInterfaces(Map? interfaceDump) {
    final interfaces = interfaceDump?['interface'];
    if (interfaces is! List) return const [];
    return [
      for (final i in interfaces)
        if (i is Map &&
            i['interface'] != 'loopback' &&
            i['interface'] != 'lo' &&
            (_hasDefaultRoute(i['route']) || _isNamedWan(i)))
          i,
    ];
  }

  /// netifd protocols whose traffic is carried inside another interface's.
  static const _tunnelProtos = {
    'wireguard',
    'openvpn',
    'openconnect',
    'vpnc',
    'l2tp',
    'pptp',
    'sstp',
    'gre',
    'gretap',
    'grev6',
    'grev6tap',
    'ipip',
    'ipip6',
    '6in4',
    '6to4',
    '6rd',
    'dslite',
    'map',
    'xfrm',
    'vti',
    'vtiv6',
  };

  static bool _isNamedWan(Map iface) =>
      iface['interface']?.toString().startsWith('wan') ?? false;

  static bool _hasDefaultRoute(Object? routes) {
    if (routes is! List) return false;
    return routes.any(
      (r) =>
          r is Map &&
          (r['target'] == '0.0.0.0' || r['target'] == '::') &&
          (r['mask'] == 0 || r['mask'] == '0'),
    );
  }

  /// One device per interface: the layer-3 one, which carries the IP
  /// traffic. Counting `device` as well counted PPPoE twice (the PPPoE
  /// frames on `eth0.2`, then the same traffic again on `pppoe-wan`).
  static String? _countedDevice(Map iface) {
    for (final key in const ['l3_device', 'device']) {
      final value = iface[key]?.toString();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  /// The devices the combined "all interfaces" graph adds up.
  ///
  /// Only internet-facing ones. Adding LAN devices too made both lines
  /// roughly download + upload: a download is received on the WAN and sent
  /// again on the LAN, so neither line said which way traffic went (#81).
  /// With no internet-facing interface to go by, every interface is counted,
  /// as before.
  ///
  /// A tunnel (a WireGuard full tunnel, an L2TP or 6in4 uplink) is left out
  /// when a direct uplink is also counted: everything in the tunnel crosses
  /// that uplink as well, so adding both showed tunnelled traffic at about
  /// twice its rate. Counting the outer layer catches all of it once.
  static Set<String> combinedThroughputDevices(Map? interfaceDump) {
    final upstream = upstreamInterfaces(interfaceDump);
    if (upstream.isNotEmpty) {
      final direct = [
        for (final i in upstream)
          if (!_tunnelProtos.contains(i['proto'])) i,
      ];
      return {
        for (final i in direct.isNotEmpty ? direct : upstream)
          ?_countedDevice(i),
      };
    }
    final interfaces = interfaceDump?['interface'];
    if (interfaces is! List) return const {};
    return {
      for (final i in interfaces)
        if (i is Map && i['interface'] != 'loopback' && i['interface'] != 'lo')
          ?_countedDevice(i),
    };
  }

  /// True when [device] faces the router's clients rather than the
  /// internet: a LAN bridge, a guest network.
  ///
  /// There, what the router *receives* is what its clients upload, so the
  /// graph swaps the two to keep "down" meaning traffic towards the user's
  /// devices. Swapping the wrong way is as bad as the bug, so it takes
  /// positive evidence: the device belongs to an interface the dump lists,
  /// and every interface on it is neither internet-facing nor named `wan…`
  /// and has no routes of its own - a secondary WAN or a VPN routing a
  /// remote subnet has some. Anything else - a device the dump does not
  /// list, or a router whose internet side cannot be told - is left alone.
  static bool isClientFacing(Map? interfaceDump, String device) {
    final upstream = upstreamInterfaces(interfaceDump);
    if (upstream.isEmpty) return false;
    final interfaces = interfaceDump?['interface'];
    if (interfaces is! List) return false;
    final owners = [
      for (final i in interfaces)
        if (i is Map &&
            (i['l3_device']?.toString() == device ||
                i['device']?.toString() == device))
          i,
    ];
    if (owners.isEmpty) return false;
    return owners.every(
      (i) =>
          !upstream.contains(i) &&
          !_isNamedWan(i) &&
          !(i['route'] is List && (i['route'] as List).isNotEmpty),
    );
  }

  List<double> get rxHistory => _rxHistory.toList();
  List<double> get txHistory => _txHistory.toList();
  double get currentRxRate => _currentRxRate;
  double get currentTxRate => _currentTxRate;

  // Interface-specific getters
  List<double> getRxHistoryForInterface(String interface) {
    return _rxHistoryPerInterface[interface]?.toList() ?? [];
  }

  List<double> getTxHistoryForInterface(String interface) {
    return _txHistoryPerInterface[interface]?.toList() ?? [];
  }

  double getCurrentRxRateForInterface(String interface) {
    return _currentRxRatePerInterface[interface] ?? 0.0;
  }

  double getCurrentTxRateForInterface(String interface) {
    return _currentTxRatePerInterface[interface] ?? 0.0;
  }

  void updateThroughput(
    Map<String, dynamic>? networkData,
    Set<String> wanDeviceNames, {
    String? specificInterface,
  }) {
    final now = DateTime.now();

    // Always update per-interface throughput for all interfaces
    if (networkData != null) {
      networkData.forEach((devName, devData) {
        _updateInterfaceThroughput(devName, devData, now);
      });
    }

    // Update overall throughput
    if (specificInterface != null && specificInterface.isNotEmpty) {
      // If specific interface requested, use only that interface's data
      if (networkData != null && networkData.containsKey(specificInterface)) {
        _updateSpecificInterfaceThroughput(
          specificInterface,
          networkData[specificInterface],
          now,
        );
      } else {
        // Interface not found in data, clear current rates
        _currentRxRate = 0;
        _currentTxRate = 0;
      }
    } else {
      // Update combined throughput as before
      if (_lastStats == null || _lastTimestamp == null) {
        _lastStats = networkData;
        _lastTimestamp = now;
        // Add an initial zero-rate data point so the UI has something to display
        _addToHistory(0.0, 0.0);
        return;
      }

      final elapsedSeconds =
          now.difference(_lastTimestamp!).inMilliseconds / 1000.0;

      // Only calculate throughput if we have a reasonable time difference
      if (elapsedSeconds >= _minElapsedSeconds) {
        final lastRx = _calculateTotalBytes(
          _lastStats,
          'rx_bytes',
          wanDeviceNames: wanDeviceNames,
        );
        final lastTx = _calculateTotalBytes(
          _lastStats,
          'tx_bytes',
          wanDeviceNames: wanDeviceNames,
        );
        final currentRx = _calculateTotalBytes(
          networkData,
          'rx_bytes',
          wanDeviceNames: wanDeviceNames,
        );
        final currentTx = _calculateTotalBytes(
          networkData,
          'tx_bytes',
          wanDeviceNames: wanDeviceNames,
        );

        // Calculate rates with a reasonable maximum to prevent spikes
        final rxRate = max(0, (currentRx - lastRx) / elapsedSeconds);
        final txRate = max(0, (currentTx - lastTx) / elapsedSeconds);

        // Cap the rates to prevent unrealistic spikes
        _currentRxRate = min(rxRate.toDouble(), _maxRate);
        _currentTxRate = min(txRate.toDouble(), _maxRate);

        _addToHistory(_currentRxRate, _currentTxRate);
      }

      _lastStats = networkData;
      _lastTimestamp = now;
    }
  }

  /// Safely coerces a counter value to a finite [num]. Some firmware builds
  /// report byte counters as strings; a hard cast would throw and kill the
  /// update. Non-finite values (NaN/Infinity, also parseable from strings)
  /// are rejected so they cannot propagate into rates and history.
  static num _asNum(Object? value) {
    if (value is num) return value.isFinite ? value : 0;
    if (value is String) {
      final parsed = num.tryParse(value);
      return (parsed != null && parsed.isFinite) ? parsed : 0;
    }
    return 0;
  }

  /// Reads a byte counter that may live under `stats.<key>` or directly at
  /// `<key>`. Some firmware builds return a non-map `stats` value - treat
  /// that as absent and fall back to the direct field.
  static Object? _counterValue(Map<String, dynamic> device, String key) {
    final stats = device['stats'];
    if (stats is Map) {
      return stats[key] ?? device[key];
    }
    return device[key];
  }

  void _updateInterfaceThroughput(
    String interface,
    dynamic devData,
    DateTime now,
  ) {
    if (devData == null || devData is! Map<String, dynamic>) return;

    final lastStats = _lastStatsPerInterface[interface];
    final lastTimestamp = _lastTimestampPerInterface[interface];

    if (lastStats == null || lastTimestamp == null) {
      _lastStatsPerInterface[interface] = devData;
      _lastTimestampPerInterface[interface] = now;

      // Initialize history for this interface
      _rxHistoryPerInterface.putIfAbsent(interface, () => Queue<double>());
      _txHistoryPerInterface.putIfAbsent(interface, () => Queue<double>());
      _rxHistoryPerInterface[interface]!.add(0.0);
      _txHistoryPerInterface[interface]!.add(0.0);
      return;
    }

    final elapsedSeconds =
        now.difference(lastTimestamp).inMilliseconds / 1000.0;

    if (elapsedSeconds >= _minElapsedSeconds) {
      // Handle both formats: stats.rx_bytes and direct rx_bytes, tolerating
      // malformed `stats` values from non-standard firmware.
      final lastRx = _asNum(_counterValue(lastStats, 'rx_bytes'));
      final lastTx = _asNum(_counterValue(lastStats, 'tx_bytes'));
      final currentRx = _asNum(_counterValue(devData, 'rx_bytes'));
      final currentTx = _asNum(_counterValue(devData, 'tx_bytes'));

      final rxRate = max(0, (currentRx - lastRx) / elapsedSeconds);
      final txRate = max(0, (currentTx - lastTx) / elapsedSeconds);

      _currentRxRatePerInterface[interface] = min(rxRate.toDouble(), _maxRate);
      _currentTxRatePerInterface[interface] = min(txRate.toDouble(), _maxRate);

      _addToInterfaceHistory(
        interface,
        _currentRxRatePerInterface[interface]!,
        _currentTxRatePerInterface[interface]!,
      );
    }

    _lastStatsPerInterface[interface] = devData;
    _lastTimestampPerInterface[interface] = now;
  }

  void _updateSpecificInterfaceThroughput(
    String interface,
    dynamic devData,
    DateTime now,
  ) {
    if (devData == null || devData is! Map<String, dynamic>) return;

    final rxRate = _currentRxRatePerInterface[interface] ?? 0.0;
    final txRate = _currentTxRatePerInterface[interface] ?? 0.0;

    _currentRxRate = rxRate;
    _currentTxRate = txRate;

    // Use the interface's history for the main display
    final rxHist = _rxHistoryPerInterface[interface];
    final txHist = _txHistoryPerInterface[interface];

    if (rxHist != null && txHist != null) {
      _rxHistory.clear();
      _txHistory.clear();
      _rxHistory.addAll(rxHist);
      _txHistory.addAll(txHist);
    }
  }

  void _addToInterfaceHistory(String interface, double rxRate, double txRate) {
    final rxHist = _rxHistoryPerInterface.putIfAbsent(
      interface,
      () => Queue<double>(),
    );
    final txHist = _txHistoryPerInterface.putIfAbsent(
      interface,
      () => Queue<double>(),
    );

    rxHist.add(rxRate);
    txHist.add(txRate);

    // Maintain fixed queue size
    if (rxHist.length > _maxHistoryLength) {
      rxHist.removeFirst();
    }
    if (txHist.length > _maxHistoryLength) {
      txHist.removeFirst();
    }
  }

  void _addToHistory(double rxRate, double txRate) {
    _rxHistory.add(rxRate);
    _txHistory.add(txRate);

    // Maintain fixed queue size for O(1) performance
    if (_rxHistory.length > _maxHistoryLength) {
      _rxHistory.removeFirst();
    }
    if (_txHistory.length > _maxHistoryLength) {
      _txHistory.removeFirst();
    }
  }

  num _calculateTotalBytes(
    Map<String, dynamic>? networkData,
    String key, {
    Set<String>? wanDeviceNames,
  }) {
    if (networkData == null) return 0;
    num total = 0;
    networkData.forEach((devName, devData) {
      // If wanDeviceNames is null, count all devices (old behavior).
      // Otherwise, only count devices in the set.
      if (wanDeviceNames == null || wanDeviceNames.contains(devName)) {
        if (devData is Map<String, dynamic>) {
          // Handle both formats: stats.rx_bytes and direct rx_bytes
          if (devData['stats'] is Map<String, dynamic> &&
              devData['stats'][key] != null) {
            total += _asNum(devData['stats'][key]);
          } else if (devData[key] != null) {
            total += _asNum(devData[key]);
          }
        }
      }
    });
    return total;
  }

  void clear() {
    _rxHistory.clear();
    _txHistory.clear();
    _currentRxRate = 0;
    _currentTxRate = 0;
    _lastStats = null;
    _lastTimestamp = null;

    // Clear per-interface data
    _rxHistoryPerInterface.clear();
    _txHistoryPerInterface.clear();
    _currentRxRatePerInterface.clear();
    _currentTxRatePerInterface.clear();
    _lastStatsPerInterface.clear();
    _lastTimestampPerInterface.clear();
  }
}
