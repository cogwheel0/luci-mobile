import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:luci_mobile/models/router_event.dart';
import 'package:luci_mobile/services/background_monitor.dart';
import 'package:luci_mobile/services/background_worker.dart';
import 'package:luci_mobile/services/notification_service.dart';
import 'package:luci_mobile/services/secure_storage_service.dart';
import 'package:luci_mobile/state/app_state_provider.dart';

@immutable
class NotificationSettings {
  const NotificationSettings({
    this.enabled = false,
    this.kinds = notifiableKinds,
    this.permissionDenied = false,
    this.schedulingFailed = false,
  });

  final bool enabled;
  final Set<RouterEventKind> kinds;

  /// True when the user turned it on but the system refused the permission —
  /// worth saying, because otherwise the switch is on and nothing arrives.
  final bool permissionDenied;

  /// True when the permission was granted but the platform would not
  /// register the background poll (iOS has no periodic tasks). Same reason
  /// to say so: the switch would otherwise read "on" over a poll that never
  /// runs.
  final bool schedulingFailed;

  NotificationSettings copyWith({
    bool? enabled,
    Set<RouterEventKind>? kinds,
    bool? permissionDenied,
    bool? schedulingFailed,
  }) => NotificationSettings(
    enabled: enabled ?? this.enabled,
    kinds: kinds ?? this.kinds,
    permissionDenied: permissionDenied ?? this.permissionDenied,
    schedulingFailed: schedulingFailed ?? this.schedulingFailed,
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
    return NotificationSettings(
      enabled: enabled,
      kinds: await readNotificationKinds(_store),
    );
  }

  Future<void> setEnabled(bool enabled) async {
    final current = state.value ?? const NotificationSettings();

    if (!enabled) {
      await _store.writeValue(BackgroundKeys.enabled, 'false');
      await _cancel();
      state = AsyncValue.data(
        current.copyWith(
          enabled: false,
          permissionDenied: false,
          schedulingFailed: false,
        ),
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
        current.copyWith(
          enabled: false,
          permissionDenied: true,
          schedulingFailed: false,
        ),
      );
      return;
    }

    // The router goes in before registering, because WorkManager may run a
    // freshly registered periodic task straight away. Register, then persist
    // "enabled": a stored flag that no task backs would come back on every
    // launch as a switch that does nothing.
    await _saveRouter();
    if (!await _schedule()) {
      await _store.writeValue(BackgroundKeys.enabled, 'false');
      // No poll will ever read them, so the credentials do not stay.
      await _store.deleteValue(BackgroundKeys.router);
      state = AsyncValue.data(
        current.copyWith(
          enabled: false,
          permissionDenied: false,
          schedulingFailed: true,
        ),
      );
      return;
    }
    await _store.writeValue(BackgroundKeys.enabled, 'true');
    state = AsyncValue.data(
      current.copyWith(
        enabled: true,
        permissionDenied: false,
        schedulingFailed: false,
      ),
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

  Future<bool> _schedule() => schedulePoll();

  Future<void> _cancel() => cancelPoll();
}
