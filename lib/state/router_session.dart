import 'package:flutter/foundation.dart';

/// An authenticated connection to one router, as a value.
///
/// Feature modules take this instead of reaching into `AppState`. Because it
/// has value equality and carries [token] — the same monotonic counter
/// `AppState` uses to discard stale async results — a router switch, a
/// re-login, a logout or a reboot-recovery cycle all produce a *different*
/// session. Providers that watch it are therefore invalidated automatically,
/// which is the stale-result guard expressed structurally rather than as a
/// hand-written token check after every `await`.
@immutable
class RouterSession {
  const RouterSession({
    required this.routerId,
    required this.ipAddress,
    required this.sysauth,
    required this.useHttps,
    required this.token,
    this.fallbackAddress,
    this.fallbackUseHttps,
    this.reviewerMode = false,
  });

  /// Identifier of the saved router profile this session belongs to.
  ///
  /// In reviewer mode there may be no saved router at all, in which case this
  /// is [reviewerRouterId].
  final String routerId;

  /// The address the session actually logged in through — which may be the
  /// router's fallback address rather than its primary one.
  final String ipAddress;

  final String sysauth;
  final bool useHttps;

  /// Mirrors `AppState.sessionToken`. Part of equality on purpose.
  final int token;

  /// The address *not* currently in use, when the profile defines one.
  final String? fallbackAddress;
  final bool? fallbackUseHttps;

  final bool reviewerMode;

  /// Stand-in router id used when reviewer mode is active with no saved
  /// routers, so mock-backed screens still have a session to key off.
  static const String reviewerRouterId = 'reviewer';

  bool get hasFallback =>
      fallbackAddress != null && fallbackAddress!.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RouterSession &&
          other.routerId == routerId &&
          other.ipAddress == ipAddress &&
          other.sysauth == sysauth &&
          other.useHttps == useHttps &&
          other.token == token &&
          other.fallbackAddress == fallbackAddress &&
          other.fallbackUseHttps == fallbackUseHttps &&
          other.reviewerMode == reviewerMode;

  @override
  int get hashCode => Object.hash(
    routerId,
    ipAddress,
    sysauth,
    useHttps,
    token,
    fallbackAddress,
    fallbackUseHttps,
    reviewerMode,
  );

  @override
  String toString() =>
      'RouterSession(routerId: $routerId, ipAddress: $ipAddress, '
      'useHttps: $useHttps, token: $token, reviewerMode: $reviewerMode)';
}
