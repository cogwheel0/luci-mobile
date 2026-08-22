import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:luci_mobile/services/interfaces/api_service_interface.dart';
import 'package:luci_mobile/config/app_config.dart';

class MockApiService implements IApiService {
  static final Random _random = Random();
  static int _baseUptime = 86400; // Base uptime of 1 day
  static int _baseRxBytes = 1234567890;
  static int _baseTxBytes = 987654321;
  static int _baseRxPackets = 12345;
  static int _baseTxPackets = 9876;
  // Scan cancellation token — incremented by cancelScan().
  int _scanToken = 0;
  static int _baseLanRxBytes = 2345678901;
  static int _baseLanTxBytes = 1876543210;
  static int _baseLanRxPackets = 23456;
  static int _baseLanTxPackets = 18765;
  @override
  Future<String> login(
    String ipAddress,
    String username,
    String password,
    bool useHttps, {
    BuildContext? context,
  }) async {
    // Simulate a short delay for realism
    await Future.delayed(const Duration(milliseconds: 500));

    // Always return a mock sysauth token
    return 'mock_sysauth_token_12345';
  }

  @override
  Future<dynamic> call(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String object,
    required String method,
    Map<String, dynamic>? params,
    BuildContext? context,
  }) async {
    // Simulate a short delay for realism
    await Future.delayed(const Duration(milliseconds: 200));

    final endpointKey = '$object.$method';

    try {
      // Return appropriate mock data based on object and method
      final mockDataFile = _getMockDataFile(object, method);

      if (mockDataFile != null) {
        try {
          final jsonString = await rootBundle.loadString(
            '${AppConfig.mockDataPath}$mockDataFile',
          );
          final jsonData = jsonDecode(jsonString);
          return [0, jsonData]; // Wrap in standard RPC response format
        } catch (e) {
          // Log file loading error and fall back to default data
          debugPrint(
            'MockApiService: Failed to load mock data file "$mockDataFile" for endpoint "$endpointKey": $e',
          );
          return _getDefaultMockData(object, method);
        }
      }

      // No mock file mapped, use default data
      final defaultData = _getDefaultMockData(object, method);
      if (defaultData[1] is Map && (defaultData[1] as Map).isEmpty) {
        debugPrint(
          'MockApiService: No mock data available for endpoint "$endpointKey", returning empty response',
        );
      }
      return defaultData;
    } catch (e) {
      // Catch-all error handler
      debugPrint(
        'MockApiService: Unexpected error for endpoint "$endpointKey": $e',
      );
      return [1, 'Mock service error: $e']; // Return error response
    }
  }

  // Simplified call method for reviewer mode
  @override
  Future<dynamic> callSimple(
    String object,
    String method,
    Map<String, dynamic> params,
  ) async {
    // Simulate a short delay for realism
    await Future.delayed(const Duration(milliseconds: 200));

    final endpointKey = '$object.$method';

    try {
      // Return appropriate mock data based on object and method
      final mockDataFile = _getMockDataFile(object, method);

      if (mockDataFile != null) {
        try {
          final jsonString = await rootBundle.loadString(
            '${AppConfig.mockDataPath}$mockDataFile',
          );
          final jsonData = jsonDecode(jsonString);
          return [0, jsonData]; // Wrap in standard RPC response format
        } catch (e) {
          // Log file loading error and fall back to default data
          debugPrint(
            'MockApiService: Failed to load mock data file "$mockDataFile" for endpoint "$endpointKey": $e',
          );
          return _getDefaultMockData(object, method);
        }
      }

      // No mock file mapped, use default data
      final defaultData = _getDefaultMockData(object, method);
      if (defaultData[1] is Map && (defaultData[1] as Map).isEmpty) {
        debugPrint(
          'MockApiService: No mock data available for endpoint "$endpointKey", returning empty response',
        );
      }
      return defaultData;
    } catch (e) {
      // Catch-all error handler
      debugPrint(
        'MockApiService: Unexpected error for endpoint "$endpointKey": $e',
      );
      return [1, 'Mock service error: $e']; // Return error response
    }
  }

  @override
  Future<bool> reboot(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  }) async {
    // Simulate a short delay for realism
    await Future.delayed(const Duration(seconds: 1));
    // Mock reboot always succeeds
    return true;
  }

  @override
  Future<Map<String, Set<String>>> fetchAssociatedStations() async {
    // Simulate a short delay for realism
    await Future.delayed(const Duration(milliseconds: 300));

    try {
      final jsonString = await rootBundle.loadString(
        '${AppConfig.mockDataPath}associated_stations.json',
      );
      final jsonData = jsonDecode(jsonString);

      final result = <String, Set<String>>{};
      if (jsonData is Map<String, dynamic>) {
        jsonData.forEach((interface, stations) {
          if (stations is List) {
            result[interface] = stations.map((s) => s.toString()).toSet();
          }
        });
      }
      return result;
    } catch (e) {
      // Log error and return comprehensive default mock data
      // Make sure these MAC addresses match some of the DHCP lease MAC addresses
      debugPrint('MockApiService: Failed to load associated stations data: $e');
      return {
        'wlan0': {
          'aa:bb:cc:11:22:33',
          'aa:bb:cc:44:55:66',
          'aa:bb:cc:77:88:99',
          'bb:cc:dd:11:22:33',
          'bb:cc:dd:44:55:66',
          'bb:cc:dd:77:88:99',
        },
        'wlan1': {
          'aa:bb:cc:aa:bb:cc',
          'aa:bb:cc:dd:ee:ff',
          'aa:bb:cc:12:34:56',
          'bb:cc:dd:aa:bb:cc',
          'bb:cc:dd:dd:ee:ff',
          'aa:bb:cc:65:43:21',
        },
      };
    }
  }

  @override
  Future<Map<String, dynamic>?> fetchWireGuardPeers({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    required String interface,
    BuildContext? context,
  }) async {
    // Simulate a short delay for realism
    await Future.delayed(const Duration(milliseconds: 300));

    try {
      final jsonString = await rootBundle.loadString(
        '${AppConfig.mockDataPath}wireguard_peers.json',
      );
      final jsonData = jsonDecode(jsonString);
      return jsonData as Map<String, dynamic>;
    } catch (e) {
      // Log error and return comprehensive default mock data
      debugPrint('MockApiService: Failed to load WireGuard peers data: $e');
      return {
        interface: {
          'interface': interface,
          'peers': {
            'peer_public_key_1': {
              'public_key': 'peer_public_key_1',
              'endpoint': '192.168.1.100:51820',
              'last_handshake':
                  _getVariedTimestamp() - _random.nextInt(300) - 30,
              'transfer_rx': _random.nextInt(1000000),
              'transfer_tx': _random.nextInt(500000),
              'persistent_keepalive': 25,
            },
            'peer_public_key_2': {
              'public_key': 'peer_public_key_2',
              'endpoint': '192.168.1.101:51820',
              'last_handshake':
                  _getVariedTimestamp() - _random.nextInt(600) - 60,
              'transfer_rx': _random.nextInt(2000000),
              'transfer_tx': _random.nextInt(1000000),
              'persistent_keepalive': 0,
            },
          },
        },
      };
    }
  }

  // No HTTP client creation required for mock service when using Dio

  String? _getMockDataFile(String object, String method) {
    // Map object.method combinations to mock data files
    final key = '$object.$method';

    final mockFileMap = {
      'system.board': 'system_board.json',
      'system.info': 'system_info.json',
      // 'network.device': 'network_devices.json', // Use dynamic data for throughput
      'network.interface': 'interface_dump.json',
      'network.interface.dump': 'interface_dump.json',
      'wireless.devices': 'wireless_devices.json',
      'file.exec': 'dhcp_leases.json', // For DHCP leases command
      'uci.get': 'uci_wireless.json', // For wireless config
      'luci.wireguard.getWgInstances': 'wireguard_peers.json',
      'iwinfo.assoclist': 'associated_stations.json',
      'luci-rpc.getNetworkDevices': 'network_devices.json',
      'luci-rpc.getWirelessDevices': 'wireless_devices.json',
      'luci-rpc.getDHCPLeases': 'dhcp_leases.json',
    };

    return mockFileMap[key];
  }

  dynamic _getDefaultMockData(String object, String method) {
    // Return default mock data based on object and method
    switch ('$object.$method') {
      case 'system.board':
        return [
          0,
          {
            'hostname': 'MockRouter',
            'model': 'Mock Router Model X',
            'release': {
              'distribution': 'OpenWrt',
              'version': '23.05.0',
              'revision': 'r23497-6637af95aa',
              'target': 'mock/generic',
              'description': 'OpenWrt 23.05.0 Mock',
            },
            'kernel': '5.15.134',
            'board_name': 'mock-router-x',
            'system': 'Mock System',
          },
        ];

      case 'system.info':
        final memory = _getVariedMemory();
        return [
          0,
          {
            'uptime': _getVariedUptime(),
            'load': _getVariedLoadAverages(),
            'memory': memory,
            'localtime': _getVariedTimestamp(),
          },
        ];

      case 'network.device':
        final wanStats = _getVariedNetworkStats('eth0');
        final lanStats = _getVariedNetworkStats('br-lan');
        return [
          0,
          {
            'eth0': {'device': 'eth0', 'up': true, 'stats': wanStats},
            'br-lan': {'device': 'br-lan', 'up': true, 'stats': lanStats},
          },
        ];

      case 'network.interface':
        return [
          0,
          [
            {
              'interface': 'wan',
              'up': true,
              'proto': 'dhcp',
              'ipv4-address': [
                {'address': '192.168.1.100', 'mask': 24},
              ],
              'ipv6-address': [],
              'device': 'eth0',
              'dns-server': ['8.8.8.8', '8.8.4.4'],
              'route': [
                {'target': '0.0.0.0', 'mask': 0, 'nexthop': '192.168.1.1'},
              ],
            },
            {
              'interface': 'lan',
              'up': true,
              'proto': 'static',
              'ipv4-address': [
                {'address': '192.168.10.1', 'mask': 24},
              ],
              'ipv6-address': [],
              'device': 'br-lan',
              'dns-server': [],
              'route': [],
            },
          ],
        ];

      case 'wireless.devices':
        return [
          0,
          {
            'radio0': {
              'up': true,
              'channel': 6,
              'frequency': 2437,
              'txpower': 20,
              'country': 'US',
              'interfaces': [
                {
                  'ifname': 'wlan0',
                  'ssid': 'MockWiFi',
                  'encryption': 'psk2',
                  'key': '********',
                  'network': 'lan',
                },
              ],
            },
          },
        ];

      case 'file.exec':
      case 'luci-rpc.getDHCPLeases':
        // DHCP leases data
        return [
          0,
          {'stdout': _getVariedDhcpLeases(), 'stderr': '', 'code': 0},
        ];

      case 'network.interface.dump':
        // Network interface dump - returns flat map of interfaces with names as keys
        return [
          0,
          {
            'interface': [
              {
                'interface': 'wan',
                'up': true,
                'pending': false,
                'available': true,
                'autostart': true,
                'dynamic': false,
                'proto': 'dhcp',
                'device': 'eth0',
                'metric': 0,
                'dns_metric': 0,
                'delegation': true,
                'ipv4-address': [
                  {'address': '100.64.0.123', 'mask': 24, 'ptpaddress': ''},
                ],
                'ipv6-address': [],
                'ipv6-prefix': [],
                'ipv6-prefix-assignment': [],
                'route': [
                  {
                    'target': '0.0.0.0',
                    'mask': 0,
                    'nexthop': '100.64.0.1',
                    'source': '',
                  },
                ],
                'dns-server': ['8.8.8.8', '8.8.4.4'],
                'dns-search': [],
                'inactive': {
                  'ipv4-address': [],
                  'ipv6-address': [],
                  'route': [],
                  'dns-server': [],
                  'dns-search': [],
                },
              },
              {
                'interface': 'wan6',
                'up': true,
                'pending': false,
                'available': true,
                'autostart': true,
                'dynamic': false,
                'proto': 'dhcpv6',
                'device': 'eth0',
                'metric': 0,
                'dns_metric': 0,
                'delegation': true,
                'ipv4-address': [],
                'ipv6-address': [
                  {'address': '2001:db8::1', 'mask': 64, 'ptpaddress': ''},
                ],
                'ipv6-prefix': [],
                'ipv6-prefix-assignment': [],
                'route': [],
                'dns-server': ['2001:4860:4860::8888'],
                'dns-search': [],
                'inactive': {
                  'ipv4-address': [],
                  'ipv6-address': [],
                  'route': [],
                  'dns-server': [],
                  'dns-search': [],
                },
              },
              {
                'interface': 'wanb',
                'up': false,
                'pending': false,
                'available': false,
                'autostart': true,
                'dynamic': false,
                'proto': 'pppoe',
                'device': 'eth1',
                'metric': 0,
                'dns_metric': 0,
                'delegation': true,
                'ipv4-address': [],
                'ipv6-address': [],
                'ipv6-prefix': [],
                'ipv6-prefix-assignment': [],
                'route': [],
                'dns-server': [],
                'dns-search': [],
                'inactive': {
                  'ipv4-address': [],
                  'ipv6-address': [],
                  'route': [],
                  'dns-server': [],
                  'dns-search': [],
                },
              },
              {
                'interface': 'lan',
                'up': true,
                'pending': false,
                'available': true,
                'autostart': true,
                'dynamic': false,
                'proto': 'static',
                'device': 'br-lan',
                'metric': 0,
                'dns_metric': 0,
                'delegation': true,
                'ipv4-address': [
                  {'address': '192.168.1.1', 'mask': 24, 'ptpaddress': ''},
                ],
                'ipv6-address': [],
                'ipv6-prefix': [],
                'ipv6-prefix-assignment': [],
                'route': [],
                'dns-server': [],
                'dns-search': [],
                'inactive': {
                  'ipv4-address': [],
                  'ipv6-address': [],
                  'route': [],
                  'dns-server': [],
                  'dns-search': [],
                },
              },
            ],
          },
        ];

      case 'luci-rpc.getNetworkDevices':
        // Network devices data (same structure as network.device)
        final wanStats = _getVariedNetworkStats('eth0');
        final lanStats = _getVariedNetworkStats('br-lan');
        return [
          0,
          {
            'eth0': {'device': 'eth0', 'up': true, 'stats': wanStats},
            'br-lan': {'device': 'br-lan', 'up': true, 'stats': lanStats},
          },
        ];

      case 'luci-rpc.getWirelessDevices':
        // Wireless devices data (same structure as wireless.devices)
        return [
          0,
          {
            'radio0': {
              'up': true,
              'channel': 6,
              'frequency': 2437,
              'txpower': 20,
              'country': 'US',
              'interfaces': [
                {
                  'ifname': 'wlan0',
                  'ssid': 'MockWiFi',
                  'encryption': 'psk2',
                  'key': '********',
                  'network': 'lan',
                },
              ],
            },
            'radio1': {
              'up': true,
              'channel': 36,
              'frequency': 5180,
              'txpower': 23,
              'country': 'US',
              'interfaces': [
                {
                  'ifname': 'wlan1',
                  'ssid': 'MockWiFi_5G',
                  'encryption': 'psk2',
                  'key': '********',
                  'network': 'lan',
                },
              ],
            },
          },
        ];

      case 'luci.wireguard.getWgInstances':
        // WireGuard instances data
        return [
          0,
          {
            'wg0': {
              'interface': 'wg0',
              'peers': {
                'peer_public_key_1': {
                  'public_key': 'peer_public_key_1',
                  'endpoint': '192.168.1.100:51820',
                  'last_handshake':
                      _getVariedTimestamp() - _random.nextInt(300) - 30,
                  'transfer_rx': _random.nextInt(1000000),
                  'transfer_tx': _random.nextInt(500000),
                  'persistent_keepalive': 25,
                },
                'peer_public_key_2': {
                  'public_key': 'peer_public_key_2',
                  'endpoint': '192.168.1.101:51820',
                  'last_handshake':
                      _getVariedTimestamp() - _random.nextInt(600) - 60,
                  'transfer_rx': _random.nextInt(2000000),
                  'transfer_tx': _random.nextInt(1000000),
                  'persistent_keepalive': 0,
                },
              },
            },
          },
        ];

      case 'iwinfo.assoclist':
        // Associated stations data
        return [
          0,
          {
            'wlan0': {
              'aa:bb:cc:dd:ee:01': {
                'signal': -40 - _random.nextInt(20),
                'noise': -95 - _random.nextInt(5),
                'inactive': _random.nextInt(300),
                'rx_packets': _random.nextInt(10000),
                'tx_packets': _random.nextInt(8000),
                'rx_rate': 144000 + _random.nextInt(100000),
                'tx_rate': 72000 + _random.nextInt(50000),
              },
              'aa:bb:cc:dd:ee:02': {
                'signal': -50 - _random.nextInt(15),
                'noise': -92 - _random.nextInt(8),
                'inactive': _random.nextInt(180),
                'rx_packets': _random.nextInt(15000),
                'tx_packets': _random.nextInt(12000),
                'rx_rate': 108000 + _random.nextInt(80000),
                'tx_rate': 54000 + _random.nextInt(30000),
              },
            },
            'wlan1': {
              'aa:bb:cc:dd:ee:03': {
                'signal': -35 - _random.nextInt(10),
                'noise': -98 - _random.nextInt(3),
                'inactive': _random.nextInt(120),
                'rx_packets': _random.nextInt(20000),
                'tx_packets': _random.nextInt(18000),
                'rx_rate': 200000 + _random.nextInt(200000),
                'tx_rate': 150000 + _random.nextInt(100000),
              },
            },
          },
        ];

      case 'uci.get':
        // UCI configuration data (generic response for various configs)
        return [
          0,
          {
            'wireless': {
              'radio0': {
                '.type': 'wifi-device',
                'type': 'mac80211',
                'channel': '6',
                'hwmode': '11g',
                'path': 'platform/10180000.wmac',
                'htmode': 'HT20',
                'disabled': '0',
              },
              'default_radio0': {
                '.type': 'wifi-iface',
                'device': 'radio0',
                'network': 'lan',
                'mode': 'ap',
                'ssid': 'MockWiFi',
                'encryption': 'psk2',
                'key': 'mock_password',
              },
            },
          },
        ];

      case 'system.exec':
        // System execution results
        return [
          0,
          {'stdout': '', 'stderr': '', 'code': 0},
        ];

      default:
        // Return generic success response for unknown endpoints
        return [0, {}];
    }
  }

  // Helper methods for generating dynamic values
  static int _getVariedUptime() {
    _baseUptime += _random.nextInt(30) + 1; // Increment by 1-30 seconds
    return _baseUptime;
  }

  static List<int> _getVariedLoadAverages() {
    return [
      1000 + _random.nextInt(1000), // 1-2 range
      2000 + _random.nextInt(1000), // 2-3 range
      1500 + _random.nextInt(500), // 1.5-2 range
    ];
  }

  static Map<String, int> _getVariedMemory() {
    const int totalMemory = 268435456; // 256MB fixed
    final int usedVariation = _random.nextInt(20971520); // Up to 20MB variation
    final int freeMemory =
        134217728 - usedVariation; // Base 128MB minus variation

    return {
      'total': totalMemory,
      'free': freeMemory,
      'shared': 1048576 + _random.nextInt(524288), // 1-1.5MB
      'buffered': 10485760 + _random.nextInt(2097152), // 10-12MB
      'cached': 20971520 + _random.nextInt(5242880), // 20-25MB
      'available':
          freeMemory +
          20971520 +
          _random.nextInt(10485760), // Free + some cache
    };
  }

  static Map<String, int> _getVariedNetworkStats(String device) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final seconds =
        (now ~/ 1000) % 3600; // Reset every hour for predictable patterns

    if (device == 'eth0') {
      // Create realistic throughput patterns with sine waves and random noise
      final timeBasedMultiplier =
          1.0 + 0.5 * sin(seconds * 2 * pi / 300); // 5-minute cycles
      final burstMultiplier = _random.nextBool()
          ? (1.0 + _random.nextDouble() * 2)
          : 1.0; // Random bursts

      // Base rates: 50-500 KB/s for download, 10-100 KB/s for upload
      final rxIncrement =
          ((50000 + _random.nextInt(450000)) *
                  timeBasedMultiplier *
                  burstMultiplier)
              .round();
      final txIncrement =
          ((10000 + _random.nextInt(90000)) *
                  timeBasedMultiplier *
                  burstMultiplier *
                  0.3)
              .round();

      _baseRxBytes += rxIncrement;
      _baseTxBytes += txIncrement;
      _baseRxPackets +=
          (rxIncrement / 1500).round() +
          _random.nextInt(50); // ~1500 bytes per packet
      _baseTxPackets += (txIncrement / 1500).round() + _random.nextInt(20);

      return {
        'rx_bytes': _baseRxBytes,
        'tx_bytes': _baseTxBytes,
        'rx_packets': _baseRxPackets,
        'tx_packets': _baseTxPackets,
        'rx_dropped': _random.nextInt(3),
        'tx_dropped': _random.nextInt(2),
        'rx_errors': _random.nextInt(2),
        'tx_errors': _random.nextInt(2),
      };
    } else {
      // For br-lan (LAN interface), simulate local network activity
      final timeBasedMultiplier =
          1.0 + 0.3 * sin(seconds * 2 * pi / 180); // 3-minute cycles
      final localActivity = _random.nextBool()
          ? (1.0 + _random.nextDouble())
          : 0.5;

      // LAN typically has lower but more consistent throughput
      final rxIncrement =
          ((20000 + _random.nextInt(100000)) *
                  timeBasedMultiplier *
                  localActivity)
              .round();
      final txIncrement =
          ((15000 + _random.nextInt(80000)) *
                  timeBasedMultiplier *
                  localActivity)
              .round();

      _baseLanRxBytes += rxIncrement;
      _baseLanTxBytes += txIncrement;
      _baseLanRxPackets += (rxIncrement / 1500).round() + _random.nextInt(20);
      _baseLanTxPackets += (txIncrement / 1500).round() + _random.nextInt(15);

      return {
        'rx_bytes': _baseLanRxBytes,
        'tx_bytes': _baseLanTxBytes,
        'rx_packets': _baseLanRxPackets,
        'tx_packets': _baseLanTxPackets,
        'rx_dropped': _random.nextInt(2),
        'tx_dropped': _random.nextInt(2),
        'rx_errors': _random.nextInt(2),
        'tx_errors': _random.nextInt(2),
      };
    }
  }

  static int _getVariedTimestamp() {
    return DateTime.now().millisecondsSinceEpoch ~/ 1000;
  }

  static String _getVariedDhcpLeases() {
    final now = _getVariedTimestamp();
    final devices = [
      'iPhone-John',
      'MacBook-Pro',
      'Smart-TV-Living-Room',
      'Gaming-PC',
      'Nest-Thermostat',
      'iPad-Sarah',
      'Amazon-Echo',
      'Samsung-Galaxy-S23',
      'Dell-Laptop-Work',
      'Ring-Doorbell',
      'Nintendo-Switch',
      'Philips-Hue-Bridge',
    ];
    final macAddresses = [
      'aa:bb:cc:11:22:33',
      'aa:bb:cc:44:55:66',
      'aa:bb:cc:77:88:99',
      'aa:bb:cc:aa:bb:cc',
      'aa:bb:cc:dd:ee:ff',
      'aa:bb:cc:12:34:56',
      'aa:bb:cc:65:43:21',
      'bb:cc:dd:11:22:33',
      'bb:cc:dd:44:55:66',
      'bb:cc:dd:77:88:99',
      'bb:cc:dd:aa:bb:cc',
      'bb:cc:dd:dd:ee:ff',
    ];
    final ipAddresses = [
      '192.168.1.100',
      '192.168.1.101',
      '192.168.1.102',
      '192.168.1.103',
      '192.168.1.104',
      '192.168.1.105',
      '192.168.1.106',
      '192.168.1.108',
      '192.168.1.109',
      '192.168.1.110',
      '192.168.1.111',
      '192.168.1.112',
    ];

    String leases = '';
    for (int i = 0; i < devices.length; i++) {
      // Vary lease time slightly
      final leaseTime = now + _random.nextInt(3600); // +0 to 1 hour variation
      leases +=
          '$leaseTime ${macAddresses[i]} ${ipAddresses[i]} ${devices[i]} 01:${macAddresses[i]}\n';
    }

    return leases;
  }

  @override
  Future<List<String>> fetchAssociatedStationsWithContext({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    required String interface,
    BuildContext? context,
  }) async {
    await Future.delayed(const Duration(milliseconds: 200));
    // Return mock associated stations
    return ['aa:bb:cc:dd:ee:01', 'aa:bb:cc:dd:ee:02', 'aa:bb:cc:dd:ee:03'];
  }

  @override
  Future<dynamic> uciSet(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String config,
    required String section,
    required Map<String, String> values,
    BuildContext? context,
  }) async {
    await Future.delayed(const Duration(milliseconds: 200));
    // Return success response for mock UCI set operation
    return [0, 'success'];
  }

  @override
  Future<dynamic> uciCommit(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String config,
    BuildContext? context,
  }) async {
    await Future.delayed(const Duration(milliseconds: 200));
    // Return success response for mock UCI commit operation
    return [0, 'success'];
  }

  @override
  Future<dynamic> systemExec(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String command,
    List<String> params = const [],
    BuildContext? context,
  }) async {
    await Future.delayed(const Duration(milliseconds: 500));
    // Return success response for mock system exec operation
    return [0, 'success'];
  }

  @override
  Future<Map<String, Set<String>>> fetchAllAssociatedWirelessMacsWithContext({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    BuildContext? context,
  }) async {
    // For mock service, just delegate to fetchAssociatedStations
    return await fetchAssociatedStations();
  }

  @override
  Future<List<Map<String, dynamic>>> scanWirelessNetworks({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    required String device,
    BuildContext? context,
  }) async {
    final token = _scanToken;
    await Future.delayed(const Duration(seconds: 2)); // Simulate scan time
    // Return empty list if scan was cancelled before completion.
    if (_scanToken != token) return [];
    return [
      {
        'ssid': 'Neighbor-WiFi',
        'bssid': 'AA:BB:CC:11:22:33',
        'mode': 'Master',
        'channel': 1,
        'signal': -45,
        'quality': 65,
        'quality_max': 70,
        'encryption': {
          'enabled': true,
          'description': 'WPA2 PSK (CCMP)',
          'wep': false,
          'wpa': 2,
          'auth_suites': ['PSK'],
          'pair_ciphers': ['CCMP'],
          'group_ciphers': ['CCMP'],
        },
      },
      {
        'ssid': 'CoffeeShop-Free',
        'bssid': 'DD:EE:FF:44:55:66',
        'mode': 'Master',
        'channel': 6,
        'signal': -62,
        'quality': 48,
        'quality_max': 70,
        'encryption': {
          'enabled': false,
          'description': 'None',
          'wep': false,
          'wpa': 0,
          'auth_suites': <String>[],
          'pair_ciphers': <String>[],
          'group_ciphers': <String>[],
        },
      },
      {
        'ssid': 'Office-5G',
        'bssid': '11:22:33:AA:BB:CC',
        'mode': 'Master',
        'channel': 36,
        'signal': -55,
        'quality': 55,
        'quality_max': 70,
        'encryption': {
          'enabled': true,
          'description': 'WPA2 PSK (CCMP)',
          'wep': false,
          'wpa': 2,
          'auth_suites': ['PSK'],
          'pair_ciphers': ['CCMP'],
          'group_ciphers': ['CCMP'],
        },
      },
      {
        'ssid': 'SmartHome-IoT',
        'bssid': '77:88:99:DD:EE:FF',
        'mode': 'Master',
        'channel': 11,
        'signal': -71,
        'quality': 35,
        'quality_max': 70,
        'encryption': {
          'enabled': true,
          'description': 'WPA3 SAE (CCMP)',
          'wep': false,
          'wpa': 3,
          'auth_suites': ['SAE'],
          'pair_ciphers': ['CCMP'],
          'group_ciphers': ['CCMP'],
        },
      },
      {
        'ssid': 'NETGEAR-Guest',
        'bssid': 'CC:DD:EE:11:22:33',
        'mode': 'Master',
        'channel': 44,
        'signal': -78,
        'quality': 22,
        'quality_max': 70,
        'encryption': {
          'enabled': true,
          'description': 'WPA2 PSK (CCMP)',
          'wep': false,
          'wpa': 2,
          'auth_suites': ['PSK'],
          'pair_ciphers': ['CCMP'],
          'group_ciphers': ['CCMP'],
        },
      },
      {
        'ssid': '',
        'bssid': 'FF:00:11:22:33:44',
        'mode': 'Master',
        'channel': 3,
        'signal': -82,
        'quality': 15,
        'quality_max': 70,
        'encryption': {
          'enabled': true,
          'description': 'WPA2 PSK (CCMP)',
          'wep': false,
          'wpa': 2,
          'auth_suites': ['PSK'],
          'pair_ciphers': ['CCMP'],
          'group_ciphers': ['CCMP'],
        },
      },
    ];
  }

  @override
  Future<dynamic> uciAdd(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String config,
    required String type,
    required Map<String, dynamic> values,
    String? name,
    BuildContext? context,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return [0, name ?? 'cfg_new_section'];
  }

  @override
  Future<dynamic> uciDelete(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String config,
    required String section,
    BuildContext? context,
  }) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return [0, 'success'];
  }

  @override
  Future<dynamic> uciGetAll(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String config,
    BuildContext? context,
  }) async {
    await Future.delayed(const Duration(milliseconds: 200));
    // Just reuse the call method for uci.get
    return await call(
      ipAddress,
      sysauth,
      useHttps,
      object: 'uci',
      method: 'get',
      params: {'config': config},
      context: context,
    );
  }

  @override
  void cancelScan() {
    _scanToken++; // invalidates any in-flight scan
  }
}
