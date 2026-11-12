import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/models/wifi_scan_result.dart';
import 'package:luci_mobile/design/luci_design_system.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:luci_mobile/widgets/platform_ui/platform_ui.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';

String _signalStrength(BuildContext context, int signal) {
  if (signal >= -50) return context.l10n.excellent;
  if (signal >= -60) return context.l10n.good;
  if (signal >= -70) return context.l10n.fair;
  if (signal >= -80) return context.l10n.weak;
  return context.l10n.veryWeak;
}

String _encryptionLabel(BuildContext context, WifiEncryption encryption) =>
    encryption.isOpen ? context.l10n.open : encryption.shortLabel;

String _encryptionDescription(
  BuildContext context,
  WifiEncryption encryption,
) => encryption.isOpen ? context.l10n.encryptionNone : encryption.description;

class WifiScanScreen extends ConsumerStatefulWidget {
  const WifiScanScreen({super.key});

  @override
  ConsumerState<WifiScanScreen> createState() => _WifiScanScreenState();
}

class _WifiScanScreenState extends ConsumerState<WifiScanScreen>
    with SingleTickerProviderStateMixin {
  List<WifiScanResult> _scanResults = [];
  bool _isScanning = false;
  bool _isRestarting = false;
  String? _error;
  String? _selectedRadio; // radioName key (e.g., 'radio0')
  List<Map<String, String>> _radioDevices = [];
  late AnimationController _pulseController;
  AppState? _appState;
  // Scan generation counter — incremented whenever a scan is cancelled or
  // superseded. Completions from older generations are ignored.
  int _scanGeneration = 0;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadRadioDevices();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _appState ??= ref.read(appStateProvider);
  }

  @override
  void dispose() {
    // Invalidate any in-flight scan so it cannot update state after disposal.
    _scanGeneration++;
    _appState?.cancelWirelessScan();
    _pulseController.dispose();
    super.dispose();
  }

  void _loadRadioDevices() {
    if (!mounted) return;
    final appState = ref.read(appStateProvider);
    final devices = appState.getAvailableRadioDevices();
    setState(() {
      _radioDevices = devices;
      if (devices.isNotEmpty) {
        _selectedRadio = devices.first['radioName'];
      }
    });
  }

  /// Get the interface name to use for scanning based on selected radio
  String? get _selectedIfname {
    if (_selectedRadio == null) return null;
    final device = _radioDevices.firstWhere(
      (d) => d['radioName'] == _selectedRadio,
      orElse: () => {},
    );
    return device['ifname'];
  }

  Future<void> _startScan() async {
    final ifname = _selectedIfname;
    if (ifname == null) return;

    // Increment generation to invalidate any previous in-flight scan.
    final generation = ++_scanGeneration;

    setState(() {
      _isScanning = true;
      _error = null;
      _scanResults = [];
    });
    _pulseController.repeat();

    try {
      final appState = ref.read(appStateProvider);
      final results = await appState.scanWirelessNetworks(
        device: ifname,
        context: context,
      );

      // Discard if a newer scan was started or this one was cancelled.
      if (!mounted || generation != _scanGeneration) return;
      setState(() {
        _scanResults = results;
        _isScanning = false;
        if (results.isEmpty) {
          _error = context.l10n.noNetworksFound;
        }
      });
    } catch (e) {
      if (!mounted || generation != _scanGeneration) return;
      setState(() {
        _isScanning = false;
        _error = context.l10n.scanFailed(e);
      });
    }
    if (mounted && generation == _scanGeneration) {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  void _stopScan() {
    // Invalidate current generation before cancelling so the awaited future
    // is ignored even if it completes before the cancel takes effect.
    _scanGeneration++;
    final appState = ref.read(appStateProvider);
    appState.cancelWirelessScan();
    setState(() {
      _isScanning = false;
    });
    _pulseController.stop();
    _pulseController.reset();
  }

  Future<void> _restartRadio() async {
    if (_selectedRadio == null || _isRestarting) return;

    setState(() {
      _isRestarting = true;
      _error = null;
    });

    try {
      final appState = ref.read(appStateProvider);
      final success = await appState.restartWirelessRadio(
        _selectedRadio!,
        context: context,
      );

      if (!mounted) return;
      setState(() => _isRestarting = false);

      if (success) {
        AdaptiveSnackBar.show(
          context,
          message: context.l10n.radioRestarted(_selectedRadio!),
          type: AdaptiveSnackBarType.success,
          duration: const Duration(seconds: 3),
        );
        _loadRadioDevices();
      } else {
        AdaptiveSnackBar.show(
          context,
          message: context.l10n.radioRestartFailed,
          type: AdaptiveSnackBarType.error,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isRestarting = false;
        _error = context.l10n.restartFailed(e);
      });
    }
  }

  void _showConnectDialog(WifiScanResult network) {
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
      builder: (context) => _ConnectBottomSheet(
        network: network,
        radioDevices: _radioDevices,
        selectedDevice: _selectedRadio,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: LuciAppBar(
        title: context.l10n.wifiScanner,
        showBack: true,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Device selector and scan button
          _buildControlBar(theme, colorScheme),

          // Results area
          Expanded(
            child: _isScanning
                ? _buildScanningIndicator(theme, colorScheme)
                : _scanResults.isEmpty
                ? _buildEmptyState(theme, colorScheme)
                : _buildResultsList(theme, colorScheme),
          ),
        ],
      ),
    );
  }

  /// The radio as an iOS picker row, filled as the buttons under it are:
  /// the system pull-down menu from iOS 26, an action sheet before, each
  /// radio with the network it serves.
  Widget _iosRadioPicker(BuildContext context) {
    final l10n = context.l10n;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CupertinoColors.tertiarySystemFill.resolveFrom(context),
        borderRadius: BorderRadius.circular(adaptiveFormCornerRadius),
      ),
      child: AdaptiveFormPicker<String>(
        label: l10n.radio,
        value: _selectedRadio,
        hint: l10n.selectRadio,
        choices: [
          for (final device in _radioDevices)
            if (device['radioName'] case final radioName?)
              AdaptiveFormChoice(
                radioName,
                switch (device['band']) {
                  final band? when band.isNotEmpty => '$radioName ($band)',
                  _ => radioName,
                },
                subtitle: switch (device['ssid']) {
                  final ssid? when ssid.isNotEmpty && ssid != radioName => ssid,
                  _ => null,
                },
              ),
        ],
        onChanged: _isScanning || _isRestarting
            ? null
            : (value) => setState(() => _selectedRadio = value),
      ),
    );
  }

  Widget _buildControlBar(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        LuciSpacing.md,
        LuciSpacing.sm,
        LuciSpacing.md,
        LuciSpacing.md,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Radio device selector (full width)
          if (PlatformUiCapabilities.isIOS)
            _iosRadioPicker(context)
          else
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
                  value: _selectedRadio,
                  isExpanded: true,
                  icon: Icon(
                    Icons.arrow_drop_down,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  hint: Text(
                    context.l10n.selectRadio,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  items: _radioDevices.map((device) {
                    final radioName = device['radioName'] ?? '';
                    final ssid = device['ssid'] ?? '';
                    final band = device['band'] ?? '';
                    final label = band.isNotEmpty
                        ? '$radioName ($band)'
                        : radioName;
                    final subtitle = ssid != radioName && ssid.isNotEmpty
                        ? ssid
                        : null;
                    return DropdownMenuItem<String>(
                      value: radioName,
                      child: Row(
                        children: [
                          Icon(
                            Icons.router,
                            size: 18,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  label,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium,
                                ),
                                if (subtitle != null)
                                  Text(
                                    subtitle,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (_isScanning || _isRestarting)
                      ? null
                      : (value) {
                          setState(() {
                            _selectedRadio = value;
                          });
                        },
                ),
              ),
            ),
          const SizedBox(height: 10),
          // Scan + Restart Radio buttons row
          Row(
            children: [
              // Scan / Stop button
              Expanded(
                // Text only on iOS: at its label size, a symbol leaves half
                // the row too narrow for "Scan Networks".
                child: _isScanning
                    ? AdaptiveButton(
                        onPressed: _stopScan,
                        label: context.l10n.stopScan,
                        materialIcon: Icons.stop,
                        style: AdaptiveButtonStyle.bordered,
                        color: colorScheme.error.withValues(alpha: 0.5),
                        textColor: colorScheme.error,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        borderRadius: BorderRadius.circular(12),
                        useSmoothRectangleBorder: false,
                      )
                    : AdaptiveButton(
                        onPressed: _isRestarting || _selectedRadio == null
                            ? null
                            : _startScan,
                        label: context.l10n.scanNetworks,
                        materialIcon: Icons.radar,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        borderRadius: BorderRadius.circular(12),
                        useSmoothRectangleBorder: false,
                      ),
              ),
              const SizedBox(width: 10),
              // Restart Radio button
              Expanded(
                child: AdaptiveButton(
                  onPressed:
                      _isScanning || _isRestarting || _selectedRadio == null
                      ? null
                      : _restartRadio,
                  busy: _isRestarting,
                  label: _isRestarting
                      ? context.l10n.restarting
                      : context.l10n.restartRadio,
                  materialIcon: Icons.restart_alt,
                  style: AdaptiveButtonStyle.bordered,
                  color: colorScheme.primary.withValues(alpha: 0.5),
                  textColor: colorScheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  borderRadius: BorderRadius.circular(12),
                  useSmoothRectangleBorder: false,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScanningIndicator(ThemeData theme, ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  // Outer pulse ring
                  Transform.scale(
                    scale: 1.0 + (_pulseController.value * 0.6),
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: colorScheme.primary.withValues(
                            alpha: 0.3 * (1.0 - _pulseController.value),
                          ),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                  // Middle pulse ring
                  Transform.scale(
                    scale: 1.0 + (_pulseController.value * 0.35),
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: colorScheme.primary.withValues(
                            alpha: 0.5 * (1.0 - _pulseController.value),
                          ),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                  // Center icon
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colorScheme.primaryContainer.withValues(
                        alpha: 0.3,
                      ),
                    ),
                    child: Icon(
                      Icons.radar,
                      size: 40,
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: LuciSpacing.lg),
          Text(
            context.l10n.scanningNetworks,
            style: theme.textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: LuciSpacing.sm),
          Text(
            context.l10n.scanWaitMessage,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme, ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.wifi_find,
            size: 64,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(height: LuciSpacing.md),
          Text(
            _error ?? context.l10n.scanEmptyMessage,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: _error != null
                  ? colorScheme.error
                  : colorScheme.onSurfaceVariant,
            ),
          ),
          if (_radioDevices.isEmpty) ...[
            const SizedBox(height: LuciSpacing.md),
            Text(
              context.l10n.noWirelessRadios,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResultsList(ThemeData theme, ColorScheme colorScheme) {
    // Separate networks with SSIDs from hidden ones
    final visibleNetworks = _scanResults
        .where((r) => r.ssid.isNotEmpty)
        .toList();
    final hiddenNetworks = _scanResults.where((r) => r.ssid.isEmpty).toList();

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: LuciSpacing.sm),
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: LuciSpacing.md,
            vertical: LuciSpacing.sm,
          ),
          child: Row(
            children: [
              Text(
                context.l10n.availableNetworks,
                style: LuciTextStyles.sectionHeader(context),
              ),
              const Spacer(),
              Text(
                context.l10n.networksFound(_scanResults.length),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),

        // Visible networks
        ...visibleNetworks.map(
          (network) => _WifiNetworkTile(
            network: network,
            onTap: () => _showConnectDialog(network),
          ),
        ),

        // Hidden networks section
        if (hiddenNetworks.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              LuciSpacing.md,
              LuciSpacing.md,
              LuciSpacing.md,
              LuciSpacing.sm,
            ),
            child: Text(
              context.l10n.hiddenNetworks,
              style: LuciTextStyles.sectionHeader(context),
            ),
          ),
          ...hiddenNetworks.map(
            (network) => _WifiNetworkTile(
              network: network,
              onTap: () => _showConnectDialog(network),
            ),
          ),
        ],
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// WiFi Network List Tile
// ──────────────────────────────────────────────────────────────────

class _WifiNetworkTile extends StatelessWidget {
  final WifiScanResult network;
  final VoidCallback onTap;

  const _WifiNetworkTile({required this.network, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final signalColor = _getSignalColor(colorScheme);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: LuciSpacing.md,
        vertical: 4,
      ),
      child: Card(
        elevation: 1,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: LuciCardStyles.standardRadius,
          side: BorderSide(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.10),
            width: 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: LuciCardStyles.standardRadius,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: LuciSpacing.md,
              vertical: 12,
            ),
            child: Row(
              children: [
                // Signal strength icon
                _SignalIcon(
                  bars: network.signalBars,
                  color: signalColor,
                  hasLock: network.encryption.enabled,
                ),
                const SizedBox(width: 14),

                // Network info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        network.ssid.isNotEmpty
                            ? network.ssid
                            : context.l10n.hiddenNetwork,
                        style: LuciTextStyles.cardTitle(context).copyWith(
                          fontStyle: network.ssid.isEmpty
                              ? FontStyle.italic
                              : FontStyle.normal,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        context.l10n.networkSummary(
                          network.band,
                          network.channel,
                          network.signal,
                        ),
                        style: LuciTextStyles.cardSubtitle(context),
                      ),
                    ],
                  ),
                ),

                // Encryption badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: network.encryption.isOpen
                        ? colorScheme.errorContainer.withValues(alpha: 0.3)
                        : colorScheme.primaryContainer.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _encryptionLabel(context, network.encryption),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: network.encryption.isOpen
                          ? colorScheme.error
                          : colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),

                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _getSignalColor(ColorScheme colorScheme) {
    if (network.signal >= -50) return Colors.green;
    if (network.signal >= -60) return Colors.lightGreen;
    if (network.signal >= -70) return Colors.orange;
    if (network.signal >= -80) return Colors.deepOrange;
    return colorScheme.error;
  }
}

// ──────────────────────────────────────────────────────────────────
// Signal strength icon with bars
// ──────────────────────────────────────────────────────────────────

class _SignalIcon extends StatelessWidget {
  final int bars;
  final Color color;
  final bool hasLock;

  const _SignalIcon({
    required this.bars,
    required this.color,
    required this.hasLock,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 36,
      height: 36,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
          ),
          // Use built-in WiFi icons based on signal level
          Icon(_getWifiIcon(), size: 22, color: color),
          // Lock indicator
          if (hasLock)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.lock,
                  size: 10,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  IconData _getWifiIcon() {
    switch (bars) {
      case 4:
        return Icons.wifi;
      case 3:
        return Icons.wifi;
      case 2:
        return Icons.wifi_2_bar;
      case 1:
        return Icons.wifi_1_bar;
      default:
        return Icons.wifi_1_bar;
    }
  }
}

// ──────────────────────────────────────────────────────────────────
// Connect Bottom Sheet
// ──────────────────────────────────────────────────────────────────

class _ConnectBottomSheet extends ConsumerStatefulWidget {
  final WifiScanResult network;
  final List<Map<String, String>> radioDevices;
  final String? selectedDevice;

  const _ConnectBottomSheet({
    required this.network,
    required this.radioDevices,
    this.selectedDevice,
  });

  @override
  ConsumerState<_ConnectBottomSheet> createState() =>
      _ConnectBottomSheetState();
}

class _ConnectBottomSheetState extends ConsumerState<_ConnectBottomSheet> {
  final _passwordController = TextEditingController();
  final _hiddenSsidController = TextEditingController();
  bool _obscurePassword = true;
  bool _isConnecting = false;
  String? _selectedRadio;
  String? _error;

  bool get _isHidden => widget.network.ssid.isEmpty;

  @override
  void initState() {
    super.initState();
    // Default to the radio that was used for scanning
    if (widget.selectedDevice != null && widget.radioDevices.isNotEmpty) {
      // selectedDevice is now a radioName directly
      _selectedRadio = widget.selectedDevice;
    } else if (widget.radioDevices.isNotEmpty) {
      _selectedRadio = widget.radioDevices.first['radioName'];
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _hiddenSsidController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (_selectedRadio == null) {
      setState(() {
        _error = context.l10n.radioRequired;
      });
      return;
    }

    // For hidden networks, an SSID must be entered by the user.
    if (_isHidden && _hiddenSsidController.text.trim().isEmpty) {
      setState(() {
        _error = context.l10n.ssidRequired;
      });
      return;
    }

    // Block unsupported enterprise networks.
    if (widget.network.encryption.isEnterprise) {
      setState(() {
        _error = context.l10n.enterpriseNetworkUnsupported;
      });
      return;
    }

    if (widget.network.encryption.requiresPassword &&
        _passwordController.text.isEmpty) {
      setState(() {
        _error = context.l10n.networkPasswordRequired;
      });
      return;
    }

    // WPA2 requires minimum 8 characters
    if (widget.network.encryption.requiresPassword &&
        !widget.network.encryption.wep &&
        _passwordController.text.length < 8) {
      setState(() {
        _error = context.l10n.passwordLengthError;
      });
      return;
    }

    setState(() {
      _isConnecting = true;
      _error = null;
    });

    // Use the entered SSID for hidden networks; otherwise use the scanned SSID.
    final ssid = _isHidden
        ? _hiddenSsidController.text.trim()
        : widget.network.ssid;

    final appState = ref.read(appStateProvider);
    final success = await appState.connectToWirelessNetwork(
      radioDevice: _selectedRadio!,
      ssid: ssid,
      encryption: widget.network.encryption.openwrtEncryption,
      password: _passwordController.text,
      bssid: widget.network.bssid,
      context: context,
    );

    if (!mounted) return;

    if (success) {
      // This sheet closes before the report shows.
      final report = AdaptiveSnackBar.reporter(context);
      final message = context.l10n.connectingToNetwork(ssid);
      Navigator.of(context).pop();
      report.show(message: message, type: AdaptiveSnackBarType.success);
    } else {
      setState(() {
        _isConnecting = false;
        _error = context.l10n.networkConnectFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final network = widget.network;
    final title = network.ssid.isNotEmpty
        ? network.ssid
        : context.l10n.hiddenNetwork;
    final summary =
        '${_encryptionLabel(context, network.encryption)} • ${network.band} • ${context.l10n.channelShort(network.channel.toString())}';

    if (PlatformUiCapabilities.isIOS) {
      // As iOS asks for a network's password: Cancel and Connect in the
      // sheet's navigation bar, over the network's details.
      return AdaptiveFormSheet(
        title: title,
        subtitle: summary,
        cancelLabel: context.l10n.cancel,
        confirmLabel: context.l10n.connect,
        onConfirm: _connect,
        busy: _isConnecting,
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
          padding: const EdgeInsets.fromLTRB(
            LuciSpacing.lg,
            LuciSpacing.md,
            LuciSpacing.lg,
            LuciSpacing.lg,
          ),
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
              const SizedBox(height: LuciSpacing.lg),

              // Network header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer.withValues(
                        alpha: 0.3,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.wifi,
                      color: colorScheme.primary,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: LuciSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          summary,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: LuciSpacing.lg),

              ..._form(context),

              const SizedBox(height: LuciSpacing.lg),

              // Connect button
              SizedBox(
                width: double.infinity,
                child: AdaptiveButton(
                  onPressed: _isConnecting ? null : _connect,
                  busy: _isConnecting,
                  label: _isConnecting
                      ? context.l10n.connecting
                      : context.l10n.connect,
                  sfSymbol: const SFSymbol('wifi'),
                  materialIcon: Icons.wifi,
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

              const SizedBox(height: LuciSpacing.sm),
            ],
          ),
        ),
      ),
    );
  }

  /// The network's details, then what connecting to it needs, as iOS
  /// groups a form; what went wrong and the station-mode warning sit under
  /// the second group.
  Widget _iosForm(BuildContext context) {
    final l10n = context.l10n;
    final network = widget.network;
    return AdaptiveForm(
      sections: [
        AdaptiveFormSection(
          children: [
            AdaptiveFormValueRow(label: l10n.bssid, value: network.bssid),
            AdaptiveFormValueRow(
              label: l10n.signal,
              value:
                  '${network.signal} dBm (${_signalStrength(context, network.signal)})',
            ),
            AdaptiveFormValueRow(
              label: l10n.encryption,
              value: _encryptionDescription(context, network.encryption),
            ),
          ],
        ),
        AdaptiveFormSection(
          error: _error,
          footer: l10n.stationModeWarning,
          children: [
            AdaptiveFormPicker<String>(
              label: l10n.connectUsingRadio,
              value: _selectedRadio,
              choices: [
                for (final device in widget.radioDevices)
                  AdaptiveFormChoice(
                    device['radioName'] ?? '',
                    (device['band'] ?? '').isNotEmpty
                        ? '${device['radioName']} (${device['band']})'
                        : device['radioName'] ?? '',
                  ),
              ],
              onChanged: _isConnecting
                  ? null
                  : (value) => setState(() => _selectedRadio = value),
            ),
            if (_isHidden)
              AdaptiveFormTextField(
                label: l10n.networkNameSsid,
                controller: _hiddenSsidController,
                enabled: !_isConnecting,
                placeholder: l10n.enterHiddenNetworkName,
              ),
            if (network.encryption.requiresPassword)
              AdaptiveFormTextField(
                label: l10n.passwordLabel,
                controller: _passwordController,
                obscureText: _obscurePassword,
                enabled: !_isConnecting,
                placeholder: l10n.enterNetworkPassword,
                textInputAction: TextInputAction.go,
                onSubmitted: (_) => _connect(),
                suffix: AdaptiveObscureToggle(
                  obscured: _obscurePassword,
                  semanticLabel: _obscurePassword
                      ? l10n.showPassword
                      : l10n.hidePassword,
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// The network's details and what connecting to it needs.
  List<Widget> _form(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final network = widget.network;
    return [
      // Network details
      _buildInfoRow(
        context,
        context.l10n.bssid,
        network.bssid,
        Icons.router_outlined,
      ),
      _buildInfoRow(
        context,
        context.l10n.signal,
        '${network.signal} dBm (${_signalStrength(context, network.signal)})',
        Icons.signal_cellular_alt,
      ),
      _buildInfoRow(
        context,
        context.l10n.encryption,
        _encryptionDescription(context, network.encryption),
        Icons.security,
      ),

      const SizedBox(height: LuciSpacing.lg),
      Divider(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      const SizedBox(height: LuciSpacing.md),

      // Radio selector
      Text(
        context.l10n.connectUsingRadio,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: LuciSpacing.sm),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.outline.withValues(alpha: 0.3)),
          color: colorScheme.surfaceContainerLow,
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _selectedRadio,
            isExpanded: true,
            icon: Icon(
              Icons.arrow_drop_down,
              color: colorScheme.onSurfaceVariant,
            ),
            items: widget.radioDevices.map((device) {
              final radioName = device['radioName'] ?? '';
              final band = device['band'] ?? '';
              final label = band.isNotEmpty ? '$radioName ($band)' : radioName;
              return DropdownMenuItem<String>(
                value: device['radioName'],
                child: Text(label, style: theme.textTheme.bodyMedium),
              );
            }).toList(),
            onChanged: _isConnecting
                ? null
                : (value) {
                    setState(() {
                      _selectedRadio = value;
                    });
                  },
          ),
        ),
      ),

      // Hidden network SSID field
      if (_isHidden) ...[
        const SizedBox(height: LuciSpacing.md),
        Text(
          context.l10n.networkNameSsid,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: LuciSpacing.sm),
        TextField(
          controller: _hiddenSsidController,
          enabled: !_isConnecting,
          decoration: InputDecoration(
            hintText: context.l10n.enterHiddenNetworkName,
            prefixIcon: const Icon(Icons.wifi_find),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: colorScheme.outline.withValues(alpha: 0.3),
              ),
            ),
          ),
        ),
      ],

      // Password field (only for encrypted networks)
      if (network.encryption.requiresPassword) ...[
        const SizedBox(height: LuciSpacing.md),
        Text(
          context.l10n.passwordLabel,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: LuciSpacing.sm),
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          enabled: !_isConnecting,
          decoration: InputDecoration(
            hintText: context.l10n.enterNetworkPassword,
            prefixIcon: const Icon(Icons.key),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off : Icons.visibility,
              ),
              onPressed: () {
                setState(() {
                  _obscurePassword = !_obscurePassword;
                });
              },
            ),
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
          ),
          onSubmitted: (_) => _connect(),
        ),
      ],

      // Error message
      if (_error != null) ...[
        const SizedBox(height: LuciSpacing.sm),
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

      const SizedBox(height: LuciSpacing.lg),

      // Warning for station mode
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
                context.l10n.stationModeWarning,
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

  Widget _buildInfoRow(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          SizedBox(
            width: 80,
            child: Text(label, style: LuciTextStyles.detailLabel(context)),
          ),
          Expanded(
            child: Text(
              value,
              style: LuciTextStyles.detailValue(context),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
