import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:luci_mobile/models/router.dart' as model;
import 'package:luci_mobile/services/mock_api_service.dart';
import 'package:luci_mobile/services/mock_auth_service.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/services/background_monitor.dart';
import 'package:luci_mobile/services/background_worker.dart';
import 'package:luci_mobile/services/secure_storage_service.dart';
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
  _RecordingApi api, {
  _FakeStorage? storage,
}) {
  final state = _TestAppState(api);
  final container = ProviderContainer(
    overrides: [
      appStateProvider.overrideWith((ref) => state),
      if (storage != null)
        passwordMutationsProvider.overrideWith(
          (ref) => PasswordMutations(ref, storage: storage),
        ),
    ],
  );
  addTearDown(container.dispose);
  return (state: state, container: container);
}

/// An in-memory stand-in; the real one needs platform channels.
class _FakeStorage implements SecureStorageService {
  _FakeStorage({this.failWritesTo});

  final Map<String, String> values = {};

  /// A key whose writes throw, so the failure path can be exercised.
  final String? failWritesTo;

  @override
  Future<String?> readValue(String key) async => values[key];

  @override
  Future<void> writeValue(String key, String value) async {
    if (key == failWritesTo) throw Exception('storage is full');
    values[key] = value;
  }

  @override
  Future<void> deleteValue(String key) async => values.remove(key);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

    // The background isolate keeps its own copy of the credentials. Leaving
    // that stale means the next poll fails to log in while the switch still
    // reads "on" — the user just stops being told anything.
    test('the background monitor credential is rotated too', () async {
      final storage = _FakeStorage()
        ..values[BackgroundKeys.router] = jsonEncode(
          const MonitoredRouter(
            id: 'r1',
            ipAddress: '192.168.1.1',
            username: 'root',
            password: 'old-password',
            useHttps: false,
          ).toJson(),
        );
      final h = _harness(_RecordingApi(), storage: storage);

      await h.container.read(passwordMutationsProvider).change('new-password');

      final stored = MonitoredRouter.fromJson(
        jsonDecode(storage.values[BackgroundKeys.router]!)
            as Map<String, dynamic>,
      );
      expect(stored!.password, 'new-password');
    });

    // Nothing should be written for a user who never turned it on.
    test(
      'no background credential is created when monitoring is off',
      () async {
        final storage = _FakeStorage();
        final h = _harness(_RecordingApi(), storage: storage);

        await h.container
            .read(passwordMutationsProvider)
            .change('new-password');

        expect(storage.values[BackgroundKeys.router], isNull);
      },
    );

    test('a refused change leaves the background credential alone', () async {
      final storage = _FakeStorage()
        ..values[BackgroundKeys.router] = jsonEncode(
          const MonitoredRouter(
            id: 'r1',
            ipAddress: '192.168.1.1',
            username: 'root',
            password: 'old-password',
            useHttps: false,
          ).toJson(),
        );
      final h = _harness(_RecordingApi(accepts: false), storage: storage);

      await h.container.read(passwordMutationsProvider).change('new-password');

      final stored = MonitoredRouter.fromJson(
        jsonDecode(storage.values[BackgroundKeys.router]!)
            as Map<String, dynamic>,
      );
      expect(stored!.password, 'old-password');
    });

    // Monitoring follows one router; changing a different router's password
    // must not quietly repoint it.
    test('a different router\'s password does not steal the monitor', () async {
      final storage = _FakeStorage()
        ..values[BackgroundKeys.router] = jsonEncode(
          const MonitoredRouter(
            id: 'other',
            ipAddress: '10.0.0.1',
            username: 'root',
            password: 'other-password',
            useHttps: false,
          ).toJson(),
        );
      final h = _harness(_RecordingApi(), storage: storage);

      await h.container.read(passwordMutationsProvider).change('new-password');

      final stored = MonitoredRouter.fromJson(
        jsonDecode(storage.values[BackgroundKeys.router]!)
            as Map<String, dynamic>,
      );
      expect(stored!.id, 'other');
      expect(stored.ipAddress, '10.0.0.1');
      expect(stored.password, 'other-password');
    });

    // Monitoring cannot work with a credential the router no longer accepts.
    // Leaving the switch reading "on" is the silent failure the whole
    // rotation exists to prevent.
    test('a failed rotation switches monitoring off', () async {
      final storage = _FakeStorage(failWritesTo: BackgroundKeys.router)
        ..values[BackgroundKeys.enabled] = 'true'
        ..values[BackgroundKeys.router] = jsonEncode(
          const MonitoredRouter(
            id: 'r1',
            ipAddress: '192.168.1.1',
            username: 'root',
            password: 'old-password',
            useHttps: false,
          ).toJson(),
        );
      final h = _harness(_RecordingApi(), storage: storage);
      var announced = 0;
      onBackgroundPollChanged = () => announced++;
      addTearDown(() => onBackgroundPollChanged = null);

      final error = await h.container
          .read(passwordMutationsProvider)
          .change('new-password');

      // The password change itself succeeded; only the side effect failed.
      expect(error, isNull);
      expect(storage.values[BackgroundKeys.enabled], 'false');
      // The credential the router has stopped accepting goes with it, and
      // the switch is told rather than waiting for its next rebuild.
      expect(storage.values[BackgroundKeys.router], isNull);
      expect(announced, 1);
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
