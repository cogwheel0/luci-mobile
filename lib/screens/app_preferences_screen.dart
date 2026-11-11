import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';
import 'package:luci_mobile/screens/dashboard_settings_list_screen.dart';
import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:luci_mobile/widgets/platform_ui/platform_ui.dart';

class AppPreferencesScreen extends ConsumerWidget {
  const AppPreferencesScreen({super.key});

  Future<void> _showReviewerModeResetDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final appState = ref.read(appStateProvider);
    // Capture the root navigator before any awaits: this screen can be gone
    // by the time logging out finishes.
    final navigator = Navigator.of(context);
    final l10n = context.l10n;
    final confirmed = await AdaptiveAlertDialog.confirm(
      context: context,
      title: l10n.exitReviewerModeQuestion,
      message: l10n.exitReviewerModeDescription,
      cancelLabel: l10n.cancel,
      confirmLabel: l10n.exit,
    );
    if (!confirmed) return;
    await appState.setReviewerMode(false);
    await appState.logout();
    unawaited(navigator.pushNamedAndRemoveUntil('/login', (route) => false));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: LuciAppBar(title: context.l10n.appPreferences, showBack: true),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        children: [
          Builder(
            builder: (context) {
              final appState = ref.watch(appStateProvider);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 28, 16, 8),
                    child: Text(
                      context.l10n.theme,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  RadioGroup<ThemeMode>(
                    groupValue: appState.themeMode,
                    onChanged: (mode) {
                      if (mode != null) appState.setThemeMode(mode);
                    },
                    child: Column(
                      children: [
                        RadioListTile<ThemeMode>(
                          title: Text(context.l10n.systemDefault),
                          value: ThemeMode.system,
                        ),
                        RadioListTile<ThemeMode>(
                          title: Text(context.l10n.light),
                          value: ThemeMode.light,
                        ),
                        RadioListTile<ThemeMode>(
                          title: Text(context.l10n.dark),
                          value: ThemeMode.dark,
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 32),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Text(
                      context.l10n.dashboard,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.dashboard_customize,
                          color: Theme.of(context)
                              .colorScheme
                              .onPrimaryContainer,
                          size: 24,
                        ),
                      ),
                      title: Text(
                        context.l10n.customizeDashboard,
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        context.l10n.customizeDashboardDescription,
                      ),
                      trailing: Icon(
                        Icons.arrow_forward_ios,
                        size: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) =>
                                const DashboardSettingsListScreen(),
                          ),
                        );
                      },
                    ),
                  ),
                  if (appState.reviewerModeEnabled) ...[
                    const Divider(height: 32),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Text(
                        context.l10n.reviewerMode,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(
                        Icons.info_outline,
                        color: Colors.orange,
                      ),
                      title: Text(context.l10n.reviewerModeActive),
                      subtitle: Text(
                        context.l10n.reviewerModeActiveDescription,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: AdaptiveButton(
                        onPressed: () =>
                            _showReviewerModeResetDialog(context, ref),
                        label: context.l10n.exitReviewerMode,
                        sfSymbol: const SFSymbol(
                          'rectangle.portrait.and.arrow.right',
                        ),
                        materialIcon: Icons.exit_to_app,
                        color: Theme.of(context).colorScheme.error,
                        textColor: Theme.of(context).colorScheme.onError,
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
