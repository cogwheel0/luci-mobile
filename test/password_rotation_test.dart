import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:luci_mobile/models/router.dart' as model;
import 'package:luci_mobile/services/mock_api_service.dart';
import 'package:luci_mobile/services/mock_auth_service.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/state/system_settings_notifier.dart';

/// Records what was asked of the router, and can refuse.
class _RecordingApi extends MockApiService {
  _RecordingApi({this.accepts = true, this.throws = false});

  final bool accepts;
  final bool throws;
  String? sentUsername;
  String? sentPassword;

  @override
  Future<bool> luciSetPassword(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String username,
    required String password,
    BuildContext? context,
  }) async {
    if (throws) throw Exception('transport failed');
    sentUsername = username;
    sentPassword = password;
    return accepts;
  }
}

/// `forTesting` leaves the router service null, so the saved profile is
/// stubbed here instead.
class _TestAppState extends AppState {
  _TestAppState(this.api)
    : super.forTesting(apiService: api, authService: MockAuthService());

  final _RecordingApi api;

  model.Router _router = model.Router(
    id: 'r1',
    ipAddress: '192.168.1.1',
    username: 'root',
    password: 'old-password',
    useHttps: false,
  );

  model.Router? updated;

  @override
  model.Router? get selectedRouter => _router;

  @override
  Future<void> updateRouter(model.Router router) async {
    updated = router;
    _router = router;
  }
}

({_TestAppState state, ProviderContainer container}) _harness(
  _RecordingApi api,
) {
  final state = _TestAppState(api);
  final container = ProviderContainer(
    overrides: [appStateProvider.overrideWith((ref) => state)],
  );
  addTearDown(container.dispose);
  return (state: state, container: container);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('changing the router password', () {
    test('sends the saved account name, not a hardcoded root', () async {
      final api = _RecordingApi();
      final h = _harness(api);
      final error = await h.container
          .read(passwordMutationsProvider)
          .change('new-password');

      expect(error, isNull);
      expect(api.sentUsername, 'root');
      expect(api.sentPassword, 'new-password');
    });

    // The stored password is what the app reconnects with. Changing it on the
    // router without updating the saved copy locks the user out of their own
    // profile on the next launch.
    test('rotates the saved credential on success', () async {
      final h = _harness(_RecordingApi());
      await h.container.read(passwordMutationsProvider).change('new-password');

      expect(h.state.updated, isNotNull);
      expect(h.state.updated!.password, 'new-password');
      // Nothing else about the profile may drift.
      expect(h.state.updated!.id, 'r1');
      expect(h.state.updated!.ipAddress, '192.168.1.1');
      expect(h.state.updated!.username, 'root');
    });

    // Storing a password the router does not have is the same lockout in the
    // other direction, so the save must not happen on a refusal.
    test('a refused change leaves the saved credential alone', () async {
      final h = _harness(_RecordingApi(accepts: false));
      final error = await h.container
          .read(passwordMutationsProvider)
          .change('new-password');

      expect(error, PasswordChangeError.rejected);
      expect(h.state.updated, isNull);
    });

    test('a transport failure leaves the saved credential alone', () async {
      final h = _harness(_RecordingApi(throws: true));
      final error = await h.container
          .read(passwordMutationsProvider)
          .change('new-password');

      expect(error, PasswordChangeError.failed);
      expect(h.state.updated, isNull);
    });
  });
}
