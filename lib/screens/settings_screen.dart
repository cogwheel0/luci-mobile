import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/screens/login_screen.dart';
import 'package:luci_mobile/screens/app_preferences_screen.dart';
import 'package:luci_mobile/screens/notifications_screen.dart';
import 'package:luci_mobile/screens/services_screen.dart';
import 'package:luci_mobile/screens/system_settings_screen.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';
import 'package:luci_mobile/design/luci_design_system.dart';
import 'package:luci_mobile/widgets/luci_hub_tile.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:luci_mobile/config/app_config.dart';
import 'package:luci_mobile/screens/manage_routers_screen.dart';
import 'package:luci_mobile/screens/wifi_scan_screen.dart';
import 'package:luci_mobile/utils/http_client_manager.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/l10n/luci_localizations.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
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
                // Captured before the pop: afterwards this dialog's context
                // is unmounted, so every `context.mounted` guard below the
                // await fails and the result snackbar never appears.
                final theme = Theme.of(context);
                final colorScheme = theme.colorScheme;
                final messenger = ScaffoldMessenger.of(context);
                final l10n = context.l10n;
                Navigator.of(context).pop();
                // Show persistent warning snackbar
                messenger.showSnackBar(
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
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      success
                          ? l10n.rebootCommandSent
                          : l10n.rebootCommandFailed,
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
      appBar: LuciAppBar(title: context.l10n.settings),
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
                final accessUnknown = ref.watch(
                  appStateProvider.select((state) => state.rebootAccessUnknown),
                );
                final rebootEnabled = canReboot == true && !isRebooting;
                return LuciHubSection(
                  tiles: [
                    LuciHubTile(
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
                    LuciHubTile(
                      icon: Icons.tune,
                      iconColor: Theme.of(context).colorScheme.primary,
                      title: context.l10n.systemSettings,
                      subtitle: context.l10n.systemSettingsDescription,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const SystemSettingsScreen(),
                          ),
                        );
                      },
                    ),
                    LuciHubTile(
                      icon: Icons.miscellaneous_services_outlined,
                      iconColor: Theme.of(context).colorScheme.primary,
                      title: context.l10n.services,
                      subtitle: context.l10n.servicesHubSubtitle,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const ServicesScreen(),
                          ),
                        );
                      },
                    ),
                    LuciHubTile(
                      icon: accessUnknown
                          ? Icons.error_outline
                          : canReboot == false
                          ? Icons.lock_outline
                          : Icons.restart_alt,
                      iconColor: Theme.of(context).colorScheme.primary,
                      title: context.l10n.rebootRouter,
                      subtitle: accessUnknown
                          ? context.l10n.rebootAccessUnknown
                          : switch (canReboot) {
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
            LuciHubSection(
              tiles: [
                LuciHubTile(
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
                LuciHubTile(
                  icon: Icons.settings_outlined,
                  iconColor: Theme.of(context).colorScheme.primary,
                  title: context.l10n.appPreferences,
                  subtitle: context.l10n.settingsDescription,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const AppPreferencesScreen(),
                      ),
                    );
                  },
                ),
                LuciHubTile(
                  icon: Icons.notifications_none,
                  iconColor: Theme.of(context).colorScheme.primary,
                  title: context.l10n.notifications,
                  subtitle: context.l10n.notificationsHubSubtitle,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const NotificationsScreen(),
                      ),
                    );
                  },
                ),
                LuciHubTile(
                  icon: Icons.info_outline,
                  iconColor: Theme.of(context).colorScheme.secondary,
                  title: context.l10n.about,
                  subtitle: context.l10n.aboutAppDescription,
                  onTap: () => _showAboutDialog(context),
                ),
                LuciHubTile(
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
}
