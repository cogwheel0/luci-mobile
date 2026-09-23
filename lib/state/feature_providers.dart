import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:luci_mobile/models/router_capabilities.dart';
import 'package:luci_mobile/services/capability_service.dart';
import 'package:luci_mobile/services/router_liveness_probe.dart';
import 'package:luci_mobile/services/uci_changeset_service.dart';
import 'package:luci_mobile/state/app_state_provider.dart';

/// Stands in for the network probe when the whole backend is mocked.
///
/// The apply flow confirms only once the router answers again. Against the
/// reviewer-mode mock there is no router to answer, so the real probe would
/// spend the entire rollback window timing out and every change would report
/// itself rolled back.
class _AlwaysReachableProbe implements IRouterLivenessProbe {
  const _AlwaysReachableProbe();

  @override
  Future<bool> isReachable(String hostWithPort, bool useHttps) async => true;
}

/// Stages and applies UCI changes for the active session.
///
/// Null when there is no API service yet (before `AppState` finishes its
/// asynchronous start-up).
final uciChangesetServiceProvider = Provider<UciChangesetService?>((ref) {
  final api = ref.watch(apiServiceProvider);
  if (api == null) return null;
  final reviewerMode = ref.watch(
    appStateProvider.select((state) => state.reviewerModeEnabled),
  );
  return UciChangesetService(
    api,
    probe: reviewerMode
        ? const _AlwaysReachableProbe()
        : const RouterLivenessProbe(),
  );
});

final capabilityServiceProvider = Provider<CapabilityService?>((ref) {
  final api = ref.watch(apiServiceProvider);
  if (api == null) return null;
  return CapabilityService(api);
});

/// What the active router supports.
///
/// Watches [sessionProvider], so switching router, re-logging in or logging
/// out re-probes automatically.
final capabilitiesProvider =
    AsyncNotifierProvider<CapabilityNotifier, RouterCapabilities>(
      CapabilityNotifier.new,
      // Riverpod retries failed providers with exponential backoff by
      // default. Against an unreachable router that turns one failed probe
      // into a stream of them, so opt out and let the user retry.
      retry: (_, _) => null,
    );

class CapabilityNotifier extends AsyncNotifier<RouterCapabilities> {
  @override
  Future<RouterCapabilities> build() async {
    final session = ref.watch(sessionProvider);
    if (session == null) return RouterCapabilities.unknown;

    final service = ref.watch(capabilityServiceProvider);
    if (service == null) return RouterCapabilities.unknown;

    return service.probe(session);
  }

  /// Re-reads capabilities — for a pull-to-refresh, or after the user has
  /// installed the package a gated feature asked for.
  Future<void> refresh() async {
    state = const AsyncValue<RouterCapabilities>.loading();
    ref.invalidateSelf();
    await future;
  }
}

/// Whether one feature can be offered, and if not, why.
///
/// While the probe is in flight this reports [UnavailableReason.notProbed] so
/// the UI shows a skeleton; a thrown probe reports
/// [UnavailableReason.probeFailed] so it shows "couldn't check", never
/// "unsupported".
final featureProvider = Provider.family<FeatureAvailability, RouterFeature>((
  ref,
  feature,
) {
  return ref
      .watch(capabilitiesProvider)
      .when(
        data: (capabilities) => capabilities.of(feature),
        loading: () =>
            const FeatureAvailability.unavailable(UnavailableReason.notProbed),
        error: (_, _) => const FeatureAvailability.unavailable(
          UnavailableReason.probeFailed,
        ),
      );
});
