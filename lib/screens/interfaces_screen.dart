import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/l10n/failure_text.dart';
import 'package:luci_mobile/utils/uci_values.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/models/glinet_data.dart';
import 'package:luci_mobile/models/interface.dart';
import 'package:luci_mobile/utils/wifi_utils.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';
import 'package:luci_mobile/design/luci_design_system.dart';
import 'package:luci_mobile/widgets/luci_loading_states.dart';
import 'package:luci_mobile/widgets/luci_refresh_components.dart';
import 'package:luci_mobile/screens/wifi_scan_screen.dart';
import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:luci_mobile/utils/format_bytes.dart';
import 'package:luci_mobile/widgets/platform_ui/platform_ui.dart';
import 'package:luci_mobile/state/app_state.dart';

class InterfacesScreen extends ConsumerStatefulWidget {
  final String? scrollToInterface;
  final VoidCallback? onScrollComplete;

  /// True when pushed as its own route rather than shown as a tab root.
  final bool showBack;

  const InterfacesScreen({
    super.key,
    this.scrollToInterface,
    this.onScrollComplete,
    this.showBack = false,
  });

  @override
  ConsumerState<InterfacesScreen> createState() => _InterfacesScreenState();
}

class _InterfacesScreenState extends ConsumerState<InterfacesScreen> {
  final ScrollController _scrollController = ScrollController();
  String? _targetInterface;
  String? _expandedInterface;

  /// Whether the target interface's page is about to open, on iOS.
  bool _openingTarget = false;
  final Map<String, GlobalKey> _interfaceKeys = {};

  /// Safely extract a String from a UCI config value that may be a List or String.
  static String _uciString(dynamic value, [String fallback = '']) =>
      uciString(value, fallback);

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
    if (PlatformUiCapabilities.isIOS) {
      // The target's row opens its page as the list builds
      // (_openTargetOnce). With the data in and no row matching, the
      // request is done.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _openingTarget || _targetInterface == null) return;
        if (ref.read(appStateProvider).dashboardData == null) return;
        setState(() => _targetInterface = null);
        widget.onScrollComplete?.call();
      });
      return;
    }
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
    // iOS lists the interfaces as inset groups, on the grouped background.
    final grouped = PlatformUiCapabilities.isIOS
        ? CupertinoColors.systemGroupedBackground.resolveFrom(context)
        : null;

    return Scaffold(
      backgroundColor: grouped,
      appBar: LuciAppBar(
        title: context.l10n.interfaces,
        showBack: widget.showBack,
        backgroundColor: grouped?.withValues(alpha: 0.94),
      ),
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
                  final failure = watchedAppState.appFailure;
                  final dashboardError = failure == null
                      ? null
                      : appFailureText(context, failure);
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
                      title: context.l10n.failedToLoadInterfaces,
                      message: dashboardError,
                      actionLabel: context.l10n.retry,
                      onAction: () => appState.fetchDashboardData(),
                      icon: Icons.wifi_off_rounded,
                    );
                  }

                  if (dashboardData == null) {
                    return LuciEmptyState(
                      title: context.l10n.noInterfaceData,
                      message: context.l10n.noInterfaceDataDescription,
                      icon: Icons.device_hub_outlined,
                      actionLabel: context.l10n.fetchData,
                      onAction: () => appState.fetchDashboardData(),
                    );
                  }

                  return CustomScrollView(
                    controller: _scrollController,
                    slivers: [
                      SliverToBoxAdapter(
                        child: LuciSectionHeader(context.l10n.wired),
                      ),
                      _buildWiredInterfacesList(),
                      // iOS opens the scanner from a row of the group.
                      if (PlatformUiCapabilities.isIOS)
                        SliverToBoxAdapter(
                          child: LuciSectionHeader(context.l10n.wireless),
                        )
                      else
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
                                  context.l10n.wireless,
                                  style: LuciTextStyles.sectionHeader(context),
                                ),
                                AdaptiveButton(
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            const WifiScanScreen(),
                                      ),
                                    );
                                  },
                                  label: context.l10n.radio,
                                  sfSymbol: const SFSymbol(
                                    'antenna.radiowaves.left.and.right',
                                    size: 16,
                                  ),
                                  materialIcon: Icons.cell_tower,
                                  style: AdaptiveButtonStyle.plain,
                                  size: AdaptiveButtonSize.small,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 4,
                                  ),
                                  materialVisualDensity: VisualDensity.compact,
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
    final interfaces = _wiredInterfacesOf(ref.watch(appStateProvider));
    if (interfaces.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    if (PlatformUiCapabilities.isIOS) {
      return SliverToBoxAdapter(child: _iosWiredGroup(interfaces));
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

  /// The router's interfaces, with their counters, from [appState]'s
  /// dashboard data.
  List<NetworkInterface> _wiredInterfacesOf(AppState appState) {
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

      // Enrich Tailscale interface with GL.iNet API data
      final glInetData = appState.dashboardData?['glinet'] as GlInetData?;
      if (glInetData?.tailscaleIp != null) {
        interfacesList = interfacesList.map((iface) {
          if (iface.name.toLowerCase() == 'tailscale' &&
              iface.ipAddress == null) {
            return NetworkInterface(
              name: iface.name,
              isUp: iface.isUp,
              protocol: 'tailscale',
              uptime: iface.uptime,
              device: iface.device,
              ipAddress: glInetData!.tailscaleIp,
              netmask: iface.netmask,
              gateway: iface.gateway,
              dnsServers: iface.dnsServers,
              stats: iface.stats,
              ipv6Addresses: iface.ipv6Addresses,
            );
          }
          return iface;
        }).toList();
      }
    }
    return interfacesList;
  }

  Widget _buildWirelessInterfacesList() {
    final interfaces = _wirelessInterfacesOf(
      context,
      ref.watch(appStateProvider),
    );
    if (interfaces.isEmpty) {
      return PlatformUiCapabilities.isIOS
          ? SliverToBoxAdapter(child: _iosWirelessGroup(const [], null))
          : const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    final target = _targetInterface;

    // Resolve the target to exactly ONE wireless card key, using the same
    // exact-section-first then normalized-alias order as the scroll
    // targeting path. Resolving up front guarantees a case-insensitive
    // target (e.g. "GUEST") cannot expand several case-variant cards at
    // once - only the card the screen would scroll to expands.
    String? resolvedTargetKey;
    if (target != null) {
      // Pass 1: exact (case-sensitive) section match.
      for (final iface in interfaces) {
        final section = (iface['section'] as String?)?.trim() ?? '';
        if (section.isNotEmpty && section == target.trim()) {
          resolvedTargetKey = _wirelessKeyOf(iface);
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
            resolvedTargetKey = _wirelessKeyOf(iface);
            break;
          }
        }
      }
    }

    if (PlatformUiCapabilities.isIOS) {
      return SliverToBoxAdapter(
        child: _iosWirelessGroup(interfaces, resolvedTargetKey),
      );
    }
    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final iface = interfaces[index];
        final deviceName = iface['deviceName'] ?? '';
        final ssid = iface['ssid'] ?? '';
        final keyStr = _wirelessKeyOf(iface);
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

  /// The key a wireless interface's card or row goes by.
  String _wirelessKeyOf(Map<String, dynamic> iface) => _interfaceKeyForWireless(
    ssid: iface['ssid'] ?? '',
    radioName: iface['radioName'] ?? '',
    deviceName: iface['deviceName'] ?? '',
    name: iface['interfaceName'] ?? '',
    sectionName: iface['section'] as String?,
    ifname: iface['ifname'] as String?,
  );

  /// The wireless interfaces, running or only configured, from
  /// [appState]'s dashboard data, described in [context]'s language.
  List<Map<String, dynamic>> _wirelessInterfacesOf(
    BuildContext context,
    AppState appState,
  ) {
    final dashboardData = appState.dashboardData;
    final wirelessData = dashboardData?['wireless'] as Map<String, dynamic>?;
    final uciWirelessConfig = dashboardData?['uciWirelessConfig'];
    final glInetData = dashboardData?['glinet'] as GlInetData?;
    final interfacesList = <Map<String, dynamic>>[];

    final uciValues = uciSectionsOf(uciWirelessConfig, config: 'wireless');
    final uciRadios = <String, Map>{
      for (final e in uciSections(uciValues, 'wifi-device')) e.key: e.value,
    };
    final uciInterfaces = <String, Map<String, dynamic>>{
      for (final e in uciSections(uciValues, 'wifi-iface')) e.key: e.value,
    };
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

            final isRadioEnabled = !uciBool(uciRadios[radioName]?['disabled']);
            final isIfaceEnabled = !uciBool(config['disabled']);
            final isEnabled = isRadioEnabled && isIfaceEnabled;

            final name = iface['name'] ?? '';
            final ssid = _uciString(iwinfo['ssid']).isNotEmpty
                ? _uciString(iwinfo['ssid'])
                : _uciString(config['ssid']);
            final deviceName = _uciString(config['device'], radioName);
            final mode = _uciString(config['mode']).toUpperCase().isNotEmpty
                ? _uciString(config['mode']).toUpperCase()
                : (iwinfo['mode']?.toString().toUpperCase() ?? 'N/A');
            final glInetRadio = glInetData?.radioForDevice(radioName);
            final channel =
                normalizeWifiChannel(iwinfo['channel']) ??
                normalizeWifiChannel(config['channel']) ??
                normalizeWifiChannel(glInetRadio?.channel) ??
                'N/A';
            final bandStr =
                glInetRadio?.band ?? config['band']?.toString() ?? '';
            final bandLabel = formatWifiBand(bandStr);
            final subtitleParts = <String>[mode];
            if (bandLabel.isNotEmpty) subtitleParts.add(bandLabel);
            subtitleParts.add(context.l10n.channelShort(channel));

            // Build encryption description
            final rawEncIwinfo = iwinfo['encryption'];
            final encIwinfo = rawEncIwinfo is Map ? rawEncIwinfo : null;
            final encDescription =
                encIwinfo?['description'] ??
                _uciString(config['encryption'], 'N/A');

            interfacesList.add({
              'name': _uciString(config['ssid']).isNotEmpty
                  ? _uciString(config['ssid'])
                  : (iwinfo['ssid']?.toString() ?? context.l10n.unnamed),
              'subtitle': subtitleParts.join(' • '),
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
              'encryption': _uciString(config['encryption']),
              'encryptionDescription': encDescription,
              'network': (config['network'] is List)
                  ? (config['network'] as List).join(', ')
                  : config['network']?.toString() ?? '',
              'channel': channel,
              'signal': iwinfo['signal']?.toString() ?? '--',
              'details': {
                context.l10n.device: _uciString(config['device'], radioName),
                context.l10n.mode: _uciString(config['mode']).isNotEmpty
                    ? _uciString(config['mode'])
                    : (iwinfo['mode']?.toString() ?? 'N/A'),
                context.l10n.band: bandLabel.isNotEmpty ? bandLabel : 'N/A',
                context.l10n.channel: channel,
                context.l10n.signal:
                    '${iwinfo['signal']?.toString() ?? '--'} dBm',
                context.l10n.network: (config['network'] is List)
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
        final isRadioEnabled = !uciBool(uciRadios[radioName]?['disabled']);
        final isIfaceEnabled = !uciBool(config['disabled']);
        final mode = config['mode'] ?? 'N/A';
        final glInetRadio = glInetData?.radioForDevice(radioName);
        final channel = resolveWifiChannel(
          actual: glInetRadio?.channel,
          configured: uciRadios[radioName]?['channel'],
        );

        final name = _uciString(config['ssid'], context.l10n.unnamed);
        interfacesList.add({
          'name': name,
          'subtitle':
              '${_uciString(config['mode'], 'N/A').toUpperCase()} • ${context.l10n.notRunning}',
          'isEnabled': false,
          'isIfaceEnabled': isIfaceEnabled,
          'isRadioEnabled': isRadioEnabled,
          'deviceName': radioName,
          'radioName': radioName,
          'ssid': name,
          'interfaceName': name,
          'section': uciName,
          'uciSection': uciName,
          'mode': mode,
          'encryption': _uciString(config['encryption']),
          'encryptionDescription': _uciString(config['encryption'], 'N/A'),
          'network': (config['network'] is List)
              ? (config['network'] as List).join(', ')
              : config['network']?.toString() ?? '',
          'channel': channel,
          'signal': '--',
          'details': {
            context.l10n.device: radioName,
            context.l10n.mode: _uciString(config['mode'], 'N/A'),
            context.l10n.ssid: _uciString(config['ssid'], 'N/A'),
            context.l10n.channel: channel,
            context.l10n.network: (config['network'] is List)
                ? (config['network'] as List).join(', ')
                : _uciString(config['network'], 'N/A'),
          },
        });
      }
    });

    return interfacesList;
  }

  // ------------------------------------------------------------------ iOS

  /// Opens the page [open] pushes for the interface the screen was asked
  /// to show, once, after this frame.
  void _openTargetOnce(VoidCallback open) {
    if (_openingTarget) return;
    _openingTarget = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openingTarget = false;
      if (!mounted) return;
      setState(() => _targetInterface = null);
      open();
      widget.onScrollComplete?.call();
    });
  }

  /// An interface's icon, in the tint while it is up and grey while down.
  Widget _statusIcon(IconData icon, bool isUp) => Icon(
    icon,
    color: isUp
        ? Theme.of(context).colorScheme.primary
        : CupertinoColors.tertiaryLabel.resolveFrom(context),
  );

  /// "Off" before the chevron of an interface that is down, as iOS
  /// Settings says so, and as Android's chip does: the state in words,
  /// read with the row, not only in the icon's colour.
  Widget? _offLabel(bool isUp) => isUp
      ? null
      : Text(
          context.l10n.off,
          style: TextStyle(
            fontSize: 17,
            color: CupertinoColors.secondaryLabel.resolveFrom(context),
          ),
        );

  /// A wireless interface's name: its SSID, or its radio without one.
  static String _wirelessTitleOf(Map<String, dynamic> iface) =>
      (iface['ssid'] ?? '').toString().isNotEmpty
      ? iface['ssid'].toString()
      : (iface['deviceName'] ?? '').toString();

  /// The wired interfaces as an iOS group, as iOS Settings lists things
  /// that open a page: a row each, its state, name and address.
  Widget _iosWiredGroup(List<NetworkInterface> interfaces) {
    final target = _targetInterface;
    if (target != null) {
      for (final iface in interfaces) {
        if (iface.name.toLowerCase() == target.toLowerCase()) {
          _openTargetOnce(() => _openWiredPage(iface.name));
          break;
        }
      }
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuciSpacing.md),
      child: AdaptiveFormSection(
        separatorIndent: 52,
        children: [
          for (final iface in interfaces)
            AdaptiveListRow(
              leading: _statusIcon(
                _getInterfaceIcon(iface.protocol),
                iface.isUp,
              ),
              title: iface.name.toUpperCase(),
              subtitle: _buildMinimalInterfaceSubtitle(iface),
              trailing: _offLabel(iface.isUp),
              showChevron: true,
              onTap: () => _openWiredPage(iface.name),
            ),
        ],
      ),
    );
  }

  /// The wireless interfaces as an iOS group, a row each opening its page,
  /// then the Wi-Fi scanner.
  Widget _iosWirelessGroup(
    List<Map<String, dynamic>> interfaces,
    String? targetKey,
  ) {
    if (targetKey != null) {
      for (final iface in interfaces) {
        if (_wirelessKeyOf(iface) == targetKey) {
          _openTargetOnce(
            () => _openWirelessPage(targetKey, _wirelessTitleOf(iface)),
          );
          break;
        }
      }
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuciSpacing.md),
      child: AdaptiveFormSection(
        separatorIndent: 52,
        children: [
          for (final iface in interfaces)
            AdaptiveListRow(
              leading: _statusIcon(
                Icons.wifi,
                iface['isEnabled'] as bool? ?? false,
              ),
              title: _wirelessTitleOf(iface),
              subtitle: iface['subtitle'] as String?,
              trailing: _offLabel(iface['isEnabled'] as bool? ?? false),
              showChevron: true,
              onTap: () => _openWirelessPage(
                _wirelessKeyOf(iface),
                _wirelessTitleOf(iface),
              ),
            ),
          AdaptiveListRow(
            leading: Icon(
              Icons.cell_tower,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: context.l10n.wifiScanner,
            showChevron: true,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => const WifiScanScreen()),
            ),
          ),
        ],
      ),
    );
  }

  void _openWiredPage(String name) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => _InterfacePage(
        title: name.toUpperCase(),
        content: (context, appState) {
          final iface = _wiredInterfacesOf(appState)
              .where((i) => i.name == name)
              .firstOrNull;
          return iface == null
              ? null
              : (
                  title: name.toUpperCase(),
                  sections: _iosWiredSections(context, appState, iface),
                );
        },
      ),
    ),
  );

  void _openWirelessPage(String key, String title) =>
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _InterfacePage(
            title: title,
            content: (context, appState) {
              final iface = _wirelessInterfacesOf(
                context,
                appState,
              ).where((i) => _wirelessKeyOf(i) == key).firstOrNull;
              // Named afresh each time, so a renamed network's page
              // follows its new name.
              return iface == null
                  ? null
                  : (
                      title: _wirelessTitleOf(iface),
                      sections: _iosWirelessSections(context, iface),
                    );
            },
          ),
        ),
      );

  /// A wired interface's page on iOS: its addresses as value rows to copy,
  /// its traffic, and for WireGuard a group per peer.
  List<Widget> _iosWiredSections(
    BuildContext context,
    AppState appState,
    NetworkInterface i,
  ) {
    final l10n = context.l10n;
    final stats = i.stats;
    return [
      AdaptiveFormSection(
        children: [
          AdaptiveFormValueRow(label: l10n.device, value: i.device),
          AdaptiveFormValueRow(label: l10n.uptime, value: i.formattedUptime),
          if (i.ipAddress != null)
            AdaptiveFormValueRow(
              label: l10n.ipAddress,
              value: i.ipAddress!,
              selectable: true,
            ),
          for (final v6 in i.ipv6Addresses ?? const <String>[])
            AdaptiveFormValueRow(
              label: l10n.ipv6Address,
              value: v6,
              selectable: true,
            ),
          if (i.gateway != null)
            AdaptiveFormValueRow(
              label: l10n.gateway,
              value: i.gateway!,
              selectable: true,
            ),
          if (i.dnsServers.isNotEmpty)
            AdaptiveFormValueRow(
              label: l10n.dns,
              value: i.dnsServers.join(', '),
              selectable: true,
            ),
        ],
      ),
      // Counters the router did not report are left out, not shown as no
      // traffic.
      if (stats.containsKey('rx_bytes') || stats.containsKey('tx_bytes'))
        AdaptiveFormSection(
          header: l10n.trafficSection,
          children: [
            if (stats.containsKey('rx_bytes'))
              AdaptiveFormValueRow(
                label: l10n.received,
                value: formatBytes(stats['rx_bytes'] ?? 0, decimals: 2),
              ),
            if (stats.containsKey('tx_bytes'))
              AdaptiveFormValueRow(
                label: l10n.transmitted,
                value: formatBytes(stats['tx_bytes'] ?? 0, decimals: 2),
              ),
          ],
        ),
      if (i.protocol.toLowerCase() == 'wireguard')
        for (final peer in _wireGuardPeersOf(appState, i.name))
          _iosPeerSection(context, peer),
    ];
  }

  /// A WireGuard peer as a group: its name (or key) over its handshake,
  /// endpoint, allowed addresses and traffic.
  Widget _iosPeerSection(BuildContext context, Map<String, dynamic> peer) {
    final l10n = context.l10n;
    final p = _peerSummary(context, peer);
    return AdaptiveFormSection(
      header: p.name?.isNotEmpty == true ? p.name : p.displayKey,
      children: [
        AdaptiveFormValueRow(label: l10n.lastHandshake, value: p.handshake),
        AdaptiveFormValueRow(
          label: l10n.endpoint,
          value: p.endpoint,
          selectable: true,
        ),
        if (p.allowedIps.isNotEmpty)
          AdaptiveFormValueRow(
            label: l10n.allowedIps,
            value: p.allowedIps.join(', '),
            selectable: true,
          ),
        if (p.rx != null)
          AdaptiveFormValueRow(
            label: l10n.received,
            value: formatBytes(p.rx!, decimals: 2),
          ),
        if (p.tx != null)
          AdaptiveFormValueRow(
            label: l10n.transmitted,
            value: formatBytes(p.tx!, decimals: 2),
          ),
      ],
    );
  }

  /// A wireless interface's page on iOS: its details as value rows, then
  /// its switch and Edit, then Remove in red.
  List<Widget> _iosWirelessSections(
    BuildContext context,
    Map<String, dynamic> iface,
  ) {
    final l10n = context.l10n;
    final details = iface['details'] as Map<String, dynamic>;
    final uciSection = iface['uciSection'] as String? ?? '';
    final encDescription = iface['encryptionDescription']?.toString() ?? '';
    return [
      AdaptiveFormSection(
        footer: uciSection.isEmpty ? l10n.limitedInterfaceManagement : null,
        children: [
          for (final entry in details.entries)
            AdaptiveFormValueRow(label: entry.key, value: '${entry.value}'),
          if (encDescription.isNotEmpty && encDescription != 'N/A')
            AdaptiveFormValueRow(label: l10n.encryption, value: encDescription),
        ],
      ),
      if (uciSection.isNotEmpty) ...[
        AdaptiveFormSection(
          children: [
            _WifiToggleRow(
              uciSection: uciSection,
              isEnabled: iface['isIfaceEnabled'] as bool? ?? true,
            ),
            AdaptiveFormButtonRow(
              label: l10n.edit,
              onPressed: () => _showEditWifiSheet(context, iface),
            ),
          ],
        ),
        AdaptiveFormSection(
          children: [
            _IosRemoveWifiRow(
              ssid: iface['ssid']?.toString() ?? '',
              uciSection: uciSection,
              mode: iface['mode']?.toString() ?? 'ap',
            ),
          ],
        ),
      ],
    ];
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
          _buildDetailRow(context, context.l10n.encryption, encDescription),

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
                      child: AdaptiveButton(
                        onPressed: () => _showEditWifiSheet(context, iface),
                        label: context.l10n.edit,
                        sfSymbol: SFSymbol(
                          'pencil',
                          color: colorScheme.primary,
                        ),
                        materialIcon: Icons.edit_outlined,
                        style: AdaptiveButtonStyle.bordered,
                        color: colorScheme.primary.withValues(alpha: 0.5),
                        textColor: colorScheme.primary,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        borderRadius: BorderRadius.circular(10),
                        useSmoothRectangleBorder: false,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: AdaptiveButton(
                        onPressed: () => _showDeleteWifiDialog(context, iface),
                        label: context.l10n.remove,
                        sfSymbol: SFSymbol('trash', color: colorScheme.error),
                        materialIcon: Icons.delete_outline,
                        style: AdaptiveButtonStyle.bordered,
                        color: colorScheme.error.withValues(alpha: 0.5),
                        textColor: colorScheme.error,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        borderRadius: BorderRadius.circular(10),
                        useSmoothRectangleBorder: false,
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
                          ? context.l10n.clientStationMode
                          : mode.toLowerCase() == 'ap'
                          ? context.l10n.accessPointMode
                          : context.l10n.modeValue(mode.toUpperCase()),
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
              context.l10n.limitedInterfaceManagement,
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
    showAdaptiveFormSheet<void>(
      context: context,
      material: const AdaptiveFormMaterialPresentation.bottomSheet(
        // The sheet draws its own handle.
        showDragHandle: false,
        useSafeArea: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      builder: (ctx) => _WifiEditBottomSheet(iface: iface),
    );
  }

  void _showDeleteWifiDialog(BuildContext context, Map<String, dynamic> iface) {
    final ssid = iface['ssid']?.toString() ?? context.l10n.thisInterface;
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
        _buildDetailRow(context, context.l10n.device, interface.device),
        _buildDetailRow(
          context,
          context.l10n.uptime,
          interface.formattedUptime,
        ),
        if (interface.ipAddress != null)
          _buildDetailRow(
            context,
            context.l10n.ipAddress,
            interface.ipAddress!,
            onTap: () => copyToClipboard(
              context,
              interface.ipAddress!,
              label: context.l10n.ipAddress,
            ),
          ),
        if (interface.ipv6Addresses != null &&
            interface.ipv6Addresses!.isNotEmpty)
          ...interface.ipv6Addresses!.map(
            (ipv6) => _buildDetailRow(
              context,
              context.l10n.ipv6Address,
              ipv6,
              onTap: () => copyToClipboard(
                context,
                ipv6,
                label: context.l10n.ipv6Address,
              ),
            ),
          ),
        if (interface.gateway != null)
          _buildDetailRow(
            context,
            context.l10n.gateway,
            interface.gateway!,
            onTap: () => copyToClipboard(
              context,
              interface.gateway!,
              label: context.l10n.gatewayIp,
            ),
          ),
        if (interface.dnsServers.isNotEmpty)
          _buildDetailRow(
            context,
            context.l10n.dns,
            interface.dnsServers.join(', '),
            onTap: () => copyToClipboard(
              context,
              interface.dnsServers.join(', '),
              label: context.l10n.dnsServers,
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
        // Counters the router did not report - the device read failed, and
        // the dump carries none - are left out, not shown as zero traffic.
        if (interface.stats.containsKey('rx_bytes') ||
            interface.stats.containsKey('tx_bytes')) ...[
          const Divider(height: 1, indent: 16, endIndent: 16),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: _buildStatsRow(context, interface.stats),
          ),
        ],
      ],
    );
  }

  /// [interfaceName]'s WireGuard peers in [appState]'s dashboard data.
  static List<Map<String, dynamic>> _wireGuardPeersOf(
    AppState appState,
    String interfaceName,
  ) {
    final wireguardData =
        appState.dashboardData?['wireguard'] as Map<String, dynamic>?;
    final peers = wireguardData?[interfaceName]?['peers'];
    return peers is Map
        ? [for (final p in peers.values) p as Map<String, dynamic>]
        : const [];
  }

  /// What the peer card and the iOS peer group show about [peer].
  ({
    String displayKey,
    String? name,
    String handshake,
    String endpoint,
    List<String> allowedIps,
    int? rx,
    int? tx,
  })
  _peerSummary(BuildContext context, Map<String, dynamic> peer) {
    final publicKey = peer['public_key'] as String? ?? 'Unknown';
    int lastHandshake = 0;
    final rawHandshake = peer['last_handshake'] ?? peer['latest_handshake'];
    if (rawHandshake is int) {
      lastHandshake = rawHandshake;
    } else if (rawHandshake is String) {
      lastHandshake = int.tryParse(rawHandshake) ?? 0;
    }
    String handshake() {
      if (lastHandshake == 0) return context.l10n.never;
      final difference = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(lastHandshake * 1000),
      );
      if (difference.inSeconds < 0) return context.l10n.never;
      if (difference.inDays > 0) {
        return context.l10n.daysAgo(difference.inDays);
      } else if (difference.inHours > 0) {
        return context.l10n.hoursAgo(difference.inHours);
      } else if (difference.inMinutes > 0) {
        return context.l10n.minutesAgo(difference.inMinutes);
      }
      return context.l10n.secondsAgo(difference.inSeconds);
    }

    final rawAllowed = peer['allowed_ips'];
    final rawRx = peer['transfer_rx'];
    final rawTx = peer['transfer_tx'];
    return (
      displayKey: publicKey.length > 16
          ? '${publicKey.substring(0, 8)}...${publicKey.substring(publicKey.length - 8)}'
          : publicKey,
      name: peer['name'] as String?,
      handshake: handshake(),
      endpoint: peer['endpoint'] as String? ?? 'N/A',
      allowedIps: rawAllowed is List
          ? [for (final ip in rawAllowed) '$ip']
          : const <String>[],
      rx: rawRx is num ? rawRx.toInt() : null,
      tx: rawTx is num ? rawTx.toInt() : null,
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
    final summary = _peerSummary(context, peer);
    final endpoint = summary.endpoint;
    final peerName = summary.name;
    final displayKey = summary.displayKey;
    final allowedIps = summary.allowedIps;
    final transferRx = summary.rx;
    final transferTx = summary.tx;
    Widget peerField(String label, String value) => Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
            fontSize: 14,
            color: colorScheme.onSurface,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
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
                      context.l10n.lastHandshake,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      summary.handshake,
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
                      context.l10n.endpoint,
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
          if (allowedIps.isNotEmpty) ...[
            const SizedBox(height: 12),
            peerField(context.l10n.allowedIps, allowedIps.join(', ')),
          ],
          if (transferRx != null || transferTx != null) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The router's view, as on the interface cards: received
                // from the peer, sent to it. A direction the router did
                // not report is left out, not shown as no traffic.
                if (transferRx != null)
                  Expanded(
                    child: peerField(
                      context.l10n.received,
                      formatBytes(transferRx, decimals: 2),
                    ),
                  ),
                if (transferRx != null && transferTx != null)
                  const SizedBox(width: 24),
                if (transferTx != null)
                  Expanded(
                    child: peerField(
                      context.l10n.transmitted,
                      formatBytes(transferTx, decimals: 2),
                    ),
                  ),
              ],
            ),
          ],
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
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8.0),
                      child: Icon(
                        Icons.copy_all_outlined,
                        size: 16,
                        semanticLabel: context.l10n.copy,
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

  Widget _buildStatsRow(BuildContext context, Map<String, dynamic> stats) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildStatColumn(
          context,
          context.l10n.received,
          formatBytes(stats['rx_bytes'] ?? 0, decimals: 2),
          Icons.arrow_downward,
          Colors.green,
        ),
        _buildStatColumn(
          context,
          context.l10n.transmitted,
          formatBytes(stats['tx_bytes'] ?? 0, decimals: 2),
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
                              semanticLabel: context.l10n.interfaceIcon,
                            ),
                          ),
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Tooltip(
                            message: widget.isUp
                                ? context.l10n.interfaceIsUp
                                : context.l10n.interfaceIsDown,
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
                            semanticsLabel: context.l10n.interfaceNameSemantics(
                              widget.name,
                            ),
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
                            semanticsLabel: context.l10n
                                .interfaceDetailsSemantics(widget.subtitle),
                          ),
                        ],
                      ),
                    ),
                    if (!widget.isUp)
                      Padding(
                        padding: const EdgeInsets.only(right: LuciSpacing.xs),
                        child: LuciStatusIndicators.statusChip(
                          context,
                          context.l10n.off.toUpperCase(),
                          false,
                        ),
                      ),
                    const SizedBox(width: LuciSpacing.sm),
                    Icon(
                      _isExpanded ? Icons.expand_less : Icons.expand_more,
                      color: colorScheme.onSurfaceVariant,
                      size: 26,
                      semanticLabel: _isExpanded
                          ? context.l10n.collapseDetails
                          : context.l10n.expandDetails,
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

/// An interface's own page on iOS, built from the latest dashboard data
/// by [content], so it follows a refresh, or a message once the interface
/// is gone from it.
class _InterfacePage extends ConsumerWidget {
  const _InterfacePage({required this.title, required this.content});

  /// The title the page opens with, and keeps once the interface is gone.
  final String title;

  /// The page's current title and groups, or null when the interface is
  /// no longer there.
  final ({String title, List<Widget> sections})? Function(
    BuildContext context,
    AppState appState,
  )
  content;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(appStateProvider);
    final grouped = CupertinoColors.systemGroupedBackground.resolveFrom(
      context,
    );
    final current = content(context, appState);
    return Scaffold(
      backgroundColor: grouped,
      appBar: LuciAppBar(
        title: current?.title ?? title,
        showBack: true,
        backgroundColor: grouped.withValues(alpha: 0.94),
      ),
      body: AdaptiveRefreshIndicator(
        onRefresh: () => ref.read(appStateProvider).fetchDashboardData(),
        child: current == null
            ? LuciMessageState(
                icon: Icons.device_hub_outlined,
                message: context.l10n.noInterfaceData,
              )
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(LuciSpacing.md),
                children: current.sections,
              ),
      ),
    );
  }
}

/// What removing a network in [mode] does to the devices on it.
String _removeWifiWarning(BuildContext context, String mode) {
  final modeLower = mode.toLowerCase();
  final isStaMode =
      modeLower.contains('sta') ||
      modeLower.contains('client') ||
      modeLower == 'station';
  return isStaMode
      ? context.l10n.removeStaWarning
      : context.l10n.removeApWarning;
}

/// Remove, in red, on a Wi-Fi network's iOS page. It asks first in an iOS
/// alert, shows it is at work while the router removes the network, then
/// leaves the page, which has nothing left to show.
class _IosRemoveWifiRow extends ConsumerStatefulWidget {
  const _IosRemoveWifiRow({
    required this.ssid,
    required this.uciSection,
    required this.mode,
  });

  final String ssid;
  final String uciSection;
  final String mode;

  @override
  ConsumerState<_IosRemoveWifiRow> createState() => _IosRemoveWifiRowState();
}

class _IosRemoveWifiRowState extends ConsumerState<_IosRemoveWifiRow> {
  bool _removing = false;

  Future<void> _remove() async {
    final l10n = context.l10n;
    final name = widget.ssid.isNotEmpty ? widget.ssid : widget.uciSection;
    final confirmed = await AdaptiveAlertDialog.confirm(
      context: context,
      title: l10n.removeWirelessInterfaceQuestion,
      message:
          '${l10n.removeWirelessInterfaceDescription(name)}\n\n'
          '${_removeWifiWarning(context, widget.mode)}',
      confirmLabel: l10n.remove,
      cancelLabel: l10n.cancel,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _removing = true);
    // Taken now: the refresh after removing rebuilds the page without this
    // row. The page's own route, so that only it is closed: Back and Edit
    // stay open while the router works.
    final navigator = Navigator.of(context);
    final page = ModalRoute.of(context);
    final report = AdaptiveSnackBar.reporter(context);
    final success = await ref
        .read(appStateProvider)
        .deleteWirelessInterface(widget.uciSection, context: context);
    if (success) {
      // Left already, or under the Edit sheet: the page then says the
      // network is gone instead.
      if (page != null && page.isCurrent) navigator.pop();
    } else if (mounted) {
      setState(() => _removing = false);
    }
    report.show(
      message: success
          ? l10n.interfaceRemoved(name)
          : l10n.removeInterfaceFailed,
      type: success ? AdaptiveSnackBarType.success : AdaptiveSnackBarType.error,
      duration: const Duration(seconds: 3),
    );
  }

  @override
  Widget build(BuildContext context) => AdaptiveFormButtonRow(
    label: context.l10n.remove,
    destructive: true,
    onPressed: _removing ? null : _remove,
  );
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

  /// The state asked for while it is being saved; the iOS switch shows it
  /// until the router's data says otherwise.
  bool? _requested;

  Future<void> _toggle(bool value) async {
    if (_isToggling) return;
    setState(() {
      _isToggling = true;
      _requested = value;
    });

    final appState = ref.read(appStateProvider);
    final success = await appState.setWirelessInterfaceEnabled(
      widget.uciSection,
      value,
      context: context,
    );

    if (mounted) {
      setState(() {
        _isToggling = false;
        _requested = null;
      });
      if (!success) {
        AdaptiveSnackBar.show(
          context,
          message: context.l10n.failedToToggleInterface,
          type: AdaptiveSnackBarType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (PlatformUiCapabilities.isIOS) {
      final shown = _requested ?? widget.isEnabled;
      return AdaptiveFormSwitch(
        label: shown
            ? context.l10n.interfaceEnabled
            : context.l10n.interfaceDisabled,
        value: shown,
        onChanged: _isToggling ? null : _toggle,
      );
    }
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
              widget.isEnabled
                  ? context.l10n.interfaceEnabled
                  : context.l10n.interfaceDisabled,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (_isToggling)
            const SizedBox(
              width: 20,
              height: 20,
              child: AdaptiveProgressIndicator(strokeWidth: 2),
            )
          else
            AdaptiveSwitch(value: widget.isEnabled, onChanged: _toggle),
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
  String? _selectedEncryption;
  late String _originalEncryption; // tracks what was set before editing
  bool _obscurePassword = true;
  bool _isSaving = false;
  String? _error;

  static const _encryptionOptions = [
    'none',
    'owe',
    'psk2',
    'psk',
    'psk-mixed',
    'sae',
    'sae-mixed',
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

    final rawEncryption = widget.iface['encryption']?.toString().trim() ?? '';
    final currentEnc = (rawEncryption.isEmpty ? 'none' : rawEncryption)
        .split('+')
        .first;
    _originalEncryption = currentEnc;
    _selectedEncryption = _encryptionOptions.contains(currentEnc)
        ? currentEnc
        : null;
  }

  @override
  void dispose() {
    _ssidController.dispose();
    _passwordController.dispose();
    _networkController.dispose();
    super.dispose();
  }

  bool get _requiresPassword =>
      _selectedEncryption != null &&
      _selectedEncryption != 'none' &&
      _selectedEncryption != 'owe';

  bool get _isEncryptionSupported =>
      _selectedEncryption != null &&
      _encryptionOptions.contains(_selectedEncryption);

  String _encryptionLabel(String value) => switch (value) {
    'none' => context.l10n.encryptionNone,
    'owe' => 'OWE',
    'psk2' => 'WPA2-PSK',
    'psk' => 'WPA-PSK',
    'psk-mixed' => 'WPA/WPA2 Mixed PSK',
    'sae' => 'WPA3-SAE',
    'sae-mixed' => 'WPA2/WPA3 Mixed',
    _ => value,
  };

  /// True when switching from an open interface to a password-protected one.
  bool get _changingToEncrypted =>
      (_originalEncryption == 'none' || _originalEncryption == 'owe') &&
      _requiresPassword;

  Future<void> _save() async {
    final ssid = _ssidController.text.trim();
    if (ssid.isEmpty) {
      setState(() => _error = context.l10n.ssidEmptyError);
      return;
    }

    // Block unsupported encryption modes (e.g. enterprise WPA-EAP)
    if (!_isEncryptionSupported) {
      setState(() => _error = context.l10n.unsupportedEncryptionError);
      return;
    }

    // Require a password when changing an open interface to an encrypted one
    if (_changingToEncrypted && _passwordController.text.isEmpty) {
      setState(() => _error = context.l10n.encryptionPasswordRequiredError);
      return;
    }

    if (_requiresPassword &&
        _passwordController.text.isNotEmpty &&
        _passwordController.text.length < 8) {
      setState(() => _error = context.l10n.passwordLengthError);
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
        _error = context.l10n.uciSectionMissingError;
      });
      return;
    }

    // Build values to update
    final values = <String, String>{
      'ssid': ssid,
      'encryption': _selectedEncryption!,
    };

    if (!_requiresPassword) {
      values['key'] = '';
    } else if (_passwordController.text.isNotEmpty) {
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
      // This sheet closes before the report shows.
      final report = AdaptiveSnackBar.reporter(context);
      final message = context.l10n.wifiUpdated(ssid);
      Navigator.of(context).pop();
      report.show(
        message: message,
        type: AdaptiveSnackBarType.success,
        duration: const Duration(seconds: 3),
      );
    } else {
      setState(() {
        _isSaving = false;
        _error = context.l10n.saveChangesFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final mode = widget.iface['mode']?.toString() ?? 'ap';
    final summary =
        '${widget.iface['radioName']} • ${context.l10n.modeValue(mode.toUpperCase())}';

    if (PlatformUiCapabilities.isIOS) {
      return AdaptiveFormSheet(
        title: context.l10n.editWirelessInterface,
        subtitle: summary,
        cancelLabel: context.l10n.cancel,
        confirmLabel: context.l10n.saveAction,
        onConfirm: _save,
        busy: _isSaving,
        grouped: true,
        child: _iosForm(context),
      );
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
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
                          context.l10n.editWirelessInterface,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          summary,
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

              ..._form(context),

              const SizedBox(height: 20),

              // Save button
              SizedBox(
                width: double.infinity,
                child: AdaptiveButton(
                  onPressed: _isSaving ? null : _save,
                  busy: _isSaving,
                  label: _isSaving
                      ? context.l10n.applying
                      : context.l10n.saveChanges,
                  sfSymbol: const SFSymbol('square.and.arrow.down'),
                  materialIcon: Icons.save,
                  size: AdaptiveButtonSize.large,
                  labelStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  borderRadius: BorderRadius.circular(14),
                  useSmoothRectangleBorder: false,
                ),
              ),

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// The interface's settings as one iOS group, with what went wrong and
  /// what saving them will do under it.
  Widget _iosForm(BuildContext context) {
    final l10n = context.l10n;
    return AdaptiveFormSection(
      error: _error,
      footer: l10n.wifiChangesWarning,
      children: [
        AdaptiveFormTextField(
          label: l10n.ssidNetworkName,
          controller: _ssidController,
          enabled: !_isSaving,
          placeholder: l10n.enterSsid,
        ),
        AdaptiveFormPicker<String>(
          label: l10n.encryption,
          value: _selectedEncryption,
          // An encryption this editor does not offer, such as WPA-EAP.
          hint: _encryptionLabel(_originalEncryption),
          choices: [
            for (final option in _encryptionOptions)
              AdaptiveFormChoice(option, _encryptionLabel(option)),
          ],
          onChanged: _isSaving
              ? null
              : (value) {
                  if (value != null) {
                    setState(() => _selectedEncryption = value);
                  }
                },
        ),
        if (_requiresPassword)
          AdaptiveFormTextField(
            label: l10n.password,
            controller: _passwordController,
            obscureText: _obscurePassword,
            enabled: !_isSaving,
            placeholder: l10n.enterNewPassword,
            helper: _changingToEncrypted
                ? l10n.passwordRequired
                : l10n.passwordKeepCurrent,
            suffix: AdaptiveObscureToggle(
              obscured: _obscurePassword,
              semanticLabel: _obscurePassword
                  ? l10n.showPassword
                  : l10n.hidePassword,
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
        AdaptiveFormTextField(
          label: l10n.network,
          controller: _networkController,
          enabled: !_isSaving,
          placeholder: l10n.networkExample,
        ),
      ],
    );
  }

  /// The interface's settings, and what saving them will do.
  List<Widget> _form(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return [
      // SSID field
      _buildLabel(context, context.l10n.ssidNetworkName),
      const SizedBox(height: 6),
      TextField(
        controller: _ssidController,
        enabled: !_isSaving,
        decoration: _inputDecoration(
          context,
          hintText: context.l10n.enterSsid,
          prefixIcon: Icons.wifi,
        ),
      ),

      const SizedBox(height: 16),

      // Encryption selector
      _buildLabel(context, context.l10n.encryption),
      const SizedBox(height: 6),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.outline.withValues(alpha: 0.3)),
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
                value: opt,
                child: Text(
                  _encryptionLabel(opt),
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
        _buildLabel(
          context,
          _changingToEncrypted
              ? context.l10n.passwordRequired
              : context.l10n.passwordKeepCurrent,
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          enabled: !_isSaving,
          decoration: _inputDecoration(
            context,
            hintText: context.l10n.enterNewPassword,
            prefixIcon: Icons.key,
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off : Icons.visibility,
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
      _buildLabel(context, context.l10n.network),
      const SizedBox(height: 6),
      TextField(
        controller: _networkController,
        enabled: !_isSaving,
        decoration: _inputDecoration(
          context,
          hintText: context.l10n.networkExample,
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
              Icon(Icons.error_outline, color: colorScheme.error, size: 18),
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
            Icon(Icons.info_outline, color: colorScheme.tertiary, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.l10n.wifiChangesWarning,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _buildLabel(BuildContext context, String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(fontWeight: FontWeight.w600),
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
      context: context,
    );

    if (!mounted) return;

    // This dialog closes before the report shows.
    final report = AdaptiveSnackBar.reporter(context);
    final message = success
        ? context.l10n.interfaceRemoved(widget.ssid)
        : context.l10n.removeInterfaceFailed;
    Navigator.of(context).pop();
    report.show(
      message: message,
      type: success ? AdaptiveSnackBarType.success : AdaptiveSnackBarType.error,
      duration: const Duration(seconds: 3),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final displayName = widget.ssid.isNotEmpty
        ? widget.ssid
        : widget.uciSection;
    final warningMessage = _removeWifiWarning(context, widget.mode);

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
      title: Text(context.l10n.removeWirelessInterfaceQuestion),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.l10n.removeWirelessInterfaceDescription(displayName),
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
          child: Text(context.l10n.cancel),
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
                  child: AdaptiveProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(context.l10n.remove),
        ),
      ],
    );
  }
}
