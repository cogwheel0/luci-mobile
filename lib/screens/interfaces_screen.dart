import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/main.dart';
import 'package:flutter/services.dart';
import 'package:luci_mobile/models/interface.dart';
import 'dart:math';
import 'package:luci_mobile/widgets/luci_app_bar.dart';
import 'package:luci_mobile/design/luci_design_system.dart';
import 'package:luci_mobile/widgets/luci_loading_states.dart';
import 'package:luci_mobile/widgets/luci_refresh_components.dart';
import 'package:luci_mobile/screens/wifi_scan_screen.dart';

class InterfacesScreen extends ConsumerStatefulWidget {
  final String? scrollToInterface;
  final VoidCallback? onScrollComplete;

  const InterfacesScreen({
    super.key,
    this.scrollToInterface,
    this.onScrollComplete,
  });

  @override
  ConsumerState<InterfacesScreen> createState() => _InterfacesScreenState();
}

class _InterfacesScreenState extends ConsumerState<InterfacesScreen> {
  final ScrollController _scrollController = ScrollController();
  String? _targetInterface;
  String? _expandedInterface;
  final Map<String, GlobalKey> _interfaceKeys = {};

  /// Safely extract a String from a UCI config value that may be a List or String.
  static String _uciString(dynamic value, [String fallback = '']) {
    if (value is String) return value;
    if (value is List) {
      return value.isNotEmpty ? value.first.toString() : fallback;
    }
    return value?.toString() ?? fallback;
  }

  // Unified key generator for all interfaces
  String _interfaceKey({String? name, String? ssid, String? deviceName}) {
    if (ssid != null && ssid.trim().isNotEmpty) {
      return ssid.trim(); // SSID is case sensitive
    } else if (deviceName != null && deviceName.trim().isNotEmpty) {
      return deviceName.trim().toLowerCase();
    } else if (name != null && name.trim().isNotEmpty) {
      return name.trim().toLowerCase();
    }
    return '';
  }

  // Unified key generator and matcher for all interfaces
  String _normalizeInterfaceKey(String? value) {
    return (value ?? '').trim().toLowerCase();
  }

  String _interfaceKeyForWireless({
    String? ssid,
    String? radioName,
    String? deviceName,
    String? name,
    String? sectionName,
    String? ifname,
  }) {
    final radio = (radioName ?? '').trim();
    final ssidTrimmed = (ssid ?? '').trim();

    // The UCI section name is the primary identity: it is unique per
    // wireless interface config and computable by both the scroll-targeting
    // and rendering paths. Keying on the section alone keeps state stable
    // across SSID edits and runtime/configuration-only transitions. Section
    // names are case-sensitive on the router, so preserve case here - two
    // sections may differ only by case and must not share a GlobalKey.
    //
    // Section- and ifname-derived keys use distinct namespaces so a missing
    // section on one row cannot collide with another row whose section
    // happens to equal an ifname (e.g. section 'wlan0' vs ifname 'wlan0').
    final section = (sectionName ?? '').trim();
    if (section.isNotEmpty) {
      return 'uci-section__$section';
    }

    // Runtime interfaces expose their OS interface name as a secondary
    // unique identity, in its own namespace (see above).
    final ifnameTrimmed = (ifname ?? '').trim();
    if (ifnameTrimmed.isNotEmpty) {
      return 'ifname__$ifnameTrimmed';
    }

    // Compose whatever distinct fields remain so records cannot collide on
    // a shared prefix; two records agreeing on every field are data-wise
    // indistinguishable.
    final parts = <String>[
      if (ssidTrimmed.isNotEmpty) ssidTrimmed.toLowerCase(),
      if (deviceName != null && deviceName.trim().isNotEmpty)
        deviceName.trim().toLowerCase(),
      if (name != null && name.trim().isNotEmpty) name.trim().toLowerCase(),
    ];
    if (parts.isNotEmpty) {
      return ['wireless', ...parts].join('__');
    }
    return 'wireless__$radio';
  }

  @override
  void initState() {
    super.initState();
    _targetInterface = widget.scrollToInterface;
    if (_targetInterface != null) {
      // Delay scrolling to allow the widget to build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToInterface(_targetInterface!);
      });
    }
  }

  @override
  void didUpdateWidget(InterfacesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Handle parameter changes (important for iOS navigation)
    if (widget.scrollToInterface != oldWidget.scrollToInterface) {
      _targetInterface = widget.scrollToInterface;
      if (_targetInterface != null) {
        // Delay scrolling to allow the widget to build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToInterface(_targetInterface!);
        });
      } else {
        // Clear target interface if no new target is provided
        setState(() {
          _targetInterface = null;
        });
      }
    }
  }

  @override
  void dispose() {
    // Clear target interface when widget is disposed
    _targetInterface = null;
    super.dispose();
  }

  void _scrollToInterface(String interfaceName) {
    if (!_scrollController.hasClients) return;

    // Find the target interface and calculate its position
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        // Get the app state to access interface data
        final appState = ref.read(appStateProvider);
        final dashboardData = appState.dashboardData;

        if (dashboardData != null) {
          // Check wired interfaces first
          final wiredInterfaces =
              dashboardData['interfaceDump']?['interface'] as List<dynamic>?;
          if (wiredInterfaces != null) {
            for (int i = 0; i < wiredInterfaces.length; i++) {
              final iface = wiredInterfaces[i] as Map<String, dynamic>;
              final name = iface['interface'] as String? ?? '';
              final keyStr = _interfaceKey(name: name);
              // Use exact matching only
              if (keyStr == interfaceName.toLowerCase()) {
                _scrollToExpandedCard(keyStr);
                return;
              }
            }
          }

          // If not found in wired, check wireless interfaces
          final wirelessData =
              dashboardData['wireless'] as Map<String, dynamic>?;
          if (wirelessData != null) {
            final normalizedTarget = _normalizeInterfaceKey(interfaceName);
            final rawTarget = interfaceName.trim();

            // Returns the card key for a wireless interface whose UCI
            // section matches the target exactly (case-sensitive), so an
            // exact variant always wins over a merely normalized one.
            String? findExactSectionMatch() {
              String? match;
              wirelessData.forEach((radioName, radioData) {
                if (match != null) return;
                final interfaces = radioData['interfaces'] as List<dynamic>?;
                if (interfaces == null) return;
                for (final interface in interfaces) {
                  final sectionName = interface['section'] as String?;
                  if (sectionName != null &&
                      sectionName.trim().isNotEmpty &&
                      sectionName.trim() == rawTarget) {
                    final config = interface['config'] ?? {};
                    final iwinfo = interface['iwinfo'] ?? {};
                    match = _interfaceKeyForWireless(
                      ssid: _uciString(iwinfo['ssid']).isNotEmpty
                          ? _uciString(iwinfo['ssid'])
                          : _uciString(config['ssid']),
                      radioName: radioName,
                      deviceName: _uciString(config['device'], radioName),
                      name: interface['name'] ?? '',
                      sectionName: sectionName,
                      ifname: interface['ifname'] as String?,
                    );
                    return;
                  }
                }
              });
              return match;
            }

            // Returns the card key using the broader alias matching
            // (normalized SSID/device/name/section).
            String? findAliasMatch() {
              String? match;
              wirelessData.forEach((radioName, radioData) {
                if (match != null) return;
                final interfaces = radioData['interfaces'] as List<dynamic>?;
                if (interfaces == null) return;
                for (var i = 0; i < interfaces.length; i++) {
                  final interface = interfaces[i];
                  final config = interface['config'] ?? {};
                  final iwinfo = interface['iwinfo'] ?? {};
                  final deviceName = _uciString(config['device'], radioName);
                  final ssid = _uciString(iwinfo['ssid']).isNotEmpty
                      ? _uciString(iwinfo['ssid'])
                      : _uciString(config['ssid']);
                  final name = interface['name'] ?? '';
                  final sectionName = interface['section'] as String?;
                  final keyStr = _interfaceKeyForWireless(
                    ssid: ssid,
                    radioName: radioName,
                    deviceName: deviceName,
                    name: name,
                    sectionName: sectionName,
                    ifname: interface['ifname'] as String?,
                  );
                  // Keys preserve section case (distinct sections must not
                  // share a GlobalKey), but target matching normalizes case
                  // so e.g. "GUEST" finds "Guest".
                  if (normalizedTarget == _normalizeInterfaceKey(ssid) ||
                      normalizedTarget == _normalizeInterfaceKey(deviceName) ||
                      normalizedTarget == _normalizeInterfaceKey(name) ||
                      normalizedTarget == _normalizeInterfaceKey(sectionName)) {
                    match = keyStr;
                    return;
                  }
                }
              });
              return match;
            }

            final matchedKey = findExactSectionMatch() ?? findAliasMatch();
            if (matchedKey != null) {
              // Returning from the outer callback is essential: falling
              // through would start the fallback section scroll on top of
              // this one and could invoke onScrollComplete twice.
              _scrollToExpandedCard(matchedKey);
              return;
            }
          }
        }

        // If not found, use section-based scrolling
        if (interfaceName.toLowerCase().contains('wifi') ||
            interfaceName.toLowerCase().contains('wireless') ||
            interfaceName.toLowerCase().contains('radio')) {
          _scrollToSection(200); // Wireless section
        } else {
          _scrollToSection(80); // Wired section
        }
      }
    });
  }

  double _headerOffset(BuildContext context) {
    // App bar (56) + section header (60)
    return 116.0;
  }

  void _scrollToExpandedCard(String keyStr, {int retry = 0}) {
    if (!mounted) return;

    // Set the expanded interface
    if (_expandedInterface != keyStr) {
      setState(() {
        _expandedInterface = keyStr;
      });

      // Wait for the expansion animation to complete (400ms) before calculating scroll
      Future.delayed(const Duration(milliseconds: 450), () {
        if (mounted) _performScrollToCard(keyStr, retry: retry);
      });
    } else {
      // Already expanded, perform scroll immediately
      _performScrollToCard(keyStr, retry: retry);
    }
  }

  void _performScrollToCard(String keyStr, {int retry = 0}) {
    if (!mounted) return;

    final key = _interfaceKeys[keyStr];
    final currentContext = context; // Store context

    final ctx = key?.currentContext;
    if (ctx == null) {
      if (retry < 5) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) _performScrollToCard(keyStr, retry: retry + 1);
        });
      }
      return;
    }

    final headerOffset = _headerOffset(currentContext);
    final renderBox = ctx.findRenderObject() as RenderBox?;
    if (renderBox == null) {
      if (retry < 5) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) _performScrollToCard(keyStr, retry: retry + 1);
        });
      }
      return;
    }

    final cardOffset = renderBox.localToGlobal(Offset.zero).dy;
    final cardHeight = renderBox.size.height;
    final scrollableBox = _scrollController.position.hasContentDimensions
        ? _scrollController.position.context.storageContext.findRenderObject()
              as RenderBox?
        : null;
    final scrollableTop = scrollableBox?.localToGlobal(Offset.zero).dy ?? 0.0;
    final visibleTop = scrollableTop + headerOffset;
    final visibleBottom = MediaQuery.of(currentContext).size.height;
    final cardBottom = cardOffset + cardHeight;

    // Calculate how much of the card is visible
    final visibleCardTop = max(cardOffset, visibleTop);
    final visibleCardBottom = min(cardBottom, visibleBottom);
    final visibleCardHeight = max(0.0, visibleCardBottom - visibleCardTop);
    final cardVisibilityRatio = cardHeight > 0
        ? visibleCardHeight / cardHeight
        : 0.0;

    // Only scroll if less than 90% of the card is visible
    final needsScroll = cardVisibilityRatio < 0.9;

    if (needsScroll) {
      // Calculate optimal scroll position to center the card
      final screenHeight = MediaQuery.of(currentContext).size.height;
      final availableHeight = screenHeight - headerOffset;
      final targetPosition =
          cardOffset - headerOffset - (availableHeight - cardHeight) / 2;
      final clampedPosition = targetPosition.clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );

      _scrollController
          .animateTo(
            clampedPosition,
            duration: const Duration(milliseconds: 500),
            curve: Curves.fastOutSlowIn,
          )
          .then((_) {
            if (mounted) {
              setState(() {
                _targetInterface = null;
              });
              widget.onScrollComplete?.call();
            }
          });
    } else {
      if (mounted) {
        setState(() {
          _targetInterface = null;
        });
        widget.onScrollComplete?.call();
      }
    }
  }

  void _scrollToSection(double targetPosition) {
    if (!_scrollController.hasClients ||
        !_scrollController.position.hasContentDimensions) {
      return;
    }

    final maxScroll = _scrollController.position.maxScrollExtent;
    final clampedPosition = targetPosition.clamp(0.0, maxScroll);

    _scrollController
        .animateTo(
          clampedPosition,
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeInOut,
        )
        .then((_) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              setState(() {
                _targetInterface = null;
              });
              widget.onScrollComplete?.call();
            }
          });
        });
  }

  @override
  Widget build(BuildContext context) {
    final appState = ref.read(appStateProvider);

    return Scaffold(
      appBar: const LuciAppBar(title: 'Interfaces'),
      body: SafeArea(
        top: true,
        bottom: false,
        child: Stack(
          children: [
            LuciPullToRefresh(
              onRefresh: () => appState.fetchDashboardData(),
              child: Builder(
                builder: (context) {
                  final watchedAppState = ref.watch(appStateProvider);
                  final isLoading = watchedAppState.isDashboardLoading;
                  final dashboardError = watchedAppState.dashboardError;
                  final dashboardData = watchedAppState.dashboardData;

                  if (isLoading && dashboardData == null) {
                    return Padding(
                      padding: EdgeInsets.symmetric(horizontal: LuciSpacing.md),
                      child: Column(
                        children: [
                          SizedBox(height: LuciSpacing.md),
                          // Interface cards skeleton
                          Expanded(
                            child: ListView.separated(
                              itemCount: 4,
                              separatorBuilder: (context, index) =>
                                  SizedBox(height: LuciSpacing.md),
                              itemBuilder: (context, index) => LuciCardSkeleton(
                                showTitle: true,
                                showSubtitle: true,
                                contentLines: 3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  if (dashboardError != null && dashboardData == null) {
                    return LuciErrorDisplay(
                      title: 'Failed to Load Interfaces',
                      message: dashboardError,
                      actionLabel: 'Retry',
                      onAction: () => appState.fetchDashboardData(),
                      icon: Icons.wifi_off_rounded,
                    );
                  }

                  if (dashboardData == null) {
                    return LuciEmptyState(
                      title: 'No Interface Data',
                      message:
                          'Unable to fetch interface information. Pull down to refresh or tap the button below.',
                      icon: Icons.device_hub_outlined,
                      actionLabel: 'Fetch Data',
                      onAction: () => appState.fetchDashboardData(),
                    );
                  }

                  return CustomScrollView(
                    controller: _scrollController,
                    slivers: [
                      SliverToBoxAdapter(child: LuciSectionHeader('Wired')),
                      _buildWiredInterfacesList(),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16.0,
                            vertical: 8.0,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Wireless',
                                style: LuciTextStyles.sectionHeader(context),
                              ),
                              TextButton.icon(
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const WifiScanScreen(),
                                    ),
                                  );
                                },
                                icon: Icon(Icons.cell_tower, size: 16),
                                label: Text('Radio'),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 4,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      _buildWirelessInterfacesList(),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.only(bottom: 16),
                          child: SizedBox.shrink(),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWiredInterfacesList() {
    final appState = ref.watch(appStateProvider);
    final dynamic detailedData = appState.dashboardData?['interfaceDump'];
    final dynamic statsDataSource = appState.dashboardData?['networkDevices'];
    var interfacesList = <NetworkInterface>[];

    if (detailedData is Map &&
        detailedData.containsKey('interface') &&
        detailedData['interface'] is List) {
      final List<dynamic> interfaceDataList = detailedData['interface'];
      final Map<String, dynamic> networkStatsMap = statsDataSource is Map
          ? Map<String, dynamic>.from(statsDataSource)
          : <String, dynamic>{};

      interfacesList = interfaceDataList.whereType<Map<String, dynamic>>().map((
        detailedInterfaceMap,
      ) {
        final stats = detailedInterfaceMap['stats'];
        if (stats == null || (stats is Map && stats.isEmpty)) {
          final String? deviceName =
              detailedInterfaceMap['l3_device'] ??
              detailedInterfaceMap['device'];
          if (deviceName != null) {
            final statsContainer = networkStatsMap[deviceName];
            if (statsContainer is Map && statsContainer['stats'] is Map) {
              detailedInterfaceMap['stats'] = statsContainer['stats'];
            }
          }
        }
        return NetworkInterface.fromJson(detailedInterfaceMap);
      }).toList();
    }

    final interfaces = interfacesList;
    if (interfaces.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final iface = interfaces[index];
        final isTargetInterface =
            _targetInterface != null &&
            iface.name.toLowerCase() == _targetInterface!.toLowerCase();

        final keyStr = _interfaceKey(name: iface.name);
        final key = _interfaceKeys.putIfAbsent(keyStr, () => GlobalKey());
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: _UnifiedNetworkCard(
            key: key,
            name: iface.name.toUpperCase(),
            subtitle: _buildMinimalInterfaceSubtitle(iface),
            isUp: iface.isUp,
            icon: _getInterfaceIcon(iface.protocol),
            details: _buildWiredDetails(context, iface),
            initiallyExpanded:
                isTargetInterface || _expandedInterface == keyStr,
          ),
        );
      }, childCount: interfaces.length),
    );
  }

  Widget _buildWirelessInterfacesList() {
    final appState = ref.watch(appStateProvider);
    final dashboardData = appState.dashboardData;
    final wirelessData = dashboardData?['wireless'] as Map<String, dynamic>?;
    final uciWirelessConfig = dashboardData?['uciWirelessConfig'];
    final interfacesList = <Map<String, dynamic>>[];

    final uciRadios = <String, Map>{};
    final uciInterfaces = <String, Map<String, dynamic>>{};

    // Try 'values' key (real API) then 'wireless' key (mock data)
    final uciValues =
        (uciWirelessConfig?['values'] as Map?) ??
        (uciWirelessConfig?['wireless'] as Map?);
    if (uciValues != null) {
      uciValues.forEach((key, value) {
        final typedValue = value as Map?;
        if (typedValue?['.type'] == 'wifi-device') {
          uciRadios[key] = typedValue!;
        } else if (typedValue?['.type'] == 'wifi-iface') {
          uciInterfaces[key] = Map<String, dynamic>.from(typedValue!);
        }
      });
    }

    final runtimeInterfaces = <String>{};
    if (wirelessData != null) {
      wirelessData.forEach((radioName, radioData) {
        final interfaces = radioData['interfaces'] as List<dynamic>?;
        if (interfaces != null) {
          for (final iface in interfaces) {
            final config = iface['config'] ?? {};
            final iwinfo = iface['iwinfo'] ?? {};
            final uciName = iface['section'] as String?;
            if (uciName != null) {
              runtimeInterfaces.add(uciName);
            }

            final isRadioEnabled = uciRadios[radioName]?['disabled'] != '1';
            final isIfaceEnabled =
                config['disabled'] != '1' &&
                config['disabled'] != 1 &&
                config['disabled'] != true;
            final isEnabled = isRadioEnabled && isIfaceEnabled;

            final name = iface['name'] ?? '';
            final ssid = _uciString(iwinfo['ssid']).isNotEmpty
                ? _uciString(iwinfo['ssid'])
                : _uciString(config['ssid']);
            final deviceName = _uciString(config['device'], radioName);
            final mode = _uciString(config['mode']).toUpperCase().isNotEmpty
                ? _uciString(config['mode']).toUpperCase()
                : (iwinfo['mode']?.toString().toUpperCase() ?? 'N/A');

            // Build encryption description
            final encIwinfo = iwinfo['encryption'] as Map<String, dynamic>?;
            final encDescription =
                encIwinfo?['description'] ??
                _uciString(config['encryption'], 'N/A');

            interfacesList.add({
              'name': _uciString(config['ssid']).isNotEmpty
                  ? _uciString(config['ssid'])
                  : (iwinfo['ssid']?.toString() ?? 'Unnamed'),
              'subtitle':
                  '$mode • Ch. ${iwinfo['channel']?.toString() ?? _uciString(config['channel'], 'N/A')}',
              'isEnabled': isEnabled,
              'isIfaceEnabled': isIfaceEnabled,
              'isRadioEnabled': isRadioEnabled,
              'deviceName': deviceName,
              'radioName': radioName,
              'ssid': ssid,
              'interfaceName': name,
              'section': uciName,
              'uciSection': uciName,
              'ifname': iface['ifname'] as String?,
              'mode': mode,
              'encryption': config['encryption'] ?? '',
              'encryptionDescription': encDescription,
              'network': (config['network'] is List)
                  ? (config['network'] as List).join(', ')
                  : config['network']?.toString() ?? '',
              'channel': iwinfo['channel']?.toString() ?? 'auto',
              'signal': iwinfo['signal']?.toString() ?? '--',
              'details': {
                'Device': _uciString(config['device'], radioName),
                'Mode': _uciString(config['mode']).isNotEmpty
                    ? _uciString(config['mode'])
                    : (iwinfo['mode']?.toString() ?? 'N/A'),
                'Channel':
                    iwinfo['channel']?.toString() ??
                    _uciString(config['channel'], 'N/A'),
                'Signal': '${iwinfo['signal']?.toString() ?? '--'} dBm',
                'Network': (config['network'] is List)
                    ? (config['network'] as List).join(', ')
                    : _uciString(config['network'], 'N/A'),
              },
            });
          }
        }
      });
    }

    uciInterfaces.forEach((uciName, config) {
      if (!runtimeInterfaces.contains(uciName)) {
        final radioName = _uciString(config['device']);
        final isRadioEnabled = uciRadios[radioName]?['disabled'] != '1';
        final isIfaceEnabled = _uciString(config['disabled']) != '1';
        final isEnabled = isRadioEnabled && isIfaceEnabled;
        final mode = config['mode'] ?? 'N/A';

        final name = _uciString(config['ssid'], 'Unnamed');
        interfacesList.add({
          'name': name,
          'subtitle':
              '${_uciString(config['mode'], 'N/A').toUpperCase()} • Disabled',
          'isEnabled': isEnabled,
          'isIfaceEnabled': isIfaceEnabled,
          'isRadioEnabled': isRadioEnabled,
          'deviceName': radioName,
          'radioName': radioName,
          'ssid': name,
          'interfaceName': name,
          'section': uciName,
          'uciSection': uciName,
          'mode': mode,
          'encryption': config['encryption'] ?? '',
          'encryptionDescription': config['encryption'] ?? 'N/A',
          'network': (config['network'] is List)
              ? (config['network'] as List).join(', ')
              : config['network']?.toString() ?? '',
          'channel': config['channel']?.toString() ?? 'auto',
          'signal': '--',
          'details': {
            'Device': radioName,
            'Mode': _uciString(config['mode'], 'N/A'),
            'SSID': _uciString(config['ssid'], 'N/A'),
            'Network': (config['network'] is List)
                ? (config['network'] as List).join(', ')
                : _uciString(config['network'], 'N/A'),
          },
        });
      }
    });

    final interfaces = interfacesList;
    if (interfaces.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    final target = _targetInterface;

    // Resolve the target to exactly ONE wireless card key, using the same
    // exact-section-first then normalized-alias order as the scroll
    // targeting path. Resolving up front guarantees a case-insensitive
    // target (e.g. "GUEST") cannot expand several case-variant cards at
    // once - only the card the screen would scroll to expands.
    String? resolvedTargetKey;
    if (target != null) {
      String? keyOf(Map<String, dynamic> iface) => _interfaceKeyForWireless(
        ssid: iface['ssid'] ?? '',
        radioName: iface['radioName'] ?? '',
        deviceName: iface['deviceName'] ?? '',
        name: iface['interfaceName'] ?? '',
        sectionName: iface['section'] as String?,
        ifname: iface['ifname'] as String?,
      );
      // Pass 1: exact (case-sensitive) section match.
      for (final iface in interfaces) {
        final section = (iface['section'] as String?)?.trim() ?? '';
        if (section.isNotEmpty && section == target.trim()) {
          resolvedTargetKey = keyOf(iface);
          break;
        }
      }
      // Pass 2: normalized alias fallback (SSID/device/name/section).
      final normalizedTarget = _normalizeInterfaceKey(target);
      if (resolvedTargetKey == null) {
        for (final iface in interfaces) {
          if (normalizedTarget == _normalizeInterfaceKey(iface['ssid'] ?? '') ||
              normalizedTarget ==
                  _normalizeInterfaceKey(iface['deviceName'] ?? '') ||
              normalizedTarget ==
                  _normalizeInterfaceKey(iface['interfaceName'] ?? '') ||
              normalizedTarget ==
                  _normalizeInterfaceKey(iface['section'] as String?)) {
            resolvedTargetKey = keyOf(iface);
            break;
          }
        }
      }
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final iface = interfaces[index];
        final deviceName = iface['deviceName'] ?? '';
        final radioName = iface['radioName'] ?? '';
        final ssid = iface['ssid'] ?? '';
        final name = iface['interfaceName'] ?? '';
        // Use the stored values for key generation
        final keyStr = _interfaceKeyForWireless(
          ssid: ssid,
          radioName: radioName,
          deviceName: deviceName,
          name: name,
          sectionName: iface['section'] as String?,
          ifname: iface['ifname'] as String?,
        );
        final key = _interfaceKeys.putIfAbsent(keyStr, () => GlobalKey());
        final displayName = ssid.toString().isNotEmpty
            ? ssid.toString()
            : deviceName.toString();

        // Only the single resolved card expands; see resolution above.
        final isTargetInterface =
            resolvedTargetKey != null && keyStr == resolvedTargetKey;

        final shouldExpand = isTargetInterface || _expandedInterface == keyStr;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: _UnifiedNetworkCard(
            key: key,
            name: displayName,
            subtitle: iface['subtitle'],
            isUp: iface['isEnabled'],
            icon: Icons.wifi,
            details: _buildWirelessDetails(context, iface),
            initiallyExpanded: shouldExpand,
          ),
        );
      }, childCount: interfaces.length),
    );
  }

  Widget _buildWirelessDetails(
    BuildContext context,
    Map<String, dynamic> iface,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final details = iface['details'] as Map<String, dynamic>;
    final uciSection = iface['uciSection'] as String? ?? '';
    final isIfaceEnabled = iface['isIfaceEnabled'] as bool? ?? true;
    final mode = iface['mode']?.toString() ?? '';
    final encDescription = iface['encryptionDescription']?.toString() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Details rows
        ...details.entries.map((entry) {
          return _buildDetailRow(context, entry.key, entry.value.toString());
        }),
        // Encryption row
        if (encDescription.isNotEmpty && encDescription != 'N/A')
          _buildDetailRow(context, 'Encryption', encDescription),

        const Divider(height: 1, indent: 16, endIndent: 16),
        const SizedBox(height: 8),

        // Management action buttons
        if (uciSection.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 12.0,
              vertical: 4.0,
            ),
            child: Column(
              children: [
                // Enable/Disable toggle row
                _WifiToggleRow(
                  uciSection: uciSection,
                  isEnabled: isIfaceEnabled,
                ),

                const SizedBox(height: 8),

                // Action buttons row
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _showEditWifiSheet(context, iface),
                        icon: Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Edit'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: colorScheme.primary,
                          side: BorderSide(
                            color: colorScheme.primary.withValues(alpha: 0.5),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _showDeleteWifiDialog(context, iface),
                        icon: Icon(Icons.delete_outline, size: 18),
                        label: const Text('Remove'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: colorScheme.error,
                          side: BorderSide(
                            color: colorScheme.error.withValues(alpha: 0.5),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 4),

                // Mode label
                if (mode.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      mode.toLowerCase() == 'sta'
                          ? 'Client (Station) mode'
                          : mode.toLowerCase() == 'ap'
                          ? 'Access Point mode'
                          : '${mode.toUpperCase()} mode',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
              ],
            ),
          )
        else
          // No UCI section - just show details
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'UCI section unavailable — limited management',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),

        const SizedBox(height: 8),
      ],
    );
  }

  void _showEditWifiSheet(BuildContext context, Map<String, dynamic> iface) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _WifiEditBottomSheet(iface: iface),
    );
  }

  void _showDeleteWifiDialog(BuildContext context, Map<String, dynamic> iface) {
    final ssid = iface['ssid']?.toString() ?? 'this interface';
    final uciSection = iface['uciSection'] as String? ?? '';
    final mode = iface['mode']?.toString() ?? 'ap';
    if (uciSection.isEmpty) return;

    showDialog(
      context: context,
      builder: (ctx) =>
          _WifiDeleteDialog(ssid: ssid, uciSection: uciSection, mode: mode),
    );
  }

  Widget _buildWiredDetails(BuildContext context, NetworkInterface interface) {
    return Column(
      children: [
        _buildDetailRow(context, 'Device', interface.device),
        _buildDetailRow(context, 'Uptime', interface.formattedUptime),
        if (interface.ipAddress != null)
          _buildDetailRow(
            context,
            'IP Address',
            interface.ipAddress!,
            onTap: () =>
                _copyToClipboard(context, interface.ipAddress!, 'IP Address'),
          ),
        if (interface.ipv6Addresses != null &&
            interface.ipv6Addresses!.isNotEmpty)
          ...interface.ipv6Addresses!.map(
            (ipv6) => _buildDetailRow(
              context,
              'IPv6 Address',
              ipv6,
              onTap: () => _copyToClipboard(context, ipv6, 'IPv6 Address'),
            ),
          ),
        if (interface.gateway != null)
          _buildDetailRow(
            context,
            'Gateway',
            interface.gateway!,
            onTap: () =>
                _copyToClipboard(context, interface.gateway!, 'Gateway IP'),
          ),
        if (interface.dnsServers.isNotEmpty)
          _buildDetailRow(
            context,
            'DNS',
            interface.dnsServers.join(', '),
            onTap: () => _copyToClipboard(
              context,
              interface.dnsServers.join(', '),
              'DNS Servers',
            ),
          ),
        // Add WireGuard peer information if this is a WireGuard interface
        if (interface.protocol.toLowerCase() == 'wireguard') ...[
          Builder(
            builder: (context) {
              return _buildWireGuardPeersSection(context, interface.name);
            },
          ),
        ],
        const Divider(height: 1, indent: 16, endIndent: 16),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: _buildStatsRow(context, interface.stats),
        ),
      ],
    );
  }

  Widget _buildWireGuardPeersSection(
    BuildContext context,
    String interfaceName,
  ) {
    final appState = ref.watch(appStateProvider);
    final wireguardData =
        appState.dashboardData?['wireguard'] as Map<String, dynamic>?;
    final peerData = wireguardData?[interfaceName];
    if (peerData == null) {
      return const SizedBox.shrink();
    }
    final peers = peerData['peers'] as Map<String, dynamic>?;
    if (peers == null || peers.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: const Divider(height: 24, thickness: 1, indent: 0, endIndent: 0),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1, thickness: 1, indent: 0, endIndent: 0),
          const SizedBox(height: 8),
          ...peers.values.map(
            (peer) =>
                _buildCohesivePeerRow(context, peer as Map<String, dynamic>),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildCohesivePeerRow(
    BuildContext context,
    Map<String, dynamic> peer,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final publicKey = peer['public_key'] as String? ?? 'Unknown';
    final endpoint = peer['endpoint'] as String? ?? 'N/A';
    final peerName = peer['name'] as String?;
    int lastHandshake = 0;
    final rawHandshake = peer['last_handshake'] ?? peer['latest_handshake'];
    if (rawHandshake != null) {
      if (rawHandshake is int) {
        lastHandshake = rawHandshake;
      } else if (rawHandshake is String) {
        lastHandshake = int.tryParse(rawHandshake) ?? 0;
      }
    }
    final displayKey = publicKey.length > 16
        ? '${publicKey.substring(0, 8)}...${publicKey.substring(publicKey.length - 8)}'
        : publicKey;
    String formatHandshakeTime(int timestamp) {
      if (timestamp == 0) return 'Never';
      final now = DateTime.now();
      final handshakeTime = DateTime.fromMillisecondsSinceEpoch(
        timestamp * 1000,
      );
      final difference = now.difference(handshakeTime);
      if (difference.inSeconds < 0) return 'Never';
      if (difference.inDays > 0) {
        return '${difference.inDays}d ago';
      } else if (difference.inHours > 0) {
        return '${difference.inHours}h ago';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}m ago';
      } else {
        return '${difference.inSeconds}s ago';
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.vpn_key, size: 18, color: colorScheme.primary),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  displayKey,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurface,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (peerName != null && peerName.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                peerName,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'Last Handshake',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatHandshakeTime(lastHandshake),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                        color: colorScheme.onSurface,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'Endpoint',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      endpoint,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                        color: colorScheme.onSurface,
                      ),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(
    BuildContext context,
    String title,
    String value, {
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface,
              ),
            ),
            Row(
              children: [
                Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurface,
                  ),
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                ),
                if (onTap != null)
                  GestureDetector(
                    onTap: onTap,
                    child: const Padding(
                      padding: EdgeInsets.only(left: 8.0),
                      child: Icon(
                        Icons.copy_all_outlined,
                        size: 16,
                        semanticLabel: 'Copy',
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _copyToClipboard(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildStatsRow(BuildContext context, Map<String, dynamic> stats) {
    String formatBytes(int bytes) {
      if (bytes <= 0) return '0 B';
      const suffixes = ["B", "KB", "MB", "GB", "TB"];
      var i = (log(bytes) / log(1024)).floor();
      return '${(bytes / pow(1024, i)).toStringAsFixed(2)} ${suffixes[i]}';
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildStatColumn(
          context,
          'Received',
          formatBytes(stats['rx_bytes'] ?? 0),
          Icons.arrow_downward,
          Colors.green,
        ),
        _buildStatColumn(
          context,
          'Transmitted',
          formatBytes(stats['tx_bytes'] ?? 0),
          Icons.arrow_upward,
          Colors.blue,
        ),
      ],
    );
  }

  Widget _buildStatColumn(
    BuildContext context,
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  IconData _getInterfaceIcon(String protocol) {
    switch (protocol.toLowerCase()) {
      case 'wireguard':
        return Icons.shield_outlined;
      case 'static':
        return Icons.settings_ethernet;
      case 'dhcp':
        return Icons.dns_outlined;
      default:
        return Icons.device_hub_outlined;
    }
  }

  String _buildMinimalInterfaceSubtitle(NetworkInterface iface) {
    final v4 = iface.ipAddress;
    final v6s = iface.ipv6Addresses ?? [];
    final v6 = v6s.isNotEmpty ? v6s.first : null;
    String? shown;
    int extra = 0;
    if (v4 != null) {
      shown = v4;
      if (v6 != null) extra++;
    } else if (v6 != null) {
      shown = v6;
    }
    if (shown == null) return iface.protocol;
    if (extra > 0) {
      return '${iface.protocol} • $shown  +$extra';
    } else {
      return '${iface.protocol} • $shown';
    }
  }
}

class LuciSectionHeader extends StatelessWidget {
  final String title;
  const LuciSectionHeader(this.title, {super.key});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          color: theme.colorScheme.onSurface,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _UnifiedNetworkCard extends StatefulWidget {
  final String name;
  final String subtitle;
  final bool isUp;
  final IconData icon;
  final Widget details;
  final bool initiallyExpanded;

  const _UnifiedNetworkCard({
    required this.name,
    required this.subtitle,
    required this.isUp,
    required this.icon,
    required this.details,
    this.initiallyExpanded = false,
    super.key,
  });

  @override
  State<_UnifiedNetworkCard> createState() => _UnifiedNetworkCardState();
}

class _UnifiedNetworkCardState extends State<_UnifiedNetworkCard>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  late AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    if (widget.initiallyExpanded) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(covariant _UnifiedNetworkCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initiallyExpanded != oldWidget.initiallyExpanded) {
      setState(() {
        _isExpanded = widget.initiallyExpanded;
        if (_isExpanded) {
          _controller.forward();
        } else {
          _controller.reverse();
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleExpand() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final card = Card(
      elevation: _isExpanded ? 6 : 2,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: LuciCardStyles.standardRadius,
        side: BorderSide(
          color: widget.initiallyExpanded && _isExpanded
              ? colorScheme.primary.withValues(alpha: 0.3)
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.10),
          width: widget.initiallyExpanded && _isExpanded ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: AnimatedScale(
        scale: widget.initiallyExpanded && _isExpanded ? 1.02 : 1.0,
        duration: LuciAnimations.standard,
        curve: Curves.easeOutBack,
        child: Column(
          children: [
            InkWell(
              onTap: _toggleExpand,
              borderRadius: LuciCardStyles.standardRadius,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: LuciSpacing.lg,
                  vertical: 10.0,
                ),
                child: Row(
                  children: [
                    Stack(
                      alignment: Alignment.topRight,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8.0),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer.withValues(
                              alpha: 0.13,
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: AnimatedScale(
                            scale: widget.initiallyExpanded && _isExpanded
                                ? 1.1
                                : 1.0,
                            duration: const Duration(milliseconds: 500),
                            curve: Curves.elasticOut,
                            child: Icon(
                              widget.icon,
                              color: widget.isUp
                                  ? colorScheme.primary
                                  : colorScheme.onSurface,
                              size: 22,
                              semanticLabel: 'Interface icon',
                            ),
                          ),
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Tooltip(
                            message: widget.isUp
                                ? 'Interface is up'
                                : 'Interface is down',
                            child: LuciStatusIndicators.statusDot(
                              context,
                              widget.isUp,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.name,
                            style: LuciTextStyles.cardTitle(context),
                            semanticsLabel: 'Interface name: ${widget.name}',
                          ),
                          const SizedBox(height: LuciSpacing.xs),
                          Container(
                            margin: const EdgeInsets.only(right: 32),
                            child: Divider(
                              color: colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.10),
                              thickness: 1,
                              height: 8,
                            ),
                          ),
                          Text(
                            widget.subtitle,
                            style: LuciTextStyles.cardSubtitle(context),
                            semanticsLabel:
                                'Interface details: ${widget.subtitle}',
                          ),
                        ],
                      ),
                    ),
                    if (!widget.isUp)
                      Padding(
                        padding: const EdgeInsets.only(right: LuciSpacing.xs),
                        child: LuciStatusIndicators.statusChip(
                          context,
                          'OFF',
                          false,
                        ),
                      ),
                    const SizedBox(width: LuciSpacing.sm),
                    Icon(
                      _isExpanded ? Icons.expand_less : Icons.expand_more,
                      color: colorScheme.onSurfaceVariant,
                      size: 26,
                      semanticLabel: _isExpanded
                          ? 'Collapse details'
                          : 'Expand details',
                    ),
                  ],
                ),
              ),
            ),
            if (_isExpanded)
              Column(
                children: [
                  const Divider(height: 1, indent: 18, endIndent: 18),
                  widget.details,
                ],
              ),
          ],
        ),
      ),
    );

    if (!widget.isUp) {
      return ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          0.2126,
          0.7152,
          0.0722,
          0,
          0,
          0.2126,
          0.7152,
          0.0722,
          0,
          0,
          0.2126,
          0.7152,
          0.0722,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
        ]),
        child: card,
      );
    }
    return card;
  }
}

// ──────────────────────────────────────────────────────────────────
// WiFi Enable/Disable Toggle Row
// ──────────────────────────────────────────────────────────────────

class _WifiToggleRow extends ConsumerStatefulWidget {
  final String uciSection;
  final bool isEnabled;

  const _WifiToggleRow({required this.uciSection, required this.isEnabled});

  @override
  ConsumerState<_WifiToggleRow> createState() => _WifiToggleRowState();
}

class _WifiToggleRowState extends ConsumerState<_WifiToggleRow> {
  bool _isToggling = false;

  Future<void> _toggle(bool value) async {
    if (_isToggling) return;
    setState(() => _isToggling = true);

    final appState = ref.read(appStateProvider);
    final success = await appState.setWirelessInterfaceEnabled(
      widget.uciSection,
      value,
      context: context,
    );

    if (mounted) {
      setState(() => _isToggling = false);
      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to toggle interface'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            widget.isEnabled ? Icons.wifi : Icons.wifi_off,
            size: 20,
            color: widget.isEnabled
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.isEnabled ? 'Interface Enabled' : 'Interface Disabled',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (_isToggling)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Switch(value: widget.isEnabled, onChanged: _toggle),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// WiFi Edit Bottom Sheet
// ──────────────────────────────────────────────────────────────────

class _WifiEditBottomSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic> iface;

  const _WifiEditBottomSheet({required this.iface});

  @override
  ConsumerState<_WifiEditBottomSheet> createState() =>
      _WifiEditBottomSheetState();
}

class _WifiEditBottomSheetState extends ConsumerState<_WifiEditBottomSheet> {
  late TextEditingController _ssidController;
  late TextEditingController _passwordController;
  late TextEditingController _networkController;
  late String _selectedEncryption;
  late String _originalEncryption; // tracks what was set before editing
  bool _obscurePassword = true;
  bool _isSaving = false;
  String? _error;

  static const _encryptionOptions = [
    {'value': 'none', 'label': 'None (Open)'},
    {'value': 'psk2', 'label': 'WPA2-PSK'},
    {'value': 'psk', 'label': 'WPA-PSK'},
    {'value': 'psk-mixed', 'label': 'WPA/WPA2 Mixed PSK'},
    {'value': 'sae', 'label': 'WPA3-SAE'},
    {'value': 'sae-mixed', 'label': 'WPA2/WPA3 Mixed'},
  ];

  @override
  void initState() {
    super.initState();
    _ssidController = TextEditingController(
      text: widget.iface['ssid']?.toString() ?? '',
    );
    _passwordController = TextEditingController();
    _networkController = TextEditingController(
      text: widget.iface['network']?.toString() ?? 'lan',
    );

    // Map the current encryption to our dropdown values, preserving it if
    // supported. For unknown/enterprise values, keep them for display but
    // prevent saving until the user makes a valid selection.
    final currentEnc = widget.iface['encryption']?.toString() ?? 'none';
    _originalEncryption = currentEnc;
    _selectedEncryption = currentEnc;
  }

  @override
  void dispose() {
    _ssidController.dispose();
    _passwordController.dispose();
    _networkController.dispose();
    super.dispose();
  }

  bool get _requiresPassword =>
      _selectedEncryption != 'none' && _selectedEncryption != 'owe';

  bool get _isEncryptionSupported =>
      _encryptionOptions.any((o) => o['value'] == _selectedEncryption);

  /// True when switching from an open interface to a password-protected one.
  bool get _changingToEncrypted =>
      (_originalEncryption == 'none' || _originalEncryption == 'owe') &&
      _requiresPassword;

  Future<void> _save() async {
    final ssid = _ssidController.text.trim();
    if (ssid.isEmpty) {
      setState(() => _error = 'SSID cannot be empty.');
      return;
    }

    // Block unsupported encryption modes (e.g. enterprise WPA-EAP)
    if (!_isEncryptionSupported) {
      setState(
        () => _error =
            'Encryption mode "$_selectedEncryption" cannot be edited here. '
            'Please select a supported mode.',
      );
      return;
    }

    // Require a password when changing an open interface to an encrypted one
    if (_changingToEncrypted && _passwordController.text.isEmpty) {
      setState(
        () => _error = 'A password is required when enabling encryption.',
      );
      return;
    }

    if (_requiresPassword &&
        _passwordController.text.isNotEmpty &&
        _passwordController.text.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters.');
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });

    final uciSection = widget.iface['uciSection'] as String? ?? '';
    if (uciSection.isEmpty) {
      setState(() {
        _isSaving = false;
        _error = 'Cannot identify UCI section for this interface.';
      });
      return;
    }

    // Build values to update
    final values = <String, String>{
      'ssid': ssid,
      'encryption': _selectedEncryption,
    };

    // Only update password if user typed one
    if (_passwordController.text.isNotEmpty) {
      values['key'] = _passwordController.text;
    }

    // Update network binding
    final network = _networkController.text.trim();
    if (network.isNotEmpty) {
      values['network'] = network;
    }

    final appState = ref.read(appStateProvider);
    final success = await appState.modifyWirelessInterface(
      uciSection,
      values,
      context: context,
    );

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text('Updated "$ssid" — reloading WiFi...'),
            ],
          ),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    } else {
      setState(() {
        _isSaving = false;
        _error = 'Failed to save changes. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final mode = widget.iface['mode']?.toString() ?? 'ap';

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer.withValues(
                        alpha: 0.3,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.edit,
                      color: colorScheme.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Edit Wireless Interface',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${widget.iface['radioName']} • ${mode.toUpperCase()} mode',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // SSID field
              _buildLabel(context, 'SSID (Network Name)'),
              const SizedBox(height: 6),
              TextField(
                controller: _ssidController,
                enabled: !_isSaving,
                decoration: _inputDecoration(
                  context,
                  hintText: 'Enter SSID',
                  prefixIcon: Icons.wifi,
                ),
              ),

              const SizedBox(height: 16),

              // Encryption selector
              _buildLabel(context, 'Encryption'),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colorScheme.outline.withValues(alpha: 0.3),
                  ),
                  color: colorScheme.surfaceContainerLow,
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedEncryption,
                    isExpanded: true,
                    icon: Icon(
                      Icons.arrow_drop_down,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    items: _encryptionOptions.map((opt) {
                      return DropdownMenuItem<String>(
                        value: opt['value'],
                        child: Text(
                          opt['label']!,
                          style: theme.textTheme.bodyMedium,
                        ),
                      );
                    }).toList(),
                    onChanged: _isSaving
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() => _selectedEncryption = value);
                            }
                          },
                  ),
                ),
              ),

              // Password field (only for encrypted networks)
              if (_requiresPassword) ...[
                const SizedBox(height: 16),
                _buildLabel(context, 'Password (leave empty to keep current)'),
                const SizedBox(height: 6),
                TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  enabled: !_isSaving,
                  decoration: _inputDecoration(
                    context,
                    hintText: 'Enter new password',
                    prefixIcon: Icons.key,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () {
                        setState(() => _obscurePassword = !_obscurePassword);
                      },
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // Network binding
              _buildLabel(context, 'Network'),
              const SizedBox(height: 6),
              TextField(
                controller: _networkController,
                enabled: !_isSaving,
                decoration: _inputDecoration(
                  context,
                  hintText: 'e.g., lan, wwan',
                  prefixIcon: Icons.lan_outlined,
                ),
              ),

              // Error
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: colorScheme.error,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // Warning
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.tertiaryContainer.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: colorScheme.tertiary,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Changes will be applied immediately. WiFi will briefly restart.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Save button
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isSaving ? null : _save,
                  icon: _isSaving
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colorScheme.onPrimary,
                          ),
                        )
                      : const Icon(Icons.save),
                  label: Text(
                    _isSaving ? 'Applying...' : 'Save Changes',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(BuildContext context, String text) {
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
    );
  }

  InputDecoration _inputDecoration(
    BuildContext context, {
    required String hintText,
    required IconData prefixIcon,
    Widget? suffixIcon,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return InputDecoration(
      hintText: hintText,
      prefixIcon: Icon(prefixIcon),
      suffixIcon: suffixIcon,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colorScheme.primary, width: 2),
      ),
      filled: true,
      fillColor: colorScheme.surfaceContainerLow,
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// WiFi Delete Confirmation Dialog
// ──────────────────────────────────────────────────────────────────

class _WifiDeleteDialog extends ConsumerStatefulWidget {
  final String ssid;
  final String uciSection;
  final String mode;

  const _WifiDeleteDialog({
    required this.ssid,
    required this.uciSection,
    required this.mode,
  });

  @override
  ConsumerState<_WifiDeleteDialog> createState() => _WifiDeleteDialogState();
}

class _WifiDeleteDialogState extends ConsumerState<_WifiDeleteDialog> {
  bool _isDeleting = false;

  Future<void> _delete() async {
    setState(() => _isDeleting = true);

    final appState = ref.read(appStateProvider);
    final success = await appState.deleteWirelessInterface(
      widget.uciSection,
      mode: widget.mode,
      context: context,
    );

    if (!mounted) return;

    Navigator.of(context).pop();

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text('"${widget.ssid}" removed'),
            ],
          ),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to remove interface'),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final displayName = widget.ssid.isNotEmpty
        ? widget.ssid
        : widget.uciSection;
    final modeLower = widget.mode.toLowerCase();
    final isStaMode =
        modeLower.contains('sta') ||
        modeLower.contains('client') ||
        modeLower == 'station' ||
        modeLower == 'n/a' ||
        widget.mode.isEmpty;
    final warningMessage = isStaMode
        ? 'This will remove the STA connection from this radio.'
        : 'WiFi will restart. Clients on this network will be disconnected.';

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      icon: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.errorContainer.withValues(alpha: 0.3),
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.delete_forever, color: colorScheme.error, size: 32),
      ),
      title: const Text('Remove Wireless Interface?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'This will permanently remove "$displayName" from your wireless configuration.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colorScheme.errorContainer.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber, color: colorScheme.error, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    warningMessage,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isDeleting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isDeleting ? null : _delete,
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.error,
            foregroundColor: colorScheme.onError,
          ),
          child: _isDeleting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Remove'),
        ),
      ],
    );
  }
}
