import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/screens/login_screen.dart';
import 'package:luci_mobile/screens/settings_screen.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';
import 'package:luci_mobile/design/luci_design_system.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:luci_mobile/config/app_config.dart';
import 'package:luci_mobile/screens/manage_routers_screen.dart';
import 'package:luci_mobile/screens/wifi_scan_screen.dart';
import 'package:luci_mobile/utils/http_client_manager.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/l10n/luci_localizations.dart';

class _MoreScreenSection extends StatelessWidget {
  final List<Widget> tiles;

  const _MoreScreenSection({required this.tiles});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(
        horizontal: LuciSpacing.md,
        vertical: LuciSpacing.sm,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: LuciCardStyles.standardRadius,
      ),
      child: Column(
        children: ListTile.divideTiles(context: context, tiles: tiles).toList(),
      ),
    );
  }
}

class MoreScreen extends ConsumerStatefulWidget {
  const MoreScreen({super.key});

  @override
  ConsumerState<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends ConsumerState<MoreScreen> {
  AppState? _appState;

  @override
  void initState() {
    super.initState();
    // Do not use context here
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _appState = ref.read(appStateProvider);
    _appState!.onRouterBackOnline = _showRouterBackOnlineMessage;
  }

  @override
  void dispose() {
    // Clear the callback before calling super.dispose()
    _appState?.onRouterBackOnline = null;
    super.dispose();
  }

  void _showRouterBackOnlineMessage() {
    if (mounted) {
      final theme = Theme.of(context);
      final colorScheme = theme.colorScheme;
      // Dismiss the warning snackbar
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: colorScheme.onPrimary, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  context.l10n.routerBackOnline,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onPrimary,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: colorScheme.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.symmetric(
            horizontal: LuciSpacing.lg,
            vertical: LuciSpacing.md,
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _showLogoutDialog(BuildContext context) async {
    final appState = ref.read(appStateProvider);
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(context.l10n.logoutQuestion),
          content: Text(context.l10n.logoutConfirmation),
          actions: <Widget>[
            TextButton(
              child: Text(context.l10n.cancel),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text(context.l10n.logout),
              onPressed: () async {
                await appState.logout();
                // Clear all accepted certificates on logout
                await HttpClientManager().clearAcceptedCertificates();
                if (context.mounted) {
                  unawaited(
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(
                        builder: (context) => const LoginScreen(),
                      ),
                      (Route<dynamic> route) => false,
                    ),
                  );
                }
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _showRebootDialog(BuildContext context) async {
    final appState = ref.read(appStateProvider);
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(context.l10n.rebootRouterQuestion),
          content: Text(context.l10n.rebootRouterConfirmation),
          actions: <Widget>[
            TextButton(
              child: Text(context.l10n.cancel),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text(context.l10n.reboot),
              onPressed: () async {
                Navigator.of(context).pop();
                // Show persistent warning snackbar
                final theme = Theme.of(context);
                final colorScheme = theme.colorScheme;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: colorScheme.onPrimary,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            context.l10n.rebootingConnectionInterrupted,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    backgroundColor: colorScheme.primary,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    margin: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    duration: const Duration(days: 1), // effectively indefinite
                  ),
                );
                final success = await appState.reboot();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      success
                          ? context.l10n.rebootCommandSent
                          : context.l10n.rebootCommandFailed,
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _showAboutDialog(BuildContext context) async {
    final info = await PackageInfo.fromPlatform();
    if (!context.mounted) return;

    unawaited(
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.router, size: 32),
                const SizedBox(width: 12),
                Text(context.l10n.appTitle),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.l10n.version(info.version)),
                const SizedBox(height: 16),
                Text(context.l10n.aboutDescription),
                const SizedBox(height: 16),
                Text(context.l10n.openSourceDescription),
                const SizedBox(height: 16),
                InkWell(
                  onTap: () async {
                    final url = AppConfig.githubRepositoryUrl;
                    final success = await launchUrlString(
                      url,
                      mode: LaunchMode.externalApplication,
                    );
                    if (!success && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(context.l10n.couldNotOpenRepository),
                          backgroundColor: Theme.of(context).colorScheme.error,
                        ),
                      );
                    }
                  },
                  child: Row(
                    children: [
                      Icon(
                        Icons.link,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          context.l10n.githubRepository,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            decoration: TextDecoration.underline,
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
                onPressed: () => Navigator.of(context).pop(),
                child: Text(context.l10n.close),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: LuciAppBar(title: context.l10n.more),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: LuciSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LuciSectionHeader(context.l10n.deviceManagement),
            Builder(
              builder: (context) {
                final isRebooting = ref.watch(
                  appStateProvider.select((state) => state.isRebooting),
                );
                final canReboot = ref.watch(
                  appStateProvider.select((state) => state.canReboot),
                );
                final accessError = ref.watch(
                  appStateProvider.select((state) => state.rebootAccessError),
                );
                final rebootEnabled = canReboot == true && !isRebooting;
                return _MoreScreenSection(
                  tiles: [
                    _buildMoreTile(
                      context,
                      icon: Icons.wifi_find,
                      iconColor: Theme.of(context).colorScheme.primary,
                      title: context.l10n.wifiScanner,
                      subtitle: context.l10n.wifiScannerDescription,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const WifiScanScreen(),
                          ),
                        );
                      },
                    ),
                    _buildMoreTile(
                      context,
                      icon: accessError != null
                          ? Icons.error_outline
                          : canReboot == false
                          ? Icons.lock_outline
                          : Icons.restart_alt,
                      iconColor: Theme.of(context).colorScheme.primary,
                      title: context.l10n.rebootRouter,
                      subtitle:
                          accessError ??
                          switch (canReboot) {
                            false => context.l10n.administratorAccessRequired,
                            null => context.l10n.checkingAdministratorAccess,
                            true => context.l10n.rebootRouterDescription,
                          },
                      onTap: rebootEnabled
                          ? () => _showRebootDialog(context)
                          : null,
                      enabled: rebootEnabled,
                      showSpinner: isRebooting,
                    ),
                  ],
                );
              },
            ),
            LuciSectionHeader(context.l10n.application),
            _MoreScreenSection(
              tiles: [
                _buildMoreTile(
                  context,
                  icon: Icons.router,
                  iconColor: Theme.of(context).colorScheme.primary,
                  title: context.l10n.manageRouters,
                  subtitle: context.l10n.manageRoutersDescription,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const ManageRoutersScreen(),
                      ),
                    );
                  },
                ),
                _buildMoreTile(
                  context,
                  icon: Icons.settings_outlined,
                  iconColor: Theme.of(context).colorScheme.primary,
                  title: context.l10n.settings,
                  subtitle: context.l10n.settingsDescription,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const SettingsScreen(),
                      ),
                    );
                  },
                ),
                _buildMoreTile(
                  context,
                  icon: Icons.info_outline,
                  iconColor: Theme.of(context).colorScheme.secondary,
                  title: context.l10n.about,
                  subtitle: context.l10n.aboutAppDescription,
                  onTap: () => _showAboutDialog(context),
                ),
                _buildMoreTile(
                  context,
                  icon: Icons.logout,
                  iconColor: Theme.of(context).colorScheme.error,
                  title: context.l10n.logout,
                  subtitle: context.l10n.logoutDescription,
                  titleColor: Theme.of(context).colorScheme.error,
                  subtitleColor: Theme.of(
                    context,
                  ).colorScheme.error.withValues(alpha: 0.7),
                  onTap: () => _showLogoutDialog(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMoreTile(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
    bool enabled = true,
    Color? titleColor,
    Color? subtitleColor,
    bool showSpinner = false,
  }) {
    final theme = Theme.of(context);
    // Persistent spinning icon using AnimationController
    Widget spinningIconWidget = Icon(
      icon,
      color: iconColor,
      size: 24,
      semanticLabel: title,
    );
    if (showSpinner) {
      spinningIconWidget = _SpinningIcon(
        icon: icon,
        color: iconColor,
        label: title,
      );
    }
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: ListTile(
        leading: Container(
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          padding: const EdgeInsets.all(10),
          child: spinningIconWidget,
        ),
        title: Text(
          title,
          style: titleColor != null
              ? LuciTextStyles.cardTitle(context).copyWith(color: titleColor)
              : LuciTextStyles.cardTitle(context),
          semanticsLabel: title,
        ),
        subtitle: Text(
          subtitle,
          style: subtitleColor != null
              ? LuciTextStyles.cardSubtitle(
                  context,
                ).copyWith(color: subtitleColor)
              : LuciTextStyles.cardSubtitle(context),
          semanticsLabel: subtitle,
        ),
        enabled: enabled,
        onTap: enabled ? onTap : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: LuciSpacing.lg,
          vertical: 10,
        ),
        hoverColor: theme.colorScheme.primary.withValues(alpha: 0.04),
        splashColor: theme.colorScheme.primary.withValues(alpha: 0.08),
        minVerticalPadding: LuciSpacing.md,
        minLeadingWidth: 0,
        visualDensity: VisualDensity.standard,
      ),
    );
  }
}

// Persistent spinning icon widget
class _SpinningIcon extends StatefulWidget {
  final IconData icon;
  final Color color;
  final String label;
  const _SpinningIcon({
    required this.icon,
    required this.color,
    required this.label,
  });
  @override
  State<_SpinningIcon> createState() => _SpinningIconState();
}

class _SpinningIconState extends State<_SpinningIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.rotate(
          angle: _controller.value * 6.28319, // 2 * pi
          child: Icon(
            widget.icon,
            color: widget.color,
            size: 24,
            semanticLabel: widget.label,
          ),
        );
      },
    );
  }
}
