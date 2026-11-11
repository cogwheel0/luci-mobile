import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/navigation/luci_tab.dart';
import 'package:luci_mobile/models/router.dart' as model;
import 'package:luci_mobile/widgets/luci_app_bar.dart';
import 'package:luci_mobile/utils/url_parser.dart';
import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:luci_mobile/widgets/autofill_form.dart';
import 'package:luci_mobile/widgets/platform_ui/platform_ui.dart';

class ManageRoutersScreen extends ConsumerStatefulWidget {
  const ManageRoutersScreen({super.key});

  @override
  ConsumerState<ManageRoutersScreen> createState() =>
      _ManageRoutersScreenState();
}

/// Truncate long addresses (e.g., Tailscale hostnames) to fit in the card.
/// Keeps the start and the TLD: "gl-be9300-1.tail..."
String _truncateAddress(String addr, {int maxLen = 24}) {
  if (addr.length <= maxLen) return addr;
  return '${addr.substring(0, maxLen - 3)}...';
}

class _ManageRoutersScreenState extends ConsumerState<ManageRoutersScreen> {
  String? _switchingRouterId;

  @override
  Widget build(BuildContext context) {
    final appState = ref.watch(appStateProvider);
    final List<model.Router> routers = appState.routers;
    final String? selectedId = appState.selectedRouter?.id;
    return Scaffold(
      appBar: LuciAppBar(title: context.l10n.routers, showBack: true),
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Column(
        children: [
          const SizedBox(height: 16),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => appState.loadRouters(),
              child: routers.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.2,
                        ),
                        Center(
                          child: Text(
                            context.l10n.noRoutersYet,
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                        ),
                      ],
                    )
                  : ListView(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      children: [
                        ...List.generate(routers.length, (index) {
                          final model.Router router = routers[index];
                          final bool isSelected = router.id == selectedId;
                          final bool isSwitching =
                              router.id == _switchingRouterId;
                          String routerTitle;
                          if (isSelected && appState.dashboardData != null) {
                            final boardInfo =
                                appState.dashboardData?['boardInfo']
                                    as Map<String, dynamic>?;
                            final hostname = boardInfo?['hostname']?.toString();
                            routerTitle =
                                (hostname != null && hostname.isNotEmpty)
                                ? hostname
                                : (router.lastKnownHostname ??
                                      router.ipAddress);
                          } else if (router.lastKnownHostname != null &&
                              router.lastKnownHostname!.isNotEmpty) {
                            routerTitle = router.lastKnownHostname!;
                          } else {
                            routerTitle = router.ipAddress;
                          }
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16.0,
                              vertical: 8.0,
                            ),
                            child: _UnifiedRouterCard(
                              routerTitle: routerTitle,
                              subtitle: router.hasFallback
                                  ? '● ${_truncateAddress(router.activeAddress)}\n○ ${_truncateAddress(router.inactiveAddress!)}'
                                  : '${router.ipAddress} (${router.username})',
                              isSelected: isSelected,
                              isSwitching: isSwitching,
                              onTap: () async {
                                if (!isSelected && !isSwitching) {
                                  setState(() {
                                    _switchingRouterId = router.id;
                                  });

                                  try {
                                    await appState.selectRouter(
                                      router.id,
                                      context: context,
                                    );
                                    if (!context.mounted) return;
                                    // Pop all the way back to MainScreen
                                    Navigator.of(context)
                                        .popUntil((route) => route.isFirst);
                                    // Set Dashboard tab as active
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                          ref
                                              .read(appStateProvider)
                                              .requestTab(LuciTab.dashboard);
                                        });
                                  } finally {
                                    if (mounted) {
                                      setState(() {
                                        _switchingRouterId = null;
                                      });
                                    }
                                  }
                                }
                              },
                              onRemoveFallback: router.hasFallback
                                  ? () async {
                                      await appState.updateRouter(
                                        router.copyWith(clearAlternate: true),
                                      );
                                      if (isSelected && context.mounted) {
                                        await appState.selectRouter(
                                          router.id,
                                          context: context,
                                        );
                                      }
                                    }
                                  : null,
                              onDelete: () async {
                                String routerLabel;
                                if (isSelected &&
                                    appState.dashboardData != null) {
                                  final boardInfo =
                                      appState.dashboardData?['boardInfo']
                                          as Map<String, dynamic>?;
                                  final hostname = boardInfo?['hostname']
                                      ?.toString();
                                  routerLabel =
                                      (hostname != null && hostname.isNotEmpty)
                                      ? hostname
                                      : router.ipAddress;
                                } else {
                                  routerLabel = router.ipAddress;
                                }
                                final confirm =
                                    await AdaptiveAlertDialog.confirm(
                                      context: context,
                                      title: context.l10n.removeRouter,
                                      message: context.l10n
                                          .removeRouterConfirmation(
                                            routerLabel,
                                          ),
                                      cancelLabel: context.l10n.cancel,
                                      confirmLabel: context.l10n.remove,
                                      destructive: true,
                                    );
                                if (!context.mounted) return;
                                if (confirm == true) {
                                  // Deleting the monitored router switches
                                  // the poll off in storage; the settings
                                  // notifier follows that write itself, so
                                  // it no longer matters whether this
                                  // screen outlives the call.
                                  await appState.removeRouter(router.id);
                                  if (!context.mounted) return;
                                  if (appState.routers.isEmpty) {
                                    unawaited(
                                      Navigator.of(context)
                                          .pushNamedAndRemoveUntil(
                                            '/login',
                                            (route) => false,
                                          ),
                                    );
                                  }
                                }
                              },
                            ),
                          );
                        }),
                        const SizedBox(height: 24),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.add, size: 20),
                              label: Text(context.l10n.addRouter),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                  horizontal: 24,
                                ),
                                textStyle: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .primary,
                                foregroundColor: Theme.of(context)
                                    .colorScheme
                                    .onPrimary,
                                elevation: 2,
                              ),
                              onPressed: () => showAdaptiveFormSheet<void>(
                                context: context,
                                builder: (_) => _AddRouterForm(
                                  appState: appState,
                                  routers: routers,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Signs in to a new router and saves it: a Material dialog on Android, an
/// iOS sheet with Connect as its confirm action on iOS.
class _AddRouterForm extends StatefulWidget {
  const _AddRouterForm({required this.appState, required this.routers});

  final AppState appState;
  final List<model.Router> routers;

  @override
  State<_AddRouterForm> createState() => _AddRouterFormState();
}

class _AddRouterFormState extends State<_AddRouterForm> {
  final _formKey = GlobalKey<FormState>();
  final _address = TextEditingController();
  final _alternate = TextEditingController();
  final _user = TextEditingController(text: 'root');
  final _password = TextEditingController();
  bool _obscure = true;
  bool _connecting = false;
  bool _showAlternate = false;
  String? _error;

  @override
  void dispose() {
    _address.dispose();
    _alternate.dispose();
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (!_formKey.currentState!.validate()) return;

    final input = _address.text.trim();
    final user = _user.text.trim();
    final pass = _password.text;

    // Parse the input to extract host, port, and protocol
    final parsedUrl = UrlParser.parse(input);

    if (!parsedUrl.isValid) {
      setState(() {
        _error = context.l10n.invalidAddressFormat;
      });
      return;
    }

    final hostWithPort = parsedUrl.hostWithPort;
    final useHttps = parsedUrl.useHttps;
    final altText = _alternate.text.trim();
    final parsedAlt = altText.isEmpty ? null : UrlParser.parse(altText);
    final id = '$hostWithPort-$user';

    if (widget.routers.any((r) => r.id == id)) {
      setState(() {
        _error = context.l10n.routerAlreadyExists;
      });
      return;
    }

    // Show connecting state
    setState(() {
      _error = null;
      _connecting = true;
    });

    // Always fetch hostname from router after login
    try {
      // Attempt login with the new router's credentials
      final loginSuccess = await widget.appState.login(
        hostWithPort,
        user,
        pass,
        useHttps,
        fromRouter: false,
        alternateAddress: parsedAlt?.hostWithPort,
        alternateUseHttps: parsedAlt?.useHttps,
        context: context,
      );
      // The form can't be dismissed while connecting, but bail out rather
      // than call setState should it have closed anyway.
      if (!mounted) {
        return;
      }
      if (!loginSuccess) {
        setState(() {
          _error =
              widget.appState.errorMessage ??
              context.l10n.failedToConnectCredentials;
          _connecting = false;
        });
        return;
      }
      // While the form is still shown: the OS saves from it.
      // Only what was signed in with, not anything typed since.
      AutofillForm.saveCredentials(
        unchanged:
            _address.text.trim() == input &&
            _user.text.trim() == user &&
            _password.text == pass,
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = context.l10n.failedToConnect(e);
        _connecting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveFormSheet(
      title: context.l10n.addRouter,
      cancelLabel: context.l10n.cancel,
      confirmLabel: context.l10n.add,
      busy: _connecting,
      onConfirm: _connect,
      child: AutofillForm(
        formKey: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _address,
              decoration: InputDecoration(
                labelText: context.l10n.routerAddress,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.router_outlined),
                helperText: context.l10n.routerAddressExample,
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return context.l10n.routerAddressRequired;
                }
                final parsed = UrlParser.parse(value);
                if (!parsed.isValid) {
                  return context.l10n.invalidAddressFormat;
                }
                return null;
              },
              autofillHints: const [AutofillHints.url],
            ),
            const SizedBox(height: 6),
            if (!_showAlternate)
              Align(
                alignment: Alignment.centerLeft,
                child: AdaptiveButton(
                  onPressed: () => setState(() => _showAlternate = true),
                  label: context.l10n.addFallbackAddress,
                  sfSymbol: const SFSymbol('plus'),
                  materialIcon: Icons.add,
                  style: AdaptiveButtonStyle.plain,
                ),
              )
            else
              TextFormField(
                controller: _alternate,
                decoration: InputDecoration(
                  labelText: context.l10n.fallbackAddress,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.swap_horiz),
                  helperText: context.l10n.fallbackCredentialsHelp,
                  helperMaxLines: 2,
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return null;
                  }
                  final parsed = UrlParser.parse(value);
                  if (!parsed.isValid) {
                    return context.l10n.invalidAddressFormat;
                  }
                  final primary = UrlParser.parse(_address.text);
                  if (primary.isValid &&
                      parsed.hostWithPort == primary.hostWithPort) {
                    return context.l10n.mustDifferFromPrimaryAddress;
                  }
                  return null;
                },
              ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _user,
              decoration: InputDecoration(
                labelText: context.l10n.username,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.person_outline),
                helperText: context.l10n.usernameDefaultHelp,
              ),
              validator: (v) =>
                  v == null || v.isEmpty ? context.l10n.required : null,
              autofillHints: const [AutofillHints.username],
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _password,
              decoration: InputDecoration(
                labelText: context.l10n.password,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.lock_outline),
                helperText: context.l10n.routerPasswordHelp,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                  tooltip: _obscure
                      ? context.l10n.hidePassword
                      : context.l10n.showPassword,
                ),
              ),
              obscureText: _obscure,
              autofillHints: const [AutofillHints.password],
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer
                      .withValues(alpha: 1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _error!,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _UnifiedRouterCard extends StatelessWidget {
  final String routerTitle;
  final String subtitle;
  final bool isSelected;
  final bool isSwitching;
  final VoidCallback? onTap;
  final VoidCallback? onRemoveFallback;
  final VoidCallback? onDelete;

  const _UnifiedRouterCard({
    required this.routerTitle,
    required this.subtitle,
    required this.isSelected,
    required this.isSwitching,
    this.onTap,
    this.onRemoveFallback,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Card(
      elevation: isSelected ? 6 : 2,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18.0),
        side: BorderSide(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.10),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(18.0),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.13),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.router,
                  color: isSelected
                      ? colorScheme.primary
                      : colorScheme.onSurface,
                  size: 22,
                  semanticLabel: context.l10n.routerIcon,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      routerTitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 11,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0.1,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (isSelected && !isSwitching)
                Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: Chip(
                    label: Text(context.l10n.active),
                    labelStyle: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onPrimary,
                    ),
                    backgroundColor: colorScheme.primary,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                ),
              if (isSwitching)
                Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              if (onRemoveFallback != null)
                AdaptiveButton.sfSymbol(
                  sfSymbol: const SFSymbol('minus.circle'),
                  materialIcon: Icons.link_off,
                  semanticLabel: context.l10n.removeFallbackAddress,
                  style: AdaptiveButtonStyle.plain,
                  onPressed: () async {
                    final confirm = await AdaptiveAlertDialog.confirm(
                      context: context,
                      title: context.l10n.removeFallbackAddressTitle,
                      message: context.l10n.removeFallbackAddressConfirmation,
                      cancelLabel: context.l10n.cancel,
                      confirmLabel: context.l10n.remove,
                      destructive: true,
                    );
                    if (confirm == true && context.mounted) {
                      onRemoveFallback!();
                    }
                  },
                ),
              if (onDelete != null)
                AdaptiveButton.sfSymbol(
                  onPressed: onDelete,
                  sfSymbol: const SFSymbol('trash'),
                  materialIcon: Icons.delete_outline,
                  semanticLabel: context.l10n.remove,
                  style: AdaptiveButtonStyle.plain,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
