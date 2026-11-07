import 'dart:async';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';
import 'package:luci_mobile/screens/dashboard_settings_list_screen.dart';
import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:luci_mobile/l10n/app_localizations.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/widgets/app_lock_gate.dart';

class AppPreferencesScreen extends ConsumerWidget {
  const AppPreferencesScreen({super.key});

  void _showReviewerModeResetDialog(BuildContext context, WidgetRef ref) {
    final appState = ref.read(appStateProvider);
    // Capture the root navigator before any awaits: the dialog's context is
    // dead once popped, so a later context.mounted check would skip the
    // navigation and leave the user on a stale screen.
    final navigator = Navigator.of(context);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.exitReviewerModeQuestion),
        content: Text(context.l10n.exitReviewerModeDescription),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await appState.setReviewerMode(false);
              await appState.logout();
              unawaited(
                navigator.pushNamedAndRemoveUntil('/login', (route) => false),
              );
            },
            child: Text(context.l10n.exit),
          ),
        ],
      ),
    );
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
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
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
                  const _AppearanceSection(),
                  const Divider(height: 32),
                  const _LanguageSection(),
                  const Divider(height: 32),
                  const _SecuritySection(),
                  const Divider(height: 32),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Text(
                      context.l10n.dashboard,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
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
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer,
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
                      child: FilledButton.icon(
                        onPressed: () =>
                            _showReviewerModeResetDialog(context, ref),
                        icon: const Icon(Icons.exit_to_app),
                        label: Text(context.l10n.exitReviewerMode),
                        style: FilledButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.error,
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.onError,
                        ),
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

Widget _sectionTitle(BuildContext context, String text) => Padding(
  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
  child: Text(
    text,
    style: Theme.of(
      context,
    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
  ),
);

/// Material You, accent colour and the pure-black dark theme.
class _AppearanceSection extends ConsumerWidget {
  const _AppearanceSection();

  static const accents = <Color>[
    Color(0xFF2196F3), // blue
    Color(0xFF009688), // teal
    Color(0xFF4CAF50), // green
    Color(0xFFFF9800), // orange
    Color(0xFFF44336), // red
    Color(0xFFE91E63), // pink
    Color(0xFF9C27B0), // purple
    Color(0xFF607D8B), // blue grey
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(appStateProvider);
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return DynamicColorBuilder(
      builder: (lightDynamic, _) {
        final hasDynamic = lightDynamic != null;
        final usingDynamic = hasDynamic && appState.dynamicColor;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(context, l10n.appearance),
            if (hasDynamic)
              SwitchListTile(
                secondary: const Icon(Icons.palette_outlined),
                title: Text(l10n.dynamicColor),
                subtitle: Text(l10n.dynamicColorDescription),
                value: appState.dynamicColor,
                onChanged: appState.setDynamicColor,
              ),
            if (!usingDynamic) ...[
              ListTile(
                leading: const Icon(Icons.color_lens_outlined),
                title: Text(l10n.accentColor),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final color in accents)
                      _AccentDot(
                        color: color,
                        selected:
                            appState.accentColor.toARGB32() ==
                            color.toARGB32(),
                        outline: scheme.onSurface,
                        onTap: () => appState.setAccentColor(color),
                      ),
                  ],
                ),
              ),
            ],
            SwitchListTile(
              secondary: const Icon(Icons.contrast),
              title: Text(l10n.amoledBlack),
              subtitle: Text(l10n.amoledBlackDescription),
              value: appState.amoledBlack,
              onChanged: appState.setAmoledBlack,
            ),
          ],
        );
      },
    );
  }
}

class _AccentDot extends StatelessWidget {
  const _AccentDot({
    required this.color,
    required this.selected,
    required this.outline,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final Color outline;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 24,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? outline : Colors.transparent,
            width: 3,
          ),
        ),
        child: selected
            ? const Icon(Icons.check, color: Colors.white, size: 20)
            : null,
      ),
    );
  }
}

/// The app's language, independent of the system's.
class _LanguageSection extends ConsumerWidget {
  const _LanguageSection();

  /// Each language by its own name, so it can be found by someone who does
  /// not read the one currently shown.
  static String nativeName(Locale locale) =>
      switch (AppState.localeTag(locale)) {
        'en' => 'English',
        'de' => 'Deutsch',
        'fr' => 'Français',
        'it' => 'Italiano',
        'zh' => '简体中文',
        'zh_Hant' => '繁體中文',
        'ru' => 'Русский',
        'nl' => 'Nederlands',
        'es' => 'Español',
        'ko' => '한국어',
        'ja' => '日本語',
        'cs' => 'Čeština',
        'sk' => 'Slovenčina',
        'pl' => 'Polski',
        final other => other,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(appStateProvider);
    final l10n = context.l10n;
    final current = appState.locale;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(context, l10n.language),
        ListTile(
          leading: const Icon(Icons.translate),
          title: Text(l10n.language),
          subtitle: Text(
            current == null ? l10n.systemDefault : nativeName(current),
          ),
          trailing: const Icon(Icons.arrow_drop_down),
          onTap: () => _pick(context, appState),
        ),
      ],
    );
  }

  Future<void> _pick(BuildContext context, AppState appState) async {
    final currentTag = appState.locale == null
        ? ''
        : AppState.localeTag(appState.locale!);
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final options = <(String, String)>[
          ('', sheetContext.l10n.systemDefault),
          for (final locale in AppLocalizations.supportedLocales)
            (AppState.localeTag(locale), nativeName(locale)),
        ];
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.7,
            ),
            child: RadioGroup<String>(
              groupValue: currentTag,
              onChanged: (tag) => Navigator.of(sheetContext).pop(tag),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final (tag, label) in options)
                    RadioListTile<String>(value: tag, title: Text(label)),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (picked == null) return;
    await appState.setLocale(AppState.parseLocaleTag(picked));
  }
}

/// Biometric / screen-lock gate on opening the app.
class _SecuritySection extends ConsumerWidget {
  const _SecuritySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(appStateProvider);
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(context, l10n.security),
        SwitchListTile(
          secondary: const Icon(Icons.fingerprint),
          title: Text(l10n.appLock),
          subtitle: Text(l10n.appLockDescription),
          value: appState.appLockEnabled,
          onChanged: (on) async {
            final messenger = ScaffoldMessenger.of(context);
            final unavailable = l10n.appLockUnavailable;
            final reason = l10n.appLockReason;
            if (!await AppLockAuth.isAvailable()) {
              messenger.showSnackBar(SnackBar(content: Text(unavailable)));
              return;
            }
            // Confirm it is the owner both ways: turning the lock off is
            // exactly what someone holding an unlocked phone would do.
            if (!await AppLockAuth.authenticate(reason)) return;
            await appState.setAppLockEnabled(on);
          },
        ),
      ],
    );
  }
}
