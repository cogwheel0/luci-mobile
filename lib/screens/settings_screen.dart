import 'dart:async';

import 'package:material_ui/material_ui.dart';
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
import 'package:luci_mobile/navigation/tab_bar_inset.dart';
import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:luci_mobile/widgets/platform_ui/platform_ui.dart';

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
    if (!mounted) return;
    // Replaces the rebooting warning, which stays up until now.
    AdaptiveSnackBar.show(
      context,
      message: context.l10n.routerBackOnline,
      type: AdaptiveSnackBarType.success,
      duration: const Duration(seconds: 3),
    );
  }

  Future<void> _showLogoutDialog(BuildContext context) async {
    final appState = ref.read(appStateProvider);
    final l10n = context.l10n;
    // Capture the navigator before any awaits: once the alert closes, the
    // user can switch tabs while logging out, which removes this screen,
    // and the session must still end on the login screen.
    final navigator = Navigator.of(context);
    final confirmed = await AdaptiveAlertDialog.confirm(
      context: context,
      title: l10n.logoutQuestion,
      message: l10n.logoutConfirmation,
      cancelLabel: l10n.cancel,
      confirmLabel: l10n.logout,
      destructive: true,
    );
    if (!confirmed) return;
    await appState.logout(userInitiated: true);
    // Clear all accepted certificates on logout
    await HttpClientManager().clearAcceptedCertificates();
    unawaited(
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (Route<dynamic> route) => false,
      ),
    );
  }

  Future<void> _showRebootDialog(BuildContext context) async {
    final appState = ref.read(appStateProvider);
    final l10n = context.l10n;
    final confirmed = await AdaptiveAlertDialog.confirm(
      context: context,
      title: l10n.rebootRouterQuestion,
      message: l10n.rebootRouterConfirmation,
      cancelLabel: l10n.cancel,
      confirmLabel: l10n.reboot,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    // Captured now: the reboot can outlive this screen, and its outcome
    // still has somewhere to show.
    final report = AdaptiveSnackBar.reporter(context);
    // Up until the router is back or the command fails, a reboot that was
    // sent needs no second message saying so. Only this screen hears that
    // the router is back, so the warning is bounded to about a reboot's
    // length rather than left up after the user moves on.
    report.show(
      message: l10n.rebootingConnectionInterrupted,
      type: AdaptiveSnackBarType.warning,
      duration: const Duration(minutes: 2),
    );
    final success = await appState.reboot();
    if (!success) {
      report.show(
        message: l10n.rebootCommandFailed,
        type: AdaptiveSnackBarType.error,
      );
    }
  }

  /// Opens the app's repository in the browser, or says it could not.
  static Future<void> _openRepository(BuildContext context) async {
    final success = await launchUrlString(
      AppConfig.githubRepositoryUrl,
      mode: LaunchMode.externalApplication,
    );
    if (!success && context.mounted) {
      AdaptiveSnackBar.show(
        context,
        message: context.l10n.couldNotOpenRepository,
        type: AdaptiveSnackBarType.error,
      );
    }
  }

  Future<void> _showAboutDialog(BuildContext context) async {
    final info = await PackageInfo.fromPlatform();
    if (!context.mounted) return;
    // iOS opens About as a page, as its row's chevron promises.
    if (PlatformUiCapabilities.isIOS) {
      unawaited(
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => _AboutPage(version: info.version),
          ),
        ),
      );
      return;
    }

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
                  onTap: () => _openRepository(context),
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
    // iOS lays the hub out as iOS Settings: inset groups on the grouped
    // background.
    final grouped = PlatformUiCapabilities.isIOS
        ? CupertinoColors.systemGroupedBackground.resolveFrom(context)
        : null;
    return Scaffold(
      backgroundColor: grouped,
      appBar: LuciAppBar(
        title: context.l10n.settings,
        backgroundColor: grouped?.withValues(alpha: 0.94),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.only(
          top: LuciSpacing.sm,
          bottom: LuciSpacing.sm + TabBarInset.of(context),
        ),
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
                  subtitleColor: Theme.of(context).colorScheme.error
                      .withValues(alpha: 0.7),
                  destructive: true,
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

/// About, on iOS: the app's version, what it is, and its repository, as a
/// page of groups.
class _AboutPage extends StatelessWidget {
  const _AboutPage({required this.version});

  final String version;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final grouped = CupertinoColors.systemGroupedBackground.resolveFrom(
      context,
    );
    return Scaffold(
      backgroundColor: grouped,
      appBar: LuciAppBar(
        title: l10n.about,
        showBack: true,
        backgroundColor: grouped.withValues(alpha: 0.94),
      ),
      body: ListView(
        padding: const EdgeInsets.all(LuciSpacing.md),
        children: [
          AdaptiveFormSection(
            header: l10n.appTitle,
            footer: '${l10n.aboutDescription} ${l10n.openSourceDescription}',
            children: [
              AdaptiveFormValueRow(label: l10n.versionLabel, value: version),
            ],
          ),
          AdaptiveFormSection(
            children: [
              AdaptiveFormButtonRow(
                label: l10n.githubRepository,
                onPressed: () => _SettingsScreenState._openRepository(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
