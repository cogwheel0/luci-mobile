import 'package:flutter/foundation.dart';

/// One associated wireless station, as reported by `iwinfo.assoclist`.
///
/// The app's existing station fetch keeps only the MAC address; this keeps
/// everything the client detail page shows — signal, rates, traffic and how
/// long the device has been connected.
@immutable
class StationInfo {
  const StationInfo({
    required this.macAddress,
    this.interface,
    this.signal,
    this.noise,
    this.inactiveMs,
    this.connectedSeconds,
    this.rxRateKbps,
    this.txRateKbps,
    this.rxBytes,
    this.txBytes,
    this.rxPackets,
    this.txPackets,
    this.rxMhz,
    this.txMhz,
    this.rxMcs,
    this.txMcs,
  });

  /// Upper-case, colon-separated.
  final String macAddress;

  /// The AP interface this station is associated with (`wlan0`, …).
  final String? interface;

  /// dBm; more negative is weaker.
  final int? signal;
  final int? noise;

  /// Milliseconds since the last frame from this station.
  final int? inactiveMs;
  final int? connectedSeconds;

  /// Negotiated PHY rates, in kbit/s as iwinfo reports them.
  final int? rxRateKbps;
  final int? txRateKbps;

  final int? rxBytes;
  final int? txBytes;
  final int? rxPackets;
  final int? txPackets;

  /// Channel width in MHz, and the modulation index.
  final int? rxMhz;
  final int? txMhz;
  final int? rxMcs;
  final int? txMcs;

  /// Signal-to-noise ratio in dB, when both halves were reported.
  int? get snr {
    final s = signal;
    final n = noise;
    if (s == null || n == null) return null;
    return s - n;
  }

  /// Signal as a rough 0-100 quality, using iwinfo's own -110..-40 dBm scale.
  int? get qualityPercent {
    final s = signal;
    if (s == null) return null;
    final clamped = s.clamp(-110, -40);
    return (((clamped + 110) / 70) * 100).round();
  }

  /// 0-4, for a signal-bars icon.
  int? get signalBars {
    final q = qualityPercent;
    if (q == null) return null;
    if (q >= 80) return 4;
    if (q >= 60) return 3;
    if (q >= 40) return 2;
    if (q >= 20) return 1;
    return 0;
  }

  /// Normalizes a MAC to upper-case colon form so lookups match regardless of
  /// whether it came from UCI, a DHCP lease or iwinfo.
  static String normalizeMac(String raw) =>
      raw.trim().toUpperCase().replaceAll('-', ':');

  static int? _int(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  static StationInfo? fromJson(Map<String, dynamic> json, {String? interface}) {
    final mac = json['mac'];
    if (mac == null) return null;

    // iwinfo nests the negotiated rate under rx/tx objects.
    final rx = json['rx'] is Map ? json['rx'] as Map : const {};
    final tx = json['tx'] is Map ? json['tx'] as Map : const {};

    return StationInfo(
      macAddress: normalizeMac(mac.toString()),
      interface: interface,
      signal: _int(json['signal']),
      noise: _int(json['noise']),
      inactiveMs: _int(json['inactive']),
      connectedSeconds: _int(json['connected_time']),
      rxRateKbps: _int(rx['rate']) ?? _int(json['rx_rate']),
      txRateKbps: _int(tx['rate']) ?? _int(json['tx_rate']),
      rxBytes: _int(json['rx_bytes']),
      txBytes: _int(json['tx_bytes']),
      rxPackets: _int(json['rx_packets']),
      txPackets: _int(json['tx_packets']),
      rxMhz: _int(rx['mhz']),
      txMhz: _int(tx['mhz']),
      rxMcs: _int(rx['mcs']),
      txMcs: _int(tx['mcs']),
    );
  }

  @override
  String toString() => 'StationInfo($macAddress on $interface, ${signal}dBm)';
}
