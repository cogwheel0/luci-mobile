import 'dart:async';
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
    this.saveFailed = false,
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

  /// True when the device's storage refused the setting itself. Not the
  /// platform refusing background work, which [schedulingFailed] says, and
  /// which would be the wrong thing to tell the user here.
  final bool saveFailed;

  /// Switched off for exactly one reason, or none. The reasons are mutually
  /// exclusive, and each exit path used to spell all of them out.
  NotificationSettings off({
    bool permissionDenied = false,
    bool schedulingFailed = false,
    bool needsRouter = false,
    bool saveFailed = false,
  }) => NotificationSettings(
    enabled: false,
    kinds: kinds,
    permissionDenied: permissionDenied,
    schedulingFailed: schedulingFailed,
    needsRouter: needsRouter,
    saveFailed: saveFailed,
  );

  NotificationSettings copyWith({
    bool? enabled,
    Set<RouterEventKind>? kinds,
    bool? permissionDenied,
    bool? schedulingFailed,
    bool? needsRouter,
    bool? saveFailed,
  }) => NotificationSettings(
    enabled: enabled ?? this.enabled,
    kinds: kinds ?? this.kinds,
    permissionDenied: permissionDenied ?? this.permissionDenied,
    schedulingFailed: schedulingFailed ?? this.schedulingFailed,
    needsRouter: needsRouter ?? this.needsRouter,
    saveFailed: saveFailed ?? this.saveFailed,
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
    // Startup may still be deciding whether the stored switch can be
    // honoured. Rather than hold the screen on a spinner for the retry, or
    // forever in a host that never runs startup, read now and read again
    // once it has settled.
    if (!backgroundStartupSettled) {
      unawaited(
        backgroundStartup.then((_) {
          if (ref.mounted) ref.invalidateSelf();
        }),
      );
    }
    // Storage is written from places that have no screen of their own, and
    // this view of it has to follow whether or not whoever triggered the
    // write is still on screen.
    onBackgroundPollChanged = _refresh;
    ref.onDispose(() {
      if (onBackgroundPollChanged == _refresh) onBackgroundPollChanged = null;
    });
    return _read();
  }

  Future<NotificationSettings> _read() async {
    final enabled = await _store.readValue(BackgroundKeys.enabled) == 'true';
    final failed =
        await _store.readValue(BackgroundKeys.schedulingFailed) == 'true';
    return NotificationSettings(
      enabled: enabled,
      kinds: await readNotificationKinds(_store),
      schedulingFailed: !enabled && failed,
    );
  }

  /// Re-reads storage in place. Not `invalidateSelf`, which would drop the
  /// current value and put the screen back on a spinner for a change that
  /// only moves a switch.
  Future<void> _refresh() async {
    final next = await _read();
    if (ref.mounted) state = AsyncValue.data(next);
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
      state = AsyncValue.data(current.off());
      return;
    }

    // Ask before scheduling: a switch that turns on and then silently never
    // fires is worse than one that refuses to turn on.
    final granted = await ref
        .read(notificationServiceProvider)
        .requestPermission();
    if (!granted) {
      state = AsyncValue.data(current.off(permissionDenied: true));
      return;
    }

    // The router goes in before registering, because WorkManager may run a
    // freshly registered periodic task straight away. Register, then persist
    // "enabled": a stored flag that no task backs would come back on every
    // launch as a switch that does nothing.
    // Every storage step is inside one guard: a locked or corrupted
    // keystore must not escape the switch's callback, and whatever was
    // registered by then must not keep polling with the switch off.
    try {
      if (!await _saveRouter()) {
        // Nothing to poll: the switch stays off and says why, rather than
        // reading "on" over a poll that returns early every run.
        state = AsyncValue.data(current.off(needsRouter: true));
        return;
      }
      if (!await _schedule()) {
        // A task from an earlier launch may have survived the failed
        // replace; it must not keep waking the app. And no poll will ever
        // read the credentials, so they do not stay.
        await _cancel();
        await disableBackgroundPoll(_store, failed: true);
        state = AsyncValue.data(current.off(schedulingFailed: true));
        return;
      }
      await _store.writeValue(BackgroundKeys.enabled, 'true');
      await _store.deleteValue(BackgroundKeys.schedulingFailed);
    } catch (e, stack) {
      // Storage, not the platform, refused - so it is not recorded as a
      // scheduling failure, which the next launch would repeat as a claim
      // that the device cannot poll in the background.
      Logger.exception('Turning notifications on failed', e, stack);
      await _cancel();
      try {
        await disableBackgroundPoll(_store);
      } catch (e, stack) {
        Logger.exception('Could not switch the poll off in storage', e, stack);
      }
      state = AsyncValue.data(current.off(saveFailed: true));
      return;
    }
    // A fresh value, not copyWith: every "off because" flag is cleared.
    state = AsyncValue.data(
      NotificationSettings(enabled: true, kinds: current.kinds),
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
    // The switch's callback drops the future, so a keystore failure here
    // would surface as an unhandled error and the toggle would snap back
    // with nothing said. Report it by leaving the state alone.
    try {
      await _store.writeValue(
        BackgroundKeys.kinds,
        jsonEncode([for (final k in next) k.name]),
      );
    } catch (e, stack) {
      Logger.exception('Saving the notification kinds failed', e, stack);
      return;
    }
    state = AsyncValue.data(current.copyWith(kinds: next));
  }

  /// Copies the selected router's credentials where the background isolate
  /// can read them. It shares no memory with the app. False when there is
  /// no saved router to copy.
  Future<bool> _saveRouter() async {
    final router = ref.read(appStateProvider).selectedRouter;
    if (router == null) return false;
    // The address the app last reached the router on, not the primary one:
    // a profile reached through its fallback would otherwise be polled at
    // an address that never answers.
    await setMonitoredRouter(
      _store,
      MonitoredRouter(
        id: router.id,
        ipAddress: router.activeAddress,
        username: router.username,
        password: router.password,
        useHttps: router.activeUseHttps,
      ),
    );
    return true;
  }

  Future<bool> _schedule() => schedulePoll();

  Future<void> _cancel() => cancelPoll();
}
