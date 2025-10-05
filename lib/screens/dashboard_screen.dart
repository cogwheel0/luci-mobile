import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';
import 'package:luci_mobile/widgets/luci_animation_system.dart';
import 'package:luci_mobile/models/router.dart' as model;

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
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
      ref.read(appStateProvider).fetchDashboardData();
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

  String _deriveReleaseChannel(Map<String, dynamic>? release) {
    if (release == null || release.isEmpty) {
      return 'stable';
    }

    final buffer = StringBuffer();
    const keys = ['channel', 'branch', 'version', 'revision', 'description'];
    for (final key in keys) {
      final value = release[key];
      if (value == null) {
        continue;
      }
      buffer
        ..write(' ')
        ..write(value.toString().toLowerCase());
    }

    final combined = buffer.toString();

    if (combined.contains('snapshot')) {
      return 'snapshot';
    }
    if (combined.contains('beta')) {
      return 'beta';
    }
    if (combined.contains('rc')) {
      return 'rc';
    }
    if (combined.contains('testing')) {
      return 'testing';
    }

    return 'stable';
  }

  ({Color background, Color foreground}) _channelColors(String channel) {
    switch (channel) {
      case 'snapshot':
        return (
          background: Colors.orange.withValues(alpha: 0.15),
          foreground: Colors.orange.shade800,
        );
      case 'beta':
        return (
          background: Colors.blue.withValues(alpha: 0.15),
          foreground: Colors.blue.shade800,
        );
      case 'rc':
        return (
          background: Colors.purple.withValues(alpha: 0.15),
          foreground: Colors.purple.shade800,
        );
      case 'testing':
        return (
          background: Colors.amber.withValues(alpha: 0.18),
          foreground: Colors.amber.shade900,
        );
      default:
        return (
          background: Colors.green.withValues(alpha: 0.15),
          foreground: Colors.green.shade800,
        );
    }
  }

  Widget _buildDeviceInfoCard(AppState appState) {
    final boardInfo =
        appState.dashboardData?['boardInfo'] as Map<String, dynamic>?;
    final model = boardInfo?['model'] ?? 'N/A';
    final release = boardInfo?['release'] as Map<String, dynamic>?;
    final version = release?['version'] ?? 'N/A';
    final channel = _deriveReleaseChannel(release);
    final channelLabel = channel.toUpperCase();
    final channelColors = _channelColors(channel);

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
                          color: channelColors.background,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          channelLabel,
                          style: TextStyle(
                            color: channelColors.foreground,
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

  Widget _buildTitleWithTimestamp(String title, AppState appState) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildRealtimeThroughputCard(AppState appState) {
    final prefs = appState.dashboardPreferences;

    // Determine which throughput data to use
    List<double> rxHistory;
    List<double> txHistory;
    double currentRxRate;
    double currentTxRate;
    String throughputLabel = '';

    if (!prefs.showAllThroughput && prefs.primaryThroughputInterface != null) {
      // Use specific interface throughput
      final interface = prefs.primaryThroughputInterface!;
      rxHistory = appState.getRxHistoryForInterface(interface);
      txHistory = appState.getTxHistoryForInterface(interface);
      currentRxRate = appState.getCurrentRxRateForInterface(interface);
      currentTxRate = appState.getCurrentTxRateForInterface(interface);
      throughputLabel = ' - $interface';
    } else {
      // Use combined throughput
      rxHistory = appState.rxHistory;
      txHistory = appState.txHistory;
      currentRxRate = appState.currentRxRate;
      currentTxRate = appState.currentTxRate;
    }

    // Show loading state if we don't have any throughput data yet
    final hasValidData =
        rxHistory.isNotEmpty ||
        txHistory.isNotEmpty ||
        currentRxRate > 0 ||
        currentTxRate > 0; // Show data as soon as we have any throughput info
    // Only show switching state if we're loading AND no dashboard data is available (true router switch)
    final isSwitchingRouter =
        appState.isLoading && appState.dashboardData == null;

    final card = Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (throughputLabel.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Center(
                child: Text(
                  'Throughput$throughputLabel',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
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
                  isSwitchingRouter ? 0.0 : currentRxRate,
                ),
                _buildSpeedIndicator(
                  Icons.arrow_upward,
                  Colors.blue,
                  '',
                  isSwitchingRouter ? 0.0 : currentTxRate,
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
                            _buildLineChartBarData(rxHistory, [
                              Colors.green.shade700,
                              Colors.green.shade400,
                            ]),
                            _buildLineChartBarData(txHistory, [
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

    // Always return the card without fixed height - let parent control sizing
    return card;
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
    // Handle single data point case - show a flat line at that value
    if (data.length == 1) {
      return LineChartBarData(
        spots: [
          FlSpot(0, data[0]),
          FlSpot(1, data[0]), // Duplicate the point to create a flat line
        ],
        isCurved: false, // Don't curve a flat line
        gradient: LinearGradient(colors: gradientColors),
        barWidth: 3,
        isStrokeCapRound: true,
        dotData: FlDotData(
          show: true,
          getDotPainter: (spot, percent, barData, index) {
            return FlDotCirclePainter(
              radius: 3,
              color: gradientColors.first,
              strokeWidth: 0,
            );
          },
        ),
        belowBarData: BarAreaData(
          show: true,
          gradient: LinearGradient(
            colors: gradientColors
                .map((color) => color.withValues(alpha: 0.1))
                .toList(),
          ),
        ),
      );
    }

    // Don't show chart data if we don't have any data points
    if (data.isEmpty) {
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
    final prefs = appState.dashboardPreferences;
    final wirelessRadios =
        appState.dashboardData?['wireless'] as Map<String, dynamic>?;
    final uciWirelessConfig = appState.dashboardData?['uciWirelessConfig'];

    // Track which interfaces we've already added from runtime data
    final addedInterfaces = <String>{};

    List<Widget> networkCardWidgets = [];

    // First, add interfaces from runtime wireless data
    if (wirelessRadios != null) {
      wirelessRadios.forEach((radioName, radioData) {
        final interfaces = radioData['interfaces'] as List<dynamic>?;
        if (interfaces != null) {
          for (var interface in interfaces) {
            final config = interface['config'] ?? {};
            final iwinfo = interface['iwinfo'] ?? {};
            final ssid = iwinfo['ssid'] ?? config['ssid'] ?? 'N/A';
            if (ssid == 'N/A') continue;

            final deviceName = config['device'] ?? radioName;
            final interfaceId = '$ssid ($deviceName)';
            final uciName = interface['section'] as String?;

            if (uciName != null) {
              addedInterfaces.add(uciName);
            }

            // If preferences are not empty, check if this interface should be shown
            // Empty preferences means show all interfaces by default
            if (prefs.enabledWirelessInterfaces.isNotEmpty &&
                !prefs.enabledWirelessInterfaces.contains(interfaceId)) {
              continue; // Skip this interface
            }

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
                    final appState = ref.read(appStateProvider);
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
    }

    // Now add disabled interfaces from UCI config that aren't in runtime data
    if (uciWirelessConfig != null) {
      final uciValues = uciWirelessConfig['values'] as Map?;
      if (uciValues != null) {
        final uciRadios = <String, Map>{};
        final uciInterfaces = <String, Map>{};

        // Categorize UCI entries
        uciValues.forEach((key, value) {
          final typedValue = value as Map?;
          if (typedValue?['.type'] == 'wifi-device') {
            uciRadios[key] = typedValue!;
          } else if (typedValue?['.type'] == 'wifi-iface') {
            uciInterfaces[key] = typedValue!;
          }
        });

        // Add interfaces that aren't in runtime data
        uciInterfaces.forEach((uciName, config) {
          if (!addedInterfaces.contains(uciName)) {
            final ssid = config['ssid'] ?? 'Unnamed';
            final device = config['device'] ?? '';
            final interfaceId = '$ssid ($device)';

            // Check if this interface should be shown based on preferences
            if (prefs.enabledWirelessInterfaces.isNotEmpty &&
                !prefs.enabledWirelessInterfaces.contains(interfaceId)) {
              return; // Skip this interface
            }

            final isRadioEnabled = uciRadios[device]?['disabled'] != '1';
            final isIfaceEnabled = config['disabled'] != '1';
            final isEnabled = isRadioEnabled && isIfaceEnabled;

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
                    final appState = ref.read(appStateProvider);
                    appState.requestTab(2, interfaceToScroll: device);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: _buildWirelessInfoCardContent(
                      context,
                      ssid: ssid,
                      isEnabled: isEnabled,
                      signal: null, // No signal for disabled interfaces
                      channel: config['channel']?.toString() ?? 'N/A',
                    ),
                  ),
                ),
              ),
            );
          }
        });
      }
    }

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

  IconData _getInterfaceIcon(String name, String proto) {
    final lower = name.toLowerCase();

    // Check name-based patterns first
    if (lower.contains('wan')) {
      return Icons.public_rounded;
    }
    if (lower.contains('lan')) {
      return Icons.router_rounded;
    }
    if (lower.contains('iot')) {
      return Icons.sensors_rounded;
    }
    if (lower.contains('guest')) {
      return Icons.people_rounded;
    }
    if (lower.contains('dmz')) {
      return Icons.security_rounded;
    }
    if (lower.contains('docker')) {
      return Icons.computer_rounded;
    }
    if (lower.contains('bridge') || lower.startsWith('br-')) {
      return Icons.hub_rounded;
    }
    if (lower.contains('vlan')) {
      return Icons.layers_rounded;
    }
    if (lower.startsWith('eth')) {
      return Icons.cable_rounded;
    }
    if (lower.startsWith('wlan')) {
      return Icons.wifi_rounded;
    }

    // Check protocol-based patterns
    switch (proto) {
      case 'wireguard':
      case 'openvpn':
        return Icons.vpn_key_rounded;
      case 'pppoe':
        return Icons.settings_ethernet_rounded;
      case 'dhcp':
      case 'static':
        return Icons.lan_rounded;
      default:
        return Icons.lan_rounded;
    }
  }

  Widget _buildInterfaceStatusCards(AppState appState) {
    final prefs = appState.dashboardPreferences;
    final interfaces =
        appState.dashboardData?['interfaceDump']?['interface']
            as List<dynamic>?;
    if (interfaces == null || interfaces.isEmpty) {
      return const SizedBox.shrink();
    }

    final wanVpnInterfaces = interfaces.where((item) {
      final interface = item as Map<String, dynamic>;
      final name = interface['interface'] as String? ?? '';

      // Skip loopback interface
      if (name == 'loopback' || name == 'lo') return false;

      // If preferences are empty, show all interfaces by default
      if (prefs.enabledWiredInterfaces.isEmpty) {
        return true; // Show all interfaces when no specific preferences
      }

      // Otherwise, check if this interface is in the enabled list
      return prefs.enabledWiredInterfaces.contains(name);
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
              final appState = ref.read(appStateProvider);
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
                    _getInterfaceIcon(name, proto),
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
    final appState = ref.watch(appStateProvider);
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
        title: null, // Always use titleWidget now
        titleWidget: routers.length > 1
            ? Center(
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLowest,
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                          borderRadius: BorderRadius.circular(
                                            2,
                                          ),
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
                                      final isSelected = r.id == selected?.id;
                                      String routerTitle;
                                      bool isStale = false;
                                      if (isSelected && boardInfo != null) {
                                        final hostname = boardInfo['hostname']
                                            ?.toString();
                                        routerTitle =
                                            (hostname != null &&
                                                hostname.isNotEmpty)
                                            ? hostname
                                            : (r.lastKnownHostname ??
                                                  r.ipAddress);
                                      } else if (r.lastKnownHostname != null &&
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
                                              : Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
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
                                                  fontWeight: FontWeight.bold,
                                                  color: isStale
                                                      ? Theme.of(context)
                                                            .colorScheme
                                                            .onSurfaceVariant
                                                            .withValues(
                                                              alpha: 0.7,
                                                            )
                                                      : Theme.of(
                                                          context,
                                                        ).colorScheme.onSurface,
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
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
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
                            selectedId != selected?.id &&
                            context.mounted) {
                          await appState.selectRouter(
                            selectedId,
                            context: context,
                          );
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(
                          left: 16.0,
                          right: 8.0,
                          top: 4.0,
                          bottom: 4.0,
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
                            const SizedBox(width: 2),
                            Icon(
                              Icons.arrow_drop_down,
                              size: 20,
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
            : _buildTitleWithTimestamp(headerText, appState),
      ),
      body: Stack(children: [_buildBody(appState)]),
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
              // Extra padding to ensure scroll behavior for RefreshIndicator
              const SizedBox(height: 100),
            ];

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: LuciStaggeredAnimation(
                  staggerDelay: const Duration(milliseconds: 50),
                  children: landscapeContent,
                ),
              ),
            );
          } else {
            // Portrait mode: Fill available height exactly without scrolling
            return LayoutBuilder(
              builder: (context, constraints) {
                return RefreshIndicator(
                  onRefresh: () => appState.fetchDashboardData(),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: SizedBox(
                      height: constraints.maxHeight,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 16),
                            _buildDeviceInfoCard(appState),
                            const SizedBox(height: 12),
                            Expanded(
                              child: _buildRealtimeThroughputCard(appState),
                            ),
                            const SizedBox(height: 12),
                            _buildSystemVitalsCard(appState),
                            const SizedBox(height: 12),
                            _buildWirelessNetworksCard(appState),
                            const SizedBox(height: 12),
                            _buildInterfaceStatusCards(appState),
                            const SizedBox(height: 12),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          }
        },
      ),
    );
  }
}
