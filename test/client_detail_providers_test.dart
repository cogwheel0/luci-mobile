import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:luci_mobile/models/router_capabilities.dart';
import 'package:luci_mobile/services/mock_api_service.dart';
import 'package:luci_mobile/services/mock_auth_service.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/models/uci_change.dart';
import 'package:luci_mobile/services/uci_changeset_service.dart';
import 'package:luci_mobile/state/client_detail_notifier.dart';
import 'package:luci_mobile/state/feature_providers.dart';

class _TestAppState extends AppState {
  _TestAppState()
    : super.forTesting(
        apiService: MockApiService(),
        authService: MockAuthService(),
      );
}

/// Reviewer mode cannot be switched on through `setReviewerMode` in a test -
/// that writes to secure storage - so the flag is overridden directly.
class _ReviewerAppState extends AppState {
  _ReviewerAppState()
    : super.forTesting(
        apiService: MockApiService(),
        authService: MockAuthService(),
      );

  @override
  bool get reviewerModeEnabled => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late _TestAppState appState;

  setUp(() {
    appState = _TestAppState();
    container = ProviderContainer(
      overrides: [appStateProvider.overrideWith((ref) => appState)],
    );
  });

  tearDown(() {
    // The container owns the overridden notifier and disposes it; disposing
    // it again here would throw.
    container.dispose();
  });

  test('the session is exposed to feature providers', () {
    final session = container.read(sessionProvider);
    expect(session, isNotNull);
    expect(session!.sysauth, isNotEmpty);
  });

  test('the api service reaches feature providers', () {
    expect(container.read(apiServiceProvider), isNotNull);
    expect(container.read(capabilityServiceProvider), isNotNull);
    expect(container.read(uciChangesetServiceProvider), isNotNull);
  });

  // The detail page's write controls are gated on these; if the probe never
  // resolves to a real capability set, every switch renders disabled.
  test(
    'capabilities probe resolves and enables the client write features',
    () async {
      final caps = await container.read(capabilitiesProvider.future);

      expect(caps.isProbed, isTrue, reason: 'probe should have completed');
      expect(caps.probeFailed, isFalse);
      expect(caps.uciConfigs, contains('dhcp'));
      expect(caps.uciConfigs, contains('firewall'));

      expect(
        caps.of(RouterFeature.dhcpReservations).available,
        isTrue,
        reason: 'reservations must be offerable in reviewer mode',
      );
      expect(caps.of(RouterFeature.clientBlocking).available, isTrue);
    },
  );

  test('featureProvider reports availability once the probe lands', () async {
    await container.read(capabilitiesProvider.future);

    expect(
      container.read(featureProvider(RouterFeature.dhcpReservations)).available,
      isTrue,
    );
    expect(
      container.read(featureProvider(RouterFeature.clientBlocking)).available,
      isTrue,
    );
  });

  // AppState notifies on every 2 s throughput tick. A detail provider that
  // reloaded on each one re-read every config from the router that often and
  // flashed the page back to its skeleton (#83).
  test('the client detail is not reloaded by unrelated app state', () async {
    const mac = 'AA:BB:CC:DD:EE:FF';
    final states = <AsyncValue<ClientDetail>>[];
    container.listen(
      clientDetailProvider(mac),
      (_, next) => states.add(next),
      fireImmediately: true,
    );
    await container.read(clientDetailProvider(mac).future);
    final settled = states.length;

    appState.notifyListeners();
    await container.pump();
    await Future<void>.delayed(Duration.zero);

    expect(states, hasLength(settled));
    expect(container.read(clientDetailProvider(mac)).isLoading, isFalse);
  });

  // The apply flow only confirms once the router answers again. Against the
  // reviewer-mode mock there is no router to answer, so with the real network
  // probe an apply would burn the whole 90-second rollback window and report
  // itself rolled back - with the UI stuck busy throughout. An App Store
  // reviewer would hit this on the first toggle they touched.
  test(
    'a reviewer-mode apply confirms promptly instead of timing out',
    () async {
      final reviewerState = _ReviewerAppState();
      final reviewerContainer = ProviderContainer(
        overrides: [appStateProvider.overrideWith((ref) => reviewerState)],
      );
      addTearDown(reviewerContainer.dispose);

      final service = reviewerContainer.read(uciChangesetServiceProvider)!;
      final session = reviewerContainer.read(sessionProvider)!;
      expect(session.reviewerMode, isTrue);

      final stopwatch = Stopwatch()..start();
      await service.stage(session, const [
        UciSet('dhcp', section: 'lan', values: {'leasetime': '24h'}),
      ]);
      final outcome = await service.apply(session);
      stopwatch.stop();

      expect(outcome.phase, ApplyPhase.confirmed);
      expect(
        stopwatch.elapsed,
        lessThan(const Duration(seconds: 10)),
        reason: 'must not sit through the rollback window',
      );
    },
  );
}
