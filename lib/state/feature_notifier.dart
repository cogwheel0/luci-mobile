import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/state/router_session.dart';

/// Discards the result of any write whose session went away mid-flight.
///
/// `AppState` does this by hand: capture `_sessionToken` before an await and
/// compare it after every one. That works, but it has to be remembered at each
/// of the forty-odd call sites. Feature code gets it structurally instead —
/// [run] captures the whole [RouterSession] (which has value equality and
/// carries the token) and drops the result if the user switched router, logged
/// out, or was re-authenticated while the write was in the air.
///
/// Reads need none of this: they `ref.watch(sessionProvider)`, so a session
/// change rebuilds them from scratch.
class SessionGuard {
  const SessionGuard(this._ref);

  final Ref _ref;

  /// The active session, or null when there is none.
  RouterSession? get session => _ref.read(sessionProvider);

  /// Runs [body] against the session current at call time.
  ///
  /// Returns null — rather than a stale value — when the provider was disposed
  /// or the session changed before [body] finished. Callers should treat null
  /// as "abandoned", not as failure.
  ///
  /// [context] is re-checked for mountedness before being handed to [body], so
  /// a certificate prompt is never raised against a dead element.
  Future<T?> run<T>(
    Future<T> Function(RouterSession session, BuildContext? context) body, {
    BuildContext? context,
  }) async {
    final captured = _ref.read(sessionProvider);
    if (captured == null) return null;

    final safeContext = context?.mounted == true ? context : null;
    final result = await body(captured, safeContext);

    if (!_ref.mounted) return null;
    if (_ref.read(sessionProvider) != captured) return null;
    return result;
  }
}

/// A guard bound to the current provider scope.
final sessionGuardProvider = Provider<SessionGuard>(SessionGuard.new);
