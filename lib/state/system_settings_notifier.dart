import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:luci_mobile/models/router.dart' as model;
import 'package:luci_mobile/models/uci_change.dart';
import 'package:luci_mobile/services/background_monitor.dart';
import 'package:luci_mobile/services/background_worker.dart';
import 'package:luci_mobile/services/secure_storage_service.dart';
import 'package:luci_mobile/services/uci_changeset_service.dart';
import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/state/uci_mutation.dart';
import 'package:luci_mobile/utils/logger.dart';

/// Hostname and time settings out of the `system` config.
@immutable
class SystemSettings {
  const SystemSettings({
    required this.section,
    required this.hostname,
    required this.zoneName,
    required this.description,
    required this.notes,
    required this.timezones,
  });

  /// The UCI section holding them — `cfg01e48a` on a stock router, not
  /// `@system[0]`, because writes need the real name.
  final String section;

  final String hostname;

  /// The human name (`Europe/Berlin`). Empty means UTC.
  final String zoneName;

  /// `system.description` and `system.notes` — LuCI's free-text fields.
  final String description;
  final String notes;

  /// Zone name -> POSIX TZ string, empty when the router would not list them.
  final Map<String, String> timezones;

  List<String> get zoneNames {
    final names = timezones.keys.toList()..sort();
    return names;
  }
}

final systemSettingsProvider = FutureProvider<SystemSettings?>((ref) async {
  final session = ref.watch(sessionProvider);
  final api = ref.watch(apiServiceProvider);
  if (session == null || api == null) return null;

  final raw = await api.uciGetAll(
    session.ipAddress,
    session.sysauth,
    session.useHttps,
    config: 'system',
  );
  final values = _values(raw);

  // The first `system`-typed section is the one LuCI edits; its name is
  // generated, so it has to be discovered rather than assumed.
  String section = '';
  Map<String, dynamic> system = const {};
  for (final entry in values.entries) {
    final v = entry.value;
    if (v is Map && v['.type'] == 'system') {
      section = (v['.name'] as String?) ?? entry.key;
      system = Map<String, dynamic>.from(v);
      break;
    }
  }

  // A router that will not list zones still lets the hostname be edited, so a
  // failure here must not blank the screen.
  var zones = const <String, String>{};
  try {
    zones = await api.luciTimezones(
      session.ipAddress,
      session.sysauth,
      session.useHttps,
    );
  } catch (e, stack) {
    Logger.exception('Timezone list unavailable', e, stack);
  }

  return SystemSettings(
    section: section,
    hostname: _string(system['hostname']),
    zoneName: _string(system['zonename']),
    description: _string(system['description']),
    notes: _string(system['notes']),
    timezones: zones,
  );
}, retry: (_, _) => null);

Map<String, dynamic> _values(dynamic raw) {
  if (raw is! List || raw.length < 2) return const {};
  final data = raw[1];
  if (data is! Map) return const {};
  final values = data['values'];
  return values is Map
      ? Map<String, dynamic>.from(values)
      : Map<String, dynamic>.from(data);
}

String _string(dynamic value) => value is String ? value : '';

/// The operations that turn [current] into the edited values.
///
/// Pure so the "did anything actually change" rule is testable: applying a
/// no-op would still run the rollback protocol and make the user wait.
List<UciOperation> planSystemSettings({
  required SystemSettings current,
  required String hostname,
  required String zoneName,
  required String description,
  required String notes,
}) {
  if (current.section.isEmpty) return const [];
  final ops = <UciOperation>[];

  void set(String option, String value, String was) {
    if (value == was) return;
    ops.add(
      UciSet('system', section: current.section, values: {option: value}),
    );
  }

  set('hostname', hostname.trim(), current.hostname);
  set('description', description.trim(), current.description);
  set('notes', notes.trim(), current.notes);

  if (zoneName != current.zoneName) {
    // LuCI writes both: `zonename` is what the UI reads back, `timezone` is
    // the POSIX string the C library actually uses. Writing only one leaves
    // the router displaying a zone it is not keeping time in.
    ops.add(
      UciSet(
        'system',
        section: current.section,
        values: {
          'zonename': zoneName,
          'timezone': current.timezones[zoneName] ?? 'UTC',
        },
      ),
    );
  }

  return ops;
}

/// A hostname the router will accept. An invalid one is not cosmetic: it can
/// stop dnsmasq resolving names while leaving the router reachable, so the
/// rollback timer would never fire.
bool isValidHostname(String value) =>
    RegExp(r'^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$').hasMatch(value);

final systemSettingsMutationsProvider = Provider<SystemSettingsMutations>(
  SystemSettingsMutations.new,
);

class SystemSettingsMutations {
  SystemSettingsMutations(this.ref);

  final Ref ref;

  Future<ApplyOutcome?> apply(
    List<UciOperation> ops, {
    BuildContext? context,
    void Function(ApplyPhase phase, Duration remaining)? onPhase,
  }) async {
    final outcome = await applyUciOperations(
      ref,
      ops,
      describe: 'system settings',
      context: context,
      onPhase: onPhase,
      // The hostname is on the dashboard, so the whole app is stale after
      // this, not just this screen.
      refreshDashboard: true,
    );
    // The hostname is on the dashboard, so the whole app is stale after
    // this, not just this screen.
    if (ref.mounted) ref.invalidate(systemSettingsProvider);
    return outcome;
  }
}

/// Why a password change was refused, or null when it went through.
enum PasswordChangeError { noSession, rejected, failed }

final passwordMutationsProvider = Provider<PasswordMutations>(
  PasswordMutations.new,
);

class PasswordMutations {
  PasswordMutations(this.ref, {SecureStorageService? storage})
    : _storage = storage ?? SecureStorageService();

  final Ref ref;
  final SecureStorageService _storage;

  /// Changes the router account's password and rotates the saved credential.
  ///
  /// The rotation is the part that matters: the stored password is what the
  /// app reconnects with, so changing it on the router without updating it
  /// here locks the user out of their own saved profile on the next launch.
  Future<PasswordChangeError?> change(
    String password, {
    BuildContext? context,
  }) async {
    final session = ref.read(sessionProvider);
    final api = ref.read(apiServiceProvider);
    final appState = ref.read(appStateProvider);
    final router = appState.selectedRouter;
    if (session == null || api == null || router == null) {
      return PasswordChangeError.noSession;
    }

    try {
      final ok = await api.luciSetPassword(
        session.ipAddress,
        session.sysauth,
        session.useHttps,
        username: router.username,
        password: password,
        context: context?.mounted == true ? context : null,
      );
      if (!ok) return PasswordChangeError.rejected;
    } catch (e, stack) {
      Logger.exception('Changing the router password failed', e, stack);
      return PasswordChangeError.failed;
    }

    // Only after the router accepted it — storing a password the router does
    // not have would be the same lockout in the other direction.
    final updated = router.copyWith(password: password);
    try {
      await appState.updateRouter(updated);
    } catch (e, stack) {
      Logger.exception('Saving the new password failed', e, stack);
      return PasswordChangeError.failed;
    }

    // The background isolate keeps its own copy of the credentials, because
    // it shares no memory with the app. Leaving that one stale means the
    // next poll fails to log in while the notifications switch still reads
    // "on" — the user simply stops being told anything, with no clue why.
    await _rotateBackgroundCredential(updated);
    return null;
  }

  Future<void> _rotateBackgroundCredential(model.Router router) async {
    try {
      final raw = await _storage.readValue(BackgroundKeys.router);
      // Nothing to rotate for a user who never switched monitoring on.
      if (raw == null) return;
      final monitored = MonitoredRouter.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      // Monitoring follows one router. Changing a *different* router's
      // password must not quietly repoint it at that one instead.
      if (monitored?.id != router.id) return;
      await _storage.writeValue(
        BackgroundKeys.router,
        jsonEncode(
          MonitoredRouter(
            id: router.id,
            ipAddress: router.ipAddress,
            username: router.username,
            password: router.password,
            useHttps: router.useHttps,
          ).toJson(),
        ),
      );
    } catch (e, stack) {
      Logger.exception('Updating the background credential failed', e, stack);
      // Monitoring cannot work with a credential the router no longer
      // accepts. Switching it off is visible and recoverable; leaving it on
      // means notifications just stop, which is the failure this whole
      // rotation exists to prevent.
      try {
        await _storage.writeValue(BackgroundKeys.enabled, 'false');
      } catch (e2, stack2) {
        Logger.exception('Could not disable background monitoring', e2, stack2);
      }
    }
  }
}
