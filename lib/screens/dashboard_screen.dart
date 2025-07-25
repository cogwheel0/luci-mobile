import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';
import 'package:luci_mobile/widgets/luci_animation_system.dart';
import 'package:luci_mobile/models/router.dart' as model;

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final ScrollController _wirelessScrollController = ScrollController();
  bool _showWirelessLeftArrow = false;
  bool _showWirelessRightArrow = false;

  final ScrollController _wanScrollController = ScrollController();
  bool _showWanLeftArrow = false;
  bool _showWanRightArrow = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<AppState>(context, listen: false).fetchDashboardData();
      // Initialize arrows after layout
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateWirelessArrows();
        _updateWanArrows();
      });
    });
    _wirelessScrollController.addListener(_updateWirelessArrows);
    _wanScrollController.addListener(_updateWanArrows);
  }

  @override
  void didUpdateWidget(covariant DashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateWirelessArrows();
      _updateWanArrows();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateWirelessArrows();
      _updateWanArrows();
    });
  }

  void _updateWirelessArrows() {
    if (!_wirelessScrollController.hasClients) return;
    final max = _wirelessScrollController.position.maxScrollExtent;
    final min = _wirelessScrollController.position.minScrollExtent;
    final offset = _wirelessScrollController.offset;
    setState(() {
      _showWirelessLeftArrow = offset > min + 2;
      _showWirelessRightArrow = offset < max - 2;
    });
  }

  void _updateWanArrows() {
    if (!_wanScrollController.hasClients) return;
    final max = _wanScrollController.position.maxScrollExtent;
    final min = _wanScrollController.position.minScrollExtent;
    final offset = _wanScrollController.offset;
    setState(() {
      _showWanLeftArrow = offset > min + 2;
      _showWanRightArrow = offset < max - 2;
    });
  }

  @override
  void dispose() {
    _wirelessScrollController.removeListener(_updateWirelessArrows);
    _wirelessScrollController.dispose();
    _wanScrollController.removeListener(_updateWanArrows);
    _wanScrollController.dispose();
    super.dispose();
  }

  String _formatUptime(int seconds) {
    final duration = Duration(seconds: seconds);
    final days = duration.inDays;
    final hours = duration.inHours.remainder(24);
    final minutes = duration.inMinutes.remainder(60);
    final parts = <String>[];
    if (days > 0) parts.add('${days}d');
    if (hours > 0 || days > 0) parts.add('${hours}h');
    parts.add('${minutes}m');
    return parts.join(' ');
  }

  String _formatCpuLoad(List<dynamic> load) {
    if (load.isEmpty) return 'N/A';
    // Use the first value as the main CPU load
    final percent = ((load[0] / 65536) * 100).clamp(0, 100);
    return '${percent.toStringAsFixed(0)}%';
  }

  Widget _buildDeviceInfoCard(AppState appState) {
    final boardInfo =
        appState.dashboardData?['boardInfo'] as Map<String, dynamic>?;
    final model = boardInfo?['model'] ?? 'N/A';
    final version = boardInfo?['release']?['version'] ?? 'N/A';
    final isSnapshot =
        boardInfo?['release']?['revision']?.toString().contains('SNAPSHOT') ==
        true;
    final branch = isSnapshot ? 'SNAPSHOT' : 'stable';

    final labelStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurface,
    );
    final valueStyle = Theme.of(
      context,
    ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Model', style: labelStyle),
                  const SizedBox(height: 4),
                  Text(
                    model,
                    style: valueStyle,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Version', style: labelStyle),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          version,
                          style: valueStyle,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isSnapshot
                              ? Colors.orange.withValues(alpha: 0.15)
                              : Colors.green.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          branch,
                          style: TextStyle(
                            color: isSnapshot
                                ? Colors.orange.shade800
                                : Colors.green.shade800,
                            fontWeight: FontWeight.bold,
                            fontSize: Theme.of(
                              context,
                            ).textTheme.bodySmall?.fontSize,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRealtimeThroughputCard(AppState appState) {
    // Show loading state if we don't have any throughput data yet
    final hasValidData =
        appState.rxHistory.length > 1 ||
        appState.txHistory.length > 1; // Need at least 2 points for a line
    // Only show switching state if we're loading AND no dashboard data is available (true router switch)
    final isSwitchingRouter =
        appState.isLoading && appState.dashboardData == null;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildSpeedIndicator(
                  Icons.arrow_downward,
                  Colors.green,
                  '',
                  isSwitchingRouter ? 0.0 : appState.currentRxRate,
                ),
                _buildSpeedIndicator(
                  Icons.arrow_upward,
                  Colors.blue,
                  '',
                  isSwitchingRouter ? 0.0 : appState.currentTxRate,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(
                top: 16.0,
              ), // Add space above the chart
              child: AnimatedSwitcher(
                duration: const Duration(
                  milliseconds: 600,
                ), // Smoother transition
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position:
                          Tween<Offset>(
                            begin: const Offset(0, 0.2),
                            end: Offset.zero,
                          ).animate(
                            CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeOutCubic,
                            ),
                          ),
                      child: child,
                    ),
                  );
                },
                child: hasValidData && !isSwitchingRouter
                    ? LineChart(
                        key: ValueKey('chart_${appState.selectedRouter?.id}'),
                        LineChartData(
                          gridData: FlGridData(show: false),
                          titlesData: FlTitlesData(show: false),
                          borderData: FlBorderData(show: false),
                          lineTouchData: LineTouchData(
                            touchTooltipData: LineTouchTooltipData(
                              fitInsideVertically: true,
                              getTooltipColor: (LineBarSpot spot) => Theme.of(
                                context,
                              ).colorScheme.surface.withValues(alpha: 0.9),
                              tooltipBorderRadius: BorderRadius.circular(8),
                              tooltipPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              getTooltipItems:
                                  (List<LineBarSpot> touchedSpots) {
                                    return touchedSpots.map((barSpot) {
                                      final flSpot = barSpot;
                                      final Color color =
                                          flSpot.bar.gradient?.colors.first ??
                                          flSpot.bar.color ??
                                          Colors.white;

                                      return LineTooltipItem(
                                        _formatSpeed(flSpot.y),
                                        TextStyle(
                                          color: color,
                                          fontWeight: FontWeight.w900,
                                        ),
                                        textAlign: TextAlign.left,
                                      );
                                    }).toList();
                                  },
                            ),
                          ),
                          lineBarsData: [
                            _buildLineChartBarData(appState.rxHistory, [
                              Colors.green.shade700,
                              Colors.green.shade400,
                            ]),
                            _buildLineChartBarData(appState.txHistory, [
                              Colors.blue.shade700,
                              Colors.blue.shade400,
                            ]),
                          ],
                        ),
                        duration: const Duration(milliseconds: 800),
                        curve: Curves.easeInOut,
                      )
                    : Center(
                        key: ValueKey('loading_${appState.selectedRouter?.id}'),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.trending_up,
                              size: 48,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.7),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              isSwitchingRouter
                                  ? 'Switching router...'
                                  : 'Collecting throughput data...',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.8),
                                  ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeedIndicator(
    IconData icon,
    Color color,
    String label,
    double speed,
  ) {
    // Show 0 if we don't have valid throughput data yet
    final displaySpeed = speed.isNaN || speed.isInfinite || speed < 0
        ? 0.0
        : speed;
    final speedText = AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.1),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: Text(
        _formatSpeed(displaySpeed),
        key: ValueKey(displaySpeed),
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        if (label.isNotEmpty)
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodyMedium),
                speedText,
              ],
            ),
          )
        else
          Flexible(child: speedText),
      ],
    );
  }

  LineChartBarData _buildLineChartBarData(
    List<double> data,
    List<Color> gradientColors,
  ) {
    // Don't show chart data if we don't have enough data points for a smooth line
    if (data.length < 2) {
      return LineChartBarData(
        spots: [],
        isCurved: true,
        gradient: LinearGradient(colors: gradientColors),
        barWidth: 3,
        isStrokeCapRound: true,
        dotData: FlDotData(show: false),
        belowBarData: BarAreaData(show: false),
      );
    }

    return LineChartBarData(
      spots: data
          .asMap()
          .entries
          .map((e) => FlSpot(e.key.toDouble(), e.value))
          .toList(),
      isCurved: true,
      gradient: LinearGradient(colors: gradientColors),
      barWidth: 3,
      isStrokeCapRound: true,
      dotData: FlDotData(show: false),
      belowBarData: BarAreaData(
        show: true,
        gradient: LinearGradient(
          colors: gradientColors
              .map((color) => color.withValues(alpha: 0.3))
              .toList(),
        ),
      ),
    );
  }

  String _formatSpeed(double bytesPerSecond) {
    // Handle edge cases
    if (bytesPerSecond.isNaN ||
        bytesPerSecond.isInfinite ||
        bytesPerSecond < 0) {
      return '0 bps';
    }

    final bitsPerSecond = bytesPerSecond * 8;
    if (bitsPerSecond < 1_000) return '${bitsPerSecond.toStringAsFixed(0)} bps';
    if (bitsPerSecond < 1_000_000) {
      return '${(bitsPerSecond / 1_000).toStringAsFixed(1)} Kbps';
    }
    return '${(bitsPerSecond / 1_000_000).toStringAsFixed(2)} Mbps';
  }

  // Consistent card builder for all dashboard vitals and summary cards
  Widget _buildVitalsColumn(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    final labelStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurface,
    );
    final valueStyle = Theme.of(
      context,
    ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: labelStyle),
        const SizedBox(height: 4),
        Text(
          value,
          style: valueStyle,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildSystemVitalsCard(AppState appState) {
    final sysInfo = appState.dashboardData?['sysInfo'] as Map<String, dynamic>?;

    final uptime = sysInfo?['uptime'] as int?;
    final uptimeValue = uptime != null ? _formatUptime(uptime) : 'N/A';

    final cpuLoad = sysInfo?['load'] as List<dynamic>?;
    final cpuLoadValue = cpuLoad != null ? _formatCpuLoad(cpuLoad) : 'N/A';

    final totalMem = sysInfo?['memory']?['total'] as int? ?? 0;
    final freeMem = sysInfo?['memory']?['free'] as int? ?? 0;
    final bufferedMem = sysInfo?['memory']?['buffered'] as int? ?? 0;
    final usedMem = totalMem - freeMem - bufferedMem;
    final memoryValue = totalMem > 0
        ? '${(usedMem / totalMem * 100).toStringAsFixed(0)}%'
        : 'N/A';

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 0),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
        child: Row(
          children: [
            Expanded(
              child: _buildVitalsColumn(
                context,
                label: 'CPU Load',
                value: cpuLoadValue,
              ),
            ),
            Expanded(
              child: _buildVitalsColumn(
                context,
                label: 'Memory',
                value: memoryValue,
              ),
            ),
            Expanded(
              child: _buildVitalsColumn(
                context,
                label: 'Uptime',
                value: uptimeValue,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWirelessInfoCardContent(
    BuildContext context, {
    required String ssid,
    required bool isEnabled,
    required int? signal,
    required String channel,
  }) {
    final textTheme = Theme.of(context).textTheme;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.wifi,
              color: isEnabled
                  ? primaryColor
                  : Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.5),
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              ssid,
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.max,
          children: [
            if (signal != null)
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.network_cell,
                      size: 16,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        '$signal dBm',
                        style: textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            if (signal != null) const SizedBox(width: 8),
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.settings_input_antenna,
                    size: 16,
                    color: Colors.grey.shade600,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      'Ch: $channel',
                      style: textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildWirelessNetworksCard(AppState appState) {
    final wirelessRadios =
        appState.dashboardData?['wireless'] as Map<String, dynamic>?;
    if (wirelessRadios == null || wirelessRadios.isEmpty) {
      return const SizedBox.shrink();
    }

    List<Widget> networkCardWidgets = [];
    wirelessRadios.forEach((radioName, radioData) {
      final interfaces = radioData['interfaces'] as List<dynamic>?;
      if (interfaces != null) {
        for (var interface in interfaces) {
          final config = interface['config'] ?? {};
          final iwinfo = interface['iwinfo'] ?? {};
          final ssid = iwinfo['ssid'] ?? config['ssid'] ?? 'N/A';
          if (ssid == 'N/A') continue;

          final deviceName = config['device'] ?? radioName;
          final isEnabled = !(config['disabled'] as bool? ?? false);
          final channel = (iwinfo['channel'] ?? config['channel'] ?? 'N/A')
              .toString();
          final signal = iwinfo['signal'] as int?;

          networkCardWidgets.add(
            Card(
              margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onLongPress: () {
                  // Navigate to interfaces tab with the specific interface name
                  final appState = Provider.of<AppState>(
                    context,
                    listen: false,
                  );
                  appState.requestTab(2, interfaceToScroll: deviceName);
                },
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: _buildWirelessInfoCardContent(
                    context,
                    ssid: ssid,
                    isEnabled: isEnabled,
                    signal: signal,
                    channel: channel,
                  ),
                ),
              ),
            ),
          );
        }
      }
    });

    if (networkCardWidgets.isEmpty) {
      return const SizedBox.shrink();
    }

    List<Widget> rowChildren = [];
    final isScrollable = networkCardWidgets.length > 2;
    for (int i = 0; i < networkCardWidgets.length; i++) {
      if (isScrollable) {
        rowChildren.add(SizedBox(width: 180, child: networkCardWidgets[i]));
      } else {
        rowChildren.add(Expanded(child: networkCardWidgets[i]));
      }
      if (i < networkCardWidgets.length - 1) {
        rowChildren.add(SizedBox(width: isScrollable ? 4 : 8));
      }
    }

    if (isScrollable) {
      return Stack(
        children: [
          SizedBox(
            height: 110, // or whatever height fits the card
            child: ListView(
              controller: _wirelessScrollController,
              scrollDirection: Axis.horizontal,
              children: rowChildren,
            ),
          ),
          if (_showWirelessRightArrow)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: IgnorePointer(
                child: Container(
                  width: 28,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.transparent,
                        Theme.of(context).colorScheme.surface,
                      ],
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 18,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.45),
                  ),
                ),
              ),
            ),
          if (_showWirelessLeftArrow)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: IgnorePointer(
                child: Container(
                  width: 28,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerRight,
                      end: Alignment.centerLeft,
                      colors: [
                        Colors.transparent,
                        Theme.of(context).colorScheme.surface,
                      ],
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    size: 18,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.45),
                  ),
                ),
              ),
            ),
        ],
      );
    } else {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rowChildren,
      );
    }
  }

  IconData _getInterfaceIcon(String proto) {
    switch (proto) {
      case 'wireguard':
      case 'openvpn':
        return Icons.vpn_key_rounded;
      case 'pppoe':
      case 'dhcp':
      default:
        return Icons.public_rounded;
    }
  }

  Widget _buildInterfaceStatusCards(AppState appState) {
    final interfaces =
        appState.dashboardData?['interfaceDump']?['interface']
            as List<dynamic>?;
    if (interfaces == null || interfaces.isEmpty) {
      return const SizedBox.shrink();
    }

    final wanVpnInterfaces = interfaces.where((item) {
      final interface = item as Map<String, dynamic>;
      final name = interface['interface'] as String? ?? '';
      final proto = interface['proto'] as String? ?? '';
      return name.startsWith('wan') ||
          proto == 'pppoe' ||
          proto == 'wireguard' ||
          proto == 'openvpn';
    }).toList();

    if (wanVpnInterfaces.isEmpty) {
      return const SizedBox.shrink();
    }

    List<Widget> interfaceCardWidgets = [];
    for (var item in wanVpnInterfaces) {
      final interface = item as Map<String, dynamic>;
      final name = interface['interface'] as String? ?? 'N/A';
      final isUp = interface['up'] as bool? ?? false;
      final proto = interface['proto'] as String? ?? '';

      interfaceCardWidgets.add(
        Card(
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onLongPress: () {
              // Navigate to interfaces tab with the specific interface name
              final appState = Provider.of<AppState>(context, listen: false);
              appState.requestTab(2, interfaceToScroll: name);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: 12.0,
                horizontal: 12.0,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    _getInterfaceIcon(proto),
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    name.toUpperCase(),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isUp
                          ? Colors.green.withValues(alpha: 0.15)
                          : Colors.red.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: SizedBox(
                      width: 63,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isUp ? Icons.check_circle : Icons.cancel,
                              size: 11,
                              color: isUp
                                  ? Colors.green.shade800
                                  : Colors.red.shade800,
                            ),
                            const SizedBox(width: 1),
                            Text(
                              isUp ? 'UP' : 'DOWN',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isUp
                                    ? Colors.green.shade900
                                    : Colors.red.shade900,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    List<Widget> rowChildren = [];
    final isScrollable = interfaceCardWidgets.length >= 5;
    for (int i = 0; i < interfaceCardWidgets.length; i++) {
      rowChildren.add(Expanded(child: interfaceCardWidgets[i]));
      if (i < interfaceCardWidgets.length - 1) {
        rowChildren.add(const SizedBox(width: 6));
      }
    }

    if (isScrollable) {
      return LayoutBuilder(
        builder: (context, constraints) {
          // 4 cards visible, 3 gaps between them
          final totalSpacing = 6.0 * 3;
          final width = constraints.maxWidth;
          final calculatedCardWidth = (width - totalSpacing) / 4;
          final localRowChildren = <Widget>[];
          for (int i = 0; i < interfaceCardWidgets.length; i++) {
            localRowChildren.add(
              SizedBox(
                width: calculatedCardWidth,
                child: interfaceCardWidgets[i],
              ),
            );
            if (i < interfaceCardWidgets.length - 1) {
              localRowChildren.add(const SizedBox(width: 6));
            }
          }
          return Stack(
            children: [
              SizedBox(
                height: 110,
                child: ListView(
                  controller: _wanScrollController,
                  scrollDirection: Axis.horizontal,
                  children: localRowChildren,
                ),
              ),
              if (_showWanRightArrow)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: Container(
                      width: 28,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Colors.transparent,
                            Theme.of(context).colorScheme.surface,
                          ],
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 18,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                ),
              if (_showWanLeftArrow)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: Container(
                      width: 28,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerRight,
                          end: Alignment.centerLeft,
                          colors: [
                            Colors.transparent,
                            Theme.of(context).colorScheme.surface,
                          ],
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 18,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      );
    } else {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rowChildren,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        final List<model.Router> routers = appState.routers;
        final model.Router? selected = appState.selectedRouter;
        final boardInfo =
            appState.dashboardData?['boardInfo'] as Map<String, dynamic>?;
        final hostname = boardInfo?['hostname']?.toString();
        final headerText = (hostname != null && hostname.isNotEmpty)
            ? hostname
            : (selected?.ipAddress ?? 'Loading...');
        return Scaffold(
          appBar: LuciAppBar(
            centerTitle: true,
            title: routers.length > 1 ? null : headerText,
            titleWidget: routers.length > 1
                ? Center(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                          width: 1.1,
                        ),
                      ),
                      constraints: const BoxConstraints(minHeight: 36),
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () async {
                            final selectedId = await showModalBottomSheet<String>(
                              context: context,
                              isScrollControlled: false,
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.surface,
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(18),
                                ),
                              ),
                              builder: (context) {
                                return SafeArea(
                                  child: Padding(
                                    padding: const EdgeInsets.only(
                                      top: 12,
                                      left: 8,
                                      right: 8,
                                      bottom: 8,
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Center(
                                          child: Container(
                                            width: 40,
                                            height: 4,
                                            margin: const EdgeInsets.only(
                                              bottom: 12,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.outlineVariant,
                                              borderRadius:
                                                  BorderRadius.circular(2),
                                            ),
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12.0,
                                            vertical: 4,
                                          ),
                                          child: Center(
                                            child: Text(
                                              'Select Router',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                              textAlign: TextAlign.center,
                                            ),
                                          ),
                                        ),
                                        const Divider(height: 16),
                                        ...routers.map((r) {
                                          final isSelected =
                                              r.id == selected?.id;
                                          String routerTitle;
                                          bool isStale = false;
                                          if (isSelected && boardInfo != null) {
                                            final hostname =
                                                boardInfo['hostname']
                                                    ?.toString();
                                            routerTitle =
                                                (hostname != null &&
                                                    hostname.isNotEmpty)
                                                ? hostname
                                                : (r.lastKnownHostname ??
                                                      r.ipAddress);
                                          } else if (r.lastKnownHostname !=
                                                  null &&
                                              r.lastKnownHostname!.isNotEmpty) {
                                            routerTitle = r.lastKnownHostname!;
                                            isStale = true;
                                          } else {
                                            routerTitle = r.ipAddress;
                                          }
                                          return ListTile(
                                            leading: Icon(
                                              Icons.router,
                                              color: isSelected
                                                  ? Theme.of(
                                                      context,
                                                    ).colorScheme.primary
                                                  : Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                            ),
                                            title: Tooltip(
                                              message: isStale
                                                  ? 'Last known hostname (may be out of date)'
                                                  : '',
                                              child: Text(
                                                routerTitle,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: isStale
                                                          ? Theme.of(context)
                                                                .colorScheme
                                                                .onSurfaceVariant
                                                                .withValues(
                                                                  alpha: 0.7,
                                                                )
                                                          : Theme.of(context)
                                                                .colorScheme
                                                                .onSurface,
                                                    ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            subtitle: Text(
                                              r.ipAddress,
                                              style: Theme.of(
                                                context,
                                              ).textTheme.bodySmall,
                                            ),
                                            trailing: isSelected
                                                ? Icon(
                                                    Icons.check_circle,
                                                    color: Theme.of(
                                                      context,
                                                    ).colorScheme.primary,
                                                  )
                                                : null,
                                            selected: isSelected,
                                            selectedTileColor: Theme.of(context)
                                                .colorScheme
                                                .primary
                                                .withValues(alpha: 0.07),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            onTap: () =>
                                                Navigator.of(context).pop(r.id),
                                          );
                                        }),
                                        const SizedBox(height: 8),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            );
                            if (selectedId != null &&
                                selectedId != selected?.id) {
                              appState.selectRouter(selectedId);
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12.0,
                              vertical: 4.0,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(
                                  headerText,
                                  style:
                                      Theme.of(
                                        context,
                                      ).appBarTheme.titleTextStyle ??
                                      Theme.of(
                                        context,
                                      ).textTheme.titleLarge?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(
                                          context,
                                        ).appBarTheme.titleTextStyle?.color,
                                      ),
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                ),
                                Icon(
                                  Icons.arrow_drop_down,
                                  size: 22,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                : null,
          ),
          body: _buildBody(appState),
        );
      },
    );
  }

  Widget _buildBody(AppState appState) {
    if (appState.dashboardError != null) {
      return LuciErrorDisplay(
        title: 'Connection Failed',
        message:
            'Unable to connect to the router. Please check your network connection and router settings.',
        actionLabel: 'Retry Connection',
        onAction: () => appState.fetchDashboardData(),
        icon: Icons.wifi_off_rounded,
      );
    }

    if (appState.isDashboardLoading && appState.dashboardData == null) {
      return const LuciLoadingWidget();
    }

    if (appState.dashboardData == null) {
      return LuciEmptyState(
        title: 'No Data Available',
        message:
            'Unable to fetch dashboard data. Pull down to refresh or tap the button below.',
        icon: Icons.dashboard_outlined,
        actionLabel: 'Fetch Data',
        onAction: () => appState.fetchDashboardData(),
      );
    }

    return RefreshIndicator(
      onRefresh: () => appState.fetchDashboardData(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isLandscape =
              MediaQuery.of(context).orientation == Orientation.landscape;

          // Split layout handling to avoid Expanded widget conflicts with staggered animations
          if (isLandscape) {
            final landscapeContent = [
              const SizedBox(height: 16),
              _buildDeviceInfoCard(appState),
              const SizedBox(height: 12),
              SizedBox(
                height: 240,
                child: _buildRealtimeThroughputCard(appState),
              ),
              const SizedBox(height: 12),
              _buildSystemVitalsCard(appState),
              const SizedBox(height: 12),
              _buildWirelessNetworksCard(appState),
              const SizedBox(height: 12),
              _buildInterfaceStatusCards(appState),
              const SizedBox(height: 12),
            ];

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: SingleChildScrollView(
                child: LuciStaggeredAnimation(
                  staggerDelay: const Duration(milliseconds: 50),
                  children: landscapeContent,
                ),
              ),
            );
          } else {
            // Portrait mode: Split animations to avoid Expanded widget layout conflicts
            // Animate cards separately above and below the expandable chart
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Animate the top cards
                  LuciStaggeredAnimation(
                    staggerDelay: const Duration(milliseconds: 50),
                    children: [
                      const SizedBox(height: 16),
                      _buildDeviceInfoCard(appState),
                      const SizedBox(height: 12),
                    ],
                  ),
                  // Expanded chart (not animated to avoid layout issues)
                  Expanded(child: _buildRealtimeThroughputCard(appState)),
                  // Animate the bottom cards
                  LuciStaggeredAnimation(
                    staggerDelay: const Duration(
                      milliseconds: 40,
                    ), // Faster for bottom section
                    children: [
                      const SizedBox(height: 12),
                      _buildSystemVitalsCard(appState),
                      const SizedBox(height: 12),
                      _buildWirelessNetworksCard(appState),
                      const SizedBox(height: 12),
                      _buildInterfaceStatusCards(appState),
                      const SizedBox(height: 12),
                    ],
                  ),
                ],
              ),
            );
          }
        },
      ),
    );
  }
}
