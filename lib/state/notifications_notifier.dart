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
    this.schedulingFailed = false,
    this.needsRouter = false,
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

  /// True when there was no saved router to poll. The background isolate
  /// reads the router from storage, so without one every run returns early.
  final bool needsRouter;

  NotificationSettings copyWith({
    bool? enabled,
    Set<RouterEventKind>? kinds,
    bool? permissionDenied,
    bool? schedulingFailed,
    bool? needsRouter,
  }) => NotificationSettings(
    enabled: enabled ?? this.enabled,
    kinds: kinds ?? this.kinds,
    permissionDenied: permissionDenied ?? this.permissionDenied,
    schedulingFailed: schedulingFailed ?? this.schedulingFailed,
    needsRouter: needsRouter ?? this.needsRouter,
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
    final failed =
        await _store.readValue(BackgroundKeys.schedulingFailed) == 'true';
    return NotificationSettings(
      enabled: enabled,
      kinds: await readNotificationKinds(_store),
      schedulingFailed: !enabled && failed,
    );
  }

  Future<void> setEnabled(bool enabled) async {
    final current = state.value ?? const NotificationSettings();

    if (!enabled) {
      // Cancel first: if storage then fails, the task at least stops
      // polling. A write failure must not escape the switch's callback.
      await _cancel();
      try {
        await disableBackgroundPoll(_store);
      } catch (e, stack) {
        Logger.exception('Persisting the notification switch failed', e, stack);
      }
      state = AsyncValue.data(
        current.copyWith(
          enabled: false,
          permissionDenied: false,
          schedulingFailed: false,
          needsRouter: false,
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
          needsRouter: false,
        ),
      );
      return;
    }

    // The router goes in before registering, because WorkManager may run a
    // freshly registered periodic task straight away. Register, then persist
    // "enabled": a stored flag that no task backs would come back on every
    // launch as a switch that does nothing.
    if (!await _saveRouter()) {
      // Nothing to poll: the switch stays off and says why, rather than
      // reading "on" over a poll that returns early every run.
      state = AsyncValue.data(
        current.copyWith(
          enabled: false,
          permissionDenied: false,
          schedulingFailed: false,
          needsRouter: true,
        ),
      );
      return;
    }
    if (!await _schedule()) {
      // No poll will ever read the credentials, so they do not stay.
      await disableBackgroundPoll(_store, failed: true);
      state = AsyncValue.data(
        current.copyWith(
          enabled: false,
          permissionDenied: false,
          schedulingFailed: true,
          needsRouter: false,
        ),
      );
      return;
    }
    try {
      await _store.writeValue(BackgroundKeys.enabled, 'true');
      await _store.deleteValue(BackgroundKeys.schedulingFailed);
    } catch (e, stack) {
      // The task is registered and would poll with stored credentials while
      // the switch reads off and nothing ever cancels it. Undo both.
      Logger.exception('Persisting the notification switch failed', e, stack);
      await _cancel();
      await disableBackgroundPoll(_store, failed: true);
      state = AsyncValue.data(
        current.copyWith(
          enabled: false,
          permissionDenied: false,
          schedulingFailed: true,
          needsRouter: false,
        ),
      );
      return;
    }
    state = AsyncValue.data(
      current.copyWith(
        enabled: true,
        permissionDenied: false,
        schedulingFailed: false,
        needsRouter: false,
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
  /// can read them. It shares no memory with the app. False when there is
  /// no saved router to copy.
  Future<bool> _saveRouter() async {
    final router = ref.read(appStateProvider).selectedRouter;
    if (router == null) return false;
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
    return true;
  }

  Future<bool> _schedule() => schedulePoll();

  Future<void> _cancel() => cancelPoll();
}
