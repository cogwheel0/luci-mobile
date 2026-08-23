import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/models/router.dart' as model;
import 'package:luci_mobile/widgets/luci_app_bar.dart';
import 'package:luci_mobile/utils/url_parser.dart';
import 'package:luci_mobile/l10n/luci_localizations.dart';

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
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
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
                                    Navigator.of(
                                      context,
                                    ).popUntil((route) => route.isFirst);
                                    // Set Dashboard tab as active
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                          ref
                                              .read(appStateProvider)
                                              .requestTab(0);
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
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: Text(context.l10n.removeRouter),
                                    content: Text(
                                      context.l10n.removeRouterConfirmation(
                                        routerLabel,
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: Text(context.l10n.cancel),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: Text(context.l10n.remove),
                                      ),
                                    ],
                                  ),
                                );
                                if (!context.mounted) return;
                                if (confirm == true) {
                                  await appState.removeRouter(router.id);
                                  if (!context.mounted) return;
                                  if (appState.routers.isEmpty) {
                                    unawaited(
                                      Navigator.of(
                                        context,
                                      ).pushNamedAndRemoveUntil(
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
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.primary,
                                foregroundColor: Theme.of(
                                  context,
                                ).colorScheme.onPrimary,
                                elevation: 2,
                              ),
                              onPressed: () async {
                                final ipController = TextEditingController();
                                final alternateController =
                                    TextEditingController();
                                final userController = TextEditingController(
                                  text: 'root',
                                );
                                final passController = TextEditingController();
                                final formKey = GlobalKey<FormState>();
                                bool obscureText = true;
                                bool isConnecting = false;
                                bool showAlternate = false;
                                String? errorMessage;
                                try {
                                  await showDialog<void>(
                                    context: context,
                                    builder: (context) {
                                      return StatefulBuilder(
                                        builder: (context, setState) {
                                          return AlertDialog(
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            backgroundColor: Theme.of(context)
                                                .colorScheme
                                                .surface
                                                .withValues(alpha: 0.95),
                                            shadowColor: Theme.of(context)
                                                .colorScheme
                                                .primary
                                                .withValues(alpha: 0.10),
                                            insetPadding:
                                                const EdgeInsets.symmetric(
                                                  horizontal: 16,
                                                  vertical: 60,
                                                ), // Make dialog larger
                                            content: ConstrainedBox(
                                              constraints: const BoxConstraints(
                                                maxWidth: 400,
                                                minWidth: 320,
                                                minHeight: 380,
                                              ),
                                              child: Form(
                                                key: formKey,
                                                child: SingleChildScrollView(
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          top: 32,
                                                        ),
                                                    child: Column(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        TextFormField(
                                                          controller:
                                                              ipController,
                                                          decoration: InputDecoration(
                                                            labelText: context
                                                                .l10n
                                                                .routerAddress,
                                                            border:
                                                                const OutlineInputBorder(),
                                                            prefixIcon: const Icon(
                                                              Icons
                                                                  .router_outlined,
                                                            ),
                                                            helperText: context
                                                                .l10n
                                                                .routerAddressExample,
                                                          ),
                                                          validator: (value) {
                                                            if (value == null ||
                                                                value.isEmpty) {
                                                              return context
                                                                  .l10n
                                                                  .routerAddressRequired;
                                                            }
                                                            final parsed =
                                                                UrlParser.parse(
                                                                  value,
                                                                );
                                                            if (!parsed
                                                                .isValid) {
                                                              return context
                                                                  .l10n
                                                                  .invalidAddressFormat;
                                                            }
                                                            return null;
                                                          },
                                                          autofillHints: const [
                                                            AutofillHints.url,
                                                            AutofillHints
                                                                .username,
                                                          ],
                                                        ),
                                                        const SizedBox(
                                                          height: 6,
                                                        ),
                                                        if (!showAlternate)
                                                          Align(
                                                            alignment: Alignment
                                                                .centerLeft,
                                                            child: TextButton.icon(
                                                              onPressed: () =>
                                                                  setState(
                                                                    () =>
                                                                        showAlternate =
                                                                            true,
                                                                  ),
                                                              icon: const Icon(
                                                                Icons.add,
                                                                size: 18,
                                                              ),
                                                              label: Text(
                                                                context
                                                                    .l10n
                                                                    .addFallbackAddress,
                                                              ),
                                                            ),
                                                          )
                                                        else
                                                          TextFormField(
                                                            controller:
                                                                alternateController,
                                                            decoration: InputDecoration(
                                                              labelText: context
                                                                  .l10n
                                                                  .fallbackAddress,
                                                              border:
                                                                  const OutlineInputBorder(),
                                                              prefixIcon:
                                                                  const Icon(
                                                                    Icons
                                                                        .swap_horiz,
                                                                  ),
                                                              helperText: context
                                                                  .l10n
                                                                  .fallbackCredentialsHelp,
                                                              helperMaxLines: 2,
                                                            ),
                                                            validator: (value) {
                                                              if (value ==
                                                                      null ||
                                                                  value
                                                                      .isEmpty) {
                                                                return null;
                                                              }
                                                              final parsed =
                                                                  UrlParser.parse(
                                                                    value,
                                                                  );
                                                              if (!parsed
                                                                  .isValid) {
                                                                return context
                                                                    .l10n
                                                                    .invalidAddressFormat;
                                                              }
                                                              final primary =
                                                                  UrlParser.parse(
                                                                    ipController
                                                                        .text,
                                                                  );
                                                              if (primary
                                                                      .isValid &&
                                                                  parsed.hostWithPort ==
                                                                      primary
                                                                          .hostWithPort) {
                                                                return context
                                                                    .l10n
                                                                    .mustDifferFromPrimaryAddress;
                                                              }
                                                              return null;
                                                            },
                                                          ),
                                                        const SizedBox(
                                                          height: 10,
                                                        ),
                                                        TextFormField(
                                                          controller:
                                                              userController,
                                                          decoration: InputDecoration(
                                                            labelText: context
                                                                .l10n
                                                                .username,
                                                            border:
                                                                const OutlineInputBorder(),
                                                            prefixIcon: const Icon(
                                                              Icons
                                                                  .person_outline,
                                                            ),
                                                            helperText: context
                                                                .l10n
                                                                .usernameDefaultHelp,
                                                          ),
                                                          validator: (v) =>
                                                              v == null ||
                                                                  v.isEmpty
                                                              ? context
                                                                    .l10n
                                                                    .required
                                                              : null,
                                                          autofillHints: const [
                                                            AutofillHints
                                                                .username,
                                                          ],
                                                        ),
                                                        const SizedBox(
                                                          height: 20,
                                                        ),
                                                        TextFormField(
                                                          controller:
                                                              passController,
                                                          decoration: InputDecoration(
                                                            labelText: context
                                                                .l10n
                                                                .password,
                                                            border:
                                                                const OutlineInputBorder(),
                                                            prefixIcon: const Icon(
                                                              Icons
                                                                  .lock_outline,
                                                            ),
                                                            helperText: context
                                                                .l10n
                                                                .routerPasswordHelp,
                                                            suffixIcon: IconButton(
                                                              icon: Icon(
                                                                obscureText
                                                                    ? Icons
                                                                          .visibility_outlined
                                                                    : Icons
                                                                          .visibility_off_outlined,
                                                              ),
                                                              onPressed: () => setState(
                                                                () => obscureText =
                                                                    !obscureText,
                                                              ),
                                                              tooltip:
                                                                  obscureText
                                                                  ? context
                                                                        .l10n
                                                                        .hidePassword
                                                                  : context
                                                                        .l10n
                                                                        .showPassword,
                                                            ),
                                                          ),
                                                          obscureText:
                                                              obscureText,
                                                          autofillHints: const [
                                                            AutofillHints
                                                                .password,
                                                          ],
                                                        ),
                                                        if (errorMessage !=
                                                            null) ...[
                                                          const SizedBox(
                                                            height: 16,
                                                          ),
                                                          Container(
                                                            padding:
                                                                const EdgeInsets.all(
                                                                  10,
                                                                ),
                                                            decoration: BoxDecoration(
                                                              color:
                                                                  Theme.of(
                                                                        context,
                                                                      )
                                                                      .colorScheme
                                                                      .errorContainer
                                                                      .withValues(
                                                                        alpha:
                                                                            1,
                                                                      ),
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    8,
                                                                  ),
                                                            ),
                                                            child: Row(
                                                              children: [
                                                                Icon(
                                                                  Icons
                                                                      .error_outline,
                                                                  color: Theme.of(
                                                                    context,
                                                                  ).colorScheme.onErrorContainer,
                                                                ),
                                                                const SizedBox(
                                                                  width: 12,
                                                                ),
                                                                Expanded(
                                                                  child: Text(
                                                                    errorMessage!,
                                                                    style: Theme.of(context)
                                                                        .textTheme
                                                                        .bodyMedium
                                                                        ?.copyWith(
                                                                          color: Theme.of(
                                                                            context,
                                                                          ).colorScheme.onErrorContainer,
                                                                        ),
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        ],
                                                        const SizedBox(
                                                          height: 28,
                                                        ),
                                                        SizedBox(
                                                          width:
                                                              double.infinity,
                                                          child: ElevatedButton(
                                                            onPressed:
                                                                isConnecting
                                                                ? null
                                                                : () async {
                                                                    if (formKey
                                                                        .currentState!
                                                                        .validate()) {
                                                                      final input = ipController
                                                                          .text
                                                                          .trim();
                                                                      final user = userController
                                                                          .text
                                                                          .trim();
                                                                      final pass =
                                                                          passController
                                                                              .text;

                                                                      // Parse the input to extract host, port, and protocol
                                                                      final parsedUrl =
                                                                          UrlParser.parse(
                                                                            input,
                                                                          );

                                                                      if (!parsedUrl
                                                                          .isValid) {
                                                                        setState(() {
                                                                          errorMessage = context
                                                                              .l10n
                                                                              .invalidAddressFormat;
                                                                        });
                                                                        return;
                                                                      }

                                                                      final hostWithPort =
                                                                          parsedUrl
                                                                              .hostWithPort;
                                                                      final useHttps =
                                                                          parsedUrl
                                                                              .useHttps;
                                                                      final altText = alternateController
                                                                          .text
                                                                          .trim();
                                                                      final parsedAlt =
                                                                          altText
                                                                              .isEmpty
                                                                          ? null
                                                                          : UrlParser.parse(
                                                                              altText,
                                                                            );
                                                                      final id =
                                                                          '$hostWithPort-$user';

                                                                      if (routers.any(
                                                                        (r) =>
                                                                            r.id ==
                                                                            id,
                                                                      )) {
                                                                        setState(() {
                                                                          errorMessage = context
                                                                              .l10n
                                                                              .routerAlreadyExists;
                                                                        });
                                                                        return;
                                                                      }

                                                                      // Show connecting state
                                                                      setState(() {
                                                                        errorMessage =
                                                                            null;
                                                                        isConnecting =
                                                                            true;
                                                                      });

                                                                      // Always fetch hostname from router after login
                                                                      try {
                                                                        // Attempt login with the new router's credentials
                                                                        final loginSuccess = await appState.login(
                                                                          hostWithPort,
                                                                          user,
                                                                          pass,
                                                                          useHttps,
                                                                          fromRouter:
                                                                              false,
                                                                          alternateAddress:
                                                                              parsedAlt?.hostWithPort,
                                                                          alternateUseHttps:
                                                                              parsedAlt?.useHttps,
                                                                          context:
                                                                              context,
                                                                        );
                                                                        // The dialog is barrier-dismissible; bail out
                                                                        // instead of calling its setState after it
                                                                        // has been dismissed.
                                                                        if (!context
                                                                            .mounted) {
                                                                          return;
                                                                        }
                                                                        if (!loginSuccess) {
                                                                          setState(() {
                                                                            errorMessage =
                                                                                appState.errorMessage ??
                                                                                context.l10n.failedToConnectCredentials;
                                                                            isConnecting =
                                                                                false;
                                                                          });
                                                                          return;
                                                                        }
                                                                        Navigator.pop(
                                                                          context,
                                                                        );
                                                                      } catch (
                                                                        e
                                                                      ) {
                                                                        if (!context
                                                                            .mounted) {
                                                                          return;
                                                                        }
                                                                        setState(() {
                                                                          errorMessage = context
                                                                              .l10n
                                                                              .failedToConnect(
                                                                                e,
                                                                              );
                                                                          isConnecting =
                                                                              false;
                                                                        });
                                                                      }
                                                                    }
                                                                  },
                                                            style: ElevatedButton.styleFrom(
                                                              padding:
                                                                  const EdgeInsets.symmetric(
                                                                    vertical:
                                                                        18,
                                                                  ),
                                                              textStyle:
                                                                  const TextStyle(
                                                                    fontSize:
                                                                        18,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold,
                                                                  ),
                                                              shape: RoundedRectangleBorder(
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      14,
                                                                    ),
                                                              ),
                                                              elevation: 4,
                                                              backgroundColor:
                                                                  Theme.of(
                                                                        context,
                                                                      )
                                                                      .colorScheme
                                                                      .primary,
                                                              foregroundColor:
                                                                  Theme.of(
                                                                        context,
                                                                      )
                                                                      .colorScheme
                                                                      .onPrimary,
                                                            ),
                                                            child: isConnecting
                                                                ? Row(
                                                                    mainAxisAlignment:
                                                                        MainAxisAlignment
                                                                            .center,
                                                                    mainAxisSize:
                                                                        MainAxisSize
                                                                            .min,
                                                                    children: [
                                                                      SizedBox(
                                                                        width:
                                                                            22,
                                                                        height:
                                                                            22,
                                                                        child: CircularProgressIndicator(
                                                                          strokeWidth:
                                                                              3,
                                                                          valueColor:
                                                                              AlwaysStoppedAnimation<
                                                                                Color
                                                                              >(
                                                                                Theme.of(
                                                                                  context,
                                                                                ).colorScheme.onPrimary,
                                                                              ),
                                                                        ),
                                                                      ),
                                                                      const SizedBox(
                                                                        width:
                                                                            12,
                                                                      ),
                                                                      Text(
                                                                        context
                                                                            .l10n
                                                                            .connecting,
                                                                      ),
                                                                    ],
                                                                  )
                                                                : Row(
                                                                    mainAxisAlignment:
                                                                        MainAxisAlignment
                                                                            .center,
                                                                    mainAxisSize:
                                                                        MainAxisSize
                                                                            .min,
                                                                    children: [
                                                                      const Icon(
                                                                        Icons
                                                                            .add,
                                                                      ),
                                                                      const SizedBox(
                                                                        width:
                                                                            12,
                                                                      ),
                                                                      Text(
                                                                        context
                                                                            .l10n
                                                                            .add,
                                                                      ),
                                                                    ],
                                                                  ),
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          height: 8,
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      );
                                    },
                                  );
                                  if (!context.mounted) return;
                                } finally {
                                  // The controllers are only used by the
                                  // dialog above; dispose them once it closes.
                                  ipController.dispose();
                                  alternateController.dispose();
                                  userController.dispose();
                                  passController.dispose();
                                }
                              },
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
                IconButton(
                  icon: const Icon(Icons.link_off),
                  tooltip: context.l10n.removeFallbackAddress,
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(context.l10n.removeFallbackAddressTitle),
                        content: Text(
                          context.l10n.removeFallbackAddressConfirmation,
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: Text(context.l10n.cancel),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: Text(context.l10n.remove),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true && context.mounted) {
                      onRemoveFallback!();
                    }
                  },
                ),
              if (onDelete != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: context.l10n.remove,
                  onPressed: onDelete,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
