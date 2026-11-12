import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/models/dashboard_preferences.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';
import 'package:luci_mobile/design/luci_design_system.dart';
import 'package:luci_mobile/widgets/luci_animation_system.dart';
import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:luci_mobile/widgets/platform_ui/platform_ui.dart';

class RouterDashboardSettingsScreen extends ConsumerStatefulWidget {
  final String routerId;
  const RouterDashboardSettingsScreen({super.key, required this.routerId});

  @override
  ConsumerState<RouterDashboardSettingsScreen> createState() =>
      _RouterDashboardSettingsScreenState();
}

class _RouterDashboardSettingsScreenState
    extends ConsumerState<RouterDashboardSettingsScreen> {
  late DashboardPreferences _preferences;
  bool _isLoading = true;
  String? _errorMessage;
  final Set<String> _availableWirelessInterfaces = {};
  final Set<String> _availableWiredInterfaces = {};
  final List<String> _allInterfaces = [];
  Timer? _autoSaveTimer;

  void _scheduleAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(milliseconds: 300), () async {
      final appState = ref.read(appStateProvider);
      try {
        await appState.saveDashboardPreferences(_preferences);
      } catch (_) {}
    });
  }

  @override
  void initState() {
    super.initState();
    // Ensure the selected router matches the requested router
    final appState = ref.read(appStateProvider);
    final current = appState.selectedRouter?.id;
    Future(() async {
      if (current != widget.routerId) {
        await appState.selectRouter(widget.routerId);
      }
      await _loadPreferences();
    });
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    try {
      final appState = ref.read(appStateProvider);
      if (appState.dashboardData == null) {
        await appState.fetchDashboardData();
      }
      if (!mounted) return;
      if (appState.dashboardData == null) {
        setState(() {
          _errorMessage = context.l10n.unableToLoadDashboardData;
          _isLoading = false;
        });
        return;
      }
      _preferences = appState.dashboardPreferences;
      _extractAvailableInterfaces(appState.dashboardData);
      setState(() => _isLoading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = context.l10n.failedToLoadSettings(e);
        _isLoading = false;
      });
    }
  }

  void _extractAvailableInterfaces(Map<String, dynamic>? dashboardData) {
    if (dashboardData == null) return;

    final wirelessRadios = dashboardData['wireless'] as Map<String, dynamic>?;
    if (wirelessRadios != null) {
      wirelessRadios.forEach((radioName, radioData) {
        final interfaces = radioData['interfaces'] as List<dynamic>?;
        if (interfaces != null) {
          for (var interface in interfaces) {
            final config = interface['config'] ?? {};
            final iwinfo = interface['iwinfo'] ?? {};
            final ssid = iwinfo['ssid'] ?? config['ssid'];
            final deviceName = config['device'] ?? radioName;
            if (ssid != null && ssid.toString().isNotEmpty) {
              final interfaceId = '$ssid ($deviceName)';
              _availableWirelessInterfaces.add(interfaceId);
              _allInterfaces.add(interfaceId);
            }
          }
        }
      });
    }

    final interfaces =
        dashboardData['interfaceDump']?['interface'] as List<dynamic>?;
    if (interfaces != null) {
      for (var item in interfaces) {
        final interface = item as Map<String, dynamic>;
        final name = interface['interface'] as String? ?? '';
        if (name.isNotEmpty && name != 'loopback' && name != 'lo') {
          _availableWiredInterfaces.add(name);
          _allInterfaces.add(name);
        }
      }
    }
    _allInterfaces.sort();
  }

  void _onPreferenceChanged() => _scheduleAutoSave();

  /// Throughput for every interface, or for one, the first by default.
  void _setShowAllThroughput(bool all, List<String> interfaces) {
    setState(() {
      _preferences = all
          ? _preferences.copyWith(
              showAllThroughput: true,
              primaryThroughputInterface: null,
            )
          : _preferences.copyWith(
              showAllThroughput: false,
              primaryThroughputInterface: interfaces.isNotEmpty
                  ? interfaces.first
                  : null,
            );
    });
    _onPreferenceChanged();
  }

  void _setPrimaryThroughput(String? interface) {
    setState(() {
      _preferences = _preferences.copyWith(
        showAllThroughput: false,
        primaryThroughputInterface: interface,
      );
    });
    _onPreferenceChanged();
  }

  /// Every wireless network, or a choice of them, all at first.
  void _setShowAllWireless(bool all) {
    setState(() {
      _preferences = _preferences.copyWith(
        enabledWirelessInterfaces: all
            ? {}
            : Set.from(_availableWirelessInterfaces),
      );
    });
    _onPreferenceChanged();
  }

  void _setWireless(String interface, bool shown) {
    setState(() {
      final next = Set<String>.from(_preferences.enabledWirelessInterfaces);
      shown ? next.add(interface) : next.remove(interface);
      _preferences = _preferences.copyWith(enabledWirelessInterfaces: next);
    });
    _onPreferenceChanged();
  }

  /// Every wired interface, or a choice of them, all at first.
  void _setShowAllWired(bool all) {
    setState(() {
      _preferences = _preferences.copyWith(
        enabledWiredInterfaces: all ? {} : Set.from(_availableWiredInterfaces),
      );
    });
    _onPreferenceChanged();
  }

  void _setWired(String interface, bool shown) {
    setState(() {
      final next = Set<String>.from(_preferences.enabledWiredInterfaces);
      shown ? next.add(interface) : next.remove(interface);
      _preferences = _preferences.copyWith(enabledWiredInterfaces: next);
    });
    _onPreferenceChanged();
  }

  /// The settings as iOS Settings lays them out: a group per part, its
  /// description under it, a switch to show everything, and otherwise the
  /// interfaces as rows to check, one for throughput and any for the rest.
  List<Widget> _iosSections() {
    final l10n = context.l10n;
    final throughput = _availableWiredInterfaces.toList()..sort();
    final wireless = _availableWirelessInterfaces.toList()..sort();
    final wired = _availableWiredInterfaces.toList()..sort();
    return [
      AdaptiveFormSection(
        header: l10n.throughputMonitoring,
        footer: l10n.throughputMonitoringDescription,
        children: [
          AdaptiveFormSwitch(
            label: l10n.showAllInterfaces,
            value: _preferences.showAllThroughput,
            onChanged: (all) => _setShowAllThroughput(all, throughput),
          ),
          if (!_preferences.showAllThroughput)
            for (final iface in throughput)
              AdaptiveListRow(
                title: iface,
                selected: _preferences.primaryThroughputInterface == iface,
                onTap: () => _setPrimaryThroughput(iface),
              ),
        ],
      ),
      if (wireless.isNotEmpty)
        AdaptiveFormSection(
          header: l10n.wirelessNetworks,
          footer: l10n.wirelessNetworksDescription,
          children: [
            AdaptiveFormSwitch(
              label: l10n.showAllNetworks,
              value: _preferences.enabledWirelessInterfaces.isEmpty,
              onChanged: _setShowAllWireless,
            ),
            if (_preferences.enabledWirelessInterfaces.isNotEmpty)
              for (final iface in wireless)
                AdaptiveListRow(
                  title: iface,
                  selected: _preferences.enabledWirelessInterfaces.contains(
                    iface,
                  ),
                  onTap: () => _setWireless(
                    iface,
                    !_preferences.enabledWirelessInterfaces.contains(iface),
                  ),
                ),
          ],
        ),
      if (wired.isNotEmpty)
        AdaptiveFormSection(
          header: l10n.networkInterfaces,
          footer: l10n.networkInterfacesDescription,
          children: [
            AdaptiveFormSwitch(
              label: l10n.showAllInterfaces,
              value: _preferences.enabledWiredInterfaces.isEmpty,
              onChanged: _setShowAllWired,
            ),
            if (_preferences.enabledWiredInterfaces.isNotEmpty)
              for (final iface in wired)
                AdaptiveListRow(
                  title: iface.toUpperCase(),
                  subtitle: _interfaceDescription(iface),
                  selected: _preferences.enabledWiredInterfaces.contains(iface),
                  onTap: () => _setWired(
                    iface,
                    !_preferences.enabledWiredInterfaces.contains(iface),
                  ),
                ),
          ],
        ),
    ];
  }

  Widget _buildSection({
    required String title,
    required String subtitle,
    required List<Widget> children,
    IconData? icon,
    bool initiallyExpanded = false,
  }) {
    return Card(
      elevation: 2,
      margin: EdgeInsets.symmetric(
        horizontal: LuciSpacing.md,
        vertical: LuciSpacing.sm,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: LuciCardStyles.standardRadius,
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: icon != null
              ? Icon(icon, color: Theme.of(context).colorScheme.primary)
              : null,
          title: Text(title, style: LuciTextStyles.cardTitle(context)),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Text(subtitle, style: LuciTextStyles.cardSubtitle(context)),
          ),
          initiallyExpanded: initiallyExpanded,
          shape: RoundedRectangleBorder(
            borderRadius: LuciCardStyles.standardRadius,
          ),
          childrenPadding: EdgeInsets.symmetric(
            horizontal: LuciSpacing.md,
            vertical: LuciSpacing.sm,
          ),
          children: children,
        ),
      ),
    );
  }

  Widget _buildThroughputSection() {
    final interfaces = _availableWiredInterfaces.toList()..sort();
    return _buildSection(
      title: context.l10n.throughputMonitoring,
      subtitle: context.l10n.throughputMonitoringDescription,
      icon: Icons.speed,
      initiallyExpanded: true,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              AdaptiveSwitchListTile(
                title: Text(
                  context.l10n.showAllInterfaces,
                  style: LuciTextStyles.detailValue(context)
                      .copyWith(fontWeight: FontWeight.w600),
                ),
                value: _preferences.showAllThroughput,
                onChanged: (value) => _setShowAllThroughput(value, interfaces),
              ),
            ],
          ),
        ),
        if (!_preferences.showAllThroughput && interfaces.isNotEmpty) ...[
          SizedBox(height: LuciSpacing.sm),
          RadioGroup<String>(
            groupValue: _preferences.primaryThroughputInterface,
            onChanged: _setPrimaryThroughput,
            child: Column(
              children: interfaces.map((iface) {
                return Padding(
                  padding: EdgeInsets.symmetric(vertical: LuciSpacing.xs),
                  child: RadioListTile<String>(
                    title: Text(
                      iface,
                      style: LuciTextStyles.detailValue(context),
                    ),
                    secondary: Icon(
                      Icons.lan,
                      size: 20,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    value: iface,
                    activeColor: Theme.of(context).colorScheme.primary,
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildWirelessInterfacesSection() {
    if (_availableWirelessInterfaces.isEmpty) return const SizedBox.shrink();
    final sortedInterfaces = _availableWirelessInterfaces.toList()..sort();
    return _buildSection(
      title: context.l10n.wirelessNetworks,
      subtitle: context.l10n.wirelessNetworksDescription,
      icon: Icons.wifi,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              AdaptiveSwitchListTile(
                title: Text(
                  context.l10n.showAllNetworks,
                  style: LuciTextStyles.detailValue(context)
                      .copyWith(fontWeight: FontWeight.w600),
                ),
                value: _preferences.enabledWirelessInterfaces.isEmpty,
                onChanged: _setShowAllWireless,
              ),
            ],
          ),
        ),
        if (_preferences.enabledWirelessInterfaces.isNotEmpty) ...[
          SizedBox(height: LuciSpacing.sm),
          ...sortedInterfaces.map((interface) {
            final isEnabled = _preferences.enabledWirelessInterfaces.contains(
              interface,
            );
            return Padding(
              padding: EdgeInsets.symmetric(vertical: LuciSpacing.xs),
              child: AdaptiveCheckboxListTile(
                title: Text(
                  interface,
                  style: LuciTextStyles.detailValue(context),
                ),
                secondary: Icon(
                  Icons.wifi,
                  size: 20,
                  color: isEnabled
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.5),
                ),
                value: isEnabled,
                onChanged: (value) => _setWireless(interface, value),
                activeColor: Theme.of(context).colorScheme.primary,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _buildWiredInterfacesSection() {
    if (_availableWiredInterfaces.isEmpty) return const SizedBox.shrink();
    final sortedInterfaces = _availableWiredInterfaces.toList()..sort();
    return _buildSection(
      title: context.l10n.networkInterfaces,
      subtitle: context.l10n.networkInterfacesDescription,
      icon: Icons.cable,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              AdaptiveSwitchListTile(
                title: Text(
                  context.l10n.showAllInterfaces,
                  style: LuciTextStyles.detailValue(context)
                      .copyWith(fontWeight: FontWeight.w600),
                ),
                value: _preferences.enabledWiredInterfaces.isEmpty,
                onChanged: _setShowAllWired,
              ),
            ],
          ),
        ),
        if (_preferences.enabledWiredInterfaces.isNotEmpty) ...[
          SizedBox(height: LuciSpacing.sm),
          ...sortedInterfaces.map((interface) {
            final isEnabled = _preferences.enabledWiredInterfaces.contains(
              interface,
            );
            final description = _getInterfaceDescription(interface);
            return Padding(
              padding: EdgeInsets.symmetric(vertical: LuciSpacing.xs),
              child: AdaptiveCheckboxListTile(
                title: Text(
                  interface.toUpperCase(),
                  style: LuciTextStyles.detailValue(context),
                ),
                subtitle: description,
                secondary: Icon(
                  Icons.cable,
                  size: 20,
                  color: isEnabled
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.5),
                ),
                value: isEnabled,
                onChanged: (value) => _setWired(interface, value),
                activeColor: Theme.of(context).colorScheme.primary,
                controlAffinity: ListTileControlAffinity.leading,
                dense: description != null,
              ),
            );
          }),
        ],
      ],
    );
  }

  /// What kind of interface [interface] looks to be, by its name.
  String? _interfaceDescription(String interface) {
    final l10n = context.l10n;
    final lower = interface.toLowerCase();
    if (lower.startsWith('wan')) return l10n.wideAreaNetwork;
    if (lower.startsWith('lan')) return l10n.localAreaNetwork;
    if (lower.contains('wireguard') || lower.startsWith('wg')) {
      return l10n.wireGuardVpn;
    }
    if (lower.contains('openvpn')) return l10n.openVpn;
    if (lower.contains('pppoe')) return l10n.pppoeConnection;
    return null;
  }

  Widget? _getInterfaceDescription(String interface) =>
      switch (_interfaceDescription(interface)) {
        final text? => Text(text, style: LuciTextStyles.cardSubtitle(context)),
        null => null,
      };

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: LuciAppBar(
          title: context.l10n.dashboardSettings,
          showBack: true,
        ),
        body: const Center(child: AdaptiveProgressIndicator()),
      );
    }
    if (_errorMessage != null) {
      return Scaffold(
        appBar: LuciAppBar(
          title: context.l10n.dashboardSettings,
          showBack: true,
        ),
        body: Center(child: Text(_errorMessage!)),
      );
    }

    if (PlatformUiCapabilities.isIOS) {
      final grouped = CupertinoColors.systemGroupedBackground.resolveFrom(
        context,
      );
      return Scaffold(
        backgroundColor: grouped,
        appBar: LuciAppBar(
          title: context.l10n.dashboardSettings,
          showBack: true,
          backgroundColor: grouped.withValues(alpha: 0.94),
        ),
        body: ListView(
          padding: const EdgeInsets.all(LuciSpacing.md),
          children: _iosSections(),
        ),
      );
    }
    return Scaffold(
      appBar: LuciAppBar(title: context.l10n.dashboardSettings, showBack: true),
      body: ListView(
        padding: EdgeInsets.symmetric(vertical: LuciSpacing.sm),
        children: [
          LuciStaggeredAnimation(
            staggerDelay: const Duration(milliseconds: 50),
            children: [
              _buildThroughputSection(),
              _buildWirelessInterfacesSection(),
              _buildWiredInterfacesSection(),
              SizedBox(height: LuciSpacing.lg),
            ],
          ),
        ],
      ),
    );
  }
}
