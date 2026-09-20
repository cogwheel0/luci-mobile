import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:luci_mobile/models/router_event.dart';
import 'package:luci_mobile/services/background_monitor.dart';
import 'package:luci_mobile/services/background_worker.dart';
import 'package:luci_mobile/services/notification_service.dart';
import 'package:luci_mobile/services/secure_storage_service.dart';
import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/utils/logger.dart';

@immutable
class NotificationSettings {
  const NotificationSettings({
    this.enabled = false,
    this.kinds = notifiableKinds,
    this.permissionDenied = false,
  });

  final bool enabled;
  final Set<RouterEventKind> kinds;

  /// True when the user turned it on but the system refused the permission —
  /// worth saying, because otherwise the switch is on and nothing arrives.
  final bool permissionDenied;

  NotificationSettings copyWith({
    bool? enabled,
    Set<RouterEventKind>? kinds,
    bool? permissionDenied,
  }) => NotificationSettings(
    enabled: enabled ?? this.enabled,
    kinds: kinds ?? this.kinds,
    permissionDenied: permissionDenied ?? this.permissionDenied,
  );
}

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(),
);

final notificationSettingsProvider =
    AsyncNotifierProvider<NotificationSettingsNotifier, NotificationSettings>(
      NotificationSettingsNotifier.new,
      retry: (_, _) => null,
    );

class NotificationSettingsNotifier extends AsyncNotifier<NotificationSettings> {
  SecureStorageService get _store => SecureStorageService();

  @override
  Future<NotificationSettings> build() async {
    final enabled = await _store.readValue(BackgroundKeys.enabled) == 'true';
    return NotificationSettings(enabled: enabled, kinds: await _readKinds());
  }

  Future<Set<RouterEventKind>> _readKinds() async {
    try {
      final raw = await _store.readValue(BackgroundKeys.kinds);
      if (raw == null || raw.isEmpty) return notifiableKinds;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return notifiableKinds;
      final names = {for (final n in decoded) n.toString()};
      return {
        for (final kind in notifiableKinds)
          if (names.contains(kind.name)) kind,
      };
    } catch (e, stack) {
      Logger.exception('Reading notification kinds failed', e, stack);
      return notifiableKinds;
    }
  }

  Future<void> setEnabled(bool enabled) async {
    final current = state.value ?? const NotificationSettings();

    if (!enabled) {
      await _store.writeValue(BackgroundKeys.enabled, 'false');
      await _cancel();
      state = AsyncValue.data(
        current.copyWith(enabled: false, permissionDenied: false),
      );
      return;
    }

    // Ask before scheduling: a switch that turns on and then silently never
    // fires is worse than one that refuses to turn on.
    final granted = await ref
        .read(notificationServiceProvider)
        .requestPermission();
    if (!granted) {
      state = AsyncValue.data(
        current.copyWith(enabled: false, permissionDenied: true),
      );
      return;
    }

    await _saveRouter();
    await _store.writeValue(BackgroundKeys.enabled, 'true');
    await _schedule();
    state = AsyncValue.data(
      current.copyWith(enabled: true, permissionDenied: false),
    );
  }

  Future<void> setKind(RouterEventKind kind, bool on) async {
    final current = state.value ?? const NotificationSettings();
    final next = {...current.kinds};
    if (on) {
      next.add(kind);
    } else {
      next.remove(kind);
    }
    await _store.writeValue(
      BackgroundKeys.kinds,
      jsonEncode([for (final k in next) k.name]),
    );
    state = AsyncValue.data(current.copyWith(kinds: next));
  }

  /// Copies the selected router's credentials where the background isolate
  /// can read them. It shares no memory with the app.
  Future<void> _saveRouter() async {
    final router = ref.read(appStateProvider).selectedRouter;
    if (router == null) return;
    await _store.writeValue(
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
    // A different router means a different baseline; diffing across the
    // switch would report the other one's clients as having left.
    await _store.deleteValue(BackgroundKeys.observation(router.id));
  }

  Future<void> _schedule() => schedulePoll();

  Future<void> _cancel() => cancelPoll();
}
