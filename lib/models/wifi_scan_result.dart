/// Represents a WiFi network found during a wireless scan.
class WifiScanResult {
  final String ssid;
  final String bssid;
  final String mode;
  final int channel;
  final int? frequency; // MHz — null when not provided by the scan response
  final int signal;
  final int quality;
  final int qualityMax;
  final WifiEncryption encryption;

  WifiScanResult({
    required this.ssid,
    required this.bssid,
    required this.mode,
    required this.channel,
    this.frequency,
    required this.signal,
    required this.quality,
    required this.qualityMax,
    required this.encryption,
  });

  factory WifiScanResult.fromJson(Map<String, dynamic> json) {
    return WifiScanResult(
      ssid: _safeString(json['ssid'], ''),
      bssid: _safeString(json['bssid'], ''),
      mode: _safeString(json['mode'], 'Unknown'),
      channel: _safeInt(json['channel'], 0),
      frequency: _safeWifiFrequency(json['frequency']),
      signal: _safeInt(json['signal'], -100),
      quality: _safeInt(json['quality'], 0),
      qualityMax: _safeInt(json['quality_max'], 100),
      encryption: WifiEncryption.fromJson(
        json['encryption'] is Map<String, dynamic>
            ? json['encryption']
            : <String, dynamic>{},
      ),
    );
  }

  /// Safely extract an int from a dynamic value (could be int, double, String, List, null).
  static int _safeInt(dynamic value, int defaultValue) {
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is String) return int.tryParse(value) ?? defaultValue;
    return defaultValue;
  }

  /// Safely extract a positive integer. Returns null for missing, zero, or
  /// negative values so callers can fall back to channel-based logic.
  static int? _safePositiveInt(dynamic value) {
    final parsed = _safeInt(value, 0);
    return parsed > 0 ? parsed : null;
  }

  /// Returns a valid Wi-Fi frequency in MHz, or null if the value is missing,
  /// zero, negative, or outside any known Wi-Fi band range.
  /// Valid ranges: 2.4 GHz (2400–2500), 4.9 GHz (4900–5000),
  ///               5 GHz (5000–5925), 6 GHz (5925–7125).
  /// Out-of-range values must fall back to channel-based classification.
  static int? _safeWifiFrequency(dynamic value) {
    final parsed = _safeInt(value, 0);
    if (parsed <= 0) return null;
    if (parsed >= 2400 && parsed <= 2500) return parsed;
    if (parsed >= 4900 && parsed <= 5000) return parsed;
    if (parsed >= 5000 && parsed <= 7125) return parsed;
    return null; // reject implausible values
  }

  /// Safely extract a String from a dynamic value.
  static String _safeString(dynamic value, String defaultValue) {
    if (value is String) return value;
    if (value == null) return defaultValue;
    return value.toString();
  }

  /// Signal quality as a percentage (0-100).
  int get qualityPercent {
    if (qualityMax <= 0) return 0;
    return ((quality / qualityMax) * 100).round().clamp(0, 100);
  }

  /// Human-readable signal strength descriptor.
  String get signalStrength {
    if (signal >= -50) return 'Excellent';
    if (signal >= -60) return 'Good';
    if (signal >= -70) return 'Fair';
    if (signal >= -80) return 'Weak';
    return 'Very Weak';
  }

  /// Returns the appropriate WiFi signal icon level (0-4 bars).
  int get signalBars {
    if (signal >= -50) return 4;
    if (signal >= -60) return 3;
    if (signal >= -70) return 2;
    if (signal >= -80) return 1;
    return 0;
  }

  /// Frequency band derived from the scan frequency (MHz), with channel fallback.
  String get band {
    if (frequency != null) {
      if (frequency! >= 5925) return '6 GHz';
      if (frequency! >= 5000) return '5 GHz';
      return '2.4 GHz';
    }
    // Channel-based fallback cannot distinguish 6 GHz
    if (channel >= 1 && channel <= 14) return '2.4 GHz';
    if (channel >= 32) return '5 GHz';
    return 'Unknown';
  }
}

/// Represents WiFi encryption details from a scan result.
class WifiEncryption {
  final bool enabled;
  final String description;
  final bool wep;
  final int wpa;
  final List<String> authSuites;
  final List<String> pairCiphers;
  final List<String> groupCiphers;

  WifiEncryption({
    required this.enabled,
    required this.description,
    required this.wep,
    required this.wpa,
    required this.authSuites,
    required this.pairCiphers,
    required this.groupCiphers,
  });

  factory WifiEncryption.fromJson(Map<String, dynamic> json) {
    // 'wpa' can be int (e.g., 2) or List<int> (e.g., [2] or [1,2])
    int wpaVersion = 0;
    final rawWpa = json['wpa'];
    if (rawWpa is int) {
      wpaVersion = rawWpa;
    } else if (rawWpa is List && rawWpa.isNotEmpty) {
      // Take the highest WPA version from the array
      wpaVersion = rawWpa
          .whereType<int>()
          .fold(0, (max, v) => v > max ? v : max);
      if (wpaVersion == 0) {
        // Try parsing from dynamic types
        for (final v in rawWpa) {
          final parsed = WifiScanResult._safeInt(v, 0);
          if (parsed > wpaVersion) wpaVersion = parsed;
        }
      }
    }

    final wep = json['wep'] == true;
    final enabled = json['enabled'] == true || wpaVersion > 0 || wep;

    // Auth suites: try multiple key names used by different OpenWrt versions
    final authSuites = _toStringList(json['auth_suites'])
        + _toStringList(json['authentication']);

    // Ciphers: try multiple key names
    final pairCiphers = _toStringList(json['pair_ciphers'])
        + _toStringList(json['ciphers']);
    final groupCiphers = _toStringList(json['group_ciphers']);

    // Build description from available data if not provided
    String description;
    final rawDesc = json['description'];
    if (rawDesc is String && rawDesc.isNotEmpty) {
      description = rawDesc;
    } else if (!enabled) {
      description = 'None';
    } else if (wep) {
      description = 'WEP';
    } else {
      // Build from wpa version + auth + ciphers
      final wpaPart = wpaVersion >= 3
          ? 'WPA3'
          : wpaVersion >= 2
              ? 'WPA2'
              : wpaVersion >= 1
                  ? 'WPA'
                  : 'WPA';
      final authPart = authSuites.isNotEmpty
          ? ' ${authSuites.map((s) => s.toUpperCase()).join("/")}'
          : '';
      final cipherPart = pairCiphers.isNotEmpty
          ? ' (${pairCiphers.map((s) => s.toUpperCase()).join(", ")})'
          : '';
      description = '$wpaPart$authPart$cipherPart';
    }

    return WifiEncryption(
      enabled: enabled,
      description: description,
      wep: wep,
      wpa: wpaVersion,
      authSuites: authSuites,
      pairCiphers: pairCiphers,
      groupCiphers: groupCiphers,
    );
  }

  static List<String> _toStringList(dynamic value) {
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    return [];
  }

  /// Whether this network is open (no encryption).
  bool get isOpen => !enabled;

  /// Short encryption label for display.
  String get shortLabel {
    if (!enabled) return 'Open';
    if (wep) return 'WEP';
    if (description.contains('WPA3')) return 'WPA3';
    if (description.contains('WPA2')) return 'WPA2';
    if (description.contains('WPA')) return 'WPA';
    return description;
  }

  /// Returns the OpenWrt encryption config string for connecting.
  String get openwrtEncryption {
    if (!enabled) return 'none';
    if (wep) return 'wep-open';
    final hasSAE = authSuites.contains('SAE');
    final hasPSK = authSuites.contains('PSK');
    final hasOWE = authSuites.contains('OWE');
    final hasEAP = authSuites.contains('EAP') || authSuites.contains('802.1X');
    // OWE: opportunistic wireless encryption
    if (hasOWE) return 'owe';
    // Enterprise: we cannot map to a PSK mode — return a sentinel so callers
    // can block the connection instead of creating a broken config.
    if (hasEAP && !hasSAE && !hasPSK) return 'wpa-eap';
    if (hasSAE && hasPSK) {
      return wpa >= 2 ? 'sae-mixed' : 'sae';
    }
    if (hasSAE) return 'sae';
    if (wpa >= 2) return 'psk2';
    if (wpa >= 1) return 'psk';
    return 'psk2'; // Default fallback
  }

  /// Whether this encryption type requires a password.
  bool get requiresPassword => enabled && !authSuites.contains('OWE');

  /// Whether this encryption type requires enterprise (EAP) credentials
  /// that the app cannot configure.
  bool get isEnterprise {
    final hasEAP = authSuites.contains('EAP') || authSuites.contains('802.1X');
    return hasEAP && !authSuites.contains('SAE') && !authSuites.contains('PSK');
  }
}
