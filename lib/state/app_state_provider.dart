import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'package:luci_mobile/services/interfaces/api_service_interface.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/state/router_session.dart';

/// The application-wide [AppState].
///
/// This lives here rather than in `main.dart` so that provider files can depend
/// on it without pulling in the screen imports that `main.dart` carries.
/// `main.dart` re-exports it, so existing `import '.../main.dart'` call sites
/// keep resolving.
final appStateProvider = ChangeNotifierProvider<AppState>(
  (ref) => AppState.instance,
);

/// The active router connection, or null when there is no usable session.
///
/// Feature providers watch this rather than reading auth fields directly.
/// [RouterSession] has value equality and carries the session token, so a
/// router switch, re-login or logout invalidates every dependent provider
/// automatically.
final sessionProvider = Provider<RouterSession?>(
  (ref) => ref.watch(appStateProvider.select((state) => state.currentSession)),
);

/// The API service for the active mode.
///
/// Rebuilds when reviewer mode is toggled, because `AppState.setReviewerMode`
/// reconfigures the service container before notifying listeners.
final apiServiceProvider = Provider<IApiService?>(
  (ref) => ref.watch(appStateProvider.select((state) => state.apiService)),
);
