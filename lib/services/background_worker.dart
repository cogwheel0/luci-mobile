import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import 'package:luci_mobile/models/router_event.dart';
import 'package:luci_mobile/services/api_service.dart';
import 'package:luci_mobile/services/interfaces/api_service_interface.dart';
import 'package:luci_mobile/services/background_monitor.dart';
import 'package:luci_mobile/services/event_log.dart';
import 'package:luci_mobile/services/notification_service.dart';
import 'package:luci_mobile/services/secure_storage_service.dart';
import 'package:luci_mobile/utils/logger.dart';

/// Keys the foreground writes and the background isolate reads.
///
/// The isolate shares no memory with the app, so everything it needs —
/// which router, what was seen last time, and what the user allows — has to
/// travel through storage.
class BackgroundKeys {
  const BackgroundKeys._();

  static const enabled = 'bg:enabled';
  static const router = 'bg:router';
  static const kinds = 'bg:kinds';

  /// Set when a registration was refused, so the settings screen can say
  /// why the switch is off even when that happened at startup.
  static const schedulingFailed = 'bg:schedulingFailed';
  static String observation(String routerId) => 'bg:last:$routerId';
}

/// Re-registers the periodic poll if the user has it switched on.
///
/// Android drops scheduled work on a force-stop, an app update and (on some
/// builds) a reboot. Without this the switch would still read "on" while
/// nothing ever ran again — the worst kind of silent failure, because the
/// user has no way to tell.
Future<void> ensureScheduled({SecureStorageService? storage}) async {
  final store = storage ?? SecureStorageService();
  if (await store.readValue(BackgroundKeys.enabled) != 'true') return;
  if (await schedulePoll(keepExisting: true)) return;
  // Refused: the switch must not keep reading "on" over a poll that will
  // never run, and the credentials it would have used have no reader. A
  // task registered by an earlier launch may still exist; it goes too,
  // rather than waking the app every 15 minutes to bail out.
  await cancelPoll();
  await disableBackgroundPoll(store, failed: true);
}

/// Turns the poll off in storage. With [failed], records that it was the
/// platform's refusal rather than the user's choice.
Future<void> disableBackgroundPoll(
  SecureStorageService store, {
  bool failed = false,
}) async {
  await store.writeValue(BackgroundKeys.enabled, 'false');
  await store.deleteValue(BackgroundKeys.router);
  if (failed) {
    await store.writeValue(BackgroundKeys.schedulingFailed, 'true');
  } else {
    await store.deleteValue(BackgroundKeys.schedulingFailed);
  }
}

/// Registers the periodic poll. Returns false when the platform refused.
///
/// [keepExisting] leaves an already-scheduled task alone, so a restart does
/// not reset its timer; the settings toggle replaces it instead.
///
/// The result matters: iOS has no periodic tasks, and an initialise that
/// failed leaves nothing to register with. A switch that turns on over a
/// registration that never happened is exactly the silent failure the
/// notifications screen exists to avoid.
Future<bool> schedulePoll({bool keepExisting = false}) async {
  try {
    await Workmanager().registerPeriodicTask(
      BackgroundMonitor.taskName,
      BackgroundMonitor.taskName,
      frequency: BackgroundMonitor.minimumInterval,
      existingWorkPolicy: keepExisting
          ? ExistingPeriodicWorkPolicy.keep
          : ExistingPeriodicWorkPolicy.replace,
      constraints: Constraints(
        // The router is only reachable over the network, so running
        // without one just burns battery to fail.
        networkType: NetworkType.connected,
      ),
    );
    return true;
  } catch (e, stack) {
    Logger.exception('Scheduling the background poll failed', e, stack);
    return false;
  }
}

Future<void> cancelPoll() async {
  try {
    await Workmanager().cancelByUniqueName(BackgroundMonitor.taskName);
  } catch (e, stack) {
    Logger.exception('Cancelling the background poll failed', e, stack);
  }
}

/// The entry point WorkManager calls. Must be a top-level function.
@pragma('vm:entry-point')
void backgroundDispatcher() {
  Workmanager().executeTask((task, _) async {
    if (task != BackgroundMonitor.taskName) return true;
    try {
      await runBackgroundPoll();
    } catch (e, stack) {
      Logger.exception('Background poll failed', e, stack);
    }
    // Always true: returning false makes WorkManager retry with backoff,
    // and a router that is simply out of range is not a failure to retry —
    // the next scheduled run is soon enough.
    return true;
  });
}

/// Polls the monitored router once and notifies about what changed.
Future<void> runBackgroundPoll({
  SecureStorageService? storage,
  IApiServiceFactory? apiFactory,
  NotificationService? notifications,
  DateTime Function()? clock,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = storage ?? SecureStorageService();
  final now = (clock ?? DateTime.now)();

  if (await store.readValue(BackgroundKeys.enabled) != 'true') return;

  final router = await _readRouter(store);
  if (router == null) return;

  final api = (apiFactory ?? _defaultApiFactory)();
  final String sysauth;
  try {
    sysauth = await api.login(
      router.ipAddress,
      router.username,
      router.password,
      router.useHttps,
    );
  } catch (e) {
    // Off the network, asleep, or the password changed. None of those is
    // something to wake the user about.
    Logger.info('Background poll could not reach ${router.ipAddress}: $e');
    return;
  }

  final current = await _observe(api, router, sysauth);
  if (current == null) return;

  final stored = await _readObservation(store, router.id);
  final baseline = (stored == null || stored.isStale(now))
      ? null
      : stored.observation;

  await store.writeValue(
    BackgroundKeys.observation(router.id),
    jsonEncode(StoredObservation(observation: current, at: now).toJson()),
  );

  final kinds = await readNotificationKinds(store);
  final events = BackgroundMonitor.capped(
    BackgroundMonitor.notifiable(
      previous: baseline,
      current: current,
      routerId: router.id,
      at: now,
      kinds: kinds,
    ),
  );
  if (events.isEmpty) return;

  // The feed is the record; the notification is only the nudge. Writing
  // here means opening the app after a notification shows the same events.
  await EventLog(store).append(router.id, events, fromBackground: true);

  await (notifications ?? NotificationService()).show([
    for (final event in events) (event: event, text: _describe(event)),
  ]);
}

Future<RouterObservation?> _observe(
  IApiService api,
  MonitoredRouter router,
  String sysauth,
) async {
  try {
    // The calls the dashboard makes, and no more: a background poll should
    // cost the router as little as the foreground one does. `system.info`
    // is there for its uptime, which is how a reboot is noticed.
    final results = await Future.wait([
      api.call(
        router.ipAddress,
        sysauth,
        router.useHttps,
        object: 'network.interface',
        method: 'dump',
      ),
      api.call(
        router.ipAddress,
        sysauth,
        router.useHttps,
        object: 'luci-rpc',
        method: 'getDHCPLeases',
        params: const {},
      ),
      api
          .call(
            router.ipAddress,
            sysauth,
            router.useHttps,
            object: 'system',
            method: 'info',
            params: const {},
          )
          .catchError((Object e) {
            // Uptime is a nice-to-have; a router that refuses it still has a
            // WAN and clients worth reporting on.
            Logger.info('Background poll could not read uptime: $e');
            return null;
          }),
    ]);

    final dump = _payload(results[0]);
    final leaseData = _payload(results[1]);
    final leases = leaseData is Map ? leaseData['dhcp_leases'] : null;
    final sysInfo = _payload(results[2]);

    return EventDeriver.observe(
      reachable: true,
      dashboardData: {
        'wan': wanStateFrom(dump),
        if (sysInfo is Map) 'sysInfo': sysInfo,
      },
      clients: clientsFromLeases(leases is List ? leases : const []),
    );
  } catch (e, stack) {
    Logger.exception('Background observation failed', e, stack);
    return null;
  }
}

/// Unwraps ubus's `[status, data]` envelope.
dynamic _payload(dynamic result) =>
    result is List && result.length > 1 && result[0] == 0 ? result[1] : null;

/// The WAN block in the shape `EventDeriver.observe` expects.
@visibleForTesting
Map<String, dynamic> wanStateFrom(dynamic dump) {
  final interfaces = dump is Map ? dump['interface'] : null;
  if (interfaces is! List) return const {'up': false};
  // Any WAN-like interface being up means there is internet. Returning on
  // the first match let a down `wan6` mask an up `wan`, which the deriver
  // then reported as "Internet connection lost" — a push notification about
  // an outage that never happened.
  var up = false;
  for (final entry in interfaces) {
    if (entry is! Map) continue;
    final name = entry['interface']?.toString() ?? '';
    if (name != 'wan' && name != 'wwan' && !name.startsWith('wan')) continue;
    up = up || entry['up'] == true;
  }
  return {'up': up};
}

Future<MonitoredRouter?> _readRouter(SecureStorageService store) async {
  try {
    final raw = await store.readValue(BackgroundKeys.router);
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic>
        ? MonitoredRouter.fromJson(decoded)
        : null;
  } catch (e, stack) {
    Logger.exception('Reading the monitored router failed', e, stack);
    return null;
  }
}

Future<StoredObservation?> _readObservation(
  SecureStorageService store,
  String routerId,
) async {
  try {
    final raw = await store.readValue(BackgroundKeys.observation(routerId));
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic>
        ? StoredObservation.fromJson(decoded)
        : null;
  } catch (e, stack) {
    Logger.exception('Reading the last observation failed', e, stack);
    return null;
  }
}

/// The event kinds the user wants notified about.
///
/// Shared with the settings screen: the background poll and the foreground
/// toggle must agree on what is stored, or the switches lie.
Future<Set<RouterEventKind>> readNotificationKinds(
  SecureStorageService store,
) async {
  try {
    final raw = await store.readValue(BackgroundKeys.kinds);
    if (raw == null || raw.isEmpty) return notifiableKinds;
    final decoded = jsonDecode(raw);
    if (decoded is! List) return notifiableKinds;
    final names = {for (final n in decoded) n.toString()};
    final kinds = {
      for (final kind in notifiableKinds)
        if (names.contains(kind.name)) kind,
    };
    return kinds;
  } catch (e, stack) {
    Logger.exception('Reading notification kinds failed', e, stack);
    return notifiableKinds;
  }
}

/// Notification text.
///
/// The background isolate has no BuildContext and therefore no
/// localizations, so these are deliberately plain English. Localizing them
/// would mean loading the delegate off-thread for one string — the honest
/// trade is to keep the in-app feed, which *is* localized, as the place
/// events are read properly.
String _describe(RouterEvent event) => switch (event.kind) {
  RouterEventKind.wanDown => 'Internet connection lost',
  RouterEventKind.wanUp => 'Internet connection restored',
  RouterEventKind.rebooted => 'The router restarted',
  RouterEventKind.clientJoined => '${event.subject ?? "A device"} joined',
  RouterEventKind.clientLeft => '${event.subject ?? "A device"} left',
  RouterEventKind.routerUnreachable => 'The router stopped responding',
  RouterEventKind.routerBack => 'The router is back',
};

typedef IApiServiceFactory = IApiService Function();

IApiService _defaultApiFactory() => RealApiService();
