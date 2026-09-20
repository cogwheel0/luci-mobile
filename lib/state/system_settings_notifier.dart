import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:luci_mobile/models/uci_change.dart';
import 'package:luci_mobile/services/uci_changeset_service.dart';
import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/state/feature_notifier.dart';
import 'package:luci_mobile/state/feature_providers.dart';
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
    if (ops.isEmpty) return null;
    final service = ref.read(uciChangesetServiceProvider);
    if (service == null) return null;

    final appState = ref.read(appStateProvider);
    appState.beginCriticalSection();
    try {
      return await ref.read(sessionGuardProvider).run<ApplyOutcome>((
        session,
        ctx,
      ) async {
        await service.stage(session, ops, context: ctx);
        return service.apply(session, onPhase: onPhase);
      }, context: context?.mounted == true ? context : null);
    } on UciStagingException catch (e, stack) {
      Logger.exception('Staging system settings failed', e, stack);
      return ApplyOutcome(
        phase: ApplyPhase.failed,
        applied: const UciChangeSet.empty(),
        error: e.cause,
      );
    } finally {
      // The hostname is on the dashboard, so the whole app is stale after
      // this, not just this screen.
      await appState.endCriticalSection(refresh: true);
      if (ref.mounted) ref.invalidate(systemSettingsProvider);
    }
  }
}

/// Why a password change was refused, or null when it went through.
enum PasswordChangeError { noSession, rejected, failed }

final passwordMutationsProvider = Provider<PasswordMutations>(
  PasswordMutations.new,
);

class PasswordMutations {
  PasswordMutations(this.ref);

  final Ref ref;

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
    try {
      await appState.updateRouter(router.copyWith(password: password));
    } catch (e, stack) {
      Logger.exception('Saving the new password failed', e, stack);
      return PasswordChangeError.failed;
    }
    return null;
  }
}
