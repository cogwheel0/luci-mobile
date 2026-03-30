import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/models/dashboard_preferences.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';
import 'package:luci_mobile/design/luci_design_system.dart';
import 'package:luci_mobile/widgets/luci_animation_system.dart';

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
      if (appState.dashboardData == null) {
        setState(() {
          _errorMessage =
              'Unable to load dashboard data. Please check your connection.';
          _isLoading = false;
        });
        return;
      }
      _preferences = appState.dashboardPreferences;
      _extractAvailableInterfaces(appState.dashboardData);
      setState(() => _isLoading = false);
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load settings: $e';
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
      title: 'Throughput Monitoring',
      subtitle: 'Configure which interfaces to monitor',
      icon: Icons.speed,
      initiallyExpanded: true,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              SwitchListTile.adaptive(
                title: Text(
                  'Show All Interfaces',
                  style: LuciTextStyles.detailValue(
                    context,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
                value: _preferences.showAllThroughput,
                onChanged: (value) {
                  setState(() {
                    if (value) {
                      _preferences = _preferences.copyWith(
                        showAllThroughput: true,
                        primaryThroughputInterface: null,
                      );
                    } else {
                      _preferences = _preferences.copyWith(
                        showAllThroughput: false,
                        primaryThroughputInterface: interfaces.isNotEmpty
                            ? interfaces.first
                            : null,
                      );
                    }
                  });
                  _onPreferenceChanged();
                },
                activeTrackColor: Theme.of(context).colorScheme.primary,
                activeThumbColor: Theme.of(context).colorScheme.onPrimary,
              ),
            ],
          ),
        ),
        if (!_preferences.showAllThroughput && interfaces.isNotEmpty) ...[
          SizedBox(height: LuciSpacing.sm),
          ...interfaces.map((iface) {
            return Padding(
              padding: EdgeInsets.symmetric(vertical: LuciSpacing.xs),
              child: RadioListTile<String>(
                title: Text(iface, style: LuciTextStyles.detailValue(context)),
                secondary: Icon(
                  Icons.lan,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                value: iface,
                groupValue: _preferences
                    .primaryThroughputInterface, // ignore: deprecated_member_use
                onChanged: (value) {
                  // ignore: deprecated_member_use
                  setState(() {
                    _preferences = _preferences.copyWith(
                      showAllThroughput: false,
                      primaryThroughputInterface: value,
                    );
                  });
                  _onPreferenceChanged();
                },
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

  Widget _buildWirelessInterfacesSection() {
    if (_availableWirelessInterfaces.isEmpty) return const SizedBox.shrink();
    final sortedInterfaces = _availableWirelessInterfaces.toList()..sort();
    return _buildSection(
      title: 'Wireless Networks',
      subtitle: 'Choose which wireless networks to display',
      icon: Icons.wifi,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              SwitchListTile.adaptive(
                title: Text(
                  'Show All Networks',
                  style: LuciTextStyles.detailValue(
                    context,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
                value: _preferences.enabledWirelessInterfaces.isEmpty,
                onChanged: (value) {
                  setState(() {
                    if (value) {
                      _preferences = _preferences.copyWith(
                        enabledWirelessInterfaces: {},
                      );
                    } else {
                      _preferences = _preferences.copyWith(
                        enabledWirelessInterfaces: Set.from(
                          _availableWirelessInterfaces,
                        ),
                      );
                    }
                  });
                  _onPreferenceChanged();
                },
                activeTrackColor: Theme.of(context).colorScheme.primary,
                activeThumbColor: Theme.of(context).colorScheme.onPrimary,
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
              child: CheckboxListTile(
                title: Text(
                  interface,
                  style: LuciTextStyles.detailValue(context),
                ),
                secondary: Icon(
                  Icons.wifi,
                  size: 20,
                  color: isEnabled
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
                value: isEnabled,
                onChanged: (value) {
                  setState(() {
                    final newSet = Set<String>.from(
                      _preferences.enabledWirelessInterfaces,
                    );
                    if (value ?? false) {
                      newSet.add(interface);
                    } else {
                      newSet.remove(interface);
                    }
                    _preferences = _preferences.copyWith(
                      enabledWirelessInterfaces: newSet,
                    );
                  });
                  _onPreferenceChanged();
                },
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
      title: 'Network Interfaces',
      subtitle: 'Choose which wired/VPN interfaces to display',
      icon: Icons.cable,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              SwitchListTile.adaptive(
                title: Text(
                  'Show All Interfaces',
                  style: LuciTextStyles.detailValue(
                    context,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
                value: _preferences.enabledWiredInterfaces.isEmpty,
                onChanged: (value) {
                  setState(() {
                    if (value) {
                      _preferences = _preferences.copyWith(
                        enabledWiredInterfaces: {},
                      );
                    } else {
                      _preferences = _preferences.copyWith(
                        enabledWiredInterfaces: Set.from(
                          _availableWiredInterfaces,
                        ),
                      );
                    }
                  });
                  _onPreferenceChanged();
                },
                activeTrackColor: Theme.of(context).colorScheme.primary,
                activeThumbColor: Theme.of(context).colorScheme.onPrimary,
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
              child: CheckboxListTile(
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
                      : Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
                value: isEnabled,
                onChanged: (value) {
                  setState(() {
                    final newSet = Set<String>.from(
                      _preferences.enabledWiredInterfaces,
                    );
                    if (value ?? false) {
                      newSet.add(interface);
                    } else {
                      newSet.remove(interface);
                    }
                    _preferences = _preferences.copyWith(
                      enabledWiredInterfaces: newSet,
                    );
                  });
                  _onPreferenceChanged();
                },
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

  Widget? _getInterfaceDescription(String interface) {
    final lower = interface.toLowerCase();
    if (lower.startsWith('wan')) {
      return Text(
        'Wide Area Network',
        style: LuciTextStyles.cardSubtitle(context),
      );
    } else if (lower.startsWith('lan')) {
      return Text(
        'Local Area Network',
        style: LuciTextStyles.cardSubtitle(context),
      );
    } else if (lower.contains('wireguard') || lower.startsWith('wg')) {
      return Text('WireGuard VPN', style: LuciTextStyles.cardSubtitle(context));
    } else if (lower.contains('openvpn')) {
      return Text('OpenVPN', style: LuciTextStyles.cardSubtitle(context));
    } else if (lower.contains('pppoe')) {
      return Text(
        'PPPoE Connection',
        style: LuciTextStyles.cardSubtitle(context),
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        appBar: LuciAppBar(title: 'Dashboard Settings', showBack: true),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_errorMessage != null) {
      return Scaffold(
        appBar: const LuciAppBar(title: 'Dashboard Settings', showBack: true),
        body: Center(child: Text(_errorMessage!)),
      );
    }

    return Scaffold(
      appBar: const LuciAppBar(title: 'Dashboard Settings', showBack: true),
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
