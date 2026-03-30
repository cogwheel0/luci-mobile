enum ConnectionType { wired, wireless, unknown }

class Client {
  final String ipAddress;
  final String macAddress;
  final String hostname;
  final String? hostId;
  final int? leaseTime; // in seconds
  final String? vendor;
  final String? dnsName;
  final String? clientId;
  final int? activeTime; // in seconds
  final int? expiresAt; // timestamp in seconds
  final ConnectionType connectionType;
  final List<String>? ipv6Addresses;
  // GL.iNet-specific enrichment fields
  final String? wifiBand; // "2G", "5G", "6G", or null (wired/unknown)
  final bool? isOnline; // true/false from GL.iNet API, null if unknown
  final String? deviceClass; // "phone", "laptop", "tv", etc.

  Client({
    required this.ipAddress,
    required this.macAddress,
    required this.hostname,
    this.hostId,
    this.leaseTime,
    this.vendor,
    this.dnsName,
    this.clientId,
    this.activeTime,
    this.expiresAt,
    this.connectionType = ConnectionType.unknown,
    this.ipv6Addresses,
    this.wifiBand,
    this.isOnline,
    this.deviceClass,
  });

  // Helper function to determine connection type from MAC address or other data
  static ConnectionType _determineConnectionType(Map<String, dynamic> lease) {
    // Check for wireless-specific fields first
    if (lease['signal'] != null || lease['noise'] != null) {
      return ConnectionType.wireless;
    }

    // Check for wired-specific fields
    if (lease['port'] != null ||
        lease['ifname']?.toString().startsWith('eth') == true) {
      return ConnectionType.wired;
    }

    // Check hostname for common wireless indicators
    final hostname = (lease['hostname'] ?? '').toString().toLowerCase();
    if (hostname.contains('android') ||
        hostname.contains('iphone') ||
        hostname.contains('ipad') ||
        hostname.contains('wireless') ||
        hostname.contains('wifi') ||
        hostname.contains('wl')) {
      return ConnectionType.wireless;
    }

    // Check MAC address OUI for common wireless vendors
    final mac = (lease['macaddr'] ?? '').toString().toLowerCase();
    if (mac.isNotEmpty) {
      // Common wireless MAC OUI prefixes
      const wirelessOuis = [
        '00:1e:2a',
        '00:23:69',
        '00:26:5e',
        '00:26:5f',
        '00:26:ab',
        '00:26:b8',
        '00:26:f2',
        '00:1d:0f',
        '00:1e:2a',
        '00:21:29',
        '00:22:3f',
        '00:22:5f',
        '00:23:08',
        '00:23:15',
        'a4:4c:c8', 'a4:4c:c9', 'a4:4c:ca', 'a4:4c:cb', 'a4:83:e7', // Apple
        '90:72:40', 'f8:0f:f9', 'f8:95:ea', // Google
        '4c:57:ca', // TP-Link
        'a0:14:3d',
        '00:1a:11',
        '00:1d:60',
        '00:25:9e',
        '00:26:5a',
        '00:50:43', // Microsoft
        '34:ab:37', // Amazon
      ];

      final oui = mac.length > 8 ? mac.substring(0, 8) : '';
      if (wirelessOuis.any((prefix) => oui.startsWith(prefix.toLowerCase()))) {
        return ConnectionType.wireless;
      }

      // If MAC starts with common wired OUI, mark as wired
      const wiredOuis = [
        '00:1d:60', '00:25:9e', '00:26:5a', '00:50:43', // Dell
        '00:1a:4d', '00:1a:4e', '00:1a:4f', // ASUS
        '00:1b:21',
        '00:1b:fc',
        '00:24:8c',
        '00:26:18',
        '00:26:5e',
        '00:26:5f',
        '00:26:ab',
        '00:26:b8',
        '00:26:f2', // Intel
      ];

      if (wiredOuis.any((prefix) => oui.startsWith(prefix.toLowerCase()))) {
        return ConnectionType.wired;
      }
    }

    return ConnectionType.unknown;
  }

  factory Client.fromLease(Map<String, dynamic> lease) {
    // Helper function to safely convert dynamic to String
    String? toStringValue(dynamic value) {
      return value?.toString();
    }

    // Helper function to safely convert dynamic to int
    int? toIntValue(dynamic value) {
      if (value == null) return null;
      if (value is int) return value;
      if (value is String) return int.tryParse(value);
      if (value is double) return value.toInt();
      return null;
    }

    final expires = toIntValue(
      lease['expires'],
    ); // This is the remaining lease time in seconds
    final activetime = toIntValue(lease['activetime']);

    // 'expires' from the API is the time remaining on the lease in seconds.
    // We can use it directly. If it's not available, we can fall back to 'leasetime',
    // though 'expires' is more accurate for the remaining duration.
    final remainingLeaseTime = expires;

    // We can calculate the absolute expiration timestamp for display purposes if needed.
    int? expiresAtTimestamp;
    if (expires != null && expires > 0) {
      expiresAtTimestamp =
          (DateTime.now().millisecondsSinceEpoch ~/ 1000) + expires;
    }

    List<String>? ipv6Addresses;
    if (lease['ipv6addrs'] != null && lease['ipv6addrs'] is List) {
      ipv6Addresses = (lease['ipv6addrs'] as List)
          .map((e) => e.toString())
          .toList();
    } else if (lease['ipv6addr'] != null) {
      // Some APIs may use a single string or a comma-separated string
      final v6 = lease['ipv6addr'];
      if (v6 is String) {
        ipv6Addresses = v6
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      } else if (v6 is List) {
        ipv6Addresses = v6.map((e) => e.toString()).toList();
      }
    }

    return Client(
      ipAddress: toStringValue(lease['ipaddr']) ?? 'N/A',
      macAddress: toStringValue(lease['macaddr']) ?? 'N/A',
      hostname:
          toStringValue(lease['hostname']) ??
          toStringValue(lease['name']) ??
          'Unknown',
      hostId: toStringValue(lease['hostid']),
      leaseTime: remainingLeaseTime, // Use the 'expires' value directly
      vendor: toStringValue(lease['vendor']),
      dnsName: toStringValue(lease['dnsname']),
      clientId: toStringValue(lease['clientid']),
      activeTime: activetime,
      expiresAt: expiresAtTimestamp, // Store the calculated absolute timestamp
      connectionType: _determineConnectionType(lease),
      ipv6Addresses: ipv6Addresses,
    );
  }

  /// Creates a Client from a wireless association MAC address (no DHCP data).
  /// Used as a fallback for AP-mode routers where DHCP is handled upstream.
  factory Client.fromWirelessStation(String macAddress) {
    return Client(
      ipAddress: 'N/A',
      macAddress: macAddress,
      hostname: 'Unknown',
      connectionType: ConnectionType.wireless,
    );
  }

  // Get formatted lease time (e.g., "2d 4h 30m")
  String get formattedLeaseTime {
    if (leaseTime == null || leaseTime == 0) return 'Unlimited';
    if (leaseTime! < 0) return 'Expired';
    return Client.formatDuration(leaseTime!);
  }

  // Get formatted active time
  String get formattedActiveTime {
    if (activeTime == null) return 'N/A';
    return Client.formatDuration(activeTime!);
  }

  // Get formatted expiration timestamp
  String get formattedExpiresAt {
    if (expiresAt == null || expiresAt == 0) return 'N/A';
    final date = DateTime.fromMillisecondsSinceEpoch(expiresAt! * 1000);
    return '${date.toLocal()}';
  }

  // Static helper to format duration in seconds to a human-readable string
  static String formatDuration(int totalSeconds) {
    if (totalSeconds <= 0) return '0m';

    final days = totalSeconds ~/ (24 * 3600);
    totalSeconds %= (24 * 3600);
    final hours = totalSeconds ~/ 3600;
    totalSeconds %= 3600;
    final minutes = totalSeconds ~/ 60;

    final parts = <String>[];
    if (days > 0) parts.add('${days}d');
    if (hours > 0) parts.add('${hours}h');
    if (minutes > 0 || parts.isEmpty) parts.add('${minutes}m');

    return parts.join(' ');
  }

  /// Human-readable connection label using GL.iNet data when available.
  String get connectionLabel {
    if (isOnline == false) return 'Offline';
    if (wifiBand != null) {
      switch (wifiBand) {
        case '2.4G':
          return '2.4 GHz';
        case '5G':
          return '5 GHz';
        case '6G':
          return '6 GHz';
        default:
          return wifiBand!;
      }
    }
    switch (connectionType) {
      case ConnectionType.wireless:
        return 'Wi-Fi';
      case ConnectionType.wired:
        return 'Ethernet';
      case ConnectionType.unknown:
        return 'Unknown';
    }
  }

  Client copyWith({
    String? ipAddress,
    String? macAddress,
    String? hostname,
    String? hostId,
    int? leaseTime,
    String? vendor,
    String? dnsName,
    String? clientId,
    int? activeTime,
    int? expiresAt,
    ConnectionType? connectionType,
    List<String>? ipv6Addresses,
    String? wifiBand,
    bool? isOnline,
    String? deviceClass,
  }) {
    return Client(
      ipAddress: ipAddress ?? this.ipAddress,
      macAddress: macAddress ?? this.macAddress,
      hostname: hostname ?? this.hostname,
      hostId: hostId ?? this.hostId,
      leaseTime: leaseTime ?? this.leaseTime,
      vendor: vendor ?? this.vendor,
      dnsName: dnsName ?? this.dnsName,
      clientId: clientId ?? this.clientId,
      activeTime: activeTime ?? this.activeTime,
      expiresAt: expiresAt ?? this.expiresAt,
      connectionType: connectionType ?? this.connectionType,
      ipv6Addresses: ipv6Addresses ?? this.ipv6Addresses,
      wifiBand: wifiBand ?? this.wifiBand,
      isOnline: isOnline ?? this.isOnline,
      deviceClass: deviceClass ?? this.deviceClass,
    );
  }
}
